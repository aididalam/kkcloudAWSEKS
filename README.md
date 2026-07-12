# Reusable KodeKloud EKS Playground

Terraform for creating a reusable KodeKloud AWS playground environment with:

- one EKS control plane
- three self-managed worker nodes
- dynamic default-VPC and public-subnet discovery
- required IAM and security-group resources
- AWS Load Balancer Controller using pod-IP targets

## 1. Configure a fresh playground

1. Sign in to the AWS Console with the username and password supplied by KodeKloud.
2. Open **IAM → Users → your playground user → Security credentials**.
3. Under **Access keys**, create an access key for CLI use and copy its access key ID and secret access key.
4. Clear credentials exported by an older playground. Environment variables override credentials saved by `aws configure`, and a stale session token causes `InvalidClientTokenId`:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
unset AWS_SECURITY_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE
```

5. Configure the AWS CLI with the newly created access key:

```bash
aws configure
```

Enter:

```text
AWS Access Key ID: <new access key ID>
AWS Secret Access Key: <new secret access key>
Default region name: us-east-1
Default output format: json
```

6. Verify the configured identity:

```bash
aws sts get-caller-identity
```

The identity command must return the new playground account and KodeKloud IAM user before continuing.

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
./destroy.sh -auto-approve
```

Omit `-auto-approve` if you want the script and Terraform confirmation prompts.

Expired credentials cannot delete resources. The destroy script removes ALB Ingress resources before uninstalling the controller to avoid orphaned load balancers. KodeKloud denies direct deletion of the EKS access entry, so the script safely removes it from Terraform state and cluster deletion removes it automatically. KodeKloud also denies deleting the controller IAM policy; `deploy.sh` creates or reuses it as a playground bootstrap resource, and it disappears when KodeKloud reclaims the temporary account.

This project follows the [KodeKloud self-managed EKS guide](https://github.com/kodekloudhub/certified-kubernetes-administrator-course/tree/master/managed-clusters/eks/console/docs).
