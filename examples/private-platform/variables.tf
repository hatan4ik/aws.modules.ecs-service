variable "region" {
  description = "AWS region of the cluster, the VPC and its endpoints."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Service name; also names the Cognito client, roles and log group."
  type        = string
  default     = "orders-api"
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster that runs the service."
  type        = string
}

variable "vpc_id" {
  description = "VPC in which the task security group is created."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC; interface endpoints answer from it."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets without a NAT route; use at least two Availability Zones."
  type        = list(string)
}

variable "image" {
  description = "Container image pinned to a sha256 digest (repository@sha256:<64 hex>), hosted in ECR so it is pulled through the endpoints."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key that encrypts the log group and protects the secrets the execution role reads."
  type        = string
}

variable "session_table_arn" {
  description = "ARN of the DynamoDB session table the task role may read and write."
  type        = string
}

variable "cognito_user_pool_id" {
  description = "Existing Cognito user pool the app client is created in."
  type        = string
}

variable "callback_urls" {
  description = "HTTPS URLs Cognito may redirect to after sign-in."
  type        = list(string)
}

variable "logout_urls" {
  description = "HTTPS URLs Cognito may redirect to after sign-out."
  type        = list(string)
}

variable "force_new_deployment" {
  description = "Force a new deployment on the next apply, for example after an endpoint policy changed."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
