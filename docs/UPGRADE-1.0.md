# Upgrading from 0.1.x to 1.0.0

## What changed and why

Version 0.1.x provisioned a fleet from one `applications` map, created a Cognito app client and a session-table grant inside the module, hard-coded egress to the VPC CIDR and the regional S3 prefix list through data sources, and injected its own tags. Version 1.0.0 provisions one service per module call, composes four focused submodules (`container-definition`, `iam`, `security-group`, `autoscaling`), makes every network rule, IAM statement, container, and scaling policy a declarative input, derives partition, region, account, and cluster name from `cluster_arn` with no data-source reads, and lets a caller substitute any managed resource. The reasons, and the table of 0.1.x behaviours that were replaced, are in [DESIGN.md](DESIGN.md). This guide gets an existing 0.1.x consumer onto 1.0.0 without recreating roles, security groups, or log groups.

## Input mapping

Root inputs of 0.1.3:

| 0.1.x input | 1.0.0 equivalent |
| --- | --- |
| `applications` | One module call per service. Keep your map and put `for_each` on the module block; `each.key` is the old application key. |
| `name` (prefix) | `name = "<prefix>-<key>"`. This is the service name, task family, and prefix for role and policy names, exactly as `local.application_names` was. |
| `cluster_arn` | `cluster_arn`, unchanged. |
| `cluster_name` | Removed. Derived from `cluster_arn`. |
| `vpc_id` | `vpc_id`, unchanged. Only needed while `create_security_group` is true. |
| `vpc_cidr` | Removed. Declare the rule yourself: `security_group_egress_rules = { vpc_tls = { from_port = 443, to_port = 443, cidr_ipv4 = var.vpc_cidr } }`. |
| implicit S3 prefix-list egress | Removed. Look the list up in your root with `data "aws_prefix_list" "s3" { name = "com.amazonaws.<region>.s3" }` and add `s3_tls = { from_port = 443, to_port = 443, prefix_list_id = data.aws_prefix_list.s3.id }` to `security_group_egress_rules`. |
| `private_subnet_ids` | `subnet_ids`. The two-subnet minimum is now the advisory `multi_az` check. |
| `application_data_kms_key_arn` | Two inputs: `cloudwatch_log_group_kms_key_id` for log encryption and `task_execution_role_kms_key_arns` for the execution role's `kms:Decrypt` grant. |
| `log_retention_in_days` | `cloudwatch_log_group_retention_in_days` (default 365). |
| `cognito_user_pool_id` | Removed. Pass the pool ID in `environment` yourself (see `cognito` below). |
| `session_table_arn` | Removed. Reference the table in a `task_role_statements` entry (see `enable_session_table_access` below). |
| `tags` | `tags`, unchanged shape. Merge any per-application tags in yourself. The module no longer injects `ManagedBy`, `IaCOwnership`, or `Application`; it adds only `Name`. |

Attributes of `applications[*]`:

