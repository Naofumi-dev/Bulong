#!/bin/bash
# Stress-tests the dictation pipeline against a RUNNING Bulong.app:
#   N record→stop cycles (plus one long recording) driven via bulong://toggle,
#   sampling Bulong's main thread throughout. The app freezes ⇔ the main
#   thread leaves its mach_msg event-loop wait — that's what we assert on.
#
# Usage: script/stress_dictation.sh [cycles] [long_seconds]
#   cycles       short record→stop cycles to run (default 9)
#   long_seconds length of the one long recording (default 65)
#
# Requires: Bulong running, mic permission granted, `say` audible to the mic.

set -euo pipefail

CYCLES="${1:-9}"
LONG_SECONDS="${2:-65}"
OUT="$(mktemp -d /tmp/bulong-stress.XXXXXX)"
HISTORY="$HOME/Library/Application Support/Bulong/history.jsonl"
FAILED=0

main_thread_ok() {
  # First thread block of a 1s sample = main thread. Healthy means it's
  # parked in the run-loop's mach_msg trap, not stuck in app code.
  # NOTE: no `grep -q` here — under pipefail its early exit SIGPIPEs awk
  # (status 141) and turns every healthy sample into a false failure.
  local file="$1"
  awk '/Call graph/{f=1} f&&/Thread_/{c++} c==1&&f' "$file" | grep "mach_msg2_trap" > /dev/null
}

sample_main() {
  local tag="$1"
  local file="$OUT/sample_$tag.txt"
  sample Bulong 1 -file "$file" >/dev/null 2>&1 || { echo "  !! sample failed (app gone?)"; FAILED=1; return; }
  if main_thread_ok "$file"; then
    echo "  main thread healthy ($tag)"
  else
    echo "  !! MAIN THREAD NOT IN EVENT LOOP ($tag) — see $file"
    FAILED=1
  fi
}

cycle() {
  local n="$1" speak="$2"
  local before after deadline
  before=$(wc -l < "$HISTORY" 2>/dev/null || echo 0)
  echo "cycle $n: start"
  open -g "bulong://toggle"
  sleep 1
  say "$speak" &
  local SAY_PID=$!
  sample_main "${n}_recording"
  wait "$SAY_PID"
  sleep 0.5
  echo "cycle $n: stop"
  open -g "bulong://toggle"
  # Poll history for the new entry while sampling the main thread.
  deadline=$((SECONDS + 90))
  while [ $SECONDS -lt $deadline ]; do
    sample_main "${n}_processing_$SECONDS"
    after=$(wc -l < "$HISTORY" 2>/dev/null || echo 0)
    if [ "$after" -gt "$before" ]; then
      echo "cycle $n: transcript landed ($(tail -1 "$HISTORY" | cut -c1-80)…)"
      return 0
    fi
    sleep 2
  done
  echo "  !! cycle $n: no transcript within 90s"
  FAILED=1
}

echo "== Bulong dictation stress: $CYCLES short cycles + one ${LONG_SECONDS}s recording =="
pgrep -x Bulong >/dev/null || { echo "Bulong is not running"; exit 1; }

for i in $(seq 1 "$CYCLES"); do
  cycle "$i" "Stress cycle $i. Kumusta! One two three, tapos na."
done

echo "== long recording (${LONG_SECONDS}s) =="
before=$(wc -l < "$HISTORY" 2>/dev/null || echo 0)
open -g "bulong://toggle"
sleep 1
END=$((SECONDS + LONG_SECONDS))
i=0
while [ $SECONDS -lt $END ]; do
  say "This is the long recording stress segment number $i. Bulong should keep the interface responsive the entire time, kahit gaano katagal ang recording." &
  SAY_PID=$!
  sample_main "long_recording_$SECONDS"
  wait "$SAY_PID"
  i=$((i + 1))
done
open -g "bulong://toggle"
deadline=$((SECONDS + 180))
while [ $SECONDS -lt $deadline ]; do
  sample_main "long_processing_$SECONDS"
  after=$(wc -l < "$HISTORY" 2>/dev/null || echo 0)
  if [ "$after" -gt "$before" ]; then
    echo "long recording: transcript landed"
    break
  fi
  sleep 2
done
[ "${after:-0}" -gt "$before" ] || { echo "!! long recording: no transcript within 180s"; FAILED=1; }

echo
if [ "$FAILED" -eq 0 ]; then
  echo "PASS — main thread stayed in its event loop through every phase; all transcripts landed. Samples: $OUT"
else
  echo "FAIL — see samples in $OUT"
  exit 1
fi
