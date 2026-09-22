resource "terraform_data" "application_contract" {
  input = {
    applications         = keys(var.applications)
    cognito_user_pool_id = var.cognito_user_pool_id
    session_table_arn    = var.session_table_arn
  }

  lifecycle {
    precondition {
      condition     = alltrue([for application in values(var.applications) : application.cognito == null || var.cognito_user_pool_id != null])
      error_message = "cognito_user_pool_id is required when an application declares Cognito client settings."
    }

    precondition {
      condition     = alltrue([for application in values(var.applications) : !application.enable_session_table_access || var.session_table_arn != null])
      error_message = "session_table_arn is required when an application enables session-table access."
    }

    precondition {
      condition     = alltrue([for application in values(var.applications) : length(application.ingress_security_group_ids) == 0 || application.container_port != null])
      error_message = "container_port is required when an application accepts traffic from another security group."
    }
  }
}

resource "aws_cloudwatch_log_group" "application" {
  for_each = var.applications

  name              = "/aws/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.application_data_kms_key_arn
  tags = merge(local.common_tags, each.value.tags, {
    Name        = "/aws/ecs/${var.name}/${each.key}"
    Application = each.key
  })
}

resource "aws_security_group" "application" {
  for_each = var.applications

  name        = "${local.application_names[each.key]}-tasks"
  description = "Private Fargate task security group for ${each.key}."
  vpc_id      = var.vpc_id
  egress      = []

  tags = merge(local.common_tags, each.value.tags, {
    Name        = "${local.application_names[each.key]}-tasks"
    Application = each.key
  })
}

resource "aws_vpc_security_group_egress_rule" "application_https_to_vpc" {
  for_each = var.applications

  security_group_id = aws_security_group.application[each.key].id
  description       = "TLS only to private VPC destinations"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${data.aws_region.current.region}.s3"
}

resource "aws_vpc_security_group_egress_rule" "application_https_to_s3" {
  for_each = var.applications

  security_group_id = aws_security_group.application[each.key].id
  description       = "TLS to the regional S3 gateway endpoint for ECR image layers"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "application" {
  for_each = local.ingress_rules

  security_group_id            = aws_security_group.application[each.value.application_key].id
  referenced_security_group_id = each.value.security_group_id
  description                  = "Private application ingress from an approved security group"
  from_port                    = each.value.container_port
  ip_protocol                  = "tcp"
  to_port                      = each.value.container_port
}

resource "aws_iam_role" "execution" {
  for_each = var.applications

  name = "${local.application_names[each.key]}-execution"
  path = "/ecs/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
  tags = merge(local.common_tags, each.value.tags, {
    Name        = "${local.application_names[each.key]}-execution"
    Application = each.key
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  for_each = var.applications

  role       = aws_iam_role.execution[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  for_each = {
    for key, application in var.applications : key => application
    if length(application.secret_arns) > 0
  }

  name   = "declared-secrets"
  role   = aws_iam_role.execution[each.key].id
  policy = jsonencode(local.execution_policy_documents[each.key])
}

resource "aws_iam_role" "task" {
  for_each = var.applications

  name = "${local.application_names[each.key]}-task"
  path = "/ecs/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
  tags = merge(local.common_tags, each.value.tags, {
    Name        = "${local.application_names[each.key]}-task"
    Application = each.key
  })
}

resource "aws_iam_role_policy" "task" {
  for_each = {
    for key, application in var.applications : key => application
    if length(local.task_policy_documents[key].Statement) > 0
  }

  name   = "application-access"
  role   = aws_iam_role.task[each.key].id
  policy = jsonencode(local.task_policy_documents[each.key])
}

resource "aws_ecs_task_definition" "application" {
  for_each = var.applications

  family                   = local.application_names[each.key]
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution[each.key].arn
  task_role_arn            = aws_iam_role.task[each.key].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = each.value.cpu_architecture
  }

  dynamic "ephemeral_storage" {
    for_each = each.value.ephemeral_storage_gib == null ? [] : [each.value.ephemeral_storage_gib]

    content {
      size_in_gib = ephemeral_storage.value
    }
  }

  container_definitions = jsonencode([
    merge(
      {
        name                   = each.key
        image                  = each.value.image_digest
        essential              = true
        readonlyRootFilesystem = each.value.readonly_root_filesystem
        environment            = [for name in sort(keys(local.application_environment[each.key])) : { name = name, value = local.application_environment[each.key][name] }]
        secrets                = [for name, value_from in each.value.secret_arns : { name = name, valueFrom = value_from }]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.application[each.key].name
            "awslogs-region"        = data.aws_region.current.region
            "awslogs-stream-prefix" = each.key
          }
        }
      },
      length(each.value.command) == 0 ? {} : { command = each.value.command },
      each.value.container_port == null ? {} : {
        portMappings = [{
          containerPort = each.value.container_port
          hostPort      = each.value.container_port
          protocol      = "tcp"
        }]
      },
      each.value.health_check == null ? {} : {
        healthCheck = {
          command     = each.value.health_check.command
          interval    = each.value.health_check.interval
          timeout     = each.value.health_check.timeout
          retries     = each.value.health_check.retries
          startPeriod = each.value.health_check.start_period
        }
      }
    )
  ])

  tags = merge(local.common_tags, each.value.tags, {
    Name        = local.application_names[each.key]
    Application = each.key
  })

  depends_on = [terraform_data.application_contract]
}

data "aws_region" "current" {}

resource "aws_ecs_service" "application" {
  for_each = var.applications

  name                    = local.application_names[each.key]
  cluster                 = var.cluster_arn
  task_definition         = aws_ecs_task_definition.application[each.key].arn
  desired_count           = each.value.desired_count
  launch_type             = "FARGATE"
  platform_version        = "LATEST"
  enable_execute_command  = each.value.enable_execute_command
  enable_ecs_managed_tags = true
  force_new_deployment    = each.value.force_new_deployment
  propagate_tags          = "SERVICE"
  wait_for_steady_state   = false

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.application[each.key].id]
    subnets          = tolist(var.private_subnet_ids)
  }

  tags = merge(local.common_tags, each.value.tags, {
    Name        = local.application_names[each.key]
    Application = each.key
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_vpc_security_group_egress_rule.application_https_to_s3,
    aws_vpc_security_group_egress_rule.application_https_to_vpc,
    aws_iam_role_policy_attachment.execution,
    terraform_data.application_contract,
  ]
}

resource "aws_appautoscaling_target" "application" {
  for_each = var.applications

  max_capacity       = each.value.autoscaling.max_capacity
  min_capacity       = each.value.autoscaling.min_capacity
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.application[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "application_cpu" {
  for_each = var.applications

  name               = "${local.application_names[each.key]}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.application[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.application[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.application[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = each.value.autoscaling.cpu_target_percent
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

resource "aws_cognito_user_pool_client" "application" {
  for_each = local.cognito_applications

  name                                 = "${local.application_names[each.key]}-client"
  user_pool_id                         = var.cognito_user_pool_id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = tolist(each.value.cognito.allowed_oauth_scopes)
  callback_urls                        = tolist(each.value.cognito.callback_urls)
  logout_urls                          = tolist(each.value.cognito.logout_urls)
  supported_identity_providers         = tolist(each.value.cognito.supported_identity_providers)
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
}
