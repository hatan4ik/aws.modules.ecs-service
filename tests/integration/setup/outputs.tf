output "name" {
  description = "Unique fixture name, also used as the service name under test."
  value       = local.name
}

output "cluster_arn" {
  description = "ARN of the disposable ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the disposable ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "vpc_id" {
  description = "ID of the disposable VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR of the disposable VPC."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "The two private subnet IDs."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "The two public subnet IDs, empty unless public_subnets is true."
  value       = aws_subnet.public[*].id
}

output "region" {
  description = "Region the fixtures were created in, resolved from the caller's credentials."
  value       = data.aws_region.current.region
}

output "tags" {
  description = "Identifying tags shared with the service under test."
  value       = local.tags
}
