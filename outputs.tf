output "id" {
  description = "ECS service ID."
  value       = local.service.id
}

output "name" {
  description = "ECS service name."
  value       = local.service.name
}

output "arn" {
  description = "ECS service ARN."
  value       = local.service.arn
}

output "cluster_name" {
  description = "Name of the cluster, derived from cluster_arn."
  value       = local.cluster_name
}

output "task_definition_arn" {
  description = "ARN of the registered task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_arn_without_revision" {
  description = "Task definition ARN without the revision suffix."
  value       = aws_ecs_task_definition.this.arn_without_revision
}

output "task_definition_family" {
  description = "Task definition family."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_revision" {
  description = "Registered task definition revision."
  value       = aws_ecs_task_definition.this.revision
}

output "container_definitions" {
  description = "Rendered container definitions in sorted order, as embedded in the task definition."
  value       = local.container_definitions
}

output "task_execution_role_arn" {
  description = "Task execution role ARN, created or supplied."
  value       = module.iam.task_execution_role_arn
}

output "task_execution_role_name" {
  description = "Task execution role name."
  value       = module.iam.task_execution_role_name
}

output "task_execution_role_derived_policy" {
  description = "JSON policy derived from secret, parameter, and KMS references, or null. Attach it to a caller-supplied execution role."
  value       = module.iam.task_execution_role_derived_policy
}

output "task_role_arn" {
  description = "Task role ARN, created or supplied."
  value       = module.iam.task_role_arn
}

output "task_role_name" {
  description = "Task role name."
  value       = module.iam.task_role_name
}

output "task_role_derived_policy" {
  description = "JSON policy derived for ECS Exec, or null. Attach it to a caller-supplied task role."
  value       = module.iam.task_role_derived_policy
}

output "security_group_id" {
  description = "ID of the managed task security group, or null when not created."
  value       = module.security_group.id
}

output "security_group_ids" {
  description = "Every security group attached to the tasks: the managed group first, then security_group_ids sorted."
  value       = local.security_group_ids
}

output "cloudwatch_log_group_name" {
  description = "Log group containers write to (created or named), or null."
  value       = local.cloudwatch_log_group_name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the created log group, or null when not created."
  value       = var.create_cloudwatch_log_group ? aws_cloudwatch_log_group.this[0].arn : null
}

output "autoscaling_target_resource_id" {
  description = "Application Auto Scaling resource ID, or null when autoscaling is disabled."
  value       = length(module.autoscaling) == 0 ? null : module.autoscaling[0].target_resource_id
}

output "autoscaling_policy_arns" {
  description = "Scaling policy ARNs keyed by policy key; empty when autoscaling is disabled."
  value       = length(module.autoscaling) == 0 ? {} : module.autoscaling[0].policy_arns
}

output "autoscaling_scheduled_action_arns" {
  description = "Scheduled action ARNs keyed by action key; empty when autoscaling is disabled."
  value       = length(module.autoscaling) == 0 ? {} : module.autoscaling[0].scheduled_action_arns
}
