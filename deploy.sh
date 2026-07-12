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

echo "Cluster is ready. Deploy an application with ingressClassName: alb."
