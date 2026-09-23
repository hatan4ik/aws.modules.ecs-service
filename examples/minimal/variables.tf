variable "region" {
  description = "AWS region of the cluster and the VPC."
  type        = string
  default     = "us-east-1"
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster that runs the service."
  type        = string
}

variable "vpc_id" {
  description = "VPC in which the task security group is created."
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

variable "egress_cidr" {
  description = "IPv4 CIDR the tasks may reach on TCP 443 for image pulls and dependencies. Use 0.0.0.0/0 when the subnets route through a NAT gateway, or the VPC CIDR when AWS APIs are reached through VPC endpoints. No default: unrestricted egress is a deliberate choice."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.egress_cidr))
    error_message = "egress_cidr must be a valid IPv4 CIDR block."
  }
}
