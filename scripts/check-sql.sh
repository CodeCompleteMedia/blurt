#!/usr/bin/env bash
# Every check in scripts/sql, each against its own freshly built database.
#
# They used to be run one at a time by hand, which meant in practice they were
# run once — on the day they were written. The report-scope bug is the cost of
# that: a check that would have caught it existed nowhere.
#
# A file that only SELECTs prints a table for a human to read and passes whatever
# the numbers say, so it is reported as "ran" rather than "ok". Only a file that
# raises on a wrong value can fail, and the way to know a check is real is to
# move its migration aside and watch it go red.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0 asserting=0 printing=0
for f in scripts/sql/*.sql; do
  name="$(basename "$f")"
  if grep -q "raise exception" "$f"; then verdict=ok; else verdict=ran; fi
  if out=$(bash scripts/check-migrations.sh "$f" 2>&1); then
    if [ "$verdict" = ok ]; then
      printf '\033[32mok\033[0m    %s\n' "$name"; asserting=$((asserting + 1))
      echo "$out" | grep -oE "NOTICE:  ok .*" | sed 's/^NOTICE:  ok  */      /' || true
    else
      printf '\033[33mran\033[0m   %s \033[2m(prints, never fails)\033[0m\n' "$name"
      printing=$((printing + 1))
    fi
  else
    printf '\033[31mFAIL\033[0m  %s\n' "$name"
    echo "$out" | grep -iE "error|exception" | head -5 | sed 's/^/      /'
    fail=1
  fi
done
printf '\n%d asserting, %d print-only' "$asserting" "$printing"
[ "$printing" -gt 0 ] && printf ' \033[2m— print-only files prove the functions run, not that the answers are right\033[0m'
printf '\n'
exit $fail
