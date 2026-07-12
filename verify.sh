#!/usr/bin/env bash
set -Eeuo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-demo-eks}"

aws sts get-caller-identity --no-cli-pager
aws eks describe-cluster \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.{name:name,status:status,version:version,vpc:resourcesVpcConfig.vpcId,auth:accessConfig.authenticationMode}' \
  --output table \
  --no-cli-pager

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

READY_NODES="$(kubectl get nodes --no-headers | awk '$2 == "Ready" { count++ } END { print count + 0 }')"
[[ "$READY_NODES" -eq 3 ]] || {
  echo "Expected exactly 3 Ready nodes, found $READY_NODES." >&2
  kubectl get nodes -o wide
  exit 1
}

kubectl get nodes -o wide
kubectl get deployment,pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=5m
kubectl get ingressclass alb
kubectl get endpoints aws-load-balancer-webhook-service -n kube-system

CONTROLLER_IMAGE="$(kubectl get deployment aws-load-balancer-controller -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}')"
EXPECTED_CONTROLLER_VERSION="${LOAD_BALANCER_CONTROLLER_VERSION:-3.4.1}"
[[ "$CONTROLLER_IMAGE" == *":v${EXPECTED_CONTROLLER_VERSION}" ]] || {
  echo "Unexpected controller image: $CONTROLLER_IMAGE" >&2
  exit 1
}

CONTROLLER_ARGS="$(kubectl get deployment aws-load-balancer-controller -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}')"
[[ "$CONTROLLER_ARGS" == *"--default-target-type=ip"* ]] || {
  echo "The controller is not configured to default to pod-IP targets." >&2
  exit 1
}

CONTROLLER_ROLE="$(kubectl get serviceaccount aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')"
[[ "$CONTROLLER_ROLE" == *":role/AmazonEKSLoadBalancerControllerRole" ]] || {
  echo "The controller ServiceAccount is missing its IRSA role annotation." >&2
  exit 1
}

echo "Verified: EKS is active, 3 workers are Ready, and the IP-target ALB controller is ready."