| 0.1.x attribute | 1.0.0 equivalent |
| --- | --- |
| `image_digest` | `container_definitions.<name>.image`. Use the old application key as the container name to keep the container name and the load balancer wiring stable. Digest enforcement is unchanged (`require_image_digest = true`). |
| `cpu`, `memory` | `cpu`, `memory`, unchanged. |
| `desired_count` | `desired_count`, unchanged and still ignored after creation. |
| `force_new_deployment` | `force_new_deployment`, unchanged. |
| `autoscaling.min_capacity`, `autoscaling.max_capacity` | `autoscaling.min_capacity`, `autoscaling.max_capacity`. |
| `autoscaling.cpu_target_percent` | `autoscaling.policies.cpu.target_tracking = { predefined_metric_type = "ECSServiceAverageCPUUtilization", target_value = <percent> }`. Omitting `policies` gives the same policy at 60 percent. 0.1.x used a 60-second scale-in cooldown; the 1.0.0 default is 300, so set `scale_in_cooldown = 60` to keep the old behaviour. |
| `container_port` | `container_definitions.<name>.port_mappings = [{ container_port = <port> }]`. Ingress rules now carry their own ports (see `ingress_security_group_ids`). |
| `command` | `container_definitions.<name>.command` (null when unset instead of `[]`). |
| `environment` | `container_definitions.<name>.environment`. |
| `secret_arns` | `container_definitions.<name>.secrets`, same map shape. SSM parameter ARNs now work. |
| `secret_kms_key_arns` | `task_execution_role_kms_key_arns`. |
| `task_policy_statements` | `task_role_statements`. Same `{ Sid = { actions, resources } }` shape plus optional `effect` (default `Allow`) and `conditions`. |
| `enable_session_table_access` with `session_table_arn` | An explicit `task_role_statements` entry, given below. |
| `ingress_security_group_ids` | `security_group_ingress_rules`, one rule per source group: `{ from_port = <port>, to_port = <port>, referenced_security_group_id = "<sg>" }`. |
| `enable_execute_command` | `enable_execute_command`, unchanged. |
| `readonly_root_filesystem` | `container_definitions.<name>.readonly_root_filesystem` (default true). |
| `ephemeral_storage_gib` | `ephemeral_storage_size_in_gib`. |
| `cpu_architecture` | `cpu_architecture`, unchanged. |
| `health_check` | `container_definitions.<name>.health_check`. `interval`, `timeout`, `retries`, and `start_period` are now optional with defaults 30, 5, 3, and unset. |
| `cognito` | Removed. Create `aws_cognito_user_pool_client` beside the service and pass `COGNITO_USER_POOL_ID` and `COGNITO_CLIENT_ID` in `environment`, shown below. |
| `tags` | Merge into the module call's `tags`. |

The session-table statement 0.1.x generated, as a `task_role_statements` entry:

```hcl
task_role_statements = {
  UseDeclaredSessionTable = {
    actions   = ["dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
    resources = [var.session_table_arn, "${var.session_table_arn}/index/*"]
  }
}
```

The Cognito client 0.1.x created, declared beside the service with the same arguments, and its ID passed into the container:

```hcl
resource "aws_cognito_user_pool_client" "api" {
  name                                 = "${local.prefix}-api-client"
  user_pool_id                         = var.cognito_user_pool_id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  callback_urls                        = ["https://app.example.com/callback"]
  logout_urls                          = ["https://app.example.com/logout"]
  supported_identity_providers         = ["COGNITO"]
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
}

# inside the module call
container_definitions = {
  api = {
    image = local.applications.api.image
    environment = merge(local.applications.api.environment, {
      COGNITO_USER_POOL_ID = var.cognito_user_pool_id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.api.id
    })
  }
}
```

A complete rewrite for a consumer whose 0.1.x block was `module "workload"` with one application `api`:

