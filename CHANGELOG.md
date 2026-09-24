# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

### Added

- Credential-driven integration suites in `tests/integration/` (`smoke` and `e2e`) with a disposable fixture module, `make integration-smoke` and `make integration-e2e` targets, a dispatch-only `integration` workflow that assumes a role through GitHub OIDC from the protected `integration` environment, and the IAM trust and permissions documents the role needs.

## [1.0.0] - 2026-09-23

Breaking release. One module call now provisions one service. [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md) maps every 0.1.x input to its replacement, lists the settings that preserve existing resources, and gives ready-to-paste `moved` blocks.

### Added

- Submodules `container-definition`, `iam`, `security-group`, and `autoscaling`, each with its own tests and usable standalone from a Git source.
- Typed `container_definitions` map with multiple containers per task: `entrypoint`, `command`, `working_directory`, `user`, container-level `cpu`, `memory`, `memory_reservation`, `environment_files`, `port_mappings` with names and `app_protocol`, `health_check`, `linux_parameters`, `ulimits`, `mount_points`, `volumes_from`, `container_dependencies`, `start_timeout`, `stop_timeout`, `docker_labels`, `system_controls`, `log_configuration` with secret options, `repository_credentials`, `firelens_configuration`, `restart_policy`, `interactive`, `pseudo_terminal`, `version_consistency`.
- Task-level `volumes` (bind mounts and EFS with encrypted transit by default), `pid_mode`, `operating_system_family` including Windows Server families, `enable_fault_injection`, `skip_destroy`, `track_latest`, `family`.
- Declarative `security_group_ingress_rules` and `security_group_egress_rules` with exactly one source per rule (`cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_id`, `self`), plus `security_group_ids` for additional or caller-supplied groups, `security_group_name`, and `security_group_description`.
- Bring-your-own for every managed resource: `create_task_execution_role`, `create_task_role`, `create_security_group`, and `create_cloudwatch_log_group` with the matching `task_execution_role_arn`, `task_role_arn`, `security_group_ids`, and `cloudwatch_log_group_name` inputs. Outputs `task_execution_role_derived_policy` and `task_role_derived_policy` expose the policy JSON to attach to supplied roles.
- IAM inputs: `task_execution_role_statements`, `task_execution_role_policy_arns`, `task_role_policy_arns`, `effect` and `conditions` on declared statements, and name, path, description, and permissions boundary for each role.
- Autoscaling: memory and ALB request-count target tracking, customized CloudWatch metrics, step scaling, scheduled actions, per-policy cooldowns and `disable_scale_in`.
- Service: `capacity_provider_strategy` for `FARGATE` and `FARGATE_SPOT`, `platform_version`, `deployment_minimum_healthy_percent`, `deployment_maximum_percent`, `deployment_circuit_breaker`, `deployment_controller_type`, `deployment_configuration` (blue/green, linear, canary, lifecycle hooks), `alarms`, `availability_zone_rebalancing`, `load_balancers` with `advanced_configuration`, `health_check_grace_period_seconds`, `service_registries`, `service_connect_configuration`, `vpc_lattice_configurations`, `enable_ecs_managed_tags`, `propagate_tags`, `force_delete`, `wait_for_steady_state`, `timeouts`, `ignore_task_definition_changes`, `assign_public_ip`.
- Logging: `cloudwatch_log_group_class` and `cloudwatch_log_group_skip_destroy`. The managed `awslogs` configuration is injected only into containers that declare no log configuration.
- Trust policies on both roles conditioned on `aws:SourceAccount` and `aws:SourceArn` of the cluster's account and region.
- Advisory `check` blocks that warn without blocking: `security_group_egress`, `multi_az`, `supplied_execution_role_secrets`.
- Plan-time validation of every input, the Fargate CPU/memory matrix, the Windows CPU minimum, image digests, volume and container references, load balancer and Service Connect wiring, and `desired_count` within autoscaling bounds.
- Flat outputs for every identifier: `id`, `name`, `arn`, `cluster_name`, `task_definition_arn`, `task_definition_arn_without_revision`, `task_definition_family`, `task_definition_revision`, `container_definitions`, both role ARNs and names, both derived policies, `security_group_id`, `security_group_ids`, `cloudwatch_log_group_name`, `cloudwatch_log_group_arn`, `autoscaling_target_resource_id`, `autoscaling_policy_arns`, `autoscaling_scheduled_action_arns`.
- `docs/DESIGN.md`, `docs/UPGRADE-1.0.md`, submodule READMEs, `CONTRIBUTING.md`, `SECURITY.md`, and `LICENSE`.

### Changed

