output "service_name" {
  description = "Name of the ECS service."
  value       = module.service.name
}

output "service_arn" {
  description = "ARN of the ECS service."
  value       = module.service.arn
}

output "task_definition_arn" {
  description = "ARN of the registered task definition revision."
  value       = module.service.task_definition_arn
}

output "task_execution_role_name" {
  description = "Name the module parsed from the supplied execution role ARN."
  value       = module.service.task_execution_role_name
}

output "task_execution_role_derived_policy" {
  description = "Policy the module derived for the supplied execution role, attached by this example."
  value       = module.service.task_execution_role_derived_policy
}

output "security_group_ids" {
  description = "Security groups attached to the tasks, exactly as supplied."
  value       = module.service.security_group_ids
}

output "cloudwatch_log_group_name" {
  description = "Log group the containers write to, exactly as supplied."
  value       = module.service.cloudwatch_log_group_name
}