```hcl
locals {
  prefix = "sandbox-workload-dev"

  applications = {
    api = {
      image                      = "123456789012.dkr.ecr.us-east-2.amazonaws.com/app@sha256:<64-hex-digest>"
      cpu                        = 256
      memory                     = 512
      desired_count              = 1
      min_capacity               = 1
      max_capacity               = 3
      container_port             = 8080
      environment                = { LOG_LEVEL = "info" }
      secrets                    = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-2:123456789012:secret:api/db-AbCdEf" }
      ingress_security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
    }
  }
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.us-east-2.s3"
}

module "workload" {
  source   = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git?ref=<commit-sha>" # v1.0.0
  for_each = local.applications

  name        = "${local.prefix}-${each.key}"
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids
  tags        = var.tags

  cpu           = each.value.cpu
  memory        = each.value.memory
  desired_count = each.value.desired_count

  container_definitions = {
    (each.key) = {
      image         = each.value.image
      port_mappings = [{ container_port = each.value.container_port }]
      secrets       = each.value.secrets
      environment = merge(each.value.environment, each.key == "api" ? {
        COGNITO_USER_POOL_ID = var.cognito_user_pool_id
        COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.api.id
      } : {})
    }
  }

  # Keep the 0.1.x names so nothing is replaced (see "Preserving existing resources").
  task_execution_role_path   = "/ecs/"
  task_role_path             = "/ecs/"
  security_group_name        = "${local.prefix}-${each.key}-tasks"
  security_group_description = "Private Fargate task security group for ${each.key}."
  cloudwatch_log_group_name  = "/aws/ecs/${local.prefix}/${each.key}"

  cloudwatch_log_group_kms_key_id        = var.application_data_kms_key_arn
  cloudwatch_log_group_retention_in_days = 365
  task_execution_role_kms_key_arns       = [var.application_data_kms_key_arn]

  security_group_egress_rules = {
    vpc_tls = { description = "TLS only to private VPC destinations", from_port = 443, to_port = 443, cidr_ipv4 = var.vpc_cidr }
    s3_tls  = { description = "TLS to the regional S3 gateway endpoint for ECR image layers", from_port = 443, to_port = 443, prefix_list_id = data.aws_prefix_list.s3.id }
  }

  security_group_ingress_rules = {
    for sg in each.value.ingress_security_group_ids : "from-${sg}" => {
      description                  = "Private application ingress from an approved security group"
      from_port                    = each.value.container_port
      to_port                      = each.value.container_port
      referenced_security_group_id = sg
    }
  }

  task_role_statements = {
    UseDeclaredSessionTable = {
      actions   = ["dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
      resources = [var.session_table_arn, "${var.session_table_arn}/index/*"]
    }
  }

  autoscaling = {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
    policies = {
      cpu = {
        target_tracking = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
          target_value           = 60
          scale_in_cooldown      = 60
        }
      }
    }
  }
}
```

The `services` output map is gone. `module.workload.services["api"].task_role_arn` becomes `module.workload["api"].task_role_arn`; the other fields map the same way (`name`, `arn`, `task_definition_arn`, `security_group_id`, `task_execution_role_arn`, `cloudwatch_log_group_name`). `cognito_client_id` is now `aws_cognito_user_pool_client.api.id` in your root.

## Preserving existing resources

The 1.0.0 defaults differ from the 0.1.x names in three places. Set these inputs so IAM roles, the security group, and the log group are updated in place instead of replaced:

| Resource | 0.1.x name | 1.0.0 input |
| --- | --- | --- |
| Service and task family | `<prefix>-<key>` | `name = "<prefix>-<key>"`. `family` defaults to `name`, so it already matches. |
| Task execution role | `<prefix>-<key>-execution`, path `/ecs/` | Name is already the default (`<name>-execution`). Set `task_execution_role_path = "/ecs/"`; the new default is `/` and a path change replaces the role. |
| Task role | `<prefix>-<key>-task`, path `/ecs/` | Name is already the default (`<name>-task`). Set `task_role_path = "/ecs/"`. |
| Security group | `<prefix>-<key>-tasks`, description `Private Fargate task security group for <key>.` | `security_group_name = "<name>-tasks"` and `security_group_description = "Private Fargate task security group for <key>."`. Both are immutable on the group; a different description would replace it. |
| Log group | `/aws/ecs/<prefix>/<key>` | `cloudwatch_log_group_name = "/aws/ecs/<prefix>/<key>"`. The new default is `/aws/ecs/<cluster>/<name>`. |
| Autoscaling policy | `<prefix>-<key>-cpu` | Policy key `cpu` produces `<name>-cpu`. |
| Container | named `<key>` | Use `<key>` as the `container_definitions` key. |

Set `cloudwatch_log_group_kms_key_id` and `cloudwatch_log_group_retention_in_days` to the old values, or the log group is updated in place to unencrypted and 365 days.

What will change even with those inputs, all expected:

