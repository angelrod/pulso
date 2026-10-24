#!/bin/sh
# Runs every check and ends with a PASS/FAIL table.
cd "$(dirname "$0")/.." || exit 2

summary=""
failed=0
step() {
  name=$1
  shift
  if out=$("$@" 2>&1); then
    summary="$summary
PASS  $name"
  else
    failed=1
    summary="$summary
FAIL  $name
$(printf '%s\n' "$out" | grep -E 'error|Error|×|FAIL|problem' | head -8 | sed 's/^/      /')"
  fi
}

step "test" pnpm -s test
step "typecheck" pnpm -s typecheck
step "check:comments" pnpm -s check:comments
step "build" pnpm -s build

tests=$(pnpm -s test 2>&1 | grep -E '^ +Tests ' | sed 's/^ *//')
printf '\n== pnpm verify ==%s\n%s\n' "$summary" "$tests"
[ "$failed" -eq 0 ] && echo "ALL GREEN" || echo "NOT GREEN"
exit "$failed"
