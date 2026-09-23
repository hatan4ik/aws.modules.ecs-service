# Design: aws.modules.ecs-service v1

Status: accepted 2026-09-23. Supersedes the v0.1.x "applications map" design.

## Purpose

`aws.modules.ecs-service` provisions **one** Amazon ECS service on AWS Fargate
together with the resources a service cannot run without: a task definition,
task and task-execution IAM roles, a task security group, a CloudWatch log
group, and Application Auto Scaling. It is secure by default, explicit by
declaration, and composable: every managed resource can be replaced by a
caller-supplied one without changing the module's outputs.

The module deliberately does **not** create the cluster, VPC, subnets, KMS
keys, secrets, load balancers, DNS, certificates, Cognito clients, or data
stores. Those are separate concerns with separate lifecycles and owners. The
module consumes their identifiers.

## Why the v0.1.x design was replaced

| v0.1.x behaviour | Problem | v1 decision |
|---|---|---|
| One `applications` map provisions N services from one module call. | Every service shares one type and one lifecycle; validation errors cannot name the offending service; per-service composition (its own target group, alarms, secrets module) is awkward. | One module call is one service. Callers use `for_each` on the module block for fleets. |
| Creates a Cognito app client and injects its ID into the environment. | An identity-provider client is not an ECS concern (SRP). It forced every caller to accept a Cognito-shaped interface (ISP). | Removed. Callers create the client with `aws.modules.cognito` and pass its ID in `environment`. |
| `enable_session_table_access` grants DynamoDB access to one platform table. | Platform-specific policy baked into a general module. | Removed. Callers declare the statement in `task_role_statements`. |
| Egress is hard-coded to TLS on `vpc_cidr` plus the regional S3 prefix list, looked up by a data source. | Network policy hidden inside the module (DIP); the data source made every plan depend on an API read; no way to add or replace egress. | Egress and ingress are declarative rule maps. No hidden lookups. A `check` warns when a managed security group has no egress. |
| One container per task; no sidecars, volumes, ulimits, restart policy, FireLens. | Could not express common production task shapes. | Typed `container_definitions` map rendered by a pure submodule. |
| Only CPU target tracking with fixed cooldowns. | Could not express memory, request-count, step, or scheduled scaling. | Autoscaling submodule with policy and scheduled-action maps. |
| IAM role names could exceed the 64-character IAM limit. | Latent apply-time failure. | `name` is validated so every derived name fits its service limit. |
| Secrets granted `secretsmanager:GetSecretValue` only. | SSM Parameter Store `valueFrom` references failed at task start. | Permissions derived per ARN service (`secretsmanager` or `ssm`). |
| Module overwrote the caller's `ManagedBy` tag. | Surprising and undocumented. | The module adds only `Name`; caller tags are never overridden. |

## Principles and how the module applies them

- **Single responsibility.** Each submodule has one reason to change:
  `container-definition` (ECS container JSON schema), `iam` (role and policy
  shape), `security-group` (rule shape), `autoscaling` (scaling policy shape).
  The root module composes them and owns only the task definition, the
  service, and the log group.
- **Open/closed.** New behaviour is added by declaring data (a container, a
  rule, a statement, a policy, a scheduled action), not by editing the module.
  Names, paths, and boundaries are overridable inputs.
- **Liskov substitution.** A caller-supplied role, security group, or log
  group is a drop-in for a module-managed one: outputs and downstream wiring
  are identical.
- **Interface segregation.** Feature groups are optional objects that default
  to `null` or `{}`. A minimal service needs `name`, `cluster_arn`,
  `subnet_ids`, and one container.
- **Dependency inversion.** The root depends on identifiers (ARNs, IDs), never
  on how upstream resources were produced. Partition, region, and account are
  derived from `cluster_arn`; the module performs no API reads at plan time.
- **Clean, deterministic code.** Sorted environment and secret lists, null
  stripping in rendered JSON, explicit `depends_on` only where the API
  requires ordering, and validations that fail at plan time with actionable
  messages.

## Architecture

```text
root (one service)
├── modules/container-definition   pure: typed inputs -> one container map
├── modules/iam                    task-execution role, task role, derived policies
├── modules/security-group         task SG with declarative ingress/egress rules
├── aws_cloudwatch_log_group.this  optional, KMS-capable
├── aws_ecs_task_definition.this   Fargate, awsvpc, multi-container
├── aws_ecs_service.this | .ignore_task_definition
└── modules/autoscaling            target, target-tracking/step policies, schedules
```