- A new task definition revision. The container JSON differs (`awslogs-stream-prefix` is now `<name>` instead of `<key>`, and empty `environment` and `secrets` lists are no longer rendered), so ECS rolls the service to the new revision under the circuit breaker. Set `log_configuration` on the container if you need the old stream prefix.
- Inline policy names. `declared-secrets` on the execution role becomes `derived`; `application-access` on the task role becomes `declared` (your statements) plus `derived` (the ECS Exec statement when enabled). `aws_iam_role_policy` names are immutable, so the old policies are destroyed and the new ones created in the same apply. The role keeps its managed policy attachment throughout. The derived execution policy also narrows: `kms:DescribeKey` is dropped and Secrets Manager resources are reduced to the base secret ARN.
- Trust policies gain the `aws:SourceAccount` and `aws:SourceArn` conditions. `assume_role_policy` is updated in place.
- Tags on the roles, security group, log group, task definition, and service: `ManagedBy`, `IaCOwnership`, and `Application` disappear unless you add them to `tags`; rules and the scalable target gain tags. All in place.
- Egress and ingress rule descriptions, in place, unless you reproduce the old text as shown above.
- `availability_zone_rebalancing` becomes `ENABLED`, in place.
- The scale-in cooldown becomes 300 seconds unless you set 60, in place.
- `terraform_data.application_contract` is destroyed and the three data sources leave state. Neither touches AWS.

## State moves

Old addresses are those of 0.1.3 under `module.workload` with application key `api`. New addresses are under `module.workload["api"]`. Rule keys (`vpc_tls`, `s3_tls`, `from-sg-...`) are the ones you chose in your egress and ingress maps.

| 0.1.3 address | 1.0.0 address |
| --- | --- |
| `module.workload.aws_ecs_service.application["api"]` | `module.workload["api"].aws_ecs_service.this[0]` |
| `module.workload.aws_ecs_task_definition.application["api"]` | `module.workload["api"].aws_ecs_task_definition.this` |
| `module.workload.aws_cloudwatch_log_group.application["api"]` | `module.workload["api"].aws_cloudwatch_log_group.this[0]` |
| `module.workload.aws_security_group.application["api"]` | `module.workload["api"].module.security_group.aws_security_group.this[0]` |
| `module.workload.aws_vpc_security_group_egress_rule.application_https_to_vpc["api"]` | `module.workload["api"].module.security_group.aws_vpc_security_group_egress_rule.this["vpc_tls"]` |
| `module.workload.aws_vpc_security_group_egress_rule.application_https_to_s3["api"]` | `module.workload["api"].module.security_group.aws_vpc_security_group_egress_rule.this["s3_tls"]` |
| `module.workload.aws_vpc_security_group_ingress_rule.application["api:sg-0aaaaaaaaaaaaaaaa"]` | `module.workload["api"].module.security_group.aws_vpc_security_group_ingress_rule.this["from-sg-0aaaaaaaaaaaaaaaa"]` |
| `module.workload.aws_iam_role.execution["api"]` | `module.workload["api"].module.iam.aws_iam_role.task_execution[0]` |
| `module.workload.aws_iam_role_policy_attachment.execution["api"]` | `module.workload["api"].module.iam.aws_iam_role_policy_attachment.task_execution_default[0]` |
| `module.workload.aws_iam_role_policy.execution_secrets["api"]` | Not moved. Destroyed; `module.iam.aws_iam_role_policy.task_execution_derived[0]` is created. |
| `module.workload.aws_iam_role.task["api"]` | `module.workload["api"].module.iam.aws_iam_role.task[0]` |
| `module.workload.aws_iam_role_policy.task["api"]` | Not moved. Destroyed; `module.iam.aws_iam_role_policy.task_declared[0]` (and `task_derived[0]` with ECS Exec) are created. |
| `module.workload.aws_appautoscaling_target.application["api"]` | `module.workload["api"].module.autoscaling[0].aws_appautoscaling_target.this` |
| `module.workload.aws_appautoscaling_policy.application_cpu["api"]` | `module.workload["api"].module.autoscaling[0].aws_appautoscaling_policy.this["cpu"]` |
| `module.workload.aws_cognito_user_pool_client.application["api"]` | `aws_cognito_user_pool_client.api` in your root (or wherever you declared it). |
| `module.workload.terraform_data.application_contract` | Not moved. Destroyed. |

