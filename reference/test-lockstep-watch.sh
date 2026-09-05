#!/usr/bin/env bash
# Exercises the phase-2 acceptance criteria against real hardware and a real
# Apple Music.
#
#   swiftc -O reference/lockstep.swift -o /tmp/lockstep
#   ./reference/test-lockstep-watch.sh /tmp/lockstep
#
# This drives Music, changes your device's sample rate, and is audible. It
# restores the rate and the play state it found. It cannot run in CI — a runner
# has no DAC and no Music, so every result there would be meaningless.

set -uo pipefail

BIN="${1:-/tmp/lockstep}"
LOG="$(mktemp -t lockstep-watch)"
fails=0
watcher=""

report() {
  if [ "$1" -eq 0 ]; then
    echo "PASS  $2"
  else
    echo "FAIL  $2"
    fails=$((fails + 1))
  fi
}

cleanup() {
  [ -n "$watcher" ] && kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
}
trap cleanup EXIT

music() { osascript -e "tell application \"Music\" to $1" 2>/dev/null; }

# Evaluations that reached a decision about the rate, since line $1. A skip is a
# decision too, but only these two mean the device was looked at and judged.
evaluations_since() {
  tail -n "+$1" "$LOG" | awk '$2=="set" || $2=="noop" {n++} END {print n+0}'
}
# Rate changes since line $1. This is the number design §8's first criterion is
# about — see docs/decisions/0013-the-debounce-criterion-counts-rate-changes.md.
sets_since() {
  tail -n "+$1" "$LOG" | awk '$2=="set" {n++} END {print n+0}'
}
lines() { wc -l < "$LOG" | tr -d ' '; }

if [ ! -x "$BIN" ]; then
  echo "no lockstep binary at $BIN — build it first" >&2
  exit 1
fi

# --- criterion 5: --watch without --devices refuses to start -----------------
"$BIN" --watch >/dev/null 2>&1
[ $? -eq 1 ]; report $? "--watch without --devices exits 1"

# --- preconditions -----------------------------------------------------------
if [ "$(music 'player state as text')" != "playing" ]; then
  echo "Apple Music must be playing before this test runs" >&2
  exit 1
fi

# This test skips about nine tracks. Playing a single album runs off the end of
# the queue part way through, Music stops, and every criterion after that point
# fails for a reason that has nothing to do with lockstep. Ask for a deep queue
# rather than letting that happen — it costs one line and it cost an afternoon
# to diagnose the first time.
ahead="$(osascript -e 'tell application "Music" to get (count of tracks of current playlist) - (index of current track)' 2>/dev/null)"
if [ -n "$ahead" ] && [ "$ahead" -lt 12 ] 2>/dev/null; then
  echo "only $ahead tracks left in the queue — this test skips about nine." >&2
  echo "Play something with more ahead of it (a large playlist, not one album)." >&2
  exit 1
fi

status="$("$BIN")"
device="$(echo "$status" | sed -n 's/^device: *//p')"
original="$(echo "$status" | awk '/^current:/ {print $2}')"
if [ -z "$device" ] || [ -z "$original" ] || [ "$original" = "unknown" ]; then
  echo "cannot read the device or its rate from $BIN — aborting" >&2
  exit 1
fi

"$BIN" --watch --devices "$device" > "$LOG" 2>&1 &
watcher=$!
sleep 2
grep -q '^allowlist:' "$LOG"; report $? "the watcher prints its allowlist at startup"

# --- criterion 1: five rapid skips produce exactly one evaluation ------------
# One osascript, five skips. Five separate osascript invocations take about
# 475 ms end to end — wider than the 400 ms debounce — so they are not "rapid
# succession" and no correct implementation would coalesce them into one. The
# process spawns, not the skips, were the slow part.
mark=$(( $(lines) + 1 ))
osascript -e 'tell application "Music"
  repeat 5 times
    next track
  end repeat
end tell' 2>/dev/null
sleep 4
# Design §8: "produces exactly one rate change". Rate changes, not evaluations —
# Music's playerInfo emissions trail a burst of skips by about 500 ms, which is
# wider than the 400 ms debounce, so a burst legitimately produces more than one
# evaluation. What must never happen is five rate changes. The no-op guard is
# what makes the trailing evaluation harmless, and criterion 4 tests that guard
# directly. See docs/decisions/0013-the-debounce-criterion-counts-rate-changes.md.
[ "$(sets_since "$mark")" -le 1 ]
report $? "five rapid skips produced at most one rate change"
[ "$(evaluations_since "$mark")" -lt 5 ]
report $? "five rapid skips did not produce five evaluations"

# --- criterion 4: no set call when the device already matches ----------------
music 'next track'
sleep 4
now="$("$BIN" | awk '/^current:/ {print $2}')"
mark=$(( $(lines) + 1 ))
music 'next track'
sleep 4
after="$("$BIN" | awk '/^current:/ {print $2}')"
if [ "$now" = "$after" ]; then
  [ "$(sets_since "$mark")" -eq 0 ]
  report $? "no set call when the device already matches the source"
else
  echo "SKIP  consecutive tracks differed in rate; no-op guard not exercised"
fi

# --- criterion 2: paused means no rate change --------------------------------
music 'pause'
sleep 1
mark=$(( $(lines) + 1 ))
music 'next track'
sleep 4
[ "$(sets_since "$mark")" -eq 0 ]; report $? "no set call while Music is paused"
tail -n "+$mark" "$LOG" | grep -q 'not playing'
report $? "the log says why it skipped"
music 'play'
sleep 2

# --- criterion 3: a device outside the allowlist is skipped by name ----------
kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
LOG="$(mktemp -t lockstep-watch)"
"$BIN" --watch --devices "No Such Device" > "$LOG" 2>&1 &
watcher=$!
sleep 2
mark=$(( $(lines) + 1 ))
music 'next track'
sleep 4
[ "$(sets_since "$mark")" -eq 0 ]; report $? "no set call for a device outside the allowlist"
tail -n "+$mark" "$LOG" | grep -q "$device is not in the allowlist"
report $? "the log names the device it skipped"

# --- restore -----------------------------------------------------------------
kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
watcher=""
"$BIN" "$original" >/dev/null 2>&1
restored="$("$BIN" | awk '/^current:/ {print $2}')"
[ "$restored" = "$original" ]; report $? "restored the original rate ($original Hz)"

echo
if [ "$fails" -eq 0 ]; then
  echo "all acceptance criteria pass"
else
  echo "$fails failing"
  exit 1
fi
