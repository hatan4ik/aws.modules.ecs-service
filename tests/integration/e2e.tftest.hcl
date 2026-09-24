# End-to-end suite: a real task must reach steady state in the caller's own
# account. The setup module adds public subnets and an internet gateway so the
# task can pull a public image without a NAT gateway; the service assigns a
# public IP to the task ENI for that reason only. Costs a few minutes of one
# Fargate task. Everything is destroyed at the end of the file.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/e2e.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix    = "ecs-service-e2e"
    public_subnets = true
  }
}

run "service_reaches_steady_state" {
  variables {
    name             = run.setup.name
    cluster_arn      = run.setup.cluster_arn
    vpc_id           = run.setup.vpc_id
    subnet_ids       = run.setup.public_subnet_ids
    assign_public_ip = true
    tags             = run.setup.tags

    desired_count         = 1
    wait_for_steady_state = true
    timeouts              = { create = "15m", update = "15m", delete = "15m" }

    # A pinned public tag is used here because the digest of a public image
    # changes on every upstream rebuild; production callers keep the default.
    require_image_digest = false

    container_definitions = {
      web = {
        image         = "public.ecr.aws/docker/library/nginx:1.27-alpine"
        port_mappings = [{ name = "http", container_port = 80 }]
        # The stock nginx image writes to /var/cache/nginx and /var/run.
        readonly_root_filesystem = false
        health_check = {
          command = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/ || exit 1"]
        }
      }
    }

    security_group_egress_rules = {
      https = { description = "Image layers from ECR Public", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
      dns   = { description = "VPC resolver", from_port = 53, to_port = 53, ip_protocol = "udp", cidr_ipv4 = run.setup.vpc_cidr }
    }
  }

  assert {
    condition     = aws_ecs_service.this[0].desired_count == 1 && aws_ecs_service.this[0].wait_for_steady_state == true
    error_message = "The service must have waited for one task to reach steady state."
  }

  assert {
    condition     = aws_ecs_service.this[0].network_configuration[0].assign_public_ip == true
    error_message = "The end-to-end task must have a public IP to pull without NAT."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.command[0] == "CMD-SHELL"
    error_message = "The container health check must be registered."
  }
}
