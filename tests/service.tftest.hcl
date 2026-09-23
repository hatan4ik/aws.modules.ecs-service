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

run "attaches_load_balancer_with_grace_period" {
  command = plan

  variables {
    health_check_grace_period_seconds = 90
    load_balancers = {
      http = { target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders/0123456789abcdef", container_name = "app", container_port = 8080 }
    }
  }

  assert {
    condition     = length(aws_ecs_service.this[0].load_balancer) == 1 && aws_ecs_service.this[0].health_check_grace_period_seconds == 90
    error_message = "Load balancer attachment and grace period must render together."
  }
}

run "uses_capacity_providers_instead_of_launch_type" {
  command = plan

  variables {
    capacity_provider_strategy = {
      spot      = { capacity_provider = "FARGATE_SPOT", weight = 3 }
      on_demand = { capacity_provider = "FARGATE", weight = 1, base = 1 }
    }
  }

  assert {
    condition     = local.launch_type == null && length(aws_ecs_service.this[0].capacity_provider_strategy) == 2
    error_message = "A capacity provider strategy must replace launch_type."
  }
}

run "selects_ignore_task_definition_variant_for_external_deployers" {
  command = plan

  variables {
    ignore_task_definition_changes = true
  }

  assert {
    condition     = length(aws_ecs_service.this) == 0 && length(aws_ecs_service.ignore_task_definition) == 1 && aws_ecs_service.ignore_task_definition[0].name == "orders-api"
    error_message = "Only the ignore-task-definition service variant may exist when requested."
  }

  assert {
    condition     = output.name == "orders-api"
    error_message = "Outputs must resolve from whichever service variant exists."
  }
}

run "renders_blue_green_deployment_and_alarms" {
  command = plan

  variables {
    deployment_configuration = {
      strategy             = "BLUE_GREEN"
      bake_time_in_minutes = 10
      lifecycle_hooks = {
        pre_scale_up = { hook_target_arn = "arn:aws:lambda:us-east-1:123456789012:function:validate", role_arn = "arn:aws:iam::123456789012:role/ecs-hooks", lifecycle_stages = ["PRE_SCALE_UP"] }
      }
    }
    load_balancers = {
      http = {
        target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders-blue/0123456789abcdef"
        container_name   = "app"
        container_port   = 8080
        advanced_configuration = {
          alternate_target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/orders-green/0123456789abcdef"
          production_listener_rule   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/orders/0123456789abcdef/0123456789abcdef/0123456789abcdef"
          role_arn                   = "arn:aws:iam::123456789012:role/ecs-blue-green"
        }
      }
    }
    alarms = { alarm_names = ["orders-5xx"] }
  }

  assert {
    condition     = aws_ecs_service.this[0].deployment_configuration[0].strategy == "BLUE_GREEN" && tonumber(aws_ecs_service.this[0].deployment_configuration[0].bake_time_in_minutes) == 10 && length(aws_ecs_service.this[0].deployment_configuration[0].lifecycle_hook) == 1
    error_message = "Blue/green deployment configuration must render with its lifecycle hooks."
  }

  assert {
    condition     = aws_ecs_service.this[0].alarms[0].enable == true && aws_ecs_service.this[0].alarms[0].rollback == true && contains(aws_ecs_service.this[0].alarms[0].alarm_names, "orders-5xx")
    error_message = "Deployment alarms must default to enabled with rollback."
  }
}

run "renders_service_connect_and_registries" {
  command = plan

  variables {
    service_connect_configuration = {
      namespace = "arn:aws:servicediscovery:us-east-1:123456789012:namespace/ns-0123456789abcdef"
      services = [{
        port_name      = "http"
        discovery_name = "orders"
        client_alias   = { port = 80, dns_name = "orders.internal" }
        timeout        = { per_request_timeout_seconds = 15 }
      }]
    }
    service_registries = { registry_arn = "arn:aws:servicediscovery:us-east-1:123456789012:service/srv-0123456789abcdef", container_name = "app", container_port = 8080 }
  }

  assert {
    condition     = aws_ecs_service.this[0].service_connect_configuration[0].enabled == true && aws_ecs_service.this[0].service_connect_configuration[0].service[0].client_alias[0].dns_name == "orders.internal" && aws_ecs_service.this[0].service_connect_configuration[0].service[0].timeout[0].per_request_timeout_seconds == 15
    error_message = "Service Connect services must render aliases and timeouts."
  }

  assert {
    condition     = aws_ecs_service.this[0].service_registries[0].container_port == 8080
    error_message = "Cloud Map registries must render."
  }
}

run "renders_task_volumes_and_ephemeral_storage" {
  command = plan

  variables {
    ephemeral_storage_size_in_gib = 50
    pid_mode                      = "task"
    cpu_architecture              = "ARM64"
    # configure_at_launch is provider-computed when null, which would make the
    # volume set unknown at plan time; pin it so the assertions can evaluate.
    volumes = {
      data  = { configure_at_launch = false, efs = { file_system_id = "fs-0123456789abcdef0", authorization_config = { access_point_id = "fsap-0123456789abcdef0" } } }
      cache = { configure_at_launch = false }
    }
    container_definitions = {
      app = {
        image        = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        mount_points = [{ source_volume = "data", container_path = "/data" }, { source_volume = "cache", container_path = "/cache" }]
      }
    }
  }

  assert {
    condition     = aws_ecs_task_definition.this.ephemeral_storage[0].size_in_gib == 50 && aws_ecs_task_definition.this.pid_mode == "task" && aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "ARM64"
    error_message = "Task-level storage, pid mode, and architecture must pass through."
  }

  assert {
    condition     = length(aws_ecs_task_definition.this.volume) == 2 && length([for volume in aws_ecs_task_definition.this.volume : volume if volume.name == "data" && (length(volume.efs_volume_configuration) == 1 ? volume.efs_volume_configuration[0].transit_encryption == "ENABLED" : false)]) == 1 && length([for volume in aws_ecs_task_definition.this.volume : volume if volume.name == "cache" && length(volume.efs_volume_configuration) == 0]) == 1
    error_message = "EFS volumes must default to encrypted transit; bind volumes must render without configuration."
  }
}

run "applies_timeouts_and_deployment_tuning" {
  command = plan

  variables {
    timeouts                           = { create = "20m", update = "20m" }
    deployment_minimum_healthy_percent = 50
    deployment_maximum_percent         = 150
    deployment_circuit_breaker         = { enable = true, rollback = false }
    force_new_deployment               = true
    wait_for_steady_state              = true
    platform_version                   = "1.4.0"
    propagate_tags                     = "TASK_DEFINITION"
  }

  assert {
    condition     = aws_ecs_service.this[0].timeouts.create == "20m" && aws_ecs_service.this[0].deployment_minimum_healthy_percent == 50 && aws_ecs_service.this[0].deployment_maximum_percent == 150 && aws_ecs_service.this[0].deployment_circuit_breaker[0].rollback == false
    error_message = "Deployment tuning and timeouts must pass through."
  }

  assert {
    condition     = aws_ecs_service.this[0].force_new_deployment == true && aws_ecs_service.this[0].wait_for_steady_state == true && aws_ecs_service.this[0].platform_version == "1.4.0" && aws_ecs_service.this[0].propagate_tags == "TASK_DEFINITION"
    error_message = "Service behaviour flags must pass through."
  }
}
