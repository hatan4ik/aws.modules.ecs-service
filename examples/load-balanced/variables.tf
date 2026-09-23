variable "region" {
  description = "AWS region of the cluster and the VPC."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Service name; also names the load balancer, target group and security groups (32 characters or fewer)."
  type        = string
  default     = "orders-api"
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster that runs the service."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the load balancer, the target group and the security groups."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the tasks and the internal load balancer; use at least two Availability Zones."
  type        = list(string)
}

variable "image" {
  description = "Container image pinned to a sha256 digest (repository@sha256:<64 hex>). It must answer GET /healthz on port 8080."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN served by the HTTPS listener."
  type        = string
}

variable "client_cidr" {
  description = "CIDR allowed to reach the load balancer on 443, for example the VPC or a corporate range."
  type        = string
}

variable "access_logs_bucket" {
  description = "Name of the S3 bucket that receives load balancer access logs. Its policy must allow the regional ELB log-delivery principal."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "egress_cidr" {
  description = "IPv4 CIDR the tasks may reach on TCP 443 for image pulls and dependencies. Use 0.0.0.0/0 when the subnets route through a NAT gateway, or the VPC CIDR when AWS APIs are reached through VPC endpoints. No default: unrestricted egress is a deliberate choice."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.egress_cidr))
    error_message = "egress_cidr must be a valid IPv4 CIDR block."
  }
}
