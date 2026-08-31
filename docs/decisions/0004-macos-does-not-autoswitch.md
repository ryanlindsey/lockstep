# 0004 — macOS does not follow the source; the problem is real

- Status: accepted
- Date: 2026-08-30
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

Briefly, that the problem might already be solved.

Mid-investigation the DAC was seen matching the playing track twice in a row —
96 kHz under a 96 kHz track, then 44.1 under a 44.1 kHz track. Two consecutive
matches with no intervention look a great deal like automatic correction. If
macOS 26 had quietly grown this feature, the entire project was unnecessary.

## What we probed

Force the device to a deliberately wrong rate while audio plays, and watch
whether anything puts it back:

```
original rate: 44100 Hz
forcing:       192000 Hz  (deliberately wrong)
watching for 8 seconds…
  t+0.5s: 192000 Hz
  …
  t+8.0s: 192000 Hz
restored to 44100 Hz

RESULT: nothing corrected the rate — macOS does not follow the source.
```

Sixteen samples across eight seconds, no correction. The two earlier "matches"
were the author's own manual work in Audio MIDI Setup, not automation.

## Decision

Proceed. The problem exists on macOS 26.6.2.

## Consequences

- **This is the probe that could have ended the project**, and it cost under a
  minute. Checking whether a problem still exists before building the thing that
  solves it is the cheapest step available, and the one most often skipped.
- It ships as [`probes/does-macos-autoswitch.swift`](../../probes/does-macos-autoswitch.swift)
  so every reader can ask it of their own system first. If it answers *yes* for
  them, they should stop reading and go and listen to something.
- The probe was later hardened: it now confirms the device actually *reached*
  the forced rate before treating any change as a correction. A device that
  advertises a rate it cannot hold would otherwise look identical to macOS
  auto-switching, and would tell the reader the opposite of the truth.
