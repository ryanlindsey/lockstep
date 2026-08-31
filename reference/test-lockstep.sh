#!/usr/bin/env bash
# Exercises the phase-1 acceptance criteria against a real output device.
#
#   swiftc -O reference/lockstep.swift -o /tmp/lockstep
#   ./reference/test-lockstep.sh /tmp/lockstep
#
# Requires real audio hardware. This cannot run in CI — a GitHub runner has no
# DAC, so every result would be meaningless. It is also audible: the device
# changes rate twice and is restored.

set -uo pipefail

BIN="${1:-/tmp/lockstep}"
fails=0

report() {
  if [ "$1" -eq 0 ]; then
    echo "PASS  $2"
  else
    echo "FAIL  $2"
    fails=$((fails + 1))
  fi
}

if [ ! -x "$BIN" ]; then
  echo "no lockstep binary at $BIN — build it first" >&2
  exit 1
fi

# --- criterion 3: no argument prints device, current rate, supported rates ---
status_output="$("$BIN")"
echo "$status_output" | grep -q '^device:'    ; report $? "no-arg output names the device"
echo "$status_output" | grep -q '^current:'   ; report $? "no-arg output reports the current rate"
echo "$status_output" | grep -q '^supported:' ; report $? "no-arg output lists supported rates"

original="$(echo "$status_output" | awk '/^current:/ {print $2}')"
supported="$(echo "$status_output" | sed -n 's/^supported: *//p')"

# --- criterion 2: an unsupported rate fails cleanly and changes nothing ---
"$BIN" 1234 >/dev/null 2>&1
[ $? -ne 0 ]; report $? "unsupported rate exits non-zero"

after="$("$BIN" | awk '/^current:/ {print $2}')"
[ "$after" = "$original" ]; report $? "unsupported rate left the device unchanged"

# --- criterion 1: a supported rate is set and verified ---
target="$(echo "$supported" | tr ',' '\n' | tr -d ' ' | grep -v "^${original}$" | head -1)"
if [ -z "$target" ]; then
  echo "SKIP  device reports only one rate; nothing to switch to"
else
  "$BIN" "$target" >/dev/null 2>&1
  [ $? -eq 0 ]; report $? "setting a supported rate exits zero"

  now="$("$BIN" | awk '/^current:/ {print $2}')"
  [ "$now" = "$target" ]; report $? "device actually reports the new rate ($target Hz)"

  "$BIN" "$original" >/dev/null 2>&1
  restored="$("$BIN" | awk '/^current:/ {print $2}')"
  [ "$restored" = "$original" ]; report $? "restored the original rate ($original Hz)"
fi

# --- non-numeric argument ---
"$BIN" banana >/dev/null 2>&1
[ $? -ne 0 ]; report $? "non-numeric argument exits non-zero"

echo
if [ "$fails" -eq 0 ]; then
  echo "all acceptance criteria pass"
else
  echo "$fails failing"
  exit 1
fi
