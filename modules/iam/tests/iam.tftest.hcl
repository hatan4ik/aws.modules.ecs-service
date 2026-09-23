mock_provider "aws" {}

variables {
  name        = "orders-api"
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
  tags        = { Environment = "test" }
}

run "creates_both_roles_with_scoped_trust" {
  command = plan

  assert {
    condition     = aws_iam_role.task_execution[0].name == "orders-api-execution" && aws_iam_role.task[0].name == "orders-api-task"
    error_message = "Role names must derive from the service name with -execution and -task suffixes."
  }

  assert {
    condition     = jsondecode(aws_iam_role.task[0].assume_role_policy).Statement[0].Principal.Service == "ecs-tasks.amazonaws.com"
    error_message = "Roles must trust the ECS tasks service principal."
  }

  assert {
    condition     = jsondecode(aws_iam_role.task[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "Trust policies must pin aws:SourceAccount to the cluster account to prevent confused-deputy assumption."
  }

  assert {
    condition     = jsondecode(aws_iam_role.task_execution[0].assume_role_policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:ecs:us-east-1:123456789012:*"
    error_message = "Trust policies must pin aws:SourceArn to the cluster region and account."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.task_execution_default[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    error_message = "The execution role must carry the AWS-managed ECS task execution policy from the cluster partition."
  }

  assert {
    condition     = length(aws_iam_role_policy.task_execution_derived) == 0 && length(aws_iam_role_policy.task_derived) == 0 && length(aws_iam_role_policy.task_execution_declared) == 0 && length(aws_iam_role_policy.task_declared) == 0
    error_message = "No inline policies may exist when nothing was declared or derived."
  }

  assert {
    condition     = output.task_execution_role_derived_policy == null && output.task_role_derived_policy == null
    error_message = "Derived policy outputs must be null when there is nothing to derive."
  }
}

run "derives_execution_permissions_from_secret_references" {
  command = plan

  variables {
    secret_arns = [
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf:password::",
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf:username::",
      "arn:aws:ssm:us-east-1:123456789012:parameter/api-key",
    ]
    kms_key_arns = ["arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"]
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_execution_derived[0].policy).Statement[0].Sid == "ReadDeclaredSecrets" && jsondecode(aws_iam_role_policy.task_execution_derived[0].policy).Statement[0].Resource == ["arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf"]
    error_message = "Secrets Manager references must be reduced to their de-duplicated base secret ARN."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_execution_derived[0].policy).Statement[1].Action == ["ssm:GetParameters"] && jsondecode(aws_iam_role_policy.task_execution_derived[0].policy).Statement[1].Resource == ["arn:aws:ssm:us-east-1:123456789012:parameter/api-key"]
    error_message = "SSM parameter references must grant ssm:GetParameters on the exact parameter."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_execution_derived[0].policy).Statement[2].Action == ["kms:Decrypt"]
    error_message = "Declared KMS keys must grant kms:Decrypt only."
  }

  assert {
    condition     = aws_iam_role_policy.task_execution_derived[0].name == "derived"
    error_message = "The derived inline policy must have a stable name."
  }
}

run "grants_exec_channels_on_the_task_role" {
  command = plan

  variables {
    enable_execute_command = true
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_derived[0].policy).Statement[0].Sid == "OpenEcsExecChannels" && contains(jsondecode(aws_iam_role_policy.task_derived[0].policy).Statement[0].Action, "ssmmessages:OpenDataChannel")
    error_message = "ECS Exec requires the SSM messages channel actions on the task role."
  }
}

run "renders_declared_statements_with_conditions" {
  command = plan

  variables {
    task_role_statements = {
      UseSessionTable = {
        actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
        resources = ["arn:aws:dynamodb:us-east-1:123456789012:table/session"]
        conditions = [
          { test = "ForAllValues:StringEquals", variable = "dynamodb:LeadingKeys", values = ["tenant-a"] },
          { test = "Bool", variable = "aws:SecureTransport", values = ["true"] },
        ]
      }
      DenyDelete = {
        effect    = "Deny"
        actions   = ["dynamodb:DeleteTable"]
        resources = ["*"]
      }
    }
    task_execution_role_statements = {
      PullFromRegistryKey = {
        actions   = ["kms:Decrypt"]
        resources = ["arn:aws:kms:us-east-1:123456789012:key/22222222-2222-2222-2222-222222222222"]
      }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_declared[0].policy).Statement[0].Sid == "DenyDelete" && jsondecode(aws_iam_role_policy.task_declared[0].policy).Statement[0].Effect == "Deny"
    error_message = "Declared statements must be sorted by Sid and keep their effect."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_declared[0].policy).Statement[1].Condition["Bool"]["aws:SecureTransport"] == ["true"] && jsondecode(aws_iam_role_policy.task_declared[0].policy).Statement[1].Condition["ForAllValues:StringEquals"]["dynamodb:LeadingKeys"] == ["tenant-a"]
    error_message = "Conditions must be grouped by test operator."
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_iam_role_policy.task_declared[0].policy).Statement[0]), "Condition")
    error_message = "Statements without conditions must not render an empty Condition block."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_execution_declared[0].policy).Statement[0].Sid == "PullFromRegistryKey"
    error_message = "Execution-role declared statements must render on the execution role."
  }
}

run "attaches_additional_managed_policies" {
  command = plan

  variables {
    task_role_policy_arns           = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
    task_execution_role_policy_arns = ["arn:aws:iam::123456789012:policy/registry-pull"]
  }

  assert {
    condition     = aws_iam_role_policy_attachment.task["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"].policy_arn == "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    error_message = "Task role managed policies must be attached by ARN."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.task_execution) == 1
    error_message = "Execution role managed policies must be attached by ARN."
  }
}

run "passes_through_caller_supplied_roles" {
  command = plan

  variables {
    create_task_execution_role = false
    task_execution_role_arn    = "arn:aws:iam::123456789012:role/shared/platform-execution"
    create_task_role           = false
    task_role_arn              = "arn:aws:iam::123456789012:role/orders-task"
    secret_arns                = ["arn:aws:ssm:us-east-1:123456789012:parameter/api-key"]
  }

  assert {
    condition     = length(aws_iam_role.task_execution) == 0 && length(aws_iam_role.task) == 0 && length(aws_iam_role_policy.task_execution_derived) == 0
    error_message = "Caller-supplied roles must not be created or modified."
  }

  assert {
    condition     = output.task_execution_role_arn == "arn:aws:iam::123456789012:role/shared/platform-execution" && output.task_execution_role_name == "platform-execution"
    error_message = "Outputs must echo the supplied role ARN and parse its name."
  }

  assert {
    condition     = output.task_execution_role_derived_policy != null
    error_message = "The derived policy must still be exposed so the caller can attach it to their role."
  }
}

run "rejects_missing_role_arn_when_not_creating" {
  command = plan

  variables {
    create_task_role = false
  }

  expect_failures = [output.task_role_arn]
}

run "rejects_role_name_over_iam_limit" {
  command = plan

  variables {
    task_execution_role_name = "this-role-name-is-far-too-long-for-the-iam-service-limit-of-sixty-four"
  }

  expect_failures = [var.task_execution_role_name]
}

run "rejects_non_alphanumeric_sid" {
  command = plan

  variables {
    task_role_statements = {
      "bad-sid" = { actions = ["s3:GetObject"], resources = ["*"] }
    }
  }

  expect_failures = [var.task_role_statements]
}

run "rejects_malformed_cluster_arn" {
  command = plan

  variables {
    cluster_arn = "platform"
  }

  expect_failures = [var.cluster_arn]
}
