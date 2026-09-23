mock_provider "aws" {}

variables {
  name        = "orders-api"
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  container_definitions = {
    app = {
      image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      port_mappings = [{ name = "http", container_port = 8080 }]
    }
  }
}

run "appends_additional_security_groups_to_the_managed_one" {
  command = plan

  variables {
    security_group_ids          = ["sg-0bbbbbbbbbbbbbbbb", "sg-0aaaaaaaaaaaaaaaa"]
    security_group_name         = "orders-api-tasks"
    security_group_description  = "Legacy description kept to avoid replacement"
    security_group_egress_rules = { vpc = { from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16" } }
    security_group_ingress_rules = {
      alb = { from_port = 8080, to_port = 8080, referenced_security_group_id = "sg-0ccccccccccccccc" }
    }
  }

  assert {
    condition     = length(local.security_group_ids) == 3
    error_message = "The service must carry the managed group plus every additional group."
  }

  assert {
    condition     = local.security_group_ids[1] == "sg-0aaaaaaaaaaaaaaaa" && local.security_group_ids[2] == "sg-0bbbbbbbbbbbbbbbb"
    error_message = "Additional security groups must be sorted after the managed group for a stable plan."
  }
}

run "uses_only_caller_security_groups_when_not_creating_one" {
  command = plan

  variables {
    create_security_group = false
    vpc_id                = null
    security_group_ids    = ["sg-0aaaaaaaaaaaaaaaa"]
  }

  assert {
    condition     = aws_ecs_service.this[0].network_configuration[0].security_groups == toset(["sg-0aaaaaaaaaaaaaaaa"]) && output.security_group_id == null
    error_message = "Without a managed group the service must use exactly the supplied groups."
  }
}

run "allows_public_ip_only_when_explicitly_requested" {
  command = plan

  variables {
    assign_public_ip            = true
    security_group_egress_rules = { all = { ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0" } }
  }

  assert {
    condition     = aws_ecs_service.this[0].network_configuration[0].assign_public_ip == true
    error_message = "assign_public_ip must pass through when the caller opts in."
  }
}
