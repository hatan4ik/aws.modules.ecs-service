# container-definition

Renders one ECS container definition from typed snake_case inputs into the camelCase JSON object that `aws_ecs_task_definition.container_definitions` expects. It creates no resources and declares no provider, so the container schema has a single owner and is unit-tested with `terraform test` alone. The root module calls it once per entry of `container_definitions`; call it directly to build task definitions the root module does not cover.

## Usage

```hcl
module "app" {
  source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git//modules/container-definition?ref=<commit-sha>" # v1.0.0

  name  = "app"
  image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:<64-hex-digest>"

  port_mappings = [{ name = "http", container_port = 8080, app_protocol = "http" }]
  environment   = { LOG_LEVEL = "info" }
  secrets       = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-AbCdEf:password::" }
  health_check  = { command = ["CMD-SHELL", "curl -f http://localhost:8080/healthz || exit 1"], start_period = 10 }

  log_configuration = {
    log_driver = "awslogs"
    options = {
      "awslogs-group"         = "/aws/ecs/platform/orders-api"
      "awslogs-region"        = "us-east-1"
      "awslogs-stream-prefix" = "orders-api"
    }
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = "orders-api"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  container_definitions    = jsonencode([module.app.container_definition])
}
```

## Behaviour

- Rendering. Every input maps to its ECS camelCase key: `entrypoint` becomes `entryPoint`, `container_dependencies` becomes `dependsOn`, `readonly_root_filesystem` becomes `readonlyRootFilesystem`, `memory_reservation` becomes `memoryReservation`, and so on.
- Stripping. Null attributes and empty lists and maps are removed, so the JSON contains only what you declared. A minimal container renders exactly `name`, `image`, `essential`, and `readonlyRootFilesystem`. Booleans and numbers always survive; `interactive` and `pseudoTerminal` render only when true; empty `capabilities.add` or `drop` lists are dropped from `linuxParameters`; an empty `options` map is dropped from `logConfiguration`.
- Determinism. `environment` and `secrets` are rendered as lists sorted by variable name, so the task definition revision changes only when a value changes.
- Defaults. `essential = true`, `readonly_root_filesystem = true`, port `protocol = "tcp"`, `hostPort` equal to `containerPort`, health check `interval = 30`, `timeout = 5`, `retries = 3`.
- `secret_arns` output. The sorted, de-duplicated union of `secrets` values and `log_configuration.secret_options[*].value_from`. The `iam` submodule turns it into execution-role permissions.
- Digest precondition. With `require_image_digest = true` (the default) the `container_definition` output fails unless `image` ends in `@sha256:<64 hex>`. The root module passes `false` here and enforces the digest once on the task definition, so a plan reports one error for the whole task instead of one per container.
- `log_configuration = null` means "let the parent decide". The root module injects an `awslogs` configuration for its managed or named log group; standalone callers get no log configuration.
- Fargate-only validations, all at plan time: `linux_parameters.capabilities.add` may contain only `SYS_PTRACE` (any capability may be dropped); `stop_timeout` must be 2 to 120 seconds; `host_port`, when set, must equal `container_port`; `protocol` is `tcp` or `udp` and `app_protocol` is `http`, `http2`, or `grpc`; `environment_files` must be S3 object ARNs; `secrets` values and log `secret_options` must be Secrets Manager or SSM Parameter Store ARNs; `container_dependencies[*].condition` must be `START`, `COMPLETE`, `SUCCESS`, or `HEALTHY`; `restart_policy.restart_attempt_period` must be 60 to 1800 seconds; `firelens_configuration.type` must be `fluentbit` or `fluentd`; `version_consistency` must be `enabled` or `disabled`; health check `interval` 5 to 300, `timeout` 2 to 60, `retries` 1 to 10, `start_period` 0 to 300.
- Cross-container references (`container_dependencies`, `volumes_from`, `mount_points.source_volume`) are validated by the root module, which knows every container and volume in the task.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_command"></a> [command](#input\_command) | Command passed to the container, overriding the image CMD. | `list(string)` | `null` | no |
| <a name="input_container_dependencies"></a> [container\_dependencies](#input\_container\_dependencies) | Start-order dependencies on other containers in the task. | <pre>list(object({<br/>    container_name = string<br/>    condition      = string<br/>  }))</pre> | `[]` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | CPU units reserved for this container. Optional on Fargate; the task-level cpu is the hard limit. | `number` | `null` | no |
| <a name="input_docker_labels"></a> [docker\_labels](#input\_docker\_labels) | Key/value labels added to the container. | `map(string)` | `{}` | no |
| <a name="input_entrypoint"></a> [entrypoint](#input\_entrypoint) | Entry point passed to the container, overriding the image ENTRYPOINT. | `list(string)` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Plain-text environment variables. Values are visible in the task definition; use secrets for sensitive values. | `map(string)` | `{}` | no |
| <a name="input_environment_files"></a> [environment\_files](#input\_environment\_files) | Environment files loaded from S3 objects (.env format). | <pre>list(object({<br/>    type  = optional(string, "s3")<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_essential"></a> [essential](#input\_essential) | Whether the task stops when this container exits. At least one container per task must be essential. | `bool` | `true` | no |
| <a name="input_firelens_configuration"></a> [firelens\_configuration](#input\_firelens\_configuration) | FireLens log router configuration for a fluentbit or fluentd sidecar. | <pre>object({<br/>    type    = string<br/>    options = optional(map(string), {})<br/>  })</pre> | `null` | no |
| <a name="input_health_check"></a> [health\_check](#input\_health\_check) | Container health check run by the ECS agent. The command is an exec-style list, usually starting with CMD-SHELL. | <pre>object({<br/>    command      = list(string)<br/>    interval     = optional(number, 30)<br/>    timeout      = optional(number, 5)<br/>    retries      = optional(number, 3)<br/>    start_period = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_image"></a> [image](#input\_image) | Container image reference. By default it must be pinned to an immutable sha256 digest; see require\_image\_digest. | `string` | n/a | yes |
| <a name="input_interactive"></a> [interactive](#input\_interactive) | Allocate stdin for the container (docker run -i). | `bool` | `false` | no |
| <a name="input_linux_parameters"></a> [linux\_parameters](#input\_linux\_parameters) | Linux-specific options. Fargate supports initProcessEnabled and capabilities (add is limited to SYS\_PTRACE; drop may remove any capability). | <pre>object({<br/>    init_process_enabled = optional(bool, false)<br/>    capabilities = optional(object({<br/>      add  = optional(list(string), [])<br/>      drop = optional(list(string), [])<br/>    }))<br/>  })</pre> | `null` | no |
| <a name="input_log_configuration"></a> [log\_configuration](#input\_log\_configuration) | Log driver configuration. When null, the parent module injects an awslogs configuration for its managed log group. | <pre>object({<br/>    log_driver = string<br/>    options    = optional(map(string), {})<br/>    secret_options = optional(list(object({<br/>      name       = string<br/>      value_from = string<br/>    })), [])<br/>  })</pre> | `null` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Hard memory limit in MiB for this container. The container is killed when it exceeds this value. | `number` | `null` | no |
| <a name="input_memory_reservation"></a> [memory\_reservation](#input\_memory\_reservation) | Soft memory reservation in MiB for this container. | `number` | `null` | no |
| <a name="input_mount_points"></a> [mount\_points](#input\_mount\_points) | Task volumes mounted into the container. source\_volume must match a volume declared on the task definition. | <pre>list(object({<br/>    source_volume  = string<br/>    container_path = string<br/>    read_only      = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | Container name. Unique within the task definition; referenced by port mappings, dependencies, load balancers, and Service Connect. | `string` | n/a | yes |
| <a name="input_port_mappings"></a> [port\_mappings](#input\_port\_mappings) | Ports the container exposes. On Fargate (awsvpc) hostPort always equals containerPort. Set name to reference the port from Service Connect. | <pre>list(object({<br/>    name           = optional(string)<br/>    container_port = number<br/>    host_port      = optional(number)<br/>    protocol       = optional(string, "tcp")<br/>    app_protocol   = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_pseudo_terminal"></a> [pseudo\_terminal](#input\_pseudo\_terminal) | Allocate a TTY for the container (docker run -t). | `bool` | `false` | no |
| <a name="input_readonly_root_filesystem"></a> [readonly\_root\_filesystem](#input\_readonly\_root\_filesystem) | Mount the container root filesystem read-only. Keep enabled and write to declared volumes or /tmp mounts instead. | `bool` | `true` | no |
| <a name="input_repository_credentials"></a> [repository\_credentials](#input\_repository\_credentials) | Secrets Manager secret ARN holding private registry credentials. | <pre>object({<br/>    credentials_parameter = string<br/>  })</pre> | `null` | no |
| <a name="input_require_image_digest"></a> [require\_image\_digest](#input\_require\_image\_digest) | Reject image references that are not pinned to a sha256 digest. Mutable tags make deployments non-reproducible and defeat rollback. | `bool` | `true` | no |
| <a name="input_restart_policy"></a> [restart\_policy](#input\_restart\_policy) | Container restart policy that restarts the container in place instead of replacing the task. | <pre>object({<br/>    enabled                = bool<br/>    ignored_exit_codes     = optional(list(number), [])<br/>    restart_attempt_period = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Secrets injected as environment variables. Keys are variable names; values are AWS Secrets Manager secret ARNs (optionally with :json-key:version-stage:version-id) or SSM Parameter Store parameter ARNs. | `map(string)` | `{}` | no |
| <a name="input_start_timeout"></a> [start\_timeout](#input\_start\_timeout) | Seconds to wait for dependencies before giving up on starting this container. | `number` | `null` | no |
| <a name="input_stop_timeout"></a> [stop\_timeout](#input\_stop\_timeout) | Seconds to wait after SIGTERM before the container is forcibly killed. Fargate allows 2-120. | `number` | `null` | no |
| <a name="input_system_controls"></a> [system\_controls](#input\_system\_controls) | Kernel parameters (sysctls) set in the container. | <pre>list(object({<br/>    namespace = string<br/>    value     = string<br/>  }))</pre> | `[]` | no |
| <a name="input_ulimits"></a> [ulimits](#input\_ulimits) | Resource limits applied to the container process. | <pre>list(object({<br/>    name       = string<br/>    soft_limit = number<br/>    hard_limit = number<br/>  }))</pre> | `[]` | no |
| <a name="input_user"></a> [user](#input\_user) | User (and optional group) the container process runs as, for example "1000:1000". Prefer a non-root user. | `string` | `null` | no |
| <a name="input_version_consistency"></a> [version\_consistency](#input\_version\_consistency) | Whether ECS resolves the image tag to a digest at deployment time (enabled or disabled). Irrelevant when the image is already digest-pinned. | `string` | `null` | no |
| <a name="input_volumes_from"></a> [volumes\_from](#input\_volumes\_from) | Volumes inherited from another container in the task. | <pre>list(object({<br/>    source_container = string<br/>    read_only        = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_working_directory"></a> [working\_directory](#input\_working\_directory) | Working directory in which commands run inside the container. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_container_definition"></a> [container\_definition](#output\_container\_definition) | Rendered ECS container definition (camelCase keys, nulls stripped) ready for jsonencode into a task definition. |
| <a name="output_secret_arns"></a> [secret\_arns](#output\_secret\_arns) | Sorted, de-duplicated ARNs referenced by secrets and log secret options; used to derive execution-role permissions. |
<!-- END_TF_DOCS -->
