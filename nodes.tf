resource "tls_private_key" "nodes" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "nodes" {
  key_name   = "node-key-pair"
  public_key = tls_private_key.nodes.public_key_openssh
}

resource "local_sensitive_file" "node_private_key" {
  filename        = "${path.root}/node-key-pair.pem"
  content         = tls_private_key.nodes.private_key_pem
  file_permission = "0600"
}

resource "aws_cloudformation_stack" "nodes" {
  name         = "eks-cluster-stack"
  capabilities = ["CAPABILITY_IAM"]
  on_failure   = "DELETE"
  template_url = "https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2025-11-26/amazon-eks-nodegroup.yaml"

  parameters = {
    AuthenticationMode                  = "EKS API and ConfigMap"
    ClusterName                         = aws_eks_cluster.this.name
    ClusterControlPlaneSecurityGroup    = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
    ApiServerEndpoint                   = aws_eks_cluster.this.endpoint
    CertificateAuthorityData            = aws_eks_cluster.this.certificate_authority[0].data
    ServiceCidr                         = aws_eks_cluster.this.kubernetes_network_config[0].service_ipv4_cidr
    NodeGroupName                       = "eks-demo-node"
    NodeAutoScalingGroupMinSize         = tostring(var.node_count)
    NodeAutoScalingGroupDesiredCapacity = tostring(var.node_count)
    NodeAutoScalingGroupMaxSize         = tostring(var.node_count)
    NodeInstanceType                    = var.node_instance_type
    NodeImageIdSSMParam                 = "/aws/service/eks/optimized-ami/${aws_eks_cluster.this.version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
    NodeVolumeSize                      = tostring(var.node_volume_size)
    KeyName                             = aws_key_pair.nodes.key_name
    VpcId                               = data.aws_vpc.default.id
    Subnets                             = join(",", local.selected_subnet_ids)
  }

  timeout_in_minutes = 30

  depends_on = [local_sensitive_file.node_private_key]
}

# The current AWS node template creates its own access entry only for API-only
# authentication. KodeKloud requires API_AND_CONFIG_MAP, so create it explicitly.
resource "aws_eks_access_entry" "nodes" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_cloudformation_stack.nodes.outputs["NodeInstanceRole"]
  type          = "EC2_LINUX"
}

# The EKS API server must reach the controller's validating webhook on the nodes.
resource "aws_vpc_security_group_ingress_rule" "controller_webhook" {
  security_group_id            = aws_cloudformation_stack.nodes.outputs["NodeSecurityGroup"]
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  from_port                    = 9443
  to_port                      = 9443
  ip_protocol                  = "tcp"
  description                  = "EKS control plane to AWS Load Balancer Controller webhook"
}

