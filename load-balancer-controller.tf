locals {
  oidc_issuer                = aws_eks_cluster.this.identity[0].oidc[0].issuer
  oidc_host                  = replace(local.oidc_issuer, "https://", "")
  controller_namespace       = "kube-system"
  controller_service_account = "aws-load-balancer-controller"
}

data "tls_certificate" "eks_oidc" {
  url = local.oidc_issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = local.oidc_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[length(data.tls_certificate.eks_oidc.certificates) - 1].sha1_fingerprint]
}

data "aws_iam_policy_document" "controller_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${local.controller_namespace}:${local.controller_service_account}"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "AmazonEKSLoadBalancerControllerRole"
  assume_role_policy = data.aws_iam_policy_document.controller_assume_role.json
}

data "aws_iam_policy" "controller" {
  arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AWSLoadBalancerControllerIAMPolicy"
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = data.aws_iam_policy.controller.arn
}

resource "helm_release" "controller" {
  name       = "aws-load-balancer-controller"
  namespace  = local.controller_namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.load_balancer_controller_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 1200
  wait            = true

  set = [
    {
      name  = "clusterName"
      value = aws_eks_cluster.this.name
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = data.aws_vpc.default.id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = local.controller_service_account
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.controller.arn
    },
    # New Ingress resources use pod IPs unless explicitly overridden.
    {
      name  = "defaultTargetType"
      value = "ip"
    },
  ]

  depends_on = [
    aws_eks_access_entry.nodes,
    aws_iam_role_policy_attachment.controller,
    aws_vpc_security_group_ingress_rule.controller_webhook,
  ]
}
