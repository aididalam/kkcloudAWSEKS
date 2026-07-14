locals {
  bidly_namespace                   = "bidly"
  bidly_auction_service_account     = "auction-s3"
  bidly_s3_config_map               = "bidly-s3"
  bidly_s3_bucket_name              = coalesce(var.bidly_s3_bucket_name, "bidly-auction-${data.aws_caller_identity.current.account_id}-${var.aws_region}")
  bidly_s3_public_base_url          = "https://${aws_s3_bucket.bidly.bucket}.s3.${var.aws_region}.amazonaws.com"
  bidly_auction_service_account_sub = "system:serviceaccount:${local.bidly_namespace}:${local.bidly_auction_service_account}"
  argocd_admin_password_bcrypt      = "$2a$10$lzmxF08dgFDDBCDhregzteKgNDt650XeV/NOG.ZsqJLqXmvjVqwmi"
}

resource "aws_s3_bucket" "bidly" {
  bucket        = local.bidly_s3_bucket_name
  force_destroy = true
}

resource "random_password" "bidly_mysql_root" {
  length  = 32
  special = false
}

resource "random_password" "bidly_auth_database" {
  length  = 32
  special = false
}

resource "random_password" "bidly_auction_database" {
  length  = 32
  special = false
}

resource "random_password" "bidly_jwt" {
  length  = 48
  special = false
}

resource "aws_s3_bucket_ownership_controls" "bidly" {
  bucket = aws_s3_bucket.bidly.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "bidly" {
  bucket = aws_s3_bucket.bidly.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_versioning" "bidly" {
  bucket = aws_s3_bucket.bidly.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bidly" {
  bucket = aws_s3_bucket.bidly.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "bidly" {
  bucket = aws_s3_bucket.bidly.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT"]
    allowed_origins = var.bidly_s3_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

data "aws_iam_policy_document" "bidly_public_read" {
  statement {
    sid       = "AllowPublicReadOfAuctionImages"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bidly.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "bidly_public_read" {
  bucket = aws_s3_bucket.bidly.id
  policy = data.aws_iam_policy_document.bidly_public_read.json

  depends_on = [aws_s3_bucket_public_access_block.bidly]
}

data "aws_iam_policy_document" "bidly_auction_assume_role" {
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
      values   = [local.bidly_auction_service_account_sub]
    }
  }
}

resource "aws_iam_role" "bidly_auction" {
  name               = "BidlyAuctionS3Role"
  assume_role_policy = data.aws_iam_policy_document.bidly_auction_assume_role.json
}

data "aws_iam_policy" "bidly_auction_s3" {
  arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BidlyAuctionBucketAccess"
}

resource "aws_iam_role_policy_attachment" "bidly_auction_s3" {
  role       = aws_iam_role.bidly_auction.name
  policy_arn = data.aws_iam_policy.bidly_auction_s3.arn
}

resource "kubernetes_namespace_v1" "bidly" {
  metadata {
    name = local.bidly_namespace
  }

  depends_on = [aws_eks_access_entry.nodes]
}

resource "kubernetes_secret_v1" "bidly_mysql" {
  metadata {
    name      = "bidly-mysql-secrets"
    namespace = kubernetes_namespace_v1.bidly.metadata[0].name
  }

  data = {
    "root-password"    = random_password.bidly_mysql_root.result
    "auth-password"    = random_password.bidly_auth_database.result
    "auction-password" = random_password.bidly_auction_database.result
  }
}

resource "kubernetes_secret_v1" "bidly_auth" {
  metadata {
    name      = "bidly-auth-secrets"
    namespace = kubernetes_namespace_v1.bidly.metadata[0].name
  }

  data = {
    "database-url" = "auth_user:${random_password.bidly_auth_database.result}@tcp(mysql:3306)/auth_db?parseTime=true&loc=UTC&charset=utf8mb4&collation=utf8mb4_unicode_ci"
    "jwt-secret"   = random_password.bidly_jwt.result
  }
}

resource "kubernetes_secret_v1" "bidly_auction" {
  metadata {
    name      = "bidly-auction-secrets"
    namespace = kubernetes_namespace_v1.bidly.metadata[0].name
  }

  data = {
    "database-url"          = "auction_user:${random_password.bidly_auction_database.result}@tcp(mysql:3306)/auction_db?parseTime=true&loc=UTC&charset=utf8mb4&collation=utf8mb4_unicode_ci"
    "jwt-secret"            = random_password.bidly_jwt.result
    "aws-region"            = var.aws_region
    "aws-access-key-id"     = ""
    "aws-secret-access-key" = ""
    "s3-bucket"             = aws_s3_bucket.bidly.bucket
    "s3-endpoint"           = ""
    "s3-public-base-url"    = local.bidly_s3_public_base_url
  }
}

resource "kubernetes_service_account_v1" "bidly_auction" {
  metadata {
    name      = local.bidly_auction_service_account
    namespace = kubernetes_namespace_v1.bidly.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.bidly_auction.arn
    }
  }
}

resource "kubernetes_config_map_v1" "bidly_s3" {
  metadata {
    name      = local.bidly_s3_config_map
    namespace = kubernetes_namespace_v1.bidly.metadata[0].name
  }

  data = {
    "aws-region"         = var.aws_region
    "s3-bucket"          = aws_s3_bucket.bidly.bucket
    "s3-public-base-url" = local.bidly_s3_public_base_url
    "s3-use-path-style"  = "false"
    "S3_PUBLIC_BASE_URL" = local.bidly_s3_public_base_url
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.argocd_namespace
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 1200
  wait            = true

  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = "true"
        }
        secret = {
          argocdServerAdminPassword      = local.argocd_admin_password_bcrypt
          argocdServerAdminPasswordMtime = "2026-07-13T00:00:00Z"
        }
      }
    })
  ]

  depends_on = [aws_eks_access_entry.nodes]
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd"
    namespace = helm_release.argocd.namespace
    annotations = {
      "alb.ingress.kubernetes.io/backend-protocol"     = "HTTP"
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/healthz"
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/load-balancer-name"   = "argocd"
      "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
      "alb.ingress.kubernetes.io/success-codes"        = "200"
      "alb.ingress.kubernetes.io/target-type"          = "ip"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"

              port {
                name = "http"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    helm_release.controller,
  ]
}
