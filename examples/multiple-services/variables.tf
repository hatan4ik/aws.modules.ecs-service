variable "region" {
  description = "AWS region of the cluster and the VPC."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every service name; the service key is appended (<prefix>-<key>)."
  type        = string
  default     = "platform"
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster shared by every service."
  type        = string
}

variable "vpc_id" {
  description = "VPC in which each task security group is created."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC; TLS egress is limited to it."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets shared by every service; use at least two Availability Zones."
  type        = list(string)
}

variable "services" {
  description = "Services to run, keyed by a short name that becomes the suffix of the service name. desired_count must lie within autoscaling bounds when autoscaling is set."
  type = map(object({
    image          = string
    container_port = number
    cpu            = number
    memory         = number
    desired_count  = number
    environment    = optional(map(string), {})
    autoscaling = optional(object({
      min_capacity = number
      max_capacity = number
    }))
  }))
}

variable "tags" {
  description = "Tags applied to every resource of every service."
  type        = map(string)
  default     = {}
}
