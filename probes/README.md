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
- **Inconclusive** — your device advertised a rate it would not actually hold.
  Nothing can be concluded either way. Worth a probe report too.

That third case is why the probe confirms the device *reached* the forced rate
before watching it. A device that cannot hold a rate it advertises otherwise
looks identical to macOS correcting it, and would tell you the opposite of the
truth.

## Why these two files repeat each other

Both files carry their own copy of the same ~40 lines of CoreAudio helpers, and
`../reference/lockstep.swift` carries a third. That is deliberate.

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
