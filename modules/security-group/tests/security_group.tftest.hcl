mock_provider "aws" {}

variables {
  name   = "orders-api"
  vpc_id = "vpc-0123456789abcdef0"
  tags   = { Environment = "test" }
}

run "creates_group_and_rules" {
  command = plan

  variables {
    ingress_rules = {
      from_alb  = { description = "HTTP from the load balancer", from_port = 8080, to_port = 8080, referenced_security_group_id = "sg-0aaaaaaaaaaaaaaaa" }
      from_self = { description = "Cluster gossip", from_port = 7946, to_port = 7946, self = true }
    }
    egress_rules = {
      vpc_tls = { description = "TLS to VPC endpoints", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16" }
      s3_tls  = { description = "TLS to S3 gateway", from_port = 443, to_port = 443, prefix_list_id = "pl-0123456789abcdef0" }
      dns     = { from_port = 53, to_port = 53, ip_protocol = "udp", cidr_ipv4 = "10.0.0.2/32" }
      all_v6  = { ip_protocol = "-1", cidr_ipv6 = "::/0" }
    }
  }

  assert {
    condition     = aws_security_group.this[0].name == "orders-api" && aws_security_group.this[0].vpc_id == "vpc-0123456789abcdef0" && aws_security_group.this[0].tags["Name"] == "orders-api"
    error_message = "The security group must use the declared name, VPC, and Name tag."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 2 && length(aws_vpc_security_group_egress_rule.this) == 4
    error_message = "Every declared rule must become one standalone rule resource."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from_alb"].referenced_security_group_id == "sg-0aaaaaaaaaaaaaaaa" && aws_vpc_security_group_ingress_rule.this["from_alb"].from_port == 8080
    error_message = "Referenced security group rules must keep their source and ports."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["s3_tls"].prefix_list_id == "pl-0123456789abcdef0" && aws_vpc_security_group_egress_rule.this["dns"].ip_protocol == "udp"
    error_message = "Prefix-list and protocol settings must pass through."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["all_v6"].from_port == null && aws_vpc_security_group_egress_rule.this["all_v6"].cidr_ipv6 == "::/0"
    error_message = "All-protocol rules must not carry ports."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["vpc_tls"].tags["Name"] == "orders-api-vpc_tls"
    error_message = "Rules must be tagged with a Name derived from the group and rule key."
  }

  assert {
    condition     = length(output.ingress_rule_ids) == 2 && length(output.egress_rule_ids) == 4
    error_message = "Rule id outputs must be keyed by rule key."
  }
}

run "creates_nothing_when_disabled" {
  command = plan

  variables {
    create        = false
    ingress_rules = { from_alb = { from_port = 80, to_port = 80, cidr_ipv4 = "10.0.0.0/8" } }
  }

  assert {
    condition     = length(aws_security_group.this) == 0 && length(aws_vpc_security_group_ingress_rule.this) == 0 && output.id == null
    error_message = "Disabling creation must produce no resources and a null id."
  }
}

run "requires_vpc_when_creating" {
  command = plan

  variables {
    vpc_id = null
  }

  expect_failures = [aws_security_group.this]
}

run "rejects_rule_with_two_sources" {
  command = plan

  variables {
    egress_rules = {
      bad = { from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16", prefix_list_id = "pl-0123456789abcdef0" }
    }
  }

  expect_failures = [var.egress_rules]
}

run "rejects_rule_without_source" {
  command = plan

  variables {
    ingress_rules = {
      bad = { from_port = 443, to_port = 443 }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_tcp_rule_without_ports" {
  command = plan

  variables {
    ingress_rules = {
      bad = { cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_all_protocol_rule_with_ports" {
  command = plan

  variables {
    egress_rules = {
      bad = { ip_protocol = "-1", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  expect_failures = [var.egress_rules]
}
