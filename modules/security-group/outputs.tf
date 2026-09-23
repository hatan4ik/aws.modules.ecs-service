output "id" {
  description = "Security group ID, or null when create is false."
  value       = var.create ? aws_security_group.this[0].id : null
}

output "arn" {
  description = "Security group ARN, or null when create is false."
  value       = var.create ? aws_security_group.this[0].arn : null
}

output "ingress_rule_ids" {
  description = "Ingress rule IDs keyed by rule key."
  value       = { for key, rule in aws_vpc_security_group_ingress_rule.this : key => rule.security_group_rule_id }
}

output "egress_rule_ids" {
  description = "Egress rule IDs keyed by rule key."
  value       = { for key, rule in aws_vpc_security_group_egress_rule.this : key => rule.security_group_rule_id }
}
