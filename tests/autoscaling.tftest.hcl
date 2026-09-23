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

  security_group_egress_rules = {
    https = { from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
  }
}

run "defaults_to_cpu_target_tracking" {
  command = plan

  variables {
    desired_count = 2
    autoscaling   = { min_capacity = 2, max_capacity = 8 }
  }

  assert {
    condition     = output.autoscaling_target_resource_id == "service/platform/orders-api" && length(output.autoscaling_policy_arns) == 1 && contains(keys(output.autoscaling_policy_arns), "cpu")
    error_message = "The autoscaling target and default policy must be exposed."
  }
}

run "passes_custom_policies_and_schedules_through" {
  command = plan

  variables {
    desired_count = 3
    autoscaling = {
      min_capacity = 2
      max_capacity = 20
      policies = {
        memory   = { target_tracking = { predefined_metric_type = "ECSServiceAverageMemoryUtilization", target_value = 75 } }
        requests = { target_tracking = { predefined_metric_type = "ALBRequestCountPerTarget", resource_label = "app/orders/0123456789abcdef/targetgroup/orders/0123456789abcdef", target_value = 500 } }
      }
      scheduled_actions = {
        weekday_morning = { schedule = "cron(0 7 ? * MON-FRI *)", timezone = "UTC", min_capacity = 5 }
      }
    }
  }

  assert {
    condition     = length(output.autoscaling_policy_arns) == 2 && contains(keys(output.autoscaling_policy_arns), "memory") && contains(keys(output.autoscaling_policy_arns), "requests") && contains(keys(output.autoscaling_scheduled_action_arns), "weekday_morning")
    error_message = "Custom policies and scheduled actions must be exposed by key."
  }
}
