# Reusable KodeKloud EKS Playground

Terraform for creating a reusable KodeKloud AWS playground environment with:

- one EKS control plane
- three self-managed worker nodes
- dynamic default-VPC and public-subnet discovery
- required IAM and security-group resources
- AWS Load Balancer Controller using pod-IP targets

## 1. Configure a fresh playground

Export the credentials supplied by the new KodeKloud AWS playground:

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"

aws sts get-caller-identity
```

The identity command must return the new playground account before continuing.

## 2. Create the cluster

```bash
chmod +x deploy.sh destroy.sh verify.sh
./deploy.sh -auto-approve
./verify.sh
```

Terraform keeps separate state for every temporary AWS account under `.terraform-account/<account-id>/`.

## 3. Deploy the example application

```bash
kubectl apply -f examples/application.yaml
kubectl get ingress web -n example -w
```

When the `ADDRESS` column is populated:

```bash
ALB_DNS=$(kubectl get ingress web -n example \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl "http://${ALB_DNS}/hello"
```

ALB DNS propagation and target registration can take several minutes. The example routes `/hello` to nginx through an ALB URL rewrite.

## 4. Clean up

Destroy everything before the three-hour playground expires:

```bash
./destroy.sh
```

Expired credentials cannot delete resources. The destroy script removes ALB Ingress resources before uninstalling the controller to avoid orphaned load balancers.

This project follows the [KodeKloud self-managed EKS guide](https://github.com/kodekloudhub/certified-kubernetes-administrator-course/tree/master/managed-clusters/eks/console/docs).
