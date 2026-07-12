terraform {
  required_version = ">= 1.6.0"

  # deploy.sh supplies an account-specific path during terraform init.
  backend "local" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# KodeKloud permits creating the controller policy but denies iam:TagPolicy.
# Use this provider only for that policy so provider-level default tags are not
# sent as part of the CreatePolicy request.
provider "aws" {
  alias  = "untagged"
  region = var.aws_region
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        aws_eks_cluster.this.name,
        "--region",
        var.aws_region,
      ]
    }
  }
}
