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
