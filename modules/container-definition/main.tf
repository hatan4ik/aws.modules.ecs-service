# Renders one ECS container definition from typed inputs. This module creates
# no resources: it exists so the container schema has a single owner and can
# be unit-tested without a provider.

locals {
  environment = [for key in sort(keys(var.environment)) : { name = key, value = var.environment[key] }]
  secrets     = [for key in sort(keys(var.secrets)) : { name = key, valueFrom = var.secrets[key] }]

  port_mappings = [for mapping in var.port_mappings : {
    for key, value in {
      name          = mapping.name
      containerPort = mapping.container_port
      hostPort      = coalesce(mapping.host_port, mapping.container_port)
      protocol      = mapping.protocol
      appProtocol   = mapping.app_protocol
    } : key => value if value != null
  }]

  health_check = var.health_check == null ? null : {
    for key, value in {
      command     = var.health_check.command
      interval    = var.health_check.interval
      timeout     = var.health_check.timeout
      retries     = var.health_check.retries
      startPeriod = var.health_check.start_period
    } : key => value if value != null
  }

  capabilities = var.linux_parameters == null || try(var.linux_parameters.capabilities, null) == null ? null : {
    for key, value in {
      add  = var.linux_parameters.capabilities.add
      drop = var.linux_parameters.capabilities.drop
    } : key => value if length(value) > 0
  }

  linux_parameters = var.linux_parameters == null ? null : merge(
    { initProcessEnabled = var.linux_parameters.init_process_enabled },
    local.capabilities == null || length(local.capabilities) == 0 ? {} : { capabilities = local.capabilities },
  )

  log_configuration = var.log_configuration == null ? null : {
    for key, value in {
      logDriver     = var.log_configuration.log_driver
      options       = var.log_configuration.options
      secretOptions = [for option in var.log_configuration.secret_options : { name = option.name, valueFrom = option.value_from }]
    } : key => value if try(length(value), 1) > 0
  }

  firelens_configuration = var.firelens_configuration == null ? null : {
    for key, value in {
      type    = var.firelens_configuration.type
      options = var.firelens_configuration.options
    } : key => value if try(length(value), 1) > 0
  }

  restart_policy = var.restart_policy == null ? null : {
    for key, value in {
      enabled              = var.restart_policy.enabled
      ignoredExitCodes     = var.restart_policy.ignored_exit_codes
      restartAttemptPeriod = var.restart_policy.restart_attempt_period
    } : key => value if value != null && try(length(value), 1) > 0
  }

  definition = {
    name                   = var.name
    image                  = var.image
    essential              = var.essential
    command                = var.command
    entryPoint             = var.entrypoint
    workingDirectory       = var.working_directory
    user                   = var.user
    cpu                    = var.cpu
    memory                 = var.memory
    memoryReservation      = var.memory_reservation
    environment            = local.environment
    environmentFiles       = [for file in var.environment_files : { type = file.type, value = file.value }]
    secrets                = local.secrets
    portMappings           = local.port_mappings
    healthCheck            = local.health_check
    readonlyRootFilesystem = var.readonly_root_filesystem
    linuxParameters        = local.linux_parameters
    ulimits                = [for limit in var.ulimits : { name = limit.name, softLimit = limit.soft_limit, hardLimit = limit.hard_limit }]
    mountPoints            = [for mount in var.mount_points : { sourceVolume = mount.source_volume, containerPath = mount.container_path, readOnly = mount.read_only }]
    volumesFrom            = [for volume in var.volumes_from : { sourceContainer = volume.source_container, readOnly = volume.read_only }]
    dependsOn              = [for dependency in var.container_dependencies : { containerName = dependency.container_name, condition = dependency.condition }]
    startTimeout           = var.start_timeout
    stopTimeout            = var.stop_timeout
    dockerLabels           = var.docker_labels
    systemControls         = [for control in var.system_controls : { namespace = control.namespace, value = control.value }]
    logConfiguration       = local.log_configuration
    repositoryCredentials  = var.repository_credentials == null ? null : { credentialsParameter = var.repository_credentials.credentials_parameter }
    firelensConfiguration  = local.firelens_configuration
    restartPolicy          = local.restart_policy
    interactive            = var.interactive ? true : null
    pseudoTerminal         = var.pseudo_terminal ? true : null
    versionConsistency     = var.version_consistency
  }

  # Null attributes and empty collections are stripped so the rendered JSON
  # contains only what the caller declared. Booleans and numbers survive
  # because length() fails on them and try() falls back to 1.
  container_definition = {
    for key, value in local.definition : key => value
    if value != null && try(length(value), 1) > 0
  }

  secret_arns = sort(distinct(concat(
    values(var.secrets),
    var.log_configuration == null ? [] : [for option in var.log_configuration.secret_options : option.value_from],
  )))
}
