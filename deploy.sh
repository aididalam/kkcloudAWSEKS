#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-us-east-1}"

for command_name in aws kubectl terraform; do
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
terraform -chdir="$ROOT" apply "$@"

REGION="$(terraform -chdir="$ROOT" output -raw aws_region)"
CLUSTER_NAME="$(terraform -chdir="$ROOT" output -raw cluster_name)"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=10m

echo "Cluster is ready. Deploy an application with ingressClassName: alb."
