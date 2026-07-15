#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-us-east-1}"

for command_name in aws curl kubectl terraform; do
  command -v "$command_name" >/dev/null || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --no-cli-pager)"
[[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || {
  echo "The current AWS credentials did not return a valid account ID." >&2
  exit 1
}

# Each temporary playground account gets independent Terraform metadata and
# resource state. These must be different paths: Terraform reserves
# TF_DATA_DIR/terraform.tfstate for backend metadata.
ACCOUNT_DIR="$ROOT/.terraform-account/$ACCOUNT_ID"
LEGACY_STATE="$ACCOUNT_DIR/terraform.tfstate"
export TF_DATA_DIR="$ACCOUNT_DIR/terraform-data"
STATE="$ACCOUNT_DIR/terraform-state/terraform.tfstate"
mkdir -p "$TF_DATA_DIR" "$(dirname "$STATE")"

# Migrate state written by the original wrapper, which accidentally placed the
# resource state at Terraform's backend-metadata path.
if [[ -f "$LEGACY_STATE" && ! -f "$STATE" ]]; then
  mv "$LEGACY_STATE" "$STATE"
  echo "Migrated existing account state to: $STATE"
fi

echo "AWS account: $ACCOUNT_ID"
echo "AWS region:  $REGION"
echo "State:       $STATE"

terraform -chdir="$ROOT" init -reconfigure -backend-config="path=$STATE"
terraform -chdir="$ROOT" fmt -check
terraform -chdir="$ROOT" validate

# KodeKloud permits creating this policy but denies tagging and deleting it.
# Bootstrap it without tags, then Terraform consumes it as a read-only data
# source. Rebuilds in the same account reuse the existing policy.
EXISTING_POLICY_ARN="$(aws iam list-policies \
  --scope Local \
  --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn | [0]" \
  --output text \
  --no-cli-pager)"
if [[ -z "$EXISTING_POLICY_ARN" || "$EXISTING_POLICY_ARN" == "None" ]]; then
  POLICY_FILE="$(mktemp)"
  trap 'rm -f "$POLICY_FILE"' EXIT
  curl -fsSL \
    "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.4.1/docs/install/iam_policy.json" \
    -o "$POLICY_FILE"
  EXISTING_POLICY_ARN="$(aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --description "Official IAM policy for AWS Load Balancer Controller 3.4.1" \
    --policy-document "file://$POLICY_FILE" \
    --query Policy.Arn \
    --output text \
    --no-cli-pager)"
  echo "Created controller IAM policy: $EXISTING_POLICY_ARN"
else
  echo "Reusing controller IAM policy: $EXISTING_POLICY_ARN"
fi

# KodeKloud denies inline role policies and policy tagging. Create the scoped
# Bidly S3 policy without tags, then attach it through Terraform as read-only
# policy data. The temporary playground account removes it when it expires.
BIDLY_BUCKET_NAME="${TF_VAR_bidly_s3_bucket_name:-bidly-auction-${ACCOUNT_ID}-${REGION}}"
BIDLY_POLICY_NAME="BidlyAuctionBucketAccess"
BIDLY_POLICY_ARN="$(aws iam list-policies \
  --scope Local \
  --query "Policies[?PolicyName=='${BIDLY_POLICY_NAME}'].Arn | [0]" \
  --output text \
  --no-cli-pager)"
if [[ -z "$BIDLY_POLICY_ARN" || "$BIDLY_POLICY_ARN" == "None" ]]; then
  BIDLY_POLICY_FILE="$(mktemp)"
  cat >"$BIDLY_POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${BIDLY_BUCKET_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::${BIDLY_BUCKET_NAME}/*"
    }
  ]
}
EOF
  BIDLY_POLICY_ARN="$(aws iam create-policy \
    --policy-name "$BIDLY_POLICY_NAME" \
    --description "Scoped S3 access for the Bidly auction service" \
    --policy-document "file://$BIDLY_POLICY_FILE" \
    --query Policy.Arn \
    --output text \
    --no-cli-pager)"
  rm -f "$BIDLY_POLICY_FILE"
  echo "Created Bidly S3 IAM policy: $BIDLY_POLICY_ARN"
else
  echo "Reusing Bidly S3 IAM policy: $BIDLY_POLICY_ARN"
fi

# Migrate state produced by older project revisions that managed this policy.
if terraform -chdir="$ROOT" state show -no-color aws_iam_policy.controller >/dev/null 2>&1; then
  terraform -chdir="$ROOT" state rm aws_iam_policy.controller
fi

terraform -chdir="$ROOT" apply "$@"

REGION="$(terraform -chdir="$ROOT" output -raw aws_region)"
CLUSTER_NAME="$(terraform -chdir="$ROOT" output -raw cluster_name)"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=10m
kubectl rollout status deployment/argocd-server -n argocd --timeout=10m
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=10m

# This branch is the complete Bidly deployment stage. Terraform provisions the
# private, Multi-AZ RDS database and runtime secrets; Argo CD owns workloads.
kubectl apply -f "$ROOT/examples/bidly-application.yaml"
kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/bidly -n argocd --timeout=10m
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/bidly -n argocd --timeout=15m

for deployment in auth auction auth-frontend auction-frontend; do
  # A running cluster can receive new RDS values through a Secret update.
  # Restarting makes each container read the new DATABASE_URL from its Secret.
  kubectl rollout restart "deployment/$deployment" -n bidly
  kubectl rollout status "deployment/$deployment" -n bidly --timeout=10m
done

# Verify through the running APIs rather than connecting to RDS with a master
# password. This proves EKS networking, RDS credentials, migrations, and demo
# data together. The pod is deleted as soon as the check completes.
kubectl run bidly-api-verifier \
  --namespace bidly \
  --rm \
  --interactive \
  --restart=Never \
  --image=curlimages/curl:8.12.1 \
  --command -- sh -ec '
    set -eu
    login="$(curl -fsS -X POST http://auth:8081/api/auth/login \
      -H "Content-Type: application/json" \
      --data "{\"email\":\"user1@bidly.com\",\"password\":\"password\"}")"
    token="$(printf "%s" "$login" | sed -n "s/.*\"token\":\"\([^\"]*\)\".*/\1/p")"
    [ -n "$token" ]
    products="$(curl -fsS http://auction:8082/api/products)"
    product_count="$(printf "%s" "$products" | grep -o "\"id\"" | wc -l | tr -d " ")"
    [ "$product_count" = "20" ]
    bids="$(curl -fsS http://auction:8082/api/products/a1000000-0000-4000-8000-000000000001/bids \
      -H "Authorization: Bearer $token")"
    bid_count="$(printf "%s" "$bids" | grep -o "\"id\"" | wc -l | tr -d " ")"
    [ "$bid_count" = "2" ]
  '

S3_BUCKET="$(terraform -chdir="$ROOT" output -raw bidly_s3_bucket)"
aws s3api head-object --bucket "$S3_BUCKET" --key products/demo/listing-01.jpg --no-cli-pager >/dev/null

echo "Bidly is deployed and verified with private Multi-AZ RDS, demo users, listings, bids, and seeded S3 images."
echo "Argo CD login: admin / password"
echo "Argo CD ALB: kubectl -n argocd get ingress argocd"
echo "Bidly ALB: kubectl -n bidly get ingress bidly"
