# Probes

A probe answers one question cheaply, before you design around the answer.

Run these on **your** hardware. The author's DAC is not your DAC, and two of the
choices in `../specs/` depend on what your device actually reports rather than
what this repo found.

## `device-capabilities.swift`

Read-only. Safe to run any time — it changes nothing.

```
swiftc -O probes/device-capabilities.swift -o /tmp/device-capabilities
/tmp/device-capabilities
```

Output is three lines: the default output device, its current sample rate, and
every rate it supports. This is exactly what
[`specs/phase-0-probe-your-hardware.md`](../specs/phase-0-probe-your-hardware.md)
asks you to record.

## `does-macos-autoswitch.swift`

> **This one changes a system setting and makes a noise.** It forces your default
> output device to a supported rate that deliberately does not match your source,
> watches for 8 seconds, then restores the rate it found. Expect a click or a
> brief dropout at each end. Nothing is left changed.

**Start playing something first.** The probe runs either way, but with nothing
playing there is nothing for macOS to correct *to*, so a negative result proves
much less. Play a track, then:

```
swiftc -O probes/does-macos-autoswitch.swift -o /tmp/does-macos-autoswitch
/tmp/does-macos-autoswitch
```

Three outcomes:

- **Nothing corrected the rate** — macOS does not follow the source. lockstep
  has a job. This is the expected result.
- **Something corrected the rate** — stop here. lockstep has nothing to do on
  your system, and you should tell us about it in a probe report.
- **Inconclusive** — your device advertised a rate it would not actually hold,
  or it stopped reporting its rate part way through. Nothing can be concluded
  either way. Worth a probe report too.

That third case is why the probe confirms the device *reached* the forced rate
before watching it. A device that cannot hold a rate it advertises otherwise
looks identical to macOS correcting it, and would tell you the opposite of the
truth.

## Phase 2 probes

Two questions the phase-1 design left open, answered before phase 2's switching
logic was designed around either. Both need Apple Music **playing** — not merely
open. With nothing playing there is no track to read a rate from, and nothing to
be notified about.

### `does-music-notify.swift`

Read-only and silent. It observes a notification for 60 seconds and changes
nothing.

```
swiftc -O probes/does-music-notify.swift -o /tmp/does-music-notify
/tmp/does-music-notify
```

Start Music playing, then skip five tracks in the first fifteen seconds, pause,
wait, and play again. The probe prints each `com.apple.Music.playerInfo`
notification as it arrives, with its arrival time and every key in its payload.

Two outcomes:

- **`RESULT: n notifications in 60 seconds. The notification fires.`** — the
  notification is delivered here, and phase 2's trigger is
  `DistributedNotificationCenter`. Read the payload keys as well as the count:
  what the notification already carries decides what still has to be asked of
  Music directly.
- **`RESULT: nothing fired in 60 seconds.`** — exit 1. This is not a bug report
  against the probe. It changes what phase 2 builds: the trigger becomes a 2 s
  poll while playing instead of an observer. It is worth a probe report, because
  it means the answer differs by machine.

### `can-swift-read-music-rate.swift`

Read-only, and it costs one Automation permission prompt the first time —
grant it. It asks Music for its play state and the current track's sample rate
by three different routes and reports which of them work.

```
swiftc -O probes/can-swift-read-music-rate.swift -o /tmp/can-swift-read-music-rate
/tmp/can-swift-read-music-rate
```

Route C, the `osascript` subprocess, is the control. It is already known to
work from [decision 0001](../docs/decisions/0001-detect-via-scriptingbridge.md),
so it exists here to tell a broken route apart from a closed Music or a denied
permission.

Four outcomes:

- **`RESULT: route A works.`** — ScriptingBridge plus KVC reads Music from a
  compiled binary, so phase 2 needs no subprocess per event. This is the
  expected result.
- **`RESULT: route A failed, route B works.`** — phase 2 uses the `@objc`
  protocol declarations instead, and why A failed is worth recording.
- **`RESULT: only route C works.`** — phase 2 has to shell out to `osascript`
  once per evaluation, which is a departure from the design and needs a decision
  record before it is implemented.
- **`RESULT: even the control failed.`** — exit 1. Music is not playing, or
  Automation was denied. Nothing can be concluded about routes A or B until this
  is fixed.

Route B is reported as `unavailable — does not compile` on Swift 6.3.3, and the
declarations that fail are kept commented in the file with the exact compiler
error. That is the probe's answer for route B, not a defect in it: `@objc
optional` requirements are reachable only through the protocol existential,
never through the concrete conforming type.

## Why these files repeat each other

The two CoreAudio probes each carry their own copy of the same ~40 lines of
helpers, and `../reference/lockstep.swift` carries a third. The two phase-2
probes duplicate less because they touch less, but they follow the same rule:
four Swift files in `probes/` and `reference/`, none of them importing another.
That is deliberate.

Each probe is self-contained so you can copy one file, compile it, and run it
without cloning anything or reasoning about a shared module. For a repo whose
job is to be read and reused a piece at a time, that is worth more than the
duplication costs. The helpers are stable — they wrap CoreAudio calls that have
not changed in years.

**Do not factor them into a shared file.** If that looks like an improvement,
read this paragraph again.

## Reporting what you found

Please do — a compatibility record built from evidence rather than anecdote is
one of the two contributions this repo actually wants.

[**Open a probe report →**](https://github.com/ryanlindsey/lockstep/issues/new?template=probe-report.yml)
