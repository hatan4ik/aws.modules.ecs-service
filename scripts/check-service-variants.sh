#!/usr/bin/env bash
# Terraform cannot make lifecycle.ignore_changes conditional, so service.tf
# declares aws_ecs_service.this and aws_ecs_service.ignore_task_definition
# with identical bodies. This check fails when the two bodies drift apart in
# anything other than their count and ignore_changes lines.
set -euo pipefail

file="${1:-$(dirname "$0")/../service.tf}"

extract() {
  awk -v name="$1" '
    $0 ~ "^resource \"aws_ecs_service\" \"" name "\" \\{" { inside = 1; next }
    inside && /^\}/ { inside = 0 }
    inside && $1 == "count" { next }
    inside && $1 == "ignore_changes" { next }
    inside { print }
  ' "$file"
}

if diff <(extract this) <(extract ignore_task_definition) >/dev/null; then
  echo "ok: aws_ecs_service.this and aws_ecs_service.ignore_task_definition are identical apart from count and ignore_changes"
else
  echo "error: the two aws_ecs_service variants in $file have drifted:" >&2
  diff <(extract this) <(extract ignore_task_definition) >&2 || true
  exit 1
fi