Data flow: container specs are rendered first (no resources). IAM derives
execution-role statements from the rendered `secrets`. The root injects an
`awslogs` configuration into any container that did not declare its own log
configuration when a log group is managed or named. The service depends on the
security-group rules and execution-role attachments so the first deployment
cannot start before its network and IAM prerequisites exist.

### Root interface (summary)

Required: `name`, `cluster_arn`, `subnet_ids`, `container_definitions`.

Optional groups (all default to a safe value):

- Task: `family`, `cpu`, `memory`, `cpu_architecture`,
  `operating_system_family`, `ephemeral_storage_size_in_gib`, `volumes`,
  `pid_mode`, `require_image_digest`, `skip_destroy`, `track_latest`.
- Service: `desired_count`, `launch_type` or `capacity_provider_strategy`,
  `platform_version`, `deployment_*`, `deployment_circuit_breaker`,
  `deployment_configuration`, `alarms`, `availability_zone_rebalancing`,
  `load_balancers`, `service_registries`, `service_connect_configuration`,
  `vpc_lattice_configurations`, `enable_execute_command`,
  `ignore_task_definition_changes`, `wait_for_steady_state`, `timeouts`.
- Network: `assign_public_ip`, `create_security_group`, `vpc_id`,
  `security_group_*`, `security_group_ids`.
- IAM: `create_task_execution_role`, `task_execution_role_*`,
  `create_task_role`, `task_role_*`.
- Logs: `create_cloudwatch_log_group`, `cloudwatch_log_group_*`.
- Scaling: `autoscaling` object (`null` disables).
- `tags`.

Outputs expose every identifier a caller may need to wire alarms, target
groups, Service Connect, or further IAM: service id/name/arn, task definition
arn/family/revision, both role arns and names, security group id, log group
name and arn, autoscaling target and policy identifiers, and the rendered
container definitions.

### Lifecycle rules

- `desired_count` is the bootstrap count; the module always ignores later
  drift because Application Auto Scaling, ECS deployments, and operators
  legitimately change it. This matches v0.1.x behaviour.
- `ignore_task_definition_changes = true` selects a second service resource
  that also ignores `task_definition`, for CI-driven deployments. Terraform
  cannot make `ignore_changes` conditional, so two resource blocks exist by
  design and must stay identical apart from `lifecycle`.

## Security defaults

- No public IP; awsvpc networking; managed security group with no ingress.
- Read-only root filesystem, no privileged containers, immutable image
  digests required, deployment circuit breaker with rollback, ECS-managed tags.
- Execution role: AWS-managed `AmazonECSTaskExecutionRolePolicy` plus only
  the secrets, parameters, and KMS keys the containers reference.
- Task role: empty unless the caller declares statements or managed policies;
  ECS Exec channel permissions only when `enable_execute_command` is on.
- Both trust policies carry `aws:SourceAccount` and `aws:SourceArn`
  conditions scoped to the cluster's account and region.
- Log group encrypted with a caller KMS key when supplied; 365-day retention
  by default.

## Testing strategy

- Contract tests use `mock_provider` with `command = plan`; no credentials.
- Root `tests/` cover: secure defaults, every variable validation via
  `expect_failures`, IAM policy derivation, networking, service integrations,
  autoscaling, and bring-your-own substitution.
- Each submodule has its own `tests/` and is exercised in CI on its own.
- Every example is initialised and validated in CI; examples are the
  documentation's executable form.
- Static policy: `tflint` with the AWS ruleset, Checkov, Trivy; generated
  docs are checked for drift.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0` (the consuming platform pins 1.7.5).
- AWS provider `>= 6.35.0, < 7.0.0`.
- Fargate only (`FARGATE` and `FARGATE_SPOT` capacity providers). EC2 launch
  type, managed EBS volumes, and App Mesh proxy configuration are roadmap
  items and will be added without breaking this interface.

## Migration

`docs/UPGRADE-1.0.md` maps every v0.1.x input to its v1 equivalent, lists the
settings that preserve existing resource names, and gives `moved` blocks so a
consumer can adopt v1 without recreating roles, security groups, or log groups.
