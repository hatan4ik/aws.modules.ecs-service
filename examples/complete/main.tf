provider "aws" {
  region = var.region
}

locals {
  # The module defaults the log group to /aws/ecs/<cluster>/<name>. Naming it
  # here lets the FireLens router target the same group the module creates.
  log_group_name = "/aws/ecs/${var.name}"

  cluster_arn_parts = split(":", var.cluster_arn)
  partition         = local.cluster_arn_parts[1]
  account_id        = local.cluster_arn_parts[4]
  log_group_arn     = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:${local.log_group_name}"
}

module "service" {
  source = "../../"

  name        = var.name
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids
  tags        = var.tags

  # ---------------------------------------------------------------- task
  cpu                           = 1024
  memory                        = 2048
  cpu_architecture              = "ARM64"
  ephemeral_storage_size_in_gib = 50

  volumes = {
    data = {
      efs = {
        file_system_id = var.efs_file_system_id
        authorization_config = {
          access_point_id = var.efs_access_point_id
        }
      }
    }
    cache = {}
  }

  container_definitions = {
    app = {
      image = var.image

      port_mappings = [{ name = "http", container_port = 8080, app_protocol = "http" }]

      health_check = {
        command      = ["CMD-SHELL", "curl -fsS http://localhost:8080/healthz || exit 1"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 15
      }

      environment = {
        APP_ENV   = "production"
        HTTP_PORT = "8080"
        DATA_DIR  = "/data"
        CACHE_DIR = "/cache"
      }

      secrets = {
        DATABASE_URL = var.database_url_secret_arn
        API_TOKEN    = var.api_token_parameter_arn
      }

      ulimits = [{ name = "nofile", soft_limit = 65536, hard_limit = 65536 }]

      linux_parameters = {
        init_process_enabled = true
        capabilities         = { drop = ["ALL"] }
      }

      mount_points = [
        { source_volume = "data", container_path = "/data" },
        { source_volume = "cache", container_path = "/cache" },
      ]

      # Wait for the log router to accept connections and for the migration
      # container to exit successfully before the application starts.
      container_dependencies = [
        { container_name = "log-router", condition = "START" },
        { container_name = "init", condition = "SUCCESS" },
      ]

      # Application logs flow through the FireLens sidecar to CloudWatch.
      log_configuration = {
        log_driver = "awsfirelens"
        options = {
          Name              = "cloudwatch_logs"
          region            = var.region
          log_group_name    = local.log_group_name
          log_stream_prefix = "app/"
          auto_create_group = "false"
        }
      }
    }

    log-router = {
      image     = var.log_router_image
      essential = false

      firelens_configuration = { type = "fluentbit" }

      # The router's own logs use the awslogs driver directly.
      log_configuration = {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "log-router"
        }
      }
    }

    init = {
      image        = var.image
      essential    = false
      command      = ["/app/orders-api", "migrate"]
      secrets      = { DATABASE_URL = var.database_url_secret_arn }
      mount_points = [{ source_volume = "data", container_path = "/data" }]
    }
  }

  # ------------------------------------------------------------- service
  desired_count = 2

  capacity_provider_strategy = {
    on_demand = { capacity_provider = "FARGATE", base = 1, weight = 1 }
    spot      = { capacity_provider = "FARGATE_SPOT", weight = 3 }
  }

  enable_execute_command = true

  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }

  alarms = {
    alarm_names = var.deployment_alarm_names
  }

  service_connect_configuration = {
    namespace = var.service_connect_namespace_arn
    services = [{
      port_name    = "http"
      client_alias = { port = 80 }
    }]
  }

  timeouts = {
    create = "20m"
    update = "20m"
  }

  # ----------------------------------------------------------------- IAM
  task_execution_role_kms_key_arns = var.secrets_kms_key_arns

  task_role_statements = {
    ReadAssets = {
      actions   = ["s3:GetObject"]
      resources = ["${var.assets_bucket_arn}/*"]
      conditions = [{
        test     = "Bool"
        variable = "aws:SecureTransport"
        values   = ["true"]
      }]
    }
    # Fluent Bit runs under the task role, not the execution role.
    WriteApplicationLogs = {
      actions   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
      resources = ["${local.log_group_arn}:*"]
    }
  }

  # ------------------------------------------------------------- network
  security_group_ingress_rules = {
    http = {
      description                  = "HTTP from the upstream gateway"
      from_port                    = 8080
      to_port                      = 8080
      referenced_security_group_id = var.ingress_security_group_id
    }
  }

  security_group_egress_rules = {
    vpc_tls = {
      description = "TLS to VPC endpoints and internal services"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.vpc_cidr
    }
    internet_tls = {
      description = "TLS for image pulls and dependencies"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.egress_cidr
    }
    efs = {
      description = "NFS over TLS to the EFS mount targets"
      from_port   = 2049
      to_port     = 2049
      cidr_ipv4   = var.vpc_cidr
    }
  }

  # ------------------------------------------------------------- logging
  cloudwatch_log_group_name       = local.log_group_name
  cloudwatch_log_group_kms_key_id = var.logs_kms_key_arn

  # ------------------------------------------------------------- scaling
  autoscaling = {
    min_capacity = 2
    max_capacity = 20
    policies = {
      cpu = {
        target_tracking = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
          target_value           = 60
        }
      }
      memory = {
        target_tracking = {
          predefined_metric_type = "ECSServiceAverageMemoryUtilization"
          target_value           = 75
        }
      }
    }
    scheduled_actions = {
      weekday_morning = {
        schedule     = "cron(0 7 ? * MON-FRI *)"
        timezone     = "Europe/London"
        min_capacity = 4
      }
    }
  }
}
