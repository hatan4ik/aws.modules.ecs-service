data "aws_partition" "current" {}

locals {
  common_tags = merge(var.tags, {
    IaCOwnership = "terraform"
    ManagedBy    = "aws.modules.ecs-service"
  })

  application_names = {
    for key in keys(var.applications) : key => "${var.name}-${key}"
  }

  ingress_rules = {
    for rule in flatten([
      for key, application in var.applications : [
        for security_group_id in application.ingress_security_group_ids : {
          key               = "${key}:${security_group_id}"
          application_key   = key
          security_group_id = security_group_id
          container_port    = application.container_port
        }
      ]
    ]) : rule.key => rule
  }

  cognito_applications = {
    for key, application in var.applications : key => application
    if application.cognito != null
  }

  application_environment = {
    for key, application in var.applications : key => merge(
      application.environment,
      application.cognito == null ? {} : {
        COGNITO_USER_POOL_ID = var.cognito_user_pool_id
        COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.application[key].id
      },
    )
  }

  execution_policy_documents = {
    for key, application in var.applications : key => {
      Version = "2012-10-17"
      Statement = concat(
        length(application.secret_arns) == 0 ? [] : [{
          Sid      = "ReadOnlyDeclaredSecrets"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = values(application.secret_arns)
        }],
        length(application.secret_arns) == 0 ? [] : [{
          Sid      = "DecryptOnlyDeclaredSecretKeys"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:DescribeKey"]
          Resource = tolist(toset(concat([var.application_data_kms_key_arn], tolist(application.secret_kms_key_arns))))
        }]
      )
    }
  }

  task_policy_documents = {
    for key, application in var.applications : key => {
      Version = "2012-10-17"
      Statement = concat(
        application.enable_session_table_access ? [{
          Sid      = "UseDeclaredSessionTable"
          Effect   = "Allow"
          Action   = ["dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
          Resource = [var.session_table_arn, "${var.session_table_arn}/index/*"]
        }] : [],
        application.enable_execute_command ? [{
          Sid      = "UseEcsExecuteCommandChannels"
          Effect   = "Allow"
          Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
          Resource = "*"
        }] : [],
        [for sid, statement in application.task_policy_statements : {
          Sid      = sid
          Effect   = "Allow"
          Action   = tolist(statement.actions)
          Resource = tolist(statement.resources)
        }]
      )
    }
  }
}
