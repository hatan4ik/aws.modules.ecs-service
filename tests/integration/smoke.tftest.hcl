# Integration suite: real apply in the caller's own account.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow). Nothing is hard-coded: the setup module creates disposable
# prerequisites, the module is applied with desired_count = 0 so no task ever
# starts (no image pull, no egress), the results are asserted against the
# real API, and everything is destroyed at the end of the file.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "ecs-service-it"
  }
}

run "smoke" {
  variables {
    name        = run.setup.name
    cluster_arn = run.setup.cluster_arn
    vpc_id      = run.setup.vpc_id
    subnet_ids  = run.setup.private_subnet_ids
    tags        = run.setup.tags

    # Zero tasks: the task definition, roles, security group, log group, and
    # scalable target are all created for real without running a container.
    desired_count = 0

    container_definitions = {
      app = {
        # Registration does not validate the image; no task is started.
        image         = "public.ecr.aws/docker/library/busybox@sha256:0000000000000000000000000000000000000000000000000000000000000000"
        port_mappings = [{ name = "http", container_port = 8080 }]
        secrets       = {}
      }
    }

    security_group_egress_rules = {
      vpc_tls = { description = "TLS inside the fixture VPC", from_port = 443, to_port = 443, cidr_ipv4 = run.setup.vpc_cidr }
    }

    autoscaling = {
      min_capacity = 0
      max_capacity = 2
    }
  }

  assert {
    condition     = aws_ecs_service.this[0].desired_count == 0 && aws_ecs_service.this[0].launch_type == "FARGATE"
    error_message = "The service must exist on Fargate with zero desired tasks."
  }

  assert {
    condition     = output.name == run.setup.name && output.cluster_name == run.setup.cluster_name
    error_message = "Outputs must reflect the fixture cluster and service name."
  }

  assert {
    condition     = startswith(output.task_execution_role_arn, "arn:") && startswith(output.task_role_arn, "arn:")
    error_message = "Both IAM roles must have been created."
  }

  assert {
    condition     = output.security_group_id != null && output.cloudwatch_log_group_arn != null
    error_message = "The managed security group and log group must have been created."
  }

  assert {
    condition     = output.cloudwatch_log_group_name == "/aws/ecs/${run.setup.cluster_name}/${run.setup.name}"
    error_message = "The log group must follow /aws/ecs/<cluster>/<service>."
  }

  assert {
    condition     = output.autoscaling_target_resource_id == "service/${run.setup.cluster_name}/${run.setup.name}" && length(output.autoscaling_policy_arns) == 1
    error_message = "The scalable target and the default CPU policy must have been registered."
  }

  assert {
    condition     = output.task_definition_revision >= 1
    error_message = "A task definition revision must have been registered."
  }
}
