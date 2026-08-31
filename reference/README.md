# Reference implementation

**You do not need this.**

This directory exists for two reasons, and neither is "install lockstep":

1. To prove the specs in [`../specs/`](../specs/) actually produce working code.
2. To give you something to compare against if your own build gets stuck.

Building it yourself from the specs, with whatever agent you use, is the point
of the repo. Reading the answer first is allowed, but it is not the exercise.

## Build

```
swiftc -O reference/lockstep.swift -o ~/bin/lockstep
```

No Xcode project, no package manifest, no dependencies. One file.

## What it does

| Invocation | Behaviour | Exit |
|---|---|---|
| `lockstep` | Print device name, current rate, supported rates | 0 |
| `lockstep <rate>` | Set default output to `<rate>` Hz, read it back, confirm | 0 on verified success |
| `lockstep <unsupported-rate>` | Print supported rates to stderr, change nothing | 1 |
| `lockstep <non-numeric>` | Print usage to stderr | 1 |
| `lockstep --help` / `-h` | Print usage | 0 |

```
$ lockstep
device:    CA DacMagic 200M 2.0
current:   44100 Hz
supported: 44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000

$ lockstep 96000
CA DacMagic 200M 2.0 → 96000 Hz
```

Note what `lockstep 96000` prints: the rate the **device reports back**, not the
rate that was requested. `setRate` polls until the device confirms, because a
`noErr` status is not proof the driver applied anything.

## Acceptance tests

```
swiftc -O reference/lockstep.swift -o /tmp/lockstep
./test-lockstep.sh /tmp/lockstep
```

> **This changes your device's sample rate twice and is audible.** It reads the
> current rate, switches to a different supported one, verifies, and restores.
> Expect a click at each change.

It cannot run in CI — a build runner has no DAC, so every result there would be
meaningless. CI compiles this code and never executes it.

## The menu bar half

The binary is only half of phase 1. Shortcuts supplies the UI:
[`shortcuts/README.md`](shortcuts/README.md).
