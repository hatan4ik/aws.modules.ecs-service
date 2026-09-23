provider "aws" {
  region = var.region
}

module "service" {
  source = "../../"

  name        = "orders-api"
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  container_definitions = {
    app = {
      image         = var.image
      port_mappings = [{ container_port = 8080 }]
    }
  }

  # The managed security group starts with no rules at all. Tasks in subnets
  # that route through NAT need TLS egress to pull the image and reach AWS APIs.
  security_group_egress_rules = {
    https = {
      description = "TLS for image pulls and dependencies"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.egress_cidr
    }
  }
}
