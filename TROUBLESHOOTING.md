# 02 Deployment Troubleshooting

| Problem | Solution |
|---|---|
| KodeKloud returned `iam:PutRolePolicy` 403. | Create/reuse scoped managed IAM policies, read them as Terraform data sources, and attach them to the roles. |
| VS Code reported unexpected Helm `set` or `kubernetes` blocks. | Pin Helm provider `~> 3.2` and use its list/object schema. |
| Argo CD login redirected back to the login page over HTTP ALB. | Enable `server.insecure`, then use HTTP for the ALB backend and health check. |
| Auction returned an internal error when creating S3 presigned URLs. | Use service account `auction-s3` and make the IRSA trust subject match it exactly. |
| Product image URLs used `localhost:9000`. | Provide the real S3 URL through `S3_PUBLIC_BASE_URL` in the `bidly-s3` ConfigMap. |
| MySQL Pod storage and credentials became inconsistent after restarts. | Use private Multi-AZ RDS and inject one generated `DATABASE_URL` through Kubernetes Secrets. |
| `kubectl run` rejected `--interactive`. | Use the supported `--stdin` flag for the API verifier Pod. |
| Argo CD or load balancers could survive teardown. | Delete the Bidly Application, ALB Ingresses, and Istio gateway Service before `terraform destroy`. |
