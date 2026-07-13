output "aws_account_id" {
  description = "AWS account selected by the current credentials."
  value       = data.aws_caller_identity.current.account_id
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "aws_region" {
  value = var.aws_region
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "worker_node_count" {
  value = var.node_count
}

output "selected_subnets" {
  value = {
    for availability_zone in local.selected_availability_zones :
    availability_zone => local.eligible_subnets_by_az[availability_zone]
  }
}

output "node_security_group_id" {
  value = aws_cloudformation_stack.nodes.outputs["NodeSecurityGroup"]
}

output "load_balancer_controller_role_arn" {
  value = aws_iam_role.controller.arn
}

output "load_balancer_controller_version" {
  value = var.load_balancer_controller_version
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "application_ingress_requirements" {
  value = "Use ingressClassName: alb. The controller defaults to target-type ip, so a ClusterIP Service is sufficient."
}

output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "argocd_port_forward" {
  value = "kubectl -n ${helm_release.argocd.namespace} port-forward svc/argocd-server 8080:443"
}

output "argocd_admin_username" {
  value = "admin"
}

output "argocd_admin_password" {
  value     = "password"
  sensitive = true
}

output "argocd_alb_address_command" {
  value = "kubectl -n ${helm_release.argocd.namespace} get ingress argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "bidly_s3_bucket" {
  value = aws_s3_bucket.bidly.bucket
}

output "bidly_s3_public_base_url" {
  value = local.bidly_s3_public_base_url
}

output "bidly_auction_s3_role_arn" {
  value = aws_iam_role.bidly_auction.arn
}

output "bidly_auction_service_account" {
  value = "${kubernetes_namespace_v1.bidly.metadata[0].name}/${kubernetes_service_account_v1.bidly_auction.metadata[0].name}"
}

output "bidly_s3_config_map" {
  value = "${kubernetes_namespace_v1.bidly.metadata[0].name}/${kubernetes_config_map_v1.bidly_s3.metadata[0].name}"
}
