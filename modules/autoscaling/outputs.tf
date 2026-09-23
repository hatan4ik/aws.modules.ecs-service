output "target_resource_id" {
  description = "Application Auto Scaling resource ID of the service (service/<cluster>/<service>)."
  value       = aws_appautoscaling_target.this.resource_id
}

output "target_arn" {
  description = "ARN of the scalable target."
  value       = aws_appautoscaling_target.this.arn
}

output "policy_arns" {
  description = "Scaling policy ARNs keyed by policy key. Use these as CloudWatch alarm actions for step scaling."
  value       = { for key, policy in aws_appautoscaling_policy.this : key => policy.arn }
}

output "scheduled_action_arns" {
  description = "Scheduled action ARNs keyed by action key."
  value       = { for key, action in aws_appautoscaling_scheduled_action.this : key => action.arn }
}
