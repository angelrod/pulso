#!/bin/sh
# Runs every check on the Swift package and ends with a PASS/FAIL table.
cd "$(dirname "$0")" || exit 2
# Xcode's toolchain (Swift 6, Swift Testing) without changing the system default.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

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
$(printf '%s\n' "$out" | grep -E 'error|✘|failed|problem' | head -8 | sed 's/^/      /')"
  fi
}

step "build" swift build
# Serial, so the timing tests do not compete with each other; the count comes from this run.
step "test" swift test --no-parallel
tests=$(printf '%s\n' "$out" | grep -E 'Test run with [0-9]+ tests?' | tail -1 | sed 's/^[^T]*//')
step "check:comments" node ../scripts/check-comments.mjs native/Sources swift
# The time and a fingerprint of the sources: a pasted block must match the code delivered.
stamp="run $(date +%H:%M:%S) · sources $(find Sources Tests Package.swift -type f \( -name '*.swift' -o -name '*.ts' -o -name '*.css' -o -name '*.html' \) -print0 2>/dev/null | sort -z | xargs -0 shasum | shasum | cut -c1-12)"
printf '\n== native verify ==%s\n%s\n%s\n' "$summary" "$tests" "$stamp"
[ "$failed" -eq 0 ] && echo "ALL GREEN" || echo "NOT GREEN"
exit "$failed"
