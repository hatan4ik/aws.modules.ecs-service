# aws.modules.ecs-service

Provisions one Amazon ECS service on AWS Fargate together with everything a service cannot run without: a task definition, a task execution role and a task role, a task security group, a CloudWatch log group, and optional Application Auto Scaling. It is secure by default and explicit by declaration. Every managed resource can be replaced by a caller-supplied one without changing the module's outputs, and the module performs no data-source reads: partition, region, account, and cluster name are derived from `cluster_arn`. Requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

## Why this module

What you get without setting anything:

- Private tasks. `assign_public_ip` is false and networking is `awsvpc` in the subnets you name.
- No ingress. The managed security group starts with no ingress rules and no egress rules. You declare what may reach the tasks and what the tasks may reach.
- Digest-pinned images. Every container image must end in `@sha256:<64 hex>` or the plan fails.
- Read-only root filesystem on every container.
- Deployment circuit breaker with rollback, rolling deployments at 100/200 percent, ECS-managed tags.
- Availability Zone rebalancing enabled.
- Least-privilege execution role: `AmazonECSTaskExecutionRolePolicy` plus read access to exactly the secrets, parameters, and KMS keys your containers reference.
- Confused-deputy protection: both role trust policies are conditioned on `aws:SourceAccount` and `aws:SourceArn` for the cluster's account and region.
- A log group with 365-day retention, encrypted with your KMS key when you pass `cloudwatch_log_group_kms_key_id`, injected as the `awslogs` driver into every container that declares no logging of its own.
- Plan-time validation of Fargate CPU/memory combinations, name lengths, and every cross-reference: container dependencies, volumes, load balancer containers, Service Connect port names, autoscaling bounds.

## Quick start

```hcl
module "orders_api" {
  source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git?ref=<commit-sha>" # v1.0.0

  name        = "orders-api"
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  container_definitions = {
    app = {
      image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:<64-hex-digest>"
      port_mappings = [{ name = "http", container_port = 8080 }]
    }
  }

  security_group_egress_rules = {
    vpc_tls = { description = "TLS to VPC endpoints", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16" }
  }

  tags = { Environment = "prod", Owner = "orders" }
}
```

This creates the task definition family `orders-api` (256 CPU units, 512 MiB, Linux x86_64), the service `orders-api` with one task, the roles `orders-api-execution` and `orders-api-task`, the security group `orders-api` with one egress rule, and the log group `/aws/ecs/platform/orders-api`; autoscaling stays off until you set `autoscaling`.

## Architecture

```text
root (one service)
├── modules/container-definition   Pure renderer: typed inputs -> one container JSON object. No resources, no provider.
├── modules/iam                    Task execution role and task role, scoped trust, derived and declared inline policies.
├── modules/security-group         Task security group with one standalone resource per ingress and egress rule.
├── aws_cloudwatch_log_group.this  Optional log group, KMS-capable, injected into containers as the awslogs driver.
├── aws_ecs_task_definition.this   Fargate, awsvpc, multi-container, volumes, runtime platform, plan-time preconditions.
├── aws_ecs_service.this           The service (or .ignore_task_definition when an external deployer owns rollouts).
└── modules/autoscaling            Scalable target, target-tracking and step policies, scheduled actions.
```

Container specs are rendered first. The IAM module derives execution-role statements from the rendered secret references. The root injects an `awslogs` configuration into any container without its own log configuration. The service depends on the security-group and IAM modules so the first deployment cannot start before its network and permissions exist.

| Concern | Managed by default | Bring your own |
| --- | --- | --- |
| Task execution role | `<name>-execution` with `AmazonECSTaskExecutionRolePolicy` and a `derived` inline policy for referenced secrets, parameters, and KMS keys. | `create_task_execution_role = false` and `task_execution_role_arn`. Attach output `task_execution_role_derived_policy` to that role yourself; the module never modifies a supplied role. |
| Task role | `<name>-task`, empty until you add `task_role_statements` or `task_role_policy_arns`. | `create_task_role = false` and `task_role_arn`. Attach output `task_role_derived_policy` when `enable_execute_command` is on. |
| Security group | `<name>` in `vpc_id` with your `security_group_ingress_rules` and `security_group_egress_rules`. | `create_security_group = false` and at least one ID in `security_group_ids`. `security_group_ids` also adds groups alongside the managed one. |
| Log group | `/aws/ecs/<cluster>/<name>`, 365-day retention, `STANDARD` class. | `create_cloudwatch_log_group = false` and `cloudwatch_log_group_name` naming an existing group. Leave the name null to inject no log configuration at all. |
| Autoscaling | None. `autoscaling` defaults to `null`. | Set `autoscaling = { min_capacity, max_capacity }` for a managed target with CPU target tracking at 60 percent, or keep it null and register your own scalable target against outputs `cluster_name` and `name`. |

## Usage patterns

