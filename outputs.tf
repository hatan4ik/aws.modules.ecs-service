output "services" {
  description = "Non-secret private workload identifiers by application key."
  value = {
    for key, service in aws_ecs_service.application : key => {
      name                = service.name
      arn                 = service.id
      task_definition_arn = aws_ecs_task_definition.application[key].arn
      security_group_id   = aws_security_group.application[key].id
      execution_role_arn  = aws_iam_role.execution[key].arn
      task_role_arn       = aws_iam_role.task[key].arn
      log_group_name      = aws_cloudwatch_log_group.application[key].name
      cognito_client_id   = try(aws_cognito_user_pool_client.application[key].id, null)
    }
  }
}