Ready to paste into your root configuration. Repeat the set for every application key and every ingress source group.

```hcl
moved {
  from = module.workload.aws_ecs_service.application["api"]
  to   = module.workload["api"].aws_ecs_service.this[0]
}

moved {
  from = module.workload.aws_ecs_task_definition.application["api"]
  to   = module.workload["api"].aws_ecs_task_definition.this
}

moved {
  from = module.workload.aws_cloudwatch_log_group.application["api"]
  to   = module.workload["api"].aws_cloudwatch_log_group.this[0]
}

moved {
  from = module.workload.aws_security_group.application["api"]
  to   = module.workload["api"].module.security_group.aws_security_group.this[0]
}

moved {
  from = module.workload.aws_vpc_security_group_egress_rule.application_https_to_vpc["api"]
  to   = module.workload["api"].module.security_group.aws_vpc_security_group_egress_rule.this["vpc_tls"]
}

moved {
  from = module.workload.aws_vpc_security_group_egress_rule.application_https_to_s3["api"]
  to   = module.workload["api"].module.security_group.aws_vpc_security_group_egress_rule.this["s3_tls"]
}

moved {
  from = module.workload.aws_vpc_security_group_ingress_rule.application["api:sg-0aaaaaaaaaaaaaaaa"]
  to   = module.workload["api"].module.security_group.aws_vpc_security_group_ingress_rule.this["from-sg-0aaaaaaaaaaaaaaaa"]
}

moved {
  from = module.workload.aws_iam_role.execution["api"]
  to   = module.workload["api"].module.iam.aws_iam_role.task_execution[0]
}

moved {
  from = module.workload.aws_iam_role_policy_attachment.execution["api"]
  to   = module.workload["api"].module.iam.aws_iam_role_policy_attachment.task_execution_default[0]
}

moved {
  from = module.workload.aws_iam_role.task["api"]
  to   = module.workload["api"].module.iam.aws_iam_role.task[0]
}

moved {
  from = module.workload.aws_appautoscaling_target.application["api"]
  to   = module.workload["api"].module.autoscaling[0].aws_appautoscaling_target.this
}

moved {
  from = module.workload.aws_appautoscaling_policy.application_cpu["api"]
  to   = module.workload["api"].module.autoscaling[0].aws_appautoscaling_policy.this["cpu"]
}

moved {
  from = module.workload.aws_cognito_user_pool_client.application["api"]
  to   = aws_cognito_user_pool_client.api
}
```

## Procedure

1. Pin the 1.0.0 release: copy the commit SHA of tag `v1.0.0` into `?ref=<commit-sha>` and put the tag in a trailing comment.
2. Rewrite the module block as shown above: `for_each` over your existing application map, one call per service, inputs mapped with the tables. Add the `aws_prefix_list` data source and the `aws_cognito_user_pool_client` resource to your root if you used those features.
3. Set the name-preserving inputs: `name`, `task_execution_role_path`, `task_role_path`, `security_group_name`, `security_group_description`, `cloudwatch_log_group_name`, plus the old KMS key and retention.
4. Add the `moved` blocks for every application key and ingress source group.
5. Run `terraform init -upgrade` to fetch the new module source, then `terraform plan`.
6. Verify the plan. There must be no replacement or destruction of `aws_iam_role`, `aws_security_group`, `aws_cloudwatch_log_group`, or `aws_appautoscaling_target`. Expect: `aws_ecs_task_definition` replaced (a new revision), `aws_ecs_service` updated in place, `aws_iam_role_policy` destroyed and created under the new names, `assume_role_policy` and tag updates in place, `terraform_data.application_contract` destroyed, and the Cognito client unchanged or updated in place. If anything else shows `must be replaced`, compare its name, path, or description with the table above before applying.
7. Apply. The service performs one rolling deployment to the new task definition revision; the circuit breaker rolls back if tasks fail to start.
8. Remove the `moved` blocks in a later change once every workspace that used 0.1.x has applied the upgrade.