- **Breaking:** the `applications` map is replaced by one service per module call. Use `for_each` on the module block for fleets.
- **Breaking:** `cluster_name` is removed and derived from `cluster_arn`, as are partition, region, and account. The module performs no data-source reads.
- **Breaking:** renamed inputs: `private_subnet_ids` to `subnet_ids`; `log_retention_in_days` to `cloudwatch_log_group_retention_in_days`; `ephemeral_storage_gib` to `ephemeral_storage_size_in_gib`; `image_digest` to `container_definitions.<name>.image`; `container_port` to `container_definitions.<name>.port_mappings`; `secret_arns` to `container_definitions.<name>.secrets`; `secret_kms_key_arns` to `task_execution_role_kms_key_arns`; `task_policy_statements` to `task_role_statements`; `autoscaling.cpu_target_percent` to `autoscaling.policies.cpu.target_tracking.target_value`.
- **Breaking:** `application_data_kms_key_arn` is split into `cloudwatch_log_group_kms_key_id` (log encryption) and `task_execution_role_kms_key_arns` (execution-role decrypt grants).
- **Breaking:** egress is no longer implied from `vpc_cidr` and the regional S3 prefix list. Declare it in `security_group_egress_rules`.
- **Breaking:** default IAM role path is `/` (was `/ecs/`); default security group name is `<name>` (was `<name>-tasks`); default log group name is `/aws/ecs/<cluster>/<name>` (was `/aws/ecs/<prefix>/<key>`). All are inputs.
- **Breaking:** inline policy names are `derived` and `declared` (were `declared-secrets` on the execution role and `application-access` on the task role).
- **Breaking:** `name` accepts 1 to 54 lowercase alphanumerics and hyphens (was 3 to 48) and now guarantees every derived name fits its AWS limit.
- `health_check.interval`, `timeout`, `retries`, and `start_period` are optional with ECS defaults (30, 5, 3, unset).
- Target-tracking `scale_in_cooldown` defaults to 300 seconds (was 60); `scale_out_cooldown` stays 60.
- `availability_zone_rebalancing` defaults to `ENABLED`.
- The execution-role KMS grant is `kms:Decrypt` only (was `kms:Decrypt` and `kms:DescribeKey`) and applies whenever `task_execution_role_kms_key_arns` is set, not only when secrets exist.
- Secrets Manager permissions target the base secret ARN even when a container references a `:json-key:version-stage:version-id` suffix.
- The `awslogs-stream-prefix` is the service name (was the application key).
- The module adds only a `Name` tag to each resource. Caller tags pass through unchanged.
- The service depends on the whole security-group and IAM modules rather than on individual rules and attachments.

### Removed

- **Breaking:** the `cognito` application settings, `cognito_user_pool_id`, and the managed `aws_cognito_user_pool_client`. Create the client beside the service and pass its ID in `environment`.
- **Breaking:** `enable_session_table_access` and `session_table_arn`. Declare the statement in `task_role_statements`.
- **Breaking:** `vpc_cidr` and the `aws_prefix_list`, `aws_region`, and `aws_partition` data sources.
- **Breaking:** the `services` map output, replaced by flat per-service outputs.
- **Breaking:** the injected `ManagedBy`, `IaCOwnership`, and `Application` tags.
- `terraform_data.application_contract`.

### Fixed

- IAM role names could exceed the 64-character limit and fail at apply time. `name` is now validated so every derived name fits.
- SSM Parameter Store `valueFrom` references failed at task start because the execution role was granted `secretsmanager:GetSecretValue` only. Permissions are now derived per ARN service, with `ssm:GetParameters` for parameters.
- The caller's `ManagedBy` tag was overwritten by the module. Caller tags are never overridden.

## [0.1.3] - 2026-09-22

### Fixed

- Task security groups allow TLS egress to the regional S3 managed prefix list so image layers of private ECR repositories can be pulled, and the service waits for that rule before its first deployment (#3).

## [0.1.2] - 2026-09-22

### Added

- `applications[*].force_new_deployment` to request one Terraform-managed fresh deployment (#2).

### Fixed

- The ECS service depends on the VPC egress rule, so the first deployment cannot start before task egress exists (#2).

## [0.1.1] - 2026-09-22

### Added

- When an application declares `cognito` settings, the managed app client's ID and the user pool ID are injected into the container environment as `COGNITO_CLIENT_ID` and `COGNITO_USER_POOL_ID`; callers may not set those keys themselves (#1).

### Changed

- Environment variables are rendered sorted by name for a stable task definition (#1).

## [0.1.0] - 2026-09-22

### Added

- Variable-driven private Fargate service module. An `applications` map provisions one or more services with immutable image digests, private subnets, dedicated task and execution roles, KMS-encrypted log groups, declared secrets, optional session-table access, optional Cognito app clients, deployment circuit breaker with rollback, and CPU target tracking.

[Unreleased]: https://github.com/hatan4ik/aws.modules.ecs-service/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.ecs-service/compare/v0.1.3...v1.0.0
[0.1.3]: https://github.com/hatan4ik/aws.modules.ecs-service/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/hatan4ik/aws.modules.ecs-service/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/hatan4ik/aws.modules.ecs-service/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hatan4ik/aws.modules.ecs-service/releases/tag/v0.1.0
