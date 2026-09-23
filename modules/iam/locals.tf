locals {
  cluster_arn_parts = split(":", var.cluster_arn)
  partition         = local.cluster_arn_parts[1]
  region            = local.cluster_arn_parts[3]
  account_id        = local.cluster_arn_parts[4]

  task_execution_role_name = coalesce(var.task_execution_role_name, "${var.name}-execution")
  task_role_name           = coalesce(var.task_role_name, "${var.name}-task")

  # Both roles trust ecs-tasks.amazonaws.com, restricted to tasks launched in
  # this account and region so another account's ECS control plane cannot
  # assume them (confused-deputy protection recommended by AWS).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EcsTasksAssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:*" }
      }
    }]
  })

  # A container may reference "arn:...:secret:name-AbCdEf:json-key:stage:id";
  # the policy must target the secret itself, which is the first seven fields.
  secretsmanager_arns = sort(distinct([
    for arn in var.secret_arns : join(":", slice(split(":", arn), 0, 7)) if split(":", arn)[2] == "secretsmanager"
  ]))
  ssm_parameter_arns = sort([for arn in var.secret_arns : arn if split(":", arn)[2] == "ssm"])

  task_execution_derived_statements = concat(
    length(local.secretsmanager_arns) == 0 ? [] : [{
      Sid      = "ReadDeclaredSecrets"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.secretsmanager_arns
    }],
    length(local.ssm_parameter_arns) == 0 ? [] : [{
      Sid      = "ReadDeclaredParameters"
      Effect   = "Allow"
      Action   = ["ssm:GetParameters"]
      Resource = local.ssm_parameter_arns
    }],
    length(var.kms_key_arns) == 0 ? [] : [{
      Sid      = "DecryptDeclaredKeys"
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = sort(tolist(var.kms_key_arns))
    }],
  )

  # ssmmessages actions do not support resource-level permissions.
  task_derived_statements = var.enable_execute_command ? [{
    Sid      = "OpenEcsExecChannels"
    Effect   = "Allow"
    Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
    Resource = "*"
  }] : []

  declared_statements = {
    for scope, statements in {
      task_execution = var.task_execution_role_statements
      task           = var.task_role_statements
      } : scope => [
      for sid in sort(keys(statements)) : merge(
        {
          Sid      = sid
          Effect   = statements[sid].effect
          Action   = sort(tolist(statements[sid].actions))
          Resource = sort(tolist(statements[sid].resources))
        },
        length(statements[sid].conditions) == 0 ? {} : {
          Condition = {
            for test in distinct([for condition in statements[sid].conditions : condition.test]) : test => {
              for condition in statements[sid].conditions : condition.variable => sort(tolist(condition.values)) if condition.test == test
            }
          }
        },
      )
    ]
  }

  task_execution_derived_policy  = length(local.task_execution_derived_statements) == 0 ? null : jsonencode({ Version = "2012-10-17", Statement = local.task_execution_derived_statements })
  task_execution_declared_policy = length(local.declared_statements.task_execution) == 0 ? null : jsonencode({ Version = "2012-10-17", Statement = local.declared_statements.task_execution })
  task_derived_policy            = length(local.task_derived_statements) == 0 ? null : jsonencode({ Version = "2012-10-17", Statement = local.task_derived_statements })
  task_declared_policy           = length(local.declared_statements.task) == 0 ? null : jsonencode({ Version = "2012-10-17", Statement = local.declared_statements.task })
}
