output "alb_dns_name" {
  description = "DNS name of the internal load balancer."
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the internal load balancer."
  value       = aws_lb.this.arn
}

output "alb_security_group_id" {
  description = "ID of the load balancer security group."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "ARN of the IP target group the service registers with."
  value       = aws_lb_target_group.this.arn
}

output "listener_arn" {
  description = "ARN of the HTTPS listener."
  value       = aws_lb_listener.https.arn
}

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

output "task_security_group_id" {
  description = "ID of the task security group."
  value       = module.service.security_group_id
}

output "autoscaling_policy_arns" {
  description = "Scaling policy ARNs keyed by policy key (requests, cpu)."
  value       = module.service.autoscaling_policy_arns
}
