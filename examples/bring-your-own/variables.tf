variable "region" {
  description = "AWS region of the cluster."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Service name; also the task definition family."
  type        = string
  default     = "orders-api"
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster that runs the service."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets the tasks run in; use at least two Availability Zones."
  type        = list(string)
}

variable "image" {
  description = "Container image pinned to a sha256 digest (repository@sha256:<64 hex>)."
  type        = string
}

variable "security_group_ids" {
  description = "Existing security groups attached to the tasks. They must already allow the egress the tasks need."
  type        = set(string)
}

variable "task_execution_role_arn" {
  description = "Existing task execution role. It must trust ecs-tasks.amazonaws.com and carry AmazonECSTaskExecutionRolePolicy."
  type        = string
}

variable "task_role_arn" {
  description = "Existing task role the application code assumes."
  type        = string
}

variable "cloudwatch_log_group_name" {
  description = "Existing CloudWatch log group the containers write to through awslogs."
  type        = string
}

variable "api_token_parameter_arn" {
  description = "SSM Parameter Store parameter ARN injected as API_TOKEN."
  type        = string
}

variable "tags" {
  description = "Tags applied to the task definition and the service."
  type        = map(string)
  default     = {}
}
