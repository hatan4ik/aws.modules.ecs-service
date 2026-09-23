mock_provider "aws" {}

variables {
  name        = "orders-api"
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  tags        = { Environment = "test", Owner = "platform" }

  container_definitions = {
    app = {
      image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      port_mappings = [{ name = "http", container_port = 8080 }]
    }
  }

  security_group_egress_rules = {
    https = { description = "TLS egress", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
  }
}

run "service_is_private_fargate_with_safe_deployment_defaults" {
  command = plan

  assert {
    condition     = aws_ecs_service.this[0].name == "orders-api" && aws_ecs_service.this[0].cluster == "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
    error_message = "The service must use the declared name and cluster."
  }

  assert {
    condition     = aws_ecs_service.this[0].launch_type == "FARGATE" && aws_ecs_service.this[0].platform_version == "LATEST" && aws_ecs_service.this[0].scheduling_strategy == "REPLICA"
    error_message = "The service must launch on Fargate with the LATEST platform version."
  }

  assert {
    condition     = aws_ecs_service.this[0].network_configuration[0].assign_public_ip == false && length(aws_ecs_service.this[0].network_configuration[0].subnets) == 2 && length(aws_ecs_service.this[0].network_configuration[0].security_groups) == 1
    error_message = "Tasks must have no public IP, use the declared subnets, and carry exactly the managed security group."
  }

  assert {
    condition     = aws_ecs_service.this[0].deployment_circuit_breaker[0].enable == true && aws_ecs_service.this[0].deployment_circuit_breaker[0].rollback == true
    error_message = "The deployment circuit breaker with rollback must be on by default."
  }

  assert {
    condition     = aws_ecs_service.this[0].deployment_minimum_healthy_percent == 100 && aws_ecs_service.this[0].deployment_maximum_percent == 200 && aws_ecs_service.this[0].deployment_controller[0].type == "ECS"
    error_message = "Rolling deployments must default to 100/200 percent under the ECS controller."
  }

  assert {
    condition     = aws_ecs_service.this[0].availability_zone_rebalancing == "ENABLED" && aws_ecs_service.this[0].enable_ecs_managed_tags == true && aws_ecs_service.this[0].propagate_tags == "SERVICE" && aws_ecs_service.this[0].enable_execute_command == false
    error_message = "AZ rebalancing and managed tags must be on; ECS Exec must be off by default."
  }

  assert {
    condition     = aws_ecs_service.this[0].desired_count == 1 && aws_ecs_service.this[0].wait_for_steady_state == false && aws_ecs_service.this[0].force_new_deployment == false
    error_message = "Service defaults must not block applies or force deployments."
  }

  assert {
    condition     = length(aws_ecs_service.ignore_task_definition) == 0 && length(aws_ecs_service.this[0].load_balancer) == 0 && length(aws_ecs_service.this[0].capacity_provider_strategy) == 0
    error_message = "No optional integrations may render unless declared."
  }

  assert {
    condition     = aws_ecs_service.this[0].tags["Name"] == "orders-api" && aws_ecs_service.this[0].tags["Owner"] == "platform"
    error_message = "Caller tags must be preserved and a Name tag added."
  }
}

run "task_definition_targets_fargate_linux" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this.family == "orders-api" && aws_ecs_task_definition.this.network_mode == "awsvpc" && contains(aws_ecs_task_definition.this.requires_compatibilities, "FARGATE")
    error_message = "The task definition must be an awsvpc Fargate family named after the service."
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "256" && aws_ecs_task_definition.this.memory == "512" && aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "X86_64" && aws_ecs_task_definition.this.runtime_platform[0].operating_system_family == "LINUX"
    error_message = "The smallest Linux x86_64 Fargate size must be the default."
  }

  assert {
    condition     = length(aws_ecs_task_definition.this.ephemeral_storage) == 0 && length(aws_ecs_task_definition.this.volume) == 0 && aws_ecs_task_definition.this.pid_mode == null
    error_message = "Optional task features must not render unless declared."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].name == "app" && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].readonlyRootFilesystem == true && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].essential == true
    error_message = "The container must render read-only and essential."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.logDriver == "awslogs" && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/aws/ecs/platform/orders-api" && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-region"] == "us-east-1" && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-stream-prefix"] == "orders-api"
    error_message = "Containers without their own log configuration must log to the managed group in the cluster region."
  }
}

run "log_group_and_roles_use_derived_names" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "/aws/ecs/platform/orders-api" && aws_cloudwatch_log_group.this[0].retention_in_days == 365 && aws_cloudwatch_log_group.this[0].log_group_class == "STANDARD"
    error_message = "The log group must follow /aws/ecs/<cluster>/<service> with one-year retention."
  }

  assert {
    condition     = output.task_execution_role_name == "orders-api-execution" && output.task_role_name == "orders-api-task"
    error_message = "Role names must derive from the service name."
  }

  assert {
    condition     = output.cloudwatch_log_group_name == "/aws/ecs/platform/orders-api" && output.cluster_name == "platform" && output.name == "orders-api"
    error_message = "Outputs must expose derived identifiers."
  }

  assert {
    condition     = output.autoscaling_target_resource_id == null && length(output.autoscaling_policy_arns) == 0
    error_message = "Autoscaling outputs must be empty when autoscaling is not declared."
  }

  assert {
    condition     = length(output.container_definitions) == 1 && output.task_definition_family == "orders-api"
    error_message = "Rendered container definitions and the family must be exposed."
  }
}

run "warns_when_managed_security_group_has_no_egress" {
  command = plan

  variables {
    security_group_egress_rules = {}
  }

  expect_failures = [check.security_group_egress]
}

run "warns_when_service_spans_one_availability_zone" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [check.multi_az]
}
