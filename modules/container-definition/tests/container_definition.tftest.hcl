variables {
  name  = "app"
  image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/app@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}

run "renders_minimal_definition" {
  command = plan

  assert {
    condition     = keys(output.container_definition) == ["essential", "image", "name", "readonlyRootFilesystem"]
    error_message = "A minimal container must render only name, image, essential, and a read-only root filesystem."
  }

  assert {
    condition     = output.container_definition.readonlyRootFilesystem == true
    error_message = "The root filesystem must be read-only by default."
  }

  assert {
    condition     = length(output.secret_arns) == 0
    error_message = "A container without secrets must report no secret ARNs."
  }
}

run "sorts_environment_and_secrets" {
  command = plan

  variables {
    environment = { ZED = "1", ALPHA = "2" }
    secrets = {
      ZED_SECRET   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:zed-AbCdEf"
      ALPHA_SECRET = "arn:aws:ssm:us-east-1:123456789012:parameter/alpha"
    }
  }

  assert {
    condition     = output.container_definition.environment[0].name == "ALPHA" && output.container_definition.environment[1].name == "ZED"
    error_message = "Environment variables must be sorted by name for deterministic task definitions."
  }

  assert {
    condition     = output.container_definition.secrets[0].name == "ALPHA_SECRET" && output.container_definition.secrets[0].valueFrom == "arn:aws:ssm:us-east-1:123456789012:parameter/alpha"
    error_message = "Secrets must be sorted by name and keep their valueFrom reference."
  }
}

run "renders_full_definition" {
  command = plan

  variables {
    essential              = false
    command                = ["serve", "--port", "8080"]
    entrypoint             = ["/bin/app"]
    working_directory      = "/srv"
    user                   = "1000:1000"
    cpu                    = 128
    memory                 = 256
    memory_reservation     = 128
    environment_files      = [{ value = "arn:aws:s3:::bucket/app.env" }]
    port_mappings          = [{ name = "http", container_port = 8080, app_protocol = "http" }]
    health_check           = { command = ["CMD-SHELL", "curl -f http://localhost:8080/healthz || exit 1"], start_period = 10 }
    linux_parameters       = { init_process_enabled = true, capabilities = { drop = ["ALL"] } }
    ulimits                = [{ name = "nofile", soft_limit = 65536, hard_limit = 65536 }]
    mount_points           = [{ source_volume = "data", container_path = "/data" }]
    volumes_from           = [{ source_container = "config" }]
    container_dependencies = [{ container_name = "init", condition = "SUCCESS" }]
    start_timeout          = 30
    stop_timeout           = 60
    docker_labels          = { team = "platform" }
    system_controls        = [{ namespace = "net.core.somaxconn", value = "1024" }]
    log_configuration      = { log_driver = "awslogs", options = { "awslogs-group" = "/aws/ecs/app" } }
    repository_credentials = { credentials_parameter = "arn:aws:secretsmanager:us-east-1:123456789012:secret:registry-AbCdEf" }
    restart_policy         = { enabled = true, ignored_exit_codes = [0], restart_attempt_period = 120 }
    interactive            = true
    pseudo_terminal        = true
    version_consistency    = "disabled"
  }

  assert {
    condition = keys(output.container_definition) == [
      "command", "cpu", "dependsOn", "dockerLabels", "entryPoint", "environmentFiles", "essential", "healthCheck",
      "image", "interactive", "linuxParameters", "logConfiguration", "memory", "memoryReservation", "mountPoints",
      "name", "portMappings", "pseudoTerminal", "readonlyRootFilesystem", "repositoryCredentials", "restartPolicy",
      "startTimeout", "stopTimeout", "systemControls", "ulimits", "user", "versionConsistency", "volumesFrom", "workingDirectory",
    ]
    error_message = "Every declared attribute must render under its ECS camelCase key."
  }

  assert {
    condition     = output.container_definition.portMappings[0].hostPort == 8080 && output.container_definition.portMappings[0].protocol == "tcp" && output.container_definition.portMappings[0].appProtocol == "http"
    error_message = "Port mappings must default hostPort to containerPort and protocol to tcp."
  }

  assert {
    condition     = output.container_definition.healthCheck.interval == 30 && output.container_definition.healthCheck.timeout == 5 && output.container_definition.healthCheck.retries == 3 && output.container_definition.healthCheck.startPeriod == 10
    error_message = "Health checks must apply ECS-compatible defaults."
  }

  assert {
    condition     = output.container_definition.linuxParameters.initProcessEnabled == true && output.container_definition.linuxParameters.capabilities.drop == tolist(["ALL"]) && !contains(keys(output.container_definition.linuxParameters.capabilities), "add")
    error_message = "Empty capability lists must be stripped from linuxParameters."
  }

  assert {
    condition     = output.container_definition.mountPoints[0].readOnly == false && output.container_definition.dependsOn[0].condition == "SUCCESS"
    error_message = "Mount points and dependencies must render with ECS field names."
  }

  assert {
    condition     = output.container_definition.restartPolicy.restartAttemptPeriod == 120 && output.container_definition.restartPolicy.ignoredExitCodes == tolist([0])
    error_message = "Restart policy must render its camelCase fields."
  }
}

run "collects_secret_arns_from_secrets_and_log_options" {
  command = plan

  variables {
    secrets = {
      DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf:password::"
      API_KEY     = "arn:aws:ssm:us-east-1:123456789012:parameter/api-key"
    }
    log_configuration = {
      log_driver     = "awsfirelens"
      secret_options = [{ name = "apikey", value_from = "arn:aws:ssm:us-east-1:123456789012:parameter/api-key" }]
    }
  }

  assert {
    condition = output.secret_arns == tolist([
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf:password::",
      "arn:aws:ssm:us-east-1:123456789012:parameter/api-key",
    ])
    error_message = "Secret ARNs must be the sorted, de-duplicated union of container secrets and log secret options."
  }

  assert {
    condition     = output.container_definition.logConfiguration.secretOptions[0].valueFrom == "arn:aws:ssm:us-east-1:123456789012:parameter/api-key" && !contains(keys(output.container_definition.logConfiguration), "options")
    error_message = "Log secret options must render and empty option maps must be stripped."
  }
}

run "rejects_mutable_image_reference" {
  command = plan

  variables {
    image = "public.ecr.aws/nginx/nginx:latest"
  }

  expect_failures = [output.container_definition]
}

run "allows_mutable_image_when_digest_not_required" {
  command = plan

  variables {
    image                = "public.ecr.aws/nginx/nginx:latest"
    require_image_digest = false
  }

  assert {
    condition     = output.container_definition.image == "public.ecr.aws/nginx/nginx:latest"
    error_message = "Callers may opt out of digest enforcement explicitly."
  }
}

run "rejects_secret_reference_that_is_not_an_arn" {
  command = plan

  variables {
    secrets = { TOKEN = "plain-text" }
  }

  expect_failures = [var.secrets]
}

run "rejects_unsupported_added_capability" {
  command = plan

  variables {
    linux_parameters = { capabilities = { add = ["NET_ADMIN"] } }
  }

  expect_failures = [var.linux_parameters]
}

run "rejects_invalid_dependency_condition" {
  command = plan

  variables {
    container_dependencies = [{ container_name = "init", condition = "DONE" }]
  }

  expect_failures = [var.container_dependencies]
}

run "rejects_stop_timeout_over_fargate_limit" {
  command = plan

  variables {
    stop_timeout = 121
  }

  expect_failures = [var.stop_timeout]
}
