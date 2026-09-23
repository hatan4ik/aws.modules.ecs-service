variable "region" {
  description = "AWS region of the cluster and the VPC."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Service name; also names the task family, roles, security group and log group."
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
  description = "CIDR of the VPC; TLS and NFS egress are limited to it."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets the tasks run in; use at least two Availability Zones."
  type        = list(string)
}

variable "image" {
  description = "Application image pinned to a sha256 digest (repository@sha256:<64 hex>). Also runs the migration container."
  type        = string
}

variable "log_router_image" {
  description = "Fluent Bit image for the FireLens sidecar, pinned to a sha256 digest."
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}

variable "efs_file_system_id" {
  description = "EFS file system mounted at /data."
  type        = string
}

variable "efs_access_point_id" {
  description = "EFS access point that scopes the /data mount."
  type        = string
}

variable "database_url_secret_arn" {
  description = "Secrets Manager secret ARN injected as DATABASE_URL."
  type        = string
}

variable "api_token_parameter_arn" {
  description = "SSM Parameter Store parameter ARN injected as API_TOKEN."
  type        = string
}

variable "secrets_kms_key_arns" {
  description = "KMS keys that protect the referenced secret and parameter; the execution role may decrypt with them."
  type        = set(string)
}

variable "logs_kms_key_arn" {
  description = "KMS key that encrypts the CloudWatch log group. Its key policy must trust the CloudWatch Logs service principal."
  type        = string
}

variable "assets_bucket_arn" {
  description = "S3 bucket ARN whose objects the task role may read."
  type        = string
}

variable "service_connect_namespace_arn" {
  description = "AWS Cloud Map namespace ARN the service publishes to through Service Connect."
  type        = string
}

variable "deployment_alarm_names" {
  description = "CloudWatch alarm names that fail and roll back a deployment."
  type        = set(string)
}

variable "ingress_security_group_id" {
  description = "Security group of the upstream that may reach the tasks on port 8080."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Environment = "production"
    Team        = "orders"
  }
}

variable "egress_cidr" {
  description = "IPv4 CIDR the tasks may reach on TCP 443 for image pulls and dependencies. Use 0.0.0.0/0 when the subnets route through a NAT gateway, or the VPC CIDR when AWS APIs are reached through VPC endpoints. No default: unrestricted egress is a deliberate choice."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.egress_cidr))
    error_message = "egress_cidr must be a valid IPv4 CIDR block."
  }
}
