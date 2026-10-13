#!/usr/bin/env bash
# Terraform cannot make lifecycle.ignore_changes conditional, so service.tf
# declares aws_ecs_service.this and aws_ecs_service.ignore_task_definition
# with identical bodies. This check fails when the two bodies drift apart in
# anything other than their count and ignore_changes lines.
#
# extract() is the generalisation point: it takes the resource type and name
# as parameters, so it can be shared with the equivalent check in
# aws.modules.dynamodb. That script still has the older awk core (single-line
# ignore_changes skip, an unguarded count skip, an awk failure reported as
# "not found"); port this version there rather than the other way round.
#
# Usage: check-service-variants.sh [file]   (default: ../service.tf)
set -euo pipefail

file="${1:-$(dirname "$0")/../service.tf}"
type="aws_ecs_service"
name_a="this"
name_b="ignore_task_definition"

if [[ ! -f "$file" || ! -r "$file" ]]; then
  echo "error: cannot read $file" >&2
  exit 1
fi

# Prints the body of resource "$type" "$1" without its top-level count (two-
# space indent, as terraform fmt writes it) and without the whole
# ignore_changes value, continuation lines up to the closing bracket included.
# Exits 3 when the resource header is not found and 4 when an ignore_changes
# list or the resource is never closed.
extract() {
  awk -v type="$type" -v name="$1" '
    $0 ~ "^resource \"" type "\" \"" name "\" \\{" { inside = 1; found = 1; next }
    inside && /^\}/ { inside = 0; next }
    inside && skipping {
      line = $0; opens = gsub(/\[/, "", line); line = $0; closes = gsub(/\]/, "", line)
      depth += opens - closes
      if (depth <= 0) { skipping = 0 }
      next
    }
    inside && /^  count[ \t]*=/ { next }
    inside && $1 == "ignore_changes" {
      line = $0; opens = gsub(/\[/, "", line); line = $0; closes = gsub(/\]/, "", line)
      depth = opens - closes
      if (depth > 0) { skipping = 1 }
      next
    }
    inside { print }
    END {
      if (!found) { exit 3 }
      if (inside || skipping) { exit 4 }
    }
  ' "$file"
}

# Capture each body once; a failed awk inside <(...) would never reach set -e.
bodies=()
for name in "$name_a" "$name_b"; do
  rc=0
  body="$(extract "$name")" || rc=$?
  case "$rc" in
    0) ;;
    3) echo "error: resource \"$type\" \"$name\" was not found in $file" >&2; exit 1 ;;
    4) echo "error: resource \"$type\" \"$name\" in $file has an unterminated block or ignore_changes list" >&2; exit 1 ;;
    *) echo "error: could not parse $file (awk exited $rc)" >&2; exit 1 ;;
  esac
  bodies+=("$body")
done

if out="$(diff <(printf '%s\n' "${bodies[0]}") <(printf '%s\n' "${bodies[1]}"))"; then
  echo "ok: aws_ecs_service.this and aws_ecs_service.ignore_task_definition are identical apart from count and ignore_changes"
else
  echo "error: the two aws_ecs_service variants in $file have drifted:" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
