#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --no-cli-pager)"
ACCOUNT_DIR="$ROOT/.terraform-account/$ACCOUNT_ID"
LEGACY_STATE="$ACCOUNT_DIR/terraform.tfstate"
export TF_DATA_DIR="$ACCOUNT_DIR/terraform-data"
STATE="$ACCOUNT_DIR/terraform-state/terraform.tfstate"
mkdir -p "$TF_DATA_DIR" "$(dirname "$STATE")"

if [[ -f "$LEGACY_STATE" && ! -f "$STATE" ]]; then
  mv "$LEGACY_STATE" "$STATE"
  echo "Migrated existing account state to: $STATE"
fi

if [[ ! -f "$STATE" ]]; then
  echo "No Terraform state exists for AWS account $ACCOUNT_ID." >&2
  exit 1
fi

read -r -p "Destroy demo-eks in account $ACCOUNT_ID? Type destroy: " confirmation
[[ "$confirmation" == "destroy" ]] || {
  echo "Cancelled."
  exit 1
}

terraform -chdir="$ROOT" init -reconfigure -backend-config="path=$STATE"
REGION="$(terraform -chdir="$ROOT" output -raw aws_region)"
CLUSTER_NAME="$(terraform -chdir="$ROOT" output -raw cluster_name)"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# Ingress resources must be removed while the controller is still running, or
# their AWS ALBs can be orphaned when the cluster is destroyed.
while read -r namespace ingress_name; do
  [[ -n "${namespace:-}" && -n "${ingress_name:-}" ]] || continue
  kubectl delete ingress "$ingress_name" -n "$namespace" --timeout=10m
done < <(
  kubectl get ingress -A \
    -o go-template='{{range .items}}{{if eq .spec.ingressClassName "alb"}}{{.metadata.namespace}} {{.metadata.name}}{{"\n"}}{{end}}{{end}}' \
    2>/dev/null || true
)

terraform -chdir="$ROOT" destroy
