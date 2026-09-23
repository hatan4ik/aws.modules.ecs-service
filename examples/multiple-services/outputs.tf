output "service_arns" {
  description = "ECS service ARNs keyed by service key."
  value       = { for key, service in module.service : key => service.arn }
}

output "task_definition_arns" {
  description = "Task definition ARNs keyed by service key."
  value       = { for key, service in module.service : key => service.task_definition_arn }
}

output "security_group_ids" {
  description = "Task security group IDs keyed by service key."
  value       = { for key, service in module.service : key => service.security_group_id }
}
