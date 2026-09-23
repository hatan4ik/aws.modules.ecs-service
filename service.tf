# Terraform cannot make lifecycle.ignore_changes conditional, so two service
# resources exist and exactly one is created. Keep their bodies identical;
# only the ignore_changes list differs.

resource "aws_ecs_service" "this" {
  count = var.ignore_task_definition_changes ? 0 : 1

  name                               = var.name
  cluster                            = var.cluster_arn
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = local.launch_type
  platform_version                   = var.platform_version
  scheduling_strategy                = "REPLICA"
  availability_zone_rebalancing      = var.availability_zone_rebalancing
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = var.enable_execute_command
  enable_ecs_managed_tags            = var.enable_ecs_managed_tags
  propagate_tags                     = var.propagate_tags
  force_new_deployment               = var.force_new_deployment
  force_delete                       = var.force_delete
  wait_for_steady_state              = var.wait_for_steady_state

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy

    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  deployment_controller {
    type = var.deployment_controller_type
  }

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_controller_type == "ECS" ? [var.deployment_circuit_breaker] : []

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "deployment_configuration" {
    for_each = var.deployment_configuration == null ? [] : [var.deployment_configuration]

    content {
      strategy             = deployment_configuration.value.strategy
      bake_time_in_minutes = deployment_configuration.value.bake_time_in_minutes

      dynamic "canary_configuration" {
        for_each = deployment_configuration.value.canary == null ? [] : [deployment_configuration.value.canary]

        content {
          canary_percent              = canary_configuration.value.canary_percent
          canary_bake_time_in_minutes = canary_configuration.value.canary_bake_time_in_minutes
        }
      }

      dynamic "linear_configuration" {
        for_each = deployment_configuration.value.linear == null ? [] : [deployment_configuration.value.linear]

        content {
          step_percent              = linear_configuration.value.step_percent
          step_bake_time_in_minutes = linear_configuration.value.step_bake_time_in_minutes
        }
      }

      dynamic "lifecycle_hook" {
        for_each = deployment_configuration.value.lifecycle_hooks

        content {
          hook_target_arn  = lifecycle_hook.value.hook_target_arn
          role_arn         = lifecycle_hook.value.role_arn
          lifecycle_stages = lifecycle_hook.value.lifecycle_stages
          target_type      = lifecycle_hook.value.target_type
          hook_details     = lifecycle_hook.value.hook_details

          dynamic "timeout_configuration" {
            for_each = lifecycle_hook.value.timeout == null ? [] : [lifecycle_hook.value.timeout]

            content {
              action             = timeout_configuration.value.action
              timeout_in_minutes = timeout_configuration.value.timeout_in_minutes
            }
          }
        }
      }
    }
  }

  dynamic "alarms" {
    for_each = var.alarms == null ? [] : [var.alarms]

    content {
      alarm_names = alarms.value.alarm_names
      enable      = alarms.value.enable
      rollback    = alarms.value.rollback
    }
  }

  network_configuration {
    assign_public_ip = var.assign_public_ip
    security_groups  = local.security_group_ids
    subnets          = var.subnet_ids
  }

  dynamic "load_balancer" {
    for_each = var.load_balancers

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port

      dynamic "advanced_configuration" {
        for_each = load_balancer.value.advanced_configuration == null ? [] : [load_balancer.value.advanced_configuration]

        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule
          role_arn                   = advanced_configuration.value.role_arn
          test_listener_rule         = advanced_configuration.value.test_listener_rule
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = var.service_registries == null ? [] : [var.service_registries]

    content {
      registry_arn   = service_registries.value.registry_arn
      port           = service_registries.value.port
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
    }
  }

  dynamic "service_connect_configuration" {
    for_each = var.service_connect_configuration == null ? [] : [var.service_connect_configuration]

    content {
      enabled   = service_connect_configuration.value.enabled
      namespace = service_connect_configuration.value.namespace

      dynamic "log_configuration" {
        for_each = service_connect_configuration.value.log_configuration == null ? [] : [service_connect_configuration.value.log_configuration]

        content {
          log_driver = log_configuration.value.log_driver
          options    = log_configuration.value.options

          dynamic "secret_option" {
            for_each = log_configuration.value.secret_options

            content {
              name       = secret_option.value.name
              value_from = secret_option.value.value_from
            }
          }
        }
      }

      dynamic "service" {
        for_each = service_connect_configuration.value.services

        content {
          port_name             = service.value.port_name
          discovery_name        = service.value.discovery_name
          ingress_port_override = service.value.ingress_port_override

          dynamic "client_alias" {
            for_each = service.value.client_alias == null ? [] : [service.value.client_alias]

            content {
              port     = client_alias.value.port
              dns_name = client_alias.value.dns_name
            }
          }

          dynamic "timeout" {
            for_each = service.value.timeout == null ? [] : [service.value.timeout]

            content {
              idle_timeout_seconds        = timeout.value.idle_timeout_seconds
              per_request_timeout_seconds = timeout.value.per_request_timeout_seconds
            }
          }

          dynamic "tls" {
            for_each = service.value.tls == null ? [] : [service.value.tls]

            content {
              role_arn = tls.value.role_arn
              kms_key  = tls.value.kms_key

              issuer_cert_authority {
                aws_pca_authority_arn = tls.value.issuer_cert_authority.aws_pca_authority_arn
              }
            }
          }
        }
      }
    }
  }

  dynamic "vpc_lattice_configurations" {
    for_each = var.vpc_lattice_configurations

    content {
      port_name        = vpc_lattice_configurations.value.port_name
      role_arn         = vpc_lattice_configurations.value.role_arn
      target_group_arn = vpc_lattice_configurations.value.target_group_arn
    }
  }

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
  }

  tags = merge(var.tags, { Name = var.name })

  # The first deployment must not start before the task network and the
  # execution role's policies exist, or image pulls fail and the circuit
  # breaker rolls back a healthy release.
  depends_on = [module.security_group, module.iam]

  lifecycle {
    precondition {
      condition     = length(local.security_group_ids) > 0
      error_message = "The service needs at least one security group: keep create_security_group true or supply security_group_ids."
    }

    precondition {
      condition     = var.health_check_grace_period_seconds == null || length(var.load_balancers) > 0
      error_message = "health_check_grace_period_seconds is only valid when load_balancers is set."
    }

    precondition {
      condition     = alltrue([for balancer in values(var.load_balancers) : contains(keys(var.container_definitions), balancer.container_name)])
      error_message = "Every load_balancers[*].container_name must be a key of container_definitions."
    }

    precondition {
      condition     = var.service_registries == null ? true : (var.service_registries.container_name == null ? true : contains(keys(var.container_definitions), var.service_registries.container_name))
      error_message = "service_registries.container_name must be a key of container_definitions."
    }

    precondition {
      condition     = var.service_connect_configuration == null ? true : alltrue([for service in var.service_connect_configuration.services : contains(local.declared_port_names, service.port_name)])
      error_message = "Every service_connect_configuration.services[*].port_name must match a named port mapping on a declared container."
    }

    precondition {
      condition     = var.deployment_controller_type == "ECS" || !var.deployment_circuit_breaker.enable
      error_message = "The deployment circuit breaker is only supported by the ECS deployment controller; set deployment_circuit_breaker.enable = false for other controllers."
    }

    precondition {
      condition     = var.autoscaling == null ? true : (var.desired_count >= var.autoscaling.min_capacity && var.desired_count <= var.autoscaling.max_capacity)
      error_message = "desired_count must lie within autoscaling.min_capacity and autoscaling.max_capacity."
    }

    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "ignore_task_definition" {
  count = var.ignore_task_definition_changes ? 1 : 0

  name                               = var.name
  cluster                            = var.cluster_arn
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = local.launch_type
  platform_version                   = var.platform_version
  scheduling_strategy                = "REPLICA"
  availability_zone_rebalancing      = var.availability_zone_rebalancing
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = var.enable_execute_command
  enable_ecs_managed_tags            = var.enable_ecs_managed_tags
  propagate_tags                     = var.propagate_tags
  force_new_deployment               = var.force_new_deployment
  force_delete                       = var.force_delete
  wait_for_steady_state              = var.wait_for_steady_state

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy

    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  deployment_controller {
    type = var.deployment_controller_type
  }

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_controller_type == "ECS" ? [var.deployment_circuit_breaker] : []

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "deployment_configuration" {
    for_each = var.deployment_configuration == null ? [] : [var.deployment_configuration]

    content {
      strategy             = deployment_configuration.value.strategy
      bake_time_in_minutes = deployment_configuration.value.bake_time_in_minutes

      dynamic "canary_configuration" {
        for_each = deployment_configuration.value.canary == null ? [] : [deployment_configuration.value.canary]

        content {
          canary_percent              = canary_configuration.value.canary_percent
          canary_bake_time_in_minutes = canary_configuration.value.canary_bake_time_in_minutes
        }
      }

      dynamic "linear_configuration" {
        for_each = deployment_configuration.value.linear == null ? [] : [deployment_configuration.value.linear]

        content {
          step_percent              = linear_configuration.value.step_percent
          step_bake_time_in_minutes = linear_configuration.value.step_bake_time_in_minutes
        }
      }

      dynamic "lifecycle_hook" {
        for_each = deployment_configuration.value.lifecycle_hooks

        content {
          hook_target_arn  = lifecycle_hook.value.hook_target_arn
          role_arn         = lifecycle_hook.value.role_arn
          lifecycle_stages = lifecycle_hook.value.lifecycle_stages
          target_type      = lifecycle_hook.value.target_type
          hook_details     = lifecycle_hook.value.hook_details

          dynamic "timeout_configuration" {
            for_each = lifecycle_hook.value.timeout == null ? [] : [lifecycle_hook.value.timeout]

            content {
              action             = timeout_configuration.value.action
              timeout_in_minutes = timeout_configuration.value.timeout_in_minutes
            }
          }
        }
      }
    }
  }

  dynamic "alarms" {
    for_each = var.alarms == null ? [] : [var.alarms]

    content {
      alarm_names = alarms.value.alarm_names
      enable      = alarms.value.enable
      rollback    = alarms.value.rollback
    }
  }

  network_configuration {
    assign_public_ip = var.assign_public_ip
    security_groups  = local.security_group_ids
    subnets          = var.subnet_ids
  }

  dynamic "load_balancer" {
    for_each = var.load_balancers

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port

      dynamic "advanced_configuration" {
        for_each = load_balancer.value.advanced_configuration == null ? [] : [load_balancer.value.advanced_configuration]

        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule
          role_arn                   = advanced_configuration.value.role_arn
          test_listener_rule         = advanced_configuration.value.test_listener_rule
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = var.service_registries == null ? [] : [var.service_registries]

    content {
      registry_arn   = service_registries.value.registry_arn
      port           = service_registries.value.port
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
    }
  }

  dynamic "service_connect_configuration" {
    for_each = var.service_connect_configuration == null ? [] : [var.service_connect_configuration]

    content {
      enabled   = service_connect_configuration.value.enabled
      namespace = service_connect_configuration.value.namespace

      dynamic "log_configuration" {
        for_each = service_connect_configuration.value.log_configuration == null ? [] : [service_connect_configuration.value.log_configuration]

        content {
          log_driver = log_configuration.value.log_driver
          options    = log_configuration.value.options

          dynamic "secret_option" {
            for_each = log_configuration.value.secret_options

            content {
              name       = secret_option.value.name
              value_from = secret_option.value.value_from
            }
          }
        }
      }

      dynamic "service" {
        for_each = service_connect_configuration.value.services

        content {
          port_name             = service.value.port_name
          discovery_name        = service.value.discovery_name
          ingress_port_override = service.value.ingress_port_override

          dynamic "client_alias" {
            for_each = service.value.client_alias == null ? [] : [service.value.client_alias]

            content {
              port     = client_alias.value.port
              dns_name = client_alias.value.dns_name
            }
          }

          dynamic "timeout" {
            for_each = service.value.timeout == null ? [] : [service.value.timeout]

            content {
              idle_timeout_seconds        = timeout.value.idle_timeout_seconds
              per_request_timeout_seconds = timeout.value.per_request_timeout_seconds
            }
          }

          dynamic "tls" {
            for_each = service.value.tls == null ? [] : [service.value.tls]

            content {
              role_arn = tls.value.role_arn
              kms_key  = tls.value.kms_key

              issuer_cert_authority {
                aws_pca_authority_arn = tls.value.issuer_cert_authority.aws_pca_authority_arn
              }
            }
          }
        }
      }
    }
  }

  dynamic "vpc_lattice_configurations" {
    for_each = var.vpc_lattice_configurations

    content {
      port_name        = vpc_lattice_configurations.value.port_name
      role_arn         = vpc_lattice_configurations.value.role_arn
      target_group_arn = vpc_lattice_configurations.value.target_group_arn
    }
  }

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
  }

  tags = merge(var.tags, { Name = var.name })

  # The first deployment must not start before the task network and the
  # execution role's policies exist, or image pulls fail and the circuit
  # breaker rolls back a healthy release.
  depends_on = [module.security_group, module.iam]

  lifecycle {
    precondition {
      condition     = length(local.security_group_ids) > 0
      error_message = "The service needs at least one security group: keep create_security_group true or supply security_group_ids."
    }

    precondition {
      condition     = var.health_check_grace_period_seconds == null || length(var.load_balancers) > 0
      error_message = "health_check_grace_period_seconds is only valid when load_balancers is set."
    }

    precondition {
      condition     = alltrue([for balancer in values(var.load_balancers) : contains(keys(var.container_definitions), balancer.container_name)])
      error_message = "Every load_balancers[*].container_name must be a key of container_definitions."
    }

    precondition {
      condition     = var.service_registries == null ? true : (var.service_registries.container_name == null ? true : contains(keys(var.container_definitions), var.service_registries.container_name))
      error_message = "service_registries.container_name must be a key of container_definitions."
    }

    precondition {
      condition     = var.service_connect_configuration == null ? true : alltrue([for service in var.service_connect_configuration.services : contains(local.declared_port_names, service.port_name)])
      error_message = "Every service_connect_configuration.services[*].port_name must match a named port mapping on a declared container."
    }

    precondition {
      condition     = var.deployment_controller_type == "ECS" || !var.deployment_circuit_breaker.enable
      error_message = "The deployment circuit breaker is only supported by the ECS deployment controller; set deployment_circuit_breaker.enable = false for other controllers."
    }

    precondition {
      condition     = var.autoscaling == null ? true : (var.desired_count >= var.autoscaling.min_capacity && var.desired_count <= var.autoscaling.max_capacity)
      error_message = "desired_count must lie within autoscaling.min_capacity and autoscaling.max_capacity."
    }

    ignore_changes = [desired_count, task_definition]
  }
}
