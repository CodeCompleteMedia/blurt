#!/usr/bin/env bash
# Every check in scripts/sql, each against its own freshly built database.
#
# They used to be run one at a time by hand, which meant in practice they were
# run once — on the day they were written. The report-scope bug is the cost of
# that: a check that would have caught it existed nowhere.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for f in scripts/sql/*.sql; do
  if out=$(bash scripts/check-migrations.sh "$f" 2>&1); then
    printf '\033[32mok\033[0m    %s\n' "$(basename "$f")"
    echo "$out" | grep -oE "NOTICE:  ok .*" | sed 's/^NOTICE:  ok  */      /' || true
  else
    printf '\033[31mFAIL\033[0m  %s\n' "$(basename "$f")"
    echo "$out" | grep -iE "error|exception" | head -5 | sed 's/^/      /'
    fail=1
  fi
done
exit $fail
