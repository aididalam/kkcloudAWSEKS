# 03 Istio Troubleshooting

| Problem | Solution |
|---|---|
| Older tutorials used unavailable `istioctl profile list` or `verify-install` commands. | Install with `istioctl install --set profile=demo -y`; verify with `istioctl version`, `proxy-status`, and `analyze`. |
| The `bidly` namespace was labeled but Pods had no sidecar. | Install Istio first, label the namespace, then restart every Bidly Deployment. |
| Kiali initially showed `0/1`. | The Pod was running but not Ready; wait for `kubectl rollout status deployment/kiali -n istio-system`. |
| Kiali reported 100% inbound failures for Auth and Auction. | Add `/healthz` endpoints and configure ALB health checks to use `/healthz` instead of `/`. |
| Kiali showed `unknown` and `PassthroughCluster`. | ALB is outside the mesh and RDS is external; this is expected unless traffic uses an Istio Gateway and RDS has a ServiceEntry. |
| Pods were `2/2`, but `istio-proxy` was not in the normal container list. | Kubernetes native sidecars place it in `initContainers` with `restartPolicy: Always`; check both lists. |
| The temporary API verifier could receive an unwanted sidecar. | Set `sidecar.istio.io/inject: "false"` on that Pod. |
| Istio gateway load balancers could survive cluster deletion. | Delete `istio-ingressgateway` before running `terraform destroy`. |
