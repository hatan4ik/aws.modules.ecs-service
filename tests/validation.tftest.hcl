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
