# Reference implementation

**You do not need this.**

This directory exists for two reasons, and neither is "install lockstep":

1. To prove the specs in [`../specs/`](../specs/) actually produce working code.
2. To give you something to compare against if your own build gets stuck.

Building it yourself from the specs, with whatever agent you use, is the point
of the repo. Reading the answer first is allowed, but it is not the exercise.

## Build

From the repository root:

```
mkdir -p ~/bin
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
| `lockstep --watch --devices "A,B"` | Follow Apple Music; set the rate when A or B is the default output | runs until killed |
| `lockstep --watch` (no `--devices`) | Print that `--devices` is required, to stderr | 1 |

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

## Watching

`lockstep --watch` follows Apple Music: it wakes on
`com.apple.Music.playerInfo`, waits out a 400 ms debounce, and sets the rate —
but only when the default output device is one you named, and only when the rate
actually needs changing. It runs until killed, which is what the launchd agent in
[`launchd/README.md`](launchd/README.md) is for.

```
$ lockstep --watch --devices "CA DacMagic 200M 2.0"
allowlist: CA DacMagic 200M 2.0
watching:  com.apple.Music.playerInfo, 400 ms debounce
2026-09-04T14:03:11Z  event  playerInfo
2026-09-04T14:03:12Z  set    44100 Hz — verified
2026-09-04T14:03:20Z  noop   already at 44100 Hz
2026-09-04T14:03:31Z  skip   MacBook Pro Speakers is not in the allowlist
```

The verb is the second field, and the acceptance test parses it there.

## Acceptance tests

Also from the repository root:

```
swiftc -O reference/lockstep.swift -o /tmp/lockstep
./reference/test-lockstep.sh /tmp/lockstep
```

> **This changes your device's sample rate twice and is audible.** It reads the
> current rate, switches to a different supported one, verifies, and restores.
> Expect a click at each change.

Phase 2 has its own:

```
./reference/test-lockstep-watch.sh /tmp/lockstep
```

> **This one also drives Apple Music.** It skips tracks, pauses, plays, and
> changes the sample rate, then restores the rate and play state it found. Play
> from a large playlist rather than a single album — it skips about nine tracks
> and will otherwise run off the end of the queue.

Neither can run in CI — a build runner has no DAC and no Apple Music, so every
result there would be meaningless. CI compiles this code and never executes it.

## The menu bar half

The binary is only half of phase 1. Shortcuts supplies the UI:
[`shortcuts/README.md`](shortcuts/README.md).
