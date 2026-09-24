# Disposable prerequisites for the integration suites: a VPC with two private
# subnets, optionally two public subnets behind an internet gateway, and an
# empty ECS cluster. Everything is created and destroyed by `terraform test`
# in the caller's own account; nothing here is shared or long-lived.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name = "${var.name_prefix}-${random_id.suffix.hex}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = merge(var.tags, {
    Name            = local.name
    IntegrationTest = "aws.modules.ecs-service"
    Disposable      = "true"
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = local.tags
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, { Name = "${local.name}-private-${count.index}", Tier = "private" })
}

resource "aws_subnet" "public" {
  count = var.public_subnets ? 2 : 0

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, 10 + count.index)
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, { Name = "${local.name}-public-${count.index}", Tier = "public" })
}

resource "aws_internet_gateway" "this" {
  count = var.public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = local.tags
}

resource "aws_route_table" "public" {
  count = var.public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(local.tags, { Name = "${local.name}-public" })
}

resource "aws_route_table_association" "public" {
  count = var.public_subnets ? 2 : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = local.tags
}
