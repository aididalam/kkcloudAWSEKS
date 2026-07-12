data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnet" "candidate" {
  for_each = toset(data.aws_subnets.default_public.ids)
  id       = each.value
}

locals {
  eligible_subnets_by_az = {
    for subnet_id, subnet in data.aws_subnet.candidate :
    subnet.availability_zone => subnet_id
    if !contains(var.excluded_availability_zones, subnet.availability_zone)
  }

  eligible_availability_zones = sort(keys(local.eligible_subnets_by_az))
  selected_availability_zones = slice(
    local.eligible_availability_zones,
    0,
    min(var.subnet_count, length(local.eligible_availability_zones)),
  )
  selected_subnet_ids = [
    for availability_zone in local.selected_availability_zones :
    local.eligible_subnets_by_az[availability_zone]
  ]
}

resource "aws_ec2_tag" "public_load_balancer_subnet" {
  for_each    = toset(local.selected_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "cluster_shared_subnet" {
  for_each    = toset(local.selected_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

