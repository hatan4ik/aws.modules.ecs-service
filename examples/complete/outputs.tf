output "service_id" {
  description = "ID of the ECS service."
  value       = module.service.id
}

output "service_name" {
  description = "Name of the ECS service."
  value       = module.service.name
}

output "service_arn" {
  description = "ARN of the ECS service."
  value       = module.service.arn
}

output "cluster_name" {
  description = "Cluster name the module derived from cluster_arn."
  value       = module.service.cluster_name
}

output "task_definition_arn" {
  description = "ARN of the registered task definition revision."
  value       = module.service.task_definition_arn
}

output "task_definition_arn_without_revision" {
  description = "Task definition ARN without the revision suffix, for deployers that always take the latest."
  value       = module.service.task_definition_arn_without_revision
}

output "task_definition_family" {
  description = "Task definition family."
  value       = module.service.task_definition_family
}

output "task_definition_revision" {
  description = "Registered task definition revision."
  value       = module.service.task_definition_revision
}

output "container_definitions" {
  description = "Rendered container definitions as embedded in the task definition."
  value       = module.service.container_definitions
}

output "task_execution_role_arn" {
  description = "ARN of the created task execution role."
  value       = module.service.task_execution_role_arn
}

output "task_execution_role_name" {
  description = "Name of the created task execution role."
  value       = module.service.task_execution_role_name
}

output "task_role_arn" {
  description = "ARN of the created task role."
  value       = module.service.task_role_arn
}

output "task_role_name" {
  description = "Name of the created task role."
  value       = module.service.task_role_name
}

output "security_group_id" {
  description = "ID of the task security group."
  value       = module.service.security_group_id
}

output "security_group_ids" {
  description = "Every security group attached to the tasks."
  value       = module.service.security_group_ids
}

output "cloudwatch_log_group_name" {
  description = "Name of the KMS-encrypted log group both containers write to."
  value       = module.service.cloudwatch_log_group_name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the created log group."
  value       = module.service.cloudwatch_log_group_arn
}

output "autoscaling_target_resource_id" {
  description = "Application Auto Scaling resource ID of the service."
  value       = module.service.autoscaling_target_resource_id
}

output "autoscaling_policy_arns" {
  description = "Scaling policy ARNs keyed by policy key (cpu, memory)."
  value       = module.service.autoscaling_policy_arns
}

output "autoscaling_scheduled_action_arns" {
  description = "Scheduled action ARNs keyed by action key."
  value       = module.service.autoscaling_scheduled_action_arns
}
