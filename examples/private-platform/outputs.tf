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

output "task_role_arn" {
  description = "ARN of the task role that holds the session-table statement."
  value       = module.service.task_role_arn
}

output "security_group_id" {
  description = "ID of the task security group (<name>-tasks)."
  value       = module.service.security_group_id
}

output "cloudwatch_log_group_name" {
  description = "Name of the KMS-encrypted log group."
  value       = module.service.cloudwatch_log_group_name
}

output "cognito_client_id" {
  description = "ID of the Cognito app client injected as COGNITO_CLIENT_ID."
  value       = aws_cognito_user_pool_client.this.id
}

output "autoscaling_target_resource_id" {
  description = "Application Auto Scaling resource ID of the service."
  value       = module.service.autoscaling_target_resource_id
}
