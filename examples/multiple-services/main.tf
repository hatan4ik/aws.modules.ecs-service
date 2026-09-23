provider "aws" {
  region = var.region
}

# One module call is one service. A fleet is a for_each over the module block,
# so each service keeps its own plan, its own validation errors, and its own
# lifecycle while sharing the cluster and network.
module "service" {
  source   = "../../"
  for_each = var.services

  name        = "${var.name_prefix}-${each.key}"
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids
  tags        = merge(var.tags, { Service = each.key })

  cpu           = each.value.cpu
  memory        = each.value.memory
  desired_count = each.value.desired_count

  container_definitions = {
    app = {
      image         = each.value.image
      port_mappings = [{ name = "http", container_port = each.value.container_port }]
      environment   = merge({ HTTP_PORT = tostring(each.value.container_port) }, each.value.environment)
    }
  }

  security_group_egress_rules = {
    vpc_tls = {
      description = "TLS to VPC endpoints and internal services"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.vpc_cidr
    }
  }

  autoscaling = each.value.autoscaling
}
