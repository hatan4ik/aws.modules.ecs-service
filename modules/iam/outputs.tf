output "task_execution_role_arn" {
  description = "ARN of the task execution role, created or supplied."
  value       = var.create_task_execution_role ? aws_iam_role.task_execution[0].arn : var.task_execution_role_arn

  precondition {
    condition     = var.create_task_execution_role || var.task_execution_role_arn != null
    error_message = "task_execution_role_arn is required when create_task_execution_role is false."
  }
}

output "task_execution_role_name" {
  description = "Name of the task execution role, created or parsed from the supplied ARN."
  value       = var.create_task_execution_role ? aws_iam_role.task_execution[0].name : (var.task_execution_role_arn == null ? null : regex("[^/]+$", var.task_execution_role_arn))
}

output "task_execution_role_derived_policy" {
  description = "JSON policy the module derived from secret, parameter, and KMS references, or null. Attach it yourself when supplying your own execution role."
  value       = local.task_execution_derived_policy
}

output "task_role_arn" {
  description = "ARN of the task role, created or supplied."
  value       = var.create_task_role ? aws_iam_role.task[0].arn : var.task_role_arn

  precondition {
    condition     = var.create_task_role || var.task_role_arn != null
    error_message = "task_role_arn is required when create_task_role is false."
  }
}

output "task_role_name" {
  description = "Name of the task role, created or parsed from the supplied ARN."
  value       = var.create_task_role ? aws_iam_role.task[0].name : (var.task_role_arn == null ? null : regex("[^/]+$", var.task_role_arn))
}

output "task_role_derived_policy" {
  description = "JSON policy the module derived for ECS Exec, or null. Attach it yourself when supplying your own task role."
  value       = local.task_derived_policy
}
