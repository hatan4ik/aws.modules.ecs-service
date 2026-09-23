# iam

Owns the two IAM roles an ECS task uses: the task execution role, which the ECS agent assumes to pull images, write logs, and fetch secrets before a container starts, and the task role, which the application code assumes. It is a separate module because role and policy shape change for different reasons than the service does, and because a caller who brings their own roles must still receive the exact policy the module would have attached.

## Usage

```hcl
module "iam" {
  source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git//modules/iam?ref=<commit-sha>" # v1.0.0

  name        = "orders-api"
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"

  secret_arns = [
    "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-AbCdEf:password::",
    "arn:aws:ssm:us-east-1:123456789012:parameter/orders/api-key",
  ]
  kms_key_arns = ["arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"]

  task_role_statements = {
    ReadOrdersTable = {
      actions    = ["dynamodb:GetItem", "dynamodb:Query"]
      resources  = ["arn:aws:dynamodb:us-east-1:123456789012:table/orders"]
      conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["true"] }]
    }
  }
  enable_execute_command = true

  tags = { Environment = "prod" }
}
```

## Behaviour

- Names. `<name>-execution` and `<name>-task` unless `task_execution_role_name` or `task_role_name` is set. `name` is validated to 1 to 54 lowercase alphanumerics and hyphens so both derived names fit the 64-character IAM limit; explicit names are validated to 64 characters. Paths default to `/`. Description and permissions boundary are optional per role.
- Trust. Both roles trust `ecs-tasks.amazonaws.com` only with `StringEquals aws:SourceAccount = <account>` and `ArnLike aws:SourceArn = arn:<partition>:ecs:<region>:<account>:*`, all parsed from `cluster_arn`. Another account's ECS control plane cannot assume them.
- Managed policies. A created execution role always gets `AmazonECSTaskExecutionRolePolicy` from the cluster's partition. `task_execution_role_policy_arns` and `task_role_policy_arns` attach more.
- Inline policies. Each role carries up to two, with stable names. `derived` holds what the module computed: on the execution role, `secretsmanager:GetSecretValue`, `ssm:GetParameters`, and `kms:Decrypt` statements for `secret_arns` and `kms_key_arns`; on the task role, the four `ssmmessages` channel actions when `enable_execute_command` is true. `declared` holds your `task_execution_role_statements` and `task_role_statements`. A policy exists only when it has at least one statement, so a role with nothing to grant has no inline policy.
- Secrets Manager reduction. A container may reference `arn:...:secret:name-AbCdEf:json-key:version-stage:version-id`. The policy targets the secret itself, the first seven colon-separated fields, de-duplicated across references.
- SSM handling. Parameter ARNs are used exactly as given and granted `ssm:GetParameters` only, which is what the ECS agent calls for `valueFrom` parameters.
- Declared statements. The map key is the Sid (1 to 100 alphanumerics). `effect` defaults to `Allow`; `actions` and `resources` must be non-empty; `conditions` are grouped by `test` operator, and a statement without conditions renders no `Condition` block. Statements are sorted by Sid and their action and resource lists are sorted, so policy JSON is stable.
- Bring your own. With `create_task_execution_role = false` or `create_task_role = false` the module creates nothing for that role, requires the matching `*_role_arn`, echoes it, and parses the role name from the ARN. A supplied role is never modified. Outputs `task_execution_role_derived_policy` and `task_role_derived_policy` still hold the JSON the module would have attached (or null), so you can attach it yourself with `aws_iam_role_policy`.

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

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.task_declared](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.task_derived](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.task_execution_declared](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.task_execution_derived](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_execution_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the ECS cluster the tasks run in. Provides the partition, region, and account used in trust-policy conditions and managed-policy ARNs. | `string` | n/a | yes |
| <a name="input_create_task_execution_role"></a> [create\_task\_execution\_role](#input\_create\_task\_execution\_role) | Create the task execution role. Set false and supply task\_execution\_role\_arn to use an existing role; the module never modifies a supplied role. | `bool` | `true` | no |
| <a name="input_create_task_role"></a> [create\_task\_role](#input\_create\_task\_role) | Create the task role. Set false and supply task\_role\_arn to use an existing role; the module never modifies a supplied role. | `bool` | `true` | no |
| <a name="input_enable_execute_command"></a> [enable\_execute\_command](#input\_enable\_execute\_command) | Grant the task role the SSM messages permissions ECS Exec needs. | `bool` | `false` | no |
| <a name="input_kms_key_arns"></a> [kms\_key\_arns](#input\_kms\_key\_arns) | KMS key ARNs the execution role may decrypt: keys protecting secrets, parameters, or ECR repositories. | `set(string)` | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | Service name used to derive role names (<name>-execution and <name>-task) unless explicit names are given. | `string` | n/a | yes |
| <a name="input_secret_arns"></a> [secret\_arns](#input\_secret\_arns) | Secrets Manager secret and SSM parameter ARNs referenced by the task's containers. The execution role is granted read access to exactly these. | `set(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every role this module creates. | `map(string)` | `{}` | no |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | Existing task execution role ARN, required when create\_task\_execution\_role is false. | `string` | `null` | no |
| <a name="input_task_execution_role_description"></a> [task\_execution\_role\_description](#input\_task\_execution\_role\_description) | Description of the created task execution role. | `string` | `null` | no |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Name of the created task execution role. Defaults to <name>-execution. | `string` | `null` | no |
| <a name="input_task_execution_role_path"></a> [task\_execution\_role\_path](#input\_task\_execution\_role\_path) | IAM path of the created task execution role. | `string` | `"/"` | no |
| <a name="input_task_execution_role_permissions_boundary"></a> [task\_execution\_role\_permissions\_boundary](#input\_task\_execution\_role\_permissions\_boundary) | Permissions boundary policy ARN applied to the created task execution role. | `string` | `null` | no |
| <a name="input_task_execution_role_policy_arns"></a> [task\_execution\_role\_policy\_arns](#input\_task\_execution\_role\_policy\_arns) | Additional managed policy ARNs attached to the created task execution role. AmazonECSTaskExecutionRolePolicy is always attached. | `set(string)` | `[]` | no |
| <a name="input_task_execution_role_statements"></a> [task\_execution\_role\_statements](#input\_task\_execution\_role\_statements) | Extra inline policy statements for the created task execution role, keyed by Sid (alphanumeric). | <pre>map(object({<br/>    effect    = optional(string, "Allow")<br/>    actions   = set(string)<br/>    resources = set(string)<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | Existing task role ARN, required when create\_task\_role is false. | `string` | `null` | no |
| <a name="input_task_role_description"></a> [task\_role\_description](#input\_task\_role\_description) | Description of the created task role. | `string` | `null` | no |
| <a name="input_task_role_name"></a> [task\_role\_name](#input\_task\_role\_name) | Name of the created task role. Defaults to <name>-task. | `string` | `null` | no |
| <a name="input_task_role_path"></a> [task\_role\_path](#input\_task\_role\_path) | IAM path of the created task role. | `string` | `"/"` | no |
| <a name="input_task_role_permissions_boundary"></a> [task\_role\_permissions\_boundary](#input\_task\_role\_permissions\_boundary) | Permissions boundary policy ARN applied to the created task role. | `string` | `null` | no |
| <a name="input_task_role_policy_arns"></a> [task\_role\_policy\_arns](#input\_task\_role\_policy\_arns) | Managed policy ARNs attached to the created task role. | `set(string)` | `[]` | no |
| <a name="input_task_role_statements"></a> [task\_role\_statements](#input\_task\_role\_statements) | Inline policy statements for the created task role, keyed by Sid (alphanumeric). This is where application data access is declared. | <pre>map(object({<br/>    effect    = optional(string, "Allow")<br/>    actions   = set(string)<br/>    resources = set(string)<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_task_execution_role_arn"></a> [task\_execution\_role\_arn](#output\_task\_execution\_role\_arn) | ARN of the task execution role, created or supplied. |
| <a name="output_task_execution_role_derived_policy"></a> [task\_execution\_role\_derived\_policy](#output\_task\_execution\_role\_derived\_policy) | JSON policy the module derived from secret, parameter, and KMS references, or null. Attach it yourself when supplying your own execution role. |
| <a name="output_task_execution_role_name"></a> [task\_execution\_role\_name](#output\_task\_execution\_role\_name) | Name of the task execution role, created or parsed from the supplied ARN. |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | ARN of the task role, created or supplied. |
| <a name="output_task_role_derived_policy"></a> [task\_role\_derived\_policy](#output\_task\_role\_derived\_policy) | JSON policy the module derived for ECS Exec, or null. Attach it yourself when supplying your own task role. |
| <a name="output_task_role_name"></a> [task\_role\_name](#output\_task\_role\_name) | Name of the task role, created or parsed from the supplied ARN. |
<!-- END_TF_DOCS -->
