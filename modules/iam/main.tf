# ---------------------------------------------------------------------------
# Task execution role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "task_execution" {
  count = var.create_task_execution_role ? 1 : 0

  name                 = local.task_execution_role_name
  path                 = var.task_execution_role_path
  description          = var.task_execution_role_description
  permissions_boundary = var.task_execution_role_permissions_boundary
  assume_role_policy   = local.assume_role_policy

  tags = merge(var.tags, { Name = local.task_execution_role_name })
}

resource "aws_iam_role_policy_attachment" "task_execution_default" {
  count = var.create_task_execution_role ? 1 : 0

  role       = aws_iam_role.task_execution[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  for_each = toset([for arn in var.task_execution_role_policy_arns : arn if var.create_task_execution_role])

  role       = aws_iam_role.task_execution[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "task_execution_derived" {
  count = var.create_task_execution_role && local.task_execution_derived_policy != null ? 1 : 0

  name   = "derived"
  role   = aws_iam_role.task_execution[0].id
  policy = local.task_execution_derived_policy
}

resource "aws_iam_role_policy" "task_execution_declared" {
  count = var.create_task_execution_role && local.task_execution_declared_policy != null ? 1 : 0

  name   = "declared"
  role   = aws_iam_role.task_execution[0].id
  policy = local.task_execution_declared_policy
}

# ---------------------------------------------------------------------------
# Task role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  count = var.create_task_role ? 1 : 0

  name                 = local.task_role_name
  path                 = var.task_role_path
  description          = var.task_role_description
  permissions_boundary = var.task_role_permissions_boundary
  assume_role_policy   = local.assume_role_policy

  tags = merge(var.tags, { Name = local.task_role_name })
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each = toset([for arn in var.task_role_policy_arns : arn if var.create_task_role])

  role       = aws_iam_role.task[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "task_derived" {
  count = var.create_task_role && local.task_derived_policy != null ? 1 : 0

  name   = "derived"
  role   = aws_iam_role.task[0].id
  policy = local.task_derived_policy
}

resource "aws_iam_role_policy" "task_declared" {
  count = var.create_task_role && local.task_declared_policy != null ? 1 : 0

  name   = "declared"
  role   = aws_iam_role.task[0].id
  policy = local.task_declared_policy
}
