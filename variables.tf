variable "aws_region" {
  description = "AWS region used by the KodeKloud playground."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name used by the KodeKloud guide."
  type        = string
  default     = "demo-eks"
}

variable "kubernetes_version" {
  description = "Optional EKS Kubernetes version. Null selects the current account default."
  type        = string
  default     = null
  nullable    = true
}

variable "service_ipv4_cidr" {
  description = "Service CIDR for the cluster."
  type        = string
  default     = "10.100.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.service_ipv4_cidr))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR."
  }
}

variable "subnet_count" {
  description = "Number of default-VPC public subnets to use. KodeKloud permits two or three."
  type        = number
  default     = 3

  validation {
    condition     = contains([2, 3], var.subnet_count)
    error_message = "subnet_count must be 2 or 3."
  }
}

variable "excluded_availability_zones" {
  description = "Availability Zones excluded by the KodeKloud guide."
  type        = set(string)
  default     = ["us-east-1e"]
}

variable "node_instance_type" {
  description = "EC2 type for each self-managed worker."
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  description = "Number of self-managed worker nodes."
  type        = number
  default     = 3

  validation {
    condition     = var.node_count == 3
    error_message = "This KodeKloud-compatible project intentionally requires exactly 3 nodes."
  }
}

variable "node_volume_size" {
  description = "Worker root disk size in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.node_volume_size >= 20
    error_message = "node_volume_size must be at least 20 GiB."
  }
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to access the public EKS API. The playground default is open."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "load_balancer_controller_version" {
  description = "AWS Load Balancer Controller Helm chart and application version."
  type        = string
  default     = "3.4.1"
}

variable "tags" {
  description = "Tags added to Terraform-managed AWS resources."
  type        = map(string)
  default = {
    Project   = "kodekloud-eks-playground"
    ManagedBy = "Terraform"
  }
}