| Example | What it shows |
| --- | --- |
| [`examples/minimal`](examples/minimal) | The smallest working service: one container, one egress rule, everything else defaulted. |
| [`examples/complete`](examples/complete) | The full interface: sidecars, volumes, secrets and KMS, ECS Exec, capacity providers, deployment tuning, autoscaling policies and schedules. |
| [`examples/private-platform`](examples/private-platform) | A service in private subnets that reaches AWS only through VPC endpoints and the regional S3 prefix list. |
| [`examples/load-balanced`](examples/load-balanced) | Registration with a target group, ingress from the load balancer's security group, health check grace period, request-count scaling. |
| [`examples/multiple-services`](examples/multiple-services) | `for_each` over a map of services: one module call per service sharing a cluster and VPC. |
| [`examples/bring-your-own`](examples/bring-your-own) | Caller-supplied roles, security group, and log group. The module creates only the task definition and the service. |

## Security model

Network

- Tasks receive no public IP unless `assign_public_ip = true`.
- The managed security group has no ingress by default. Each ingress and egress rule names exactly one source or destination (`cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_id`, or `self`) and is its own resource, so adding or removing a rule never touches the others.
- Egress is explicit. The AWS provider removes the default allow-all egress when it creates the group, so tasks cannot pull images until you declare egress. The `security_group_egress` check warns on every plan while the managed group has no egress rules.
- The service depends on the security-group and IAM modules, so the first deployment cannot start before rules and role policies exist.

Identity

- The execution role (`<name>-execution`) gets `AmazonECSTaskExecutionRolePolicy` from the cluster's partition, `secretsmanager:GetSecretValue` on the base ARN of every Secrets Manager secret referenced in `secrets` or log `secret_options`, `ssm:GetParameters` on every referenced SSM parameter, `kms:Decrypt` on `task_execution_role_kms_key_arns`, and whatever you add through `task_execution_role_policy_arns` and `task_execution_role_statements`. It does not get access to secrets you did not reference, `kms:DescribeKey`, or wildcard resources.
- The task role (`<name>-task`) is empty. Application access is declared in `task_role_statements` (keyed by Sid, with optional `effect` and `conditions`) and `task_role_policy_arns`. `enable_execute_command = true` adds only the four `ssmmessages` channel actions.
- Both trust policies allow `ecs-tasks.amazonaws.com` only when `aws:SourceAccount` equals the cluster's account and `aws:SourceArn` matches `arn:<partition>:ecs:<region>:<account>:*`.
- Each created role accepts a permissions boundary, path, and description. Supplied roles are never modified.

Images

- `require_image_digest` is true by default. A precondition on the task definition rejects any container image that does not end in `@sha256:<64 hex>`, so rollbacks are exact and deployments reproducible. Set `require_image_digest = false` to opt out deliberately; `version_consistency` is available per container when you do.

Logs

- One log group per service, `/aws/ecs/<cluster>/<name>`, retention 365 days (`cloudwatch_log_group_retention_in_days`), class `STANDARD`. `cloudwatch_log_group_kms_key_id` encrypts it with your key; the key policy must allow the CloudWatch Logs service principal. `cloudwatch_log_group_skip_destroy` keeps the data on destroy.
- A container with its own `log_configuration` keeps it; the managed configuration is injected only where none is declared.

Not created here

- The ECS cluster, VPC and subnets, load balancers and target groups, DNS records, certificates, identity-provider clients, data stores, KMS keys, and secrets. They have separate lifecycles and owners. The module consumes their identifiers.

## Lifecycle notes

- `desired_count` is the bootstrap count. Both service resources set `ignore_changes = [desired_count]`, so changing the variable after creation does nothing; Application Auto Scaling, deployments, and operators own the running count. At plan time it must lie within `autoscaling.min_capacity` and `max_capacity` when autoscaling is set.
- `ignore_task_definition_changes = true` selects `aws_ecs_service.ignore_task_definition[0]`, which also ignores `task_definition`, so a CI pipeline or CodeDeploy can own rollouts while Terraform still owns the service. Terraform cannot make `ignore_changes` conditional, so two identical resource blocks exist and exactly one is created; outputs resolve from whichever exists. Toggling the flag on an existing service changes the resource address. Add a `moved` block from `aws_ecs_service.this[0]` to `aws_ecs_service.ignore_task_definition[0]` (or back) to avoid replacing the service.
- Three `check` blocks warn on every plan and apply but never block: `security_group_egress` (the managed group has no egress rules), `multi_az` (fewer than two subnets), and `supplied_execution_role_secrets` (containers reference secrets but the execution role is caller-supplied; attach `task_execution_role_derived_policy`).
- `force_new_deployment = true` forces a new deployment on every apply, for example after a networking prerequisite changed. It defaults to false.
- Task definitions are immutable. Every content change registers a new revision and the service rolls to it under the circuit breaker. `skip_destroy` keeps old revisions active; `track_latest` follows revisions registered outside Terraform.

## Testing

Two layers, deliberately separate:

- **Contract tests** (`tests/`, run by `make test` and by CI) use `mock_provider`: no credentials, nothing created, placeholder identifiers such as the AWS documentation account `123456789012`. They pin the module's interface, validations, rendered JSON, and defaults, and run identically for everyone.
- **Integration suites** (`tests/integration/`, run by `make integration-smoke` and `make integration-e2e`, or the dispatch-only `integration` workflow) apply the module for real in **your** account with **your** credentials and region from the environment, against disposable fixtures the suite creates and destroys itself. `smoke` proves every resource is accepted by the AWS APIs without starting a task; `e2e` runs one task to steady state. See [tests/integration/README.md](tests/integration/README.md) for permissions and the GitHub environment contract.

## Design principles

- Single responsibility. Each submodule has one reason to change: the container JSON schema, the IAM role and policy shape, the security-group rule shape, the scaling policy shape. The root owns only the task definition, the service, and the log group.
- Open/closed. New behaviour is added by declaring data (a container, a rule, a statement, a policy, a scheduled action), not by editing the module. Names, paths, descriptions, and boundaries are inputs.
- Liskov substitution. A caller-supplied role, security group, or log group is a drop-in for a managed one. Outputs and downstream wiring are identical; only the `create_*` flag and its ARN, ID, or name input change.
- Interface segregation. Feature groups are optional objects that default to `null` or `{}`. Required inputs are `name`, `cluster_arn`, `subnet_ids`, and one container; with the default managed security group you also pass `vpc_id`.
- Dependency inversion. The root depends on identifiers, never on how upstream resources were produced. Partition, region, account, and cluster name derive from `cluster_arn`, and there are no data sources.

The full rationale, including why the v0.1.x design was replaced, is in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- Fargate only. The service uses `launch_type = "FARGATE"`, or a `capacity_provider_strategy` of `FARGATE` and `FARGATE_SPOT` entries, which replaces `launch_type`. Linux and Windows Server operating system families, x86_64 and ARM64.
- Roadmap: EC2 launch type, managed EBS volumes, and App Mesh proxy configuration. They will arrive as optional inputs and will not break the v1 interface.

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the major version, new optional inputs and outputs bump the minor version, fixes bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment, so the source cannot move under you:

```hcl
module "orders_api" {
  source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git?ref=<commit-sha>" # v1.0.0
}

module "app_container" {
  source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git//modules/container-definition?ref=<commit-sha>" # v1.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only from a GitHub-verified, signed, annotated semantic-version tag that points at the merged `main` revision; lightweight or unsigned tags are rejected before anything is published. With a GitHub-associated GPG or SSH signing key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

Dispatch from the tag, never from `main`: the workflow verifies that the tag points at the revision it checked out, and a maintenance release for an older line (for example a 0.1.x fix after 1.0.0 landed on `main`) is cut from that line's commit.

Upgrading from 0.1.x: read [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md) for the input mapping, the settings that preserve existing resources, and ready-to-paste `moved` blocks. All changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Development setup, the local quality gate, the test-first workflow, and the release process are described in [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_autoscaling"></a> [autoscaling](#module\_autoscaling) | ./modules/autoscaling | n/a |
| <a name="module_container_definition"></a> [container\_definition](#module\_container\_definition) | ./modules/container-definition | n/a |
| <a name="module_iam"></a> [iam](#module\_iam) | ./modules/iam | n/a |
| <a name="module_security_group"></a> [security\_group](#module\_security\_group) | ./modules/security-group | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_service.ignore_task_definition](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarms"></a> [alarms](#input\_alarms) | CloudWatch alarms that fail (and by default roll back) a deployment. | <pre>object({<br/>    alarm_names = set(string)<br/>    enable      = optional(bool, true)<br/>    rollback    = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_assign_public_ip"></a> [assign\_public\_ip](#input\_assign\_public\_ip) | Give tasks a public IP. Leave false; expose services through a load balancer instead. | `bool` | `false` | no |
| <a name="input_autoscaling"></a> [autoscaling](#input\_autoscaling) | Application Auto Scaling for the service. Null disables it. Omitting policies applies CPU target tracking at 60 percent. See modules/autoscaling for policy and schedule shapes. | <pre>object({<br/>    min_capacity = number<br/>    max_capacity = number<br/>    policies = optional(map(object({<br/>      policy_type = optional(string, "TargetTrackingScaling")<br/>      target_tracking = optional(object({<br/>        predefined_metric_type = optional(string)<br/>        resource_label         = optional(string)<br/>        customized_metric = optional(object({<br/>          metric_name = string<br/>          namespace   = string<br/>          statistic   = string<br/>          unit        = optional(string)<br/>          dimensions  = optional(map(string), {})<br/>        }))<br/>        target_value       = number<br/>        scale_in_cooldown  = optional(number, 300)<br/>        scale_out_cooldown = optional(number, 60)<br/>        disable_scale_in   = optional(bool, false)<br/>      }))<br/>      step_scaling = optional(object({<br/>        adjustment_type          = optional(string, "ChangeInCapacity")<br/>        cooldown                 = optional(number, 60)<br/>        metric_aggregation_type  = optional(string, "Average")<br/>        min_adjustment_magnitude = optional(number)<br/>        step_adjustments = list(object({<br/>          scaling_adjustment          = number<br/>          metric_interval_lower_bound = optional(number)<br/>          metric_interval_upper_bound = optional(number)<br/>        }))<br/>      }))<br/>    })))<br/>    scheduled_actions = optional(map(object({<br/>      schedule     = string<br/>      timezone     = optional(string)<br/>      min_capacity = optional(number)<br/>      max_capacity = optional(number)<br/>      start_time   = optional(string)<br/>      end_time     = optional(string)<br/>    })), {})<br/>  })</pre> | `null` | no |
| <a name="input_availability_zone_rebalancing"></a> [availability\_zone\_rebalancing](#input\_availability\_zone\_rebalancing) | Let ECS rebalance tasks across Availability Zones: ENABLED or DISABLED. | `string` | `"ENABLED"` | no |
| <a name="input_capacity_provider_strategy"></a> [capacity\_provider\_strategy](#input\_capacity\_provider\_strategy) | Fargate capacity provider strategy keyed by a short name. When non-empty the service uses the strategy instead of launch\_type FARGATE, which enables FARGATE\_SPOT. | <pre>map(object({<br/>    capacity_provider = string<br/>    weight            = optional(number, 1)<br/>    base              = optional(number)<br/>  }))</pre> | `{}` | no |
| <a name="input_cloudwatch_log_group_class"></a> [cloudwatch\_log\_group\_class](#input\_cloudwatch\_log\_group\_class) | Log group class: STANDARD or INFREQUENT\_ACCESS. | `string` | `"STANDARD"` | no |
| <a name="input_cloudwatch_log_group_kms_key_id"></a> [cloudwatch\_log\_group\_kms\_key\_id](#input\_cloudwatch\_log\_group\_kms\_key\_id) | KMS key ARN that encrypts the created log group. The key policy must allow the CloudWatch Logs service principal. | `string` | `null` | no |
| <a name="input_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#input\_cloudwatch\_log\_group\_name) | Log group name. Defaults to /aws/ecs/<cluster>/<name>. When create\_cloudwatch\_log\_group is false and this is set, containers log to the named existing group. | `string` | `null` | no |
| <a name="input_cloudwatch_log_group_retention_in_days"></a> [cloudwatch\_log\_group\_retention\_in\_days](#input\_cloudwatch\_log\_group\_retention\_in\_days) | Retention of the created log group in days (0 keeps logs forever). | `number` | `365` | no |
| <a name="input_cloudwatch_log_group_skip_destroy"></a> [cloudwatch\_log\_group\_skip\_destroy](#input\_cloudwatch\_log\_group\_skip\_destroy) | Keep the log group and its data when the module is destroyed. | `bool` | `false` | no |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the existing ECS cluster that runs the service. The module derives the cluster name, partition, region, and account from it and performs no lookups. | `string` | n/a | yes |
| <a name="input_container_definitions"></a> [container\_definitions](#input\_container\_definitions) | Containers in the task keyed by container name. At least one must be essential. See modules/container-definition for every attribute. | <pre>map(object({<br/>    image              = string<br/>    essential          = optional(bool, true)<br/>    command            = optional(list(string))<br/>    entrypoint         = optional(list(string))<br/>    working_directory  = optional(string)<br/>    user               = optional(string)<br/>    cpu                = optional(number)<br/>    memory             = optional(number)<br/>    memory_reservation = optional(number)<br/>    environment        = optional(map(string), {})<br/>    environment_files = optional(list(object({<br/>      type  = optional(string, "s3")<br/>      value = string<br/>    })), [])<br/>    secrets = optional(map(string), {})<br/>    port_mappings = optional(list(object({<br/>      name           = optional(string)<br/>      container_port = number<br/>      host_port      = optional(number)<br/>      protocol       = optional(string, "tcp")<br/>      app_protocol   = optional(string)<br/>    })), [])<br/>    health_check = optional(object({<br/>      command      = list(string)<br/>      interval     = optional(number, 30)<br/>      timeout      = optional(number, 5)<br/>      retries      = optional(number, 3)<br/>      start_period = optional(number)<br/>    }))<br/>    readonly_root_filesystem = optional(bool, true)<br/>    linux_parameters = optional(object({<br/>      init_process_enabled = optional(bool, false)<br/>      capabilities = optional(object({<br/>        add  = optional(list(string), [])<br/>        drop = optional(list(string), [])<br/>      }))<br/>    }))<br/>    ulimits = optional(list(object({<br/>      name       = string<br/>      soft_limit = number<br/>      hard_limit = number<br/>    })), [])<br/>    mount_points = optional(list(object({<br/>      source_volume  = string<br/>      container_path = string<br/>      read_only      = optional(bool, false)<br/>    })), [])<br/>    volumes_from = optional(list(object({<br/>      source_container = string<br/>      read_only        = optional(bool, false)<br/>    })), [])<br/>    container_dependencies = optional(list(object({<br/>      container_name = string<br/>      condition      = string<br/>    })), [])<br/>    start_timeout = optional(number)<br/>    stop_timeout  = optional(number)<br/>    docker_labels = optional(map(string), {})<br/>    system_controls = optional(list(object({<br/>      namespace = string<br/>      value     = string<br/>    })), [])<br/>    log_configuration = optional(object({<br/>      log_driver = string<br/>      options    = optional(map(string), {})<br/>      secret_options = optional(list(object({<br/>        name       = string<br/>        value_from = string<br/>      })), [])<br/>    }))<br/>    repository_credentials = optional(object({<br/>      credentials_parameter = string<br/>    }))<br/>    firelens_configuration = optional(object({<br/>      type    = string<br/>      options = optional(map(string), {})<br/>    }))<br/>    restart_policy = optional(object({<br/>      enabled                = bool<br/>      ignored_exit_codes     = optional(list(number), [])<br/>      restart_attempt_period = optional(number)<br/>    }))<br/>    interactive         = optional(bool, false)<br/>    pseudo_terminal     = optional(bool, false)<br/>    version_consistency = optional(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task-level CPU units. Must be a Fargate size (256, 512, 1024, 2048, 4096, 8192, 16384) and compatible with memory. | `number` | `256` | no |
| <a name="input_cpu_architecture"></a> [cpu\_architecture](#input\_cpu\_architecture) | CPU architecture of the task: X86\_64 or ARM64. | `string` | `"X86_64"` | no |
| <a name="input_create_cloudwatch_log_group"></a> [create\_cloudwatch\_log\_group](#input\_create\_cloudwatch\_log\_group) | Create a CloudWatch log group and inject an awslogs configuration into every container that has none. | `bool` | `true` | no |
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create\_security\_group) | Create a task security group. When false, security\_group\_ids must supply at least one group. | `bool` | `true` | no |
| <a name="input_create_task_execution_role"></a> [create\_task\_execution\_role](#input\_create\_task\_execution\_role) | Create the task execution role. When false, supply task\_execution\_role\_arn and grant it the permissions in output task\_execution\_role\_derived\_policy. | `bool` | `true` | no |
| <a name="input_create_task_role"></a> [create\_task\_role](#input\_create\_task\_role) | Create the task role. When false, supply task\_role\_arn. | `bool` | `true` | no |
| <a name="input_deployment_circuit_breaker"></a> [deployment\_circuit\_breaker](#input\_deployment\_circuit\_breaker) | ECS deployment circuit breaker. Enabled with rollback by default; only valid with the ECS deployment controller. | <pre>object({<br/>    enable   = optional(bool, true)<br/>    rollback = optional(bool, true)<br/>  })</pre> | `{}` | no |
| <a name="input_deployment_configuration"></a> [deployment\_configuration](#input\_deployment\_configuration) | ECS-native deployment strategy (ROLLING, BLUE\_GREEN, LINEAR, or CANARY) with bake time, traffic shifting, and lifecycle hooks. Blue/green needs load\_balancers[*].advanced\_configuration. | <pre>object({<br/>    strategy             = optional(string, "ROLLING")<br/>    bake_time_in_minutes = optional(number)<br/>    canary = optional(object({<br/>      canary_percent              = number<br/>      canary_bake_time_in_minutes = optional(number)<br/>    }))<br/>    linear = optional(object({<br/>      step_percent              = number<br/>      step_bake_time_in_minutes = optional(number)<br/>    }))<br/>    lifecycle_hooks = optional(map(object({<br/>      hook_target_arn  = string<br/>      role_arn         = string<br/>      lifecycle_stages = set(string)<br/>      target_type      = optional(string)<br/>      hook_details     = optional(string)<br/>      timeout = optional(object({<br/>        action             = optional(string)<br/>        timeout_in_minutes = optional(number)<br/>      }))<br/>    })), {})<br/>  })</pre> | `null` | no |
| <a name="input_deployment_controller_type"></a> [deployment\_controller\_type](#input\_deployment\_controller\_type) | Deployment controller: ECS, CODE\_DEPLOY, or EXTERNAL. | `string` | `"ECS"` | no |
| <a name="input_deployment_maximum_percent"></a> [deployment\_maximum\_percent](#input\_deployment\_maximum\_percent) | Upper limit of running tasks during a deployment, as a percentage of desired\_count. | `number` | `200` | no |
| <a name="input_deployment_minimum_healthy_percent"></a> [deployment\_minimum\_healthy\_percent](#input\_deployment\_minimum\_healthy\_percent) | Lower limit of running tasks during a deployment, as a percentage of desired\_count. | `number` | `100` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Number of tasks to run at creation. Later drift is ignored because autoscaling, deployments, and operators legitimately change it. | `number` | `1` | no |
| <a name="input_enable_ecs_managed_tags"></a> [enable\_ecs\_managed\_tags](#input\_enable\_ecs\_managed\_tags) | Let ECS tag tasks with cluster and service names. | `bool` | `true` | no |
| <a name="input_enable_execute_command"></a> [enable\_execute\_command](#input\_enable\_execute\_command) | Enable ECS Exec on the service and grant the task role the SSM channel permissions it needs. | `bool` | `false` | no |
| <a name="input_enable_fault_injection"></a> [enable\_fault\_injection](#input\_enable\_fault\_injection) | Allow AWS Fault Injection Service experiments against the task. | `bool` | `false` | no |
| <a name="input_ephemeral_storage_size_in_gib"></a> [ephemeral\_storage\_size\_in\_gib](#input\_ephemeral\_storage\_size\_in\_gib) | Ephemeral task storage in GiB (21-200). Null keeps the 20 GiB Fargate default. | `number` | `null` | no |
| <a name="input_family"></a> [family](#input\_family) | Task definition family. Defaults to name. | `string` | `null` | no |
| <a name="input_force_delete"></a> [force\_delete](#input\_force\_delete) | Delete the service even when it still has running tasks. | `bool` | `false` | no |
| <a name="input_force_new_deployment"></a> [force\_new\_deployment](#input\_force\_new\_deployment) | Force a new deployment on every apply, for example after a networking prerequisite changed. | `bool` | `false` | no |
| <a name="input_health_check_grace_period_seconds"></a> [health\_check\_grace\_period\_seconds](#input\_health\_check\_grace\_period\_seconds) | Seconds to ignore failing load balancer health checks after a task starts. Only valid with load\_balancers. | `number` | `null` | no |
| <a name="input_ignore_task_definition_changes"></a> [ignore\_task\_definition\_changes](#input\_ignore\_task\_definition\_changes) | Ignore task definition drift on the service so an external deployer (CI, CodeDeploy) owns rollouts while Terraform still owns the service. | `bool` | `false` | no |
| <a name="input_load_balancers"></a> [load\_balancers](#input\_load\_balancers) | Target groups the service registers with, keyed by a short name. container\_name must be a declared container. advanced\_configuration is required for blue/green deployments. | <pre>map(object({<br/>    target_group_arn = string<br/>    container_name   = string<br/>    container_port   = number<br/>    advanced_configuration = optional(object({<br/>      alternate_target_group_arn = string<br/>      production_listener_rule   = string<br/>      role_arn                   = string<br/>      test_listener_rule         = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Task-level memory in MiB. Must be a Fargate size compatible with cpu (validated at plan time). | `number` | `512` | no |
| <a name="input_name"></a> [name](#input\_name) | Service name. Also the default task family, security group name, and prefix for IAM roles and autoscaling policies. Lowercase alphanumerics and hyphens, 1-54 characters, so every derived name fits its AWS limit. | `string` | n/a | yes |
| <a name="input_operating_system_family"></a> [operating\_system\_family](#input\_operating\_system\_family) | Operating system family of the task: LINUX or a WINDOWS\_SERVER\_<2019\|2022\|2025>\_<CORE\|FULL> value. Windows tasks need at least 1024 CPU units. | `string` | `"LINUX"` | no |
| <a name="input_pid_mode"></a> [pid\_mode](#input\_pid\_mode) | Process namespace sharing for the task. Fargate supports only task (shared) or null (per container). | `string` | `null` | no |
| <a name="input_platform_version"></a> [platform\_version](#input\_platform\_version) | Fargate platform version: LATEST or an explicit version such as 1.4.0. | `string` | `"LATEST"` | no |
| <a name="input_propagate_tags"></a> [propagate\_tags](#input\_propagate\_tags) | Propagate tags to tasks from the SERVICE, the TASK\_DEFINITION, or NONE. | `string` | `"SERVICE"` | no |
| <a name="input_require_image_digest"></a> [require\_image\_digest](#input\_require\_image\_digest) | Reject container images that are not pinned to a sha256 digest. Digest pinning makes deployments reproducible and rollbacks exact. | `bool` | `true` | no |
| <a name="input_security_group_description"></a> [security\_group\_description](#input\_security\_group\_description) | Description of the managed security group. Changing it replaces the group. | `string` | `null` | no |
| <a name="input_security_group_egress_rules"></a> [security\_group\_egress\_rules](#input\_security\_group\_egress\_rules) | Egress rules for the managed security group, same shape as security\_group\_ingress\_rules. Declare what the tasks may reach; without egress they cannot pull images. | <pre>map(object({<br/>    description                  = optional(string)<br/>    from_port                    = optional(number)<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    self                         = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Additional security groups attached to the tasks, or the only groups when create\_security\_group is false. | `set(string)` | `[]` | no |
| <a name="input_security_group_ingress_rules"></a> [security\_group\_ingress\_rules](#input\_security\_group\_ingress\_rules) | Ingress rules for the managed security group keyed by a stable identifier. Each rule names exactly one source: cidr\_ipv4, cidr\_ipv6, prefix\_list\_id, referenced\_security\_group\_id, or self. Empty by default: nothing can reach the tasks. | <pre>map(object({<br/>    description                  = optional(string)<br/>    from_port                    = optional(number)<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    self                         = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_security_group_name"></a> [security\_group\_name](#input\_security\_group\_name) | Name of the managed security group. Defaults to name. | `string` | `null` | no |
| <a name="input_service_connect_configuration"></a> [service\_connect\_configuration](#input\_service\_connect\_configuration) | ECS Service Connect configuration. Each service's port\_name must match a named port mapping on a declared container. | <pre>object({<br/>    enabled   = optional(bool, true)<br/>    namespace = optional(string)<br/>    log_configuration = optional(object({<br/>      log_driver = string<br/>      options    = optional(map(string), {})<br/>      secret_options = optional(list(object({<br/>        name       = string<br/>        value_from = string<br/>      })), [])<br/>    }))<br/>    services = optional(list(object({<br/>      port_name             = string<br/>      discovery_name        = optional(string)<br/>      ingress_port_override = optional(number)<br/>      client_alias = optional(object({<br/>        port     = number<br/>        dns_name = optional(string)<br/>      }))<br/>      timeout = optional(object({<br/>        idle_timeout_seconds        = optional(number)<br/>        per_request_timeout_seconds = optional(number)<br/>      }))<br/>      tls = optional(object({<br/>        role_arn = optional(string)<br/>        kms_key  = optional(string)<br/>        issuer_cert_authority = object({<br/>          aws_pca_authority_arn = string<br/>        })<br/>      }))<br/>    })), [])<br/>  })</pre> | `null` | no |
| <a name="input_service_registries"></a> [service\_registries](#input\_service\_registries) | AWS Cloud Map service registry for the service. | <pre>object({<br/>    registry_arn   = string<br/>    port           = optional(number)<br/>    container_name = optional(string)<br/>    container_port = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_skip_destroy"></a> [skip\_destroy](#input\_skip\_destroy) | Keep old task definition revisions active when Terraform would deregister them. | `bool` | `false` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets the tasks run in. Use at least two, in different Availability Zones, for resilience. | `set(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. The module adds a Name tag and never overrides caller tags. | `map(string)` | `{}` | no |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | Existing task execution role ARN used when create\_task\_execution\_role is false. | `string` | `null` | no |
| <a name="input_task_execution_role_description"></a> [task\_execution\_role\_description](#input\_task\_execution\_role\_description) | Description of the created task execution role. | `string` | `null` | no |
| <a name="input_task_execution_role_kms_key_arns"></a> [task\_execution\_role\_kms\_key\_arns](#input\_task\_execution\_role\_kms\_key\_arns) | KMS keys the execution role may decrypt: keys protecting referenced secrets, parameters, or ECR repositories. | `set(string)` | `[]` | no |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Name of the created task execution role. Defaults to <name>-execution. | `string` | `null` | no |
| <a name="input_task_execution_role_path"></a> [task\_execution\_role\_path](#input\_task\_execution\_role\_path) | IAM path of the created task execution role. | `string` | `"/"` | no |
| <a name="input_task_execution_role_permissions_boundary"></a> [task\_execution\_role\_permissions\_boundary](#input\_task\_execution\_role\_permissions\_boundary) | Permissions boundary policy ARN for the created task execution role. | `string` | `null` | no |
| <a name="input_task_execution_role_policy_arns"></a> [task\_execution\_role\_policy\_arns](#input\_task\_execution\_role\_policy\_arns) | Additional managed policies attached to the created task execution role. | `set(string)` | `[]` | no |
| <a name="input_task_execution_role_statements"></a> [task\_execution\_role\_statements](#input\_task\_execution\_role\_statements) | Additional inline statements for the created task execution role, keyed by alphanumeric Sid. | <pre>map(object({<br/>    effect    = optional(string, "Allow")<br/>    actions   = set(string)<br/>    resources = set(string)<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | Existing task role ARN used when create\_task\_role is false. | `string` | `null` | no |
| <a name="input_task_role_description"></a> [task\_role\_description](#input\_task\_role\_description) | Description of the created task role. | `string` | `null` | no |
| <a name="input_task_role_name"></a> [task\_role\_name](#input\_task\_role\_name) | Name of the created task role. Defaults to <name>-task. | `string` | `null` | no |
| <a name="input_task_role_path"></a> [task\_role\_path](#input\_task\_role\_path) | IAM path of the created task role. | `string` | `"/"` | no |
| <a name="input_task_role_permissions_boundary"></a> [task\_role\_permissions\_boundary](#input\_task\_role\_permissions\_boundary) | Permissions boundary policy ARN for the created task role. | `string` | `null` | no |
| <a name="input_task_role_policy_arns"></a> [task\_role\_policy\_arns](#input\_task\_role\_policy\_arns) | Managed policies attached to the created task role. | `set(string)` | `[]` | no |
| <a name="input_task_role_statements"></a> [task\_role\_statements](#input\_task\_role\_statements) | Inline statements for the created task role, keyed by alphanumeric Sid. Declare application data access here. | <pre>map(object({<br/>    effect    = optional(string, "Allow")<br/>    actions   = set(string)<br/>    resources = set(string)<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | Create, update, and delete timeouts for the service, as duration strings. | <pre>object({<br/>    create = optional(string)<br/>    update = optional(string)<br/>    delete = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_track_latest"></a> [track\_latest](#input\_track\_latest) | Track the latest ACTIVE revision of the family, for families also registered outside Terraform. | `bool` | `false` | no |
| <a name="input_volumes"></a> [volumes](#input\_volumes) | Task volumes keyed by name. An empty object is a bind mount on ephemeral storage; efs attaches an EFS file system (encrypted in transit by default). | <pre>map(object({<br/>    configure_at_launch = optional(bool)<br/>    efs = optional(object({<br/>      file_system_id          = string<br/>      root_directory          = optional(string, "/")<br/>      transit_encryption      = optional(string, "ENABLED")<br/>      transit_encryption_port = optional(number)<br/>      authorization_config = optional(object({<br/>        access_point_id = optional(string)<br/>        iam             = optional(string, "ENABLED")<br/>      }))<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC of the managed security group. Required when create\_security\_group is true. | `string` | `null` | no |
| <a name="input_vpc_lattice_configurations"></a> [vpc\_lattice\_configurations](#input\_vpc\_lattice\_configurations) | VPC Lattice target groups the service registers with. | <pre>set(object({<br/>    port_name        = string<br/>    role_arn         = string<br/>    target_group_arn = string<br/>  }))</pre> | `[]` | no |
| <a name="input_wait_for_steady_state"></a> [wait\_for\_steady\_state](#input\_wait\_for\_steady\_state) | Block apply until the service reaches a steady state. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | ECS service ARN. |
| <a name="output_autoscaling_policy_arns"></a> [autoscaling\_policy\_arns](#output\_autoscaling\_policy\_arns) | Scaling policy ARNs keyed by policy key; empty when autoscaling is disabled. |
| <a name="output_autoscaling_scheduled_action_arns"></a> [autoscaling\_scheduled\_action\_arns](#output\_autoscaling\_scheduled\_action\_arns) | Scheduled action ARNs keyed by action key; empty when autoscaling is disabled. |
| <a name="output_autoscaling_target_resource_id"></a> [autoscaling\_target\_resource\_id](#output\_autoscaling\_target\_resource\_id) | Application Auto Scaling resource ID, or null when autoscaling is disabled. |
| <a name="output_cloudwatch_log_group_arn"></a> [cloudwatch\_log\_group\_arn](#output\_cloudwatch\_log\_group\_arn) | ARN of the created log group, or null when not created. |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Log group containers write to (created or named), or null. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the cluster, derived from cluster\_arn. |
| <a name="output_container_definitions"></a> [container\_definitions](#output\_container\_definitions) | Rendered container definitions in sorted order, as embedded in the task definition. |
| <a name="output_id"></a> [id](#output\_id) | ECS service ID. |
| <a name="output_name"></a> [name](#output\_name) | ECS service name. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the managed task security group, or null when not created. |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Every security group attached to the tasks: the managed group first, then security\_group\_ids sorted. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the registered task definition revision. |
| <a name="output_task_definition_arn_without_revision"></a> [task\_definition\_arn\_without\_revision](#output\_task\_definition\_arn\_without\_revision) | Task definition ARN without the revision suffix. |
| <a name="output_task_definition_family"></a> [task\_definition\_family](#output\_task\_definition\_family) | Task definition family. |
| <a name="output_task_definition_revision"></a> [task\_definition\_revision](#output\_task\_definition\_revision) | Registered task definition revision. |
| <a name="output_task_execution_role_arn"></a> [task\_execution\_role\_arn](#output\_task\_execution\_role\_arn) | Task execution role ARN, created or supplied. |
| <a name="output_task_execution_role_derived_policy"></a> [task\_execution\_role\_derived\_policy](#output\_task\_execution\_role\_derived\_policy) | JSON policy derived from secret, parameter, and KMS references, or null. Attach it to a caller-supplied execution role. |
| <a name="output_task_execution_role_name"></a> [task\_execution\_role\_name](#output\_task\_execution\_role\_name) | Task execution role name. |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | Task role ARN, created or supplied. |
| <a name="output_task_role_derived_policy"></a> [task\_role\_derived\_policy](#output\_task\_role\_derived\_policy) | JSON policy derived for ECS Exec, or null. Attach it to a caller-supplied task role. |
| <a name="output_task_role_name"></a> [task\_role\_name](#output\_task\_role\_name) | Task role name. |
<!-- END_TF_DOCS -->
