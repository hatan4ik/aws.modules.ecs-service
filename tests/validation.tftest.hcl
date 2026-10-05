mock_provider "aws" {}

variables {
  name        = "orders-api"
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  container_definitions = {
    app = {
      image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      port_mappings = [{ name = "http", container_port = 8080 }]
    }
  }

  security_group_egress_rules = {
    https = { from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
  }
}

run "rejects_name_that_would_overflow_iam_role_names" {
  command = plan
  variables {
    name = "this-service-name-is-fifty-five-characters-long-exactly"
  }
  expect_failures = [var.name]
}

run "rejects_uppercase_name" {
  command = plan
  variables {
    name = "Orders-API"
  }
  expect_failures = [var.name]
}

run "rejects_partial_cluster_arn" {
  command = plan
  variables {
    cluster_arn = "platform"
  }
  expect_failures = [var.cluster_arn]
}

run "rejects_unsupported_cpu_value" {
  command = plan
  variables {
    cpu = 300
  }
  expect_failures = [var.cpu]
}

run "rejects_invalid_cpu_memory_combination" {
  command = plan
  variables {
    cpu    = 256
    memory = 4096
  }
  expect_failures = [aws_ecs_task_definition.this]
}

run "rejects_windows_task_below_one_vcpu" {
  command = plan
  variables {
    operating_system_family = "WINDOWS_SERVER_2022_CORE"
    cpu                     = 512
    memory                  = 1024
  }
  expect_failures = [aws_ecs_task_definition.this]
}

run "rejects_unknown_operating_system_family" {
  command = plan
  variables {
    operating_system_family = "FREEBSD"
  }
  expect_failures = [var.operating_system_family]
}

run "rejects_ephemeral_storage_outside_fargate_range" {
  command = plan
  variables {
    ephemeral_storage_size_in_gib = 20
  }
  expect_failures = [var.ephemeral_storage_size_in_gib]
}

run "rejects_empty_container_map" {
  command = plan
  variables {
    container_definitions = {}
  }
  expect_failures = [var.container_definitions]
}

run "rejects_task_without_essential_container" {
  command = plan
  variables {
    container_definitions = {
      sidecar = {
        image     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/sidecar@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        essential = false
      }
    }
  }
  expect_failures = [var.container_definitions]
}

run "rejects_mutable_image_tag" {
  command = plan
  variables {
    container_definitions = {
      app = { image = "public.ecr.aws/nginx/nginx:1.27" }
    }
  }
  expect_failures = [aws_ecs_task_definition.this]
}

run "rejects_mount_point_to_undeclared_volume" {
  command = plan
  variables {
    container_definitions = {
      app = {
        image        = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        mount_points = [{ source_volume = "missing", container_path = "/data" }]
      }
    }
  }
  expect_failures = [aws_ecs_task_definition.this]
}

run "rejects_efs_iam_authorization_without_transit_encryption" {
  command = plan
  variables {
    volumes = {
      data = { efs = { file_system_id = "fs-0123456789abcdef0", transit_encryption = "DISABLED", authorization_config = { iam = "ENABLED" } } }
    }
  }
  expect_failures = [var.volumes]
}

run "rejects_unsupported_log_retention" {
  command = plan
  variables {
    cloudwatch_log_group_retention_in_days = 42
  }
  expect_failures = [var.cloudwatch_log_group_retention_in_days]
}

run "rejects_unknown_propagate_tags_value" {
  command = plan
  variables {
    propagate_tags = "CLUSTER"
  }
  expect_failures = [var.propagate_tags]
}

run "rejects_malformed_platform_version" {
  command = plan
  variables {
    platform_version = "latest"
  }
  expect_failures = [var.platform_version]
}

run "rejects_grace_period_without_load_balancer" {
  command = plan
  variables {
    health_check_grace_period_seconds = 60
  }
  expect_failures = [aws_ecs_service.this]
}

run "rejects_load_balancer_for_undeclared_container" {
  command = plan
  variables {
    load_balancers = {
      web = { target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders/0123456789abcdef", container_name = "web", container_port = 8080 }
    }
  }
  expect_failures = [aws_ecs_service.this]
}

run "rejects_service_connect_port_name_not_exposed_by_a_container" {
  command = plan
  variables {
    service_connect_configuration = {
      namespace = "arn:aws:servicediscovery:us-east-1:123456789012:namespace/ns-0123456789abcdef"
      services  = [{ port_name = "grpc" }]
    }
  }
  expect_failures = [aws_ecs_service.this]
}

run "rejects_non_fargate_capacity_provider" {
  command = plan
  variables {
    capacity_provider_strategy = {
      ec2 = { capacity_provider = "my-asg-provider" }
    }
  }
  expect_failures = [var.capacity_provider_strategy]
}

run "rejects_circuit_breaker_under_external_controller" {
  command = plan
  variables {
    deployment_controller_type = "EXTERNAL"
  }
  expect_failures = [aws_ecs_service.this]
}

run "rejects_desired_count_outside_autoscaling_bounds" {
  command = plan
  variables {
    desired_count = 1
    autoscaling   = { min_capacity = 2, max_capacity = 4 }
  }
  expect_failures = [aws_ecs_service.this]
}

run "rejects_service_without_any_security_group" {
  command = plan
  variables {
    create_security_group = false
    security_group_ids    = []
  }
  expect_failures = [aws_ecs_service.this]
}

run "rejects_empty_subnet_list" {
  command = plan
  variables {
    subnet_ids = []
  }
  expect_failures = [var.subnet_ids]
}

run "rejects_deployment_percentages_outside_range" {
  command = plan
  variables {
    deployment_maximum_percent = 50
  }
  expect_failures = [var.deployment_maximum_percent]
}

# deployment_configuration: each strategy must carry exactly its own
# traffic-shifting block, so mismatches fail at plan instead of at apply.

run "rejects_canary_strategy_without_canary_block" {
  command = plan
  variables {
    deployment_configuration = { strategy = "CANARY" }
  }
  expect_failures = [var.deployment_configuration]
}

run "rejects_canary_block_under_another_strategy" {
  command = plan
  variables {
    deployment_configuration = {
      strategy = "ROLLING"
      canary   = { canary_percent = 10 }
    }
  }
  expect_failures = [var.deployment_configuration]
}

run "rejects_linear_strategy_without_linear_block" {
  command = plan
  variables {
    deployment_configuration = { strategy = "LINEAR" }
  }
  expect_failures = [var.deployment_configuration]
}

run "rejects_linear_block_under_another_strategy" {
  command = plan
  variables {
    deployment_configuration = {
      strategy = "ROLLING"
      linear   = { step_percent = 20 }
    }
  }
  expect_failures = [var.deployment_configuration]
}

run "rejects_linear_block_under_canary_strategy" {
  command = plan
  variables {
    deployment_configuration = {
      strategy = "CANARY"
      canary   = { canary_percent = 10 }
      linear   = { step_percent = 20 }
    }
  }
  expect_failures = [var.deployment_configuration]
}

run "accepts_canary_strategy_with_canary_block" {
  command = plan
  variables {
    deployment_configuration = {
      strategy = "CANARY"
      canary   = { canary_percent = 10, canary_bake_time_in_minutes = 5 }
    }
  }
  assert {
    condition     = aws_ecs_service.this[0].deployment_configuration[0].strategy == "CANARY" && length(aws_ecs_service.this[0].deployment_configuration[0].canary_configuration) == 1
    error_message = "A CANARY strategy with its canary block must plan and render the canary configuration."
  }
}

run "accepts_linear_strategy_with_linear_block" {
  command = plan
  variables {
    deployment_configuration = {
      strategy = "LINEAR"
      linear   = { step_percent = 20 }
    }
  }
  assert {
    condition     = aws_ecs_service.this[0].deployment_configuration[0].strategy == "LINEAR" && length(aws_ecs_service.this[0].deployment_configuration[0].linear_configuration) == 1
    error_message = "A LINEAR strategy with its linear block must plan and render the linear configuration."
  }
}

run "rejects_blue_green_without_load_balancer_advanced_configuration" {
  command = plan
  variables {
    deployment_configuration = { strategy = "BLUE_GREEN" }
    load_balancers = {
      http = { target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders/0123456789abcdef", container_name = "app", container_port = 8080 }
    }
  }
  expect_failures = [aws_ecs_service.this]
}

run "rejects_blue_green_when_any_load_balancer_lacks_advanced_configuration" {
  command = plan
  variables {
    deployment_configuration = { strategy = "BLUE_GREEN" }
    load_balancers = {
      blue = {
        target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders-blue/0123456789abcdef"
        container_name   = "app"
        container_port   = 8080
        advanced_configuration = {
          alternate_target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders-green/0123456789abcdef"
          production_listener_rule   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/orders/0123456789abcdef/0123456789abcdef/0123456789abcdef"
          role_arn                   = "arn:aws:iam::123456789012:role/ecs-blue-green"
        }
      }
      admin = { target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders-admin/0123456789abcdef", container_name = "app", container_port = 8080 }
    }
  }
  expect_failures = [aws_ecs_service.this]
}

run "rejects_blue_green_without_advanced_configuration_on_ignore_task_definition_variant" {
  command = plan
  variables {
    ignore_task_definition_changes = true
    deployment_configuration       = { strategy = "BLUE_GREEN" }
    load_balancers = {
      http = { target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders/0123456789abcdef", container_name = "app", container_port = 8080 }
    }
  }
  expect_failures = [aws_ecs_service.ignore_task_definition]
}

run "rejects_malformed_vpc_id" {
  command = plan
  variables {
    vpc_id = "my-vpc"
  }
  expect_failures = [var.vpc_id]
}

run "rejects_log_group_kms_key_that_is_not_a_key_arn" {
  command = plan
  variables {
    cloudwatch_log_group_kms_key_id = "alias/logs"
  }
  expect_failures = [var.cloudwatch_log_group_kms_key_id]
}

run "accepts_log_group_kms_key_arn" {
  command = plan
  variables {
    cloudwatch_log_group_kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/0123abcd-01ab-23cd-45ef-0123456789ab"
  }
  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/0123abcd-01ab-23cd-45ef-0123456789ab"
    error_message = "A KMS key ARN must be accepted and passed to the log group."
  }
}

run "rejects_task_execution_role_name_over_iam_limit" {
  command = plan
  variables {
    task_execution_role_name = "an-execution-role-name-that-is-far-too-long-for-iam-to-ever-accept"
  }
  expect_failures = [var.task_execution_role_name]
}

run "rejects_task_role_name_over_iam_limit" {
  command = plan
  variables {
    task_role_name = "a-task-role-name-that-is-definitely-far-too-long-for-iam-to-accept"
  }
  expect_failures = [var.task_role_name]
}
