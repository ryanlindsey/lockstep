# Phase 0 — Probe your hardware

## Goal

You have a written hardware profile listing your default output device and every
sample rate it supports, and you know whether anything on your system already
corrects the rate for you.

## Why this is a numbered phase

Your DAC is not the author's DAC.

The reference hardware reports ten sample rates, 44.1 kHz through 768 kHz. A USB
dongle reporting only 44.1 and 48 kHz needs a different fallback rule, and a
reader who skips this step builds against constraints that are not theirs.

There is a second reason. This phase puts you through the loop the rest of the
repo describes — name the assumption, probe it, record the result — on your own
machine, before you read a word of prose about it.

## Steps

### 1. What can your device do?

Read-only. Changes nothing.

```
swiftc -O probes/device-capabilities.swift -o /tmp/device-capabilities
/tmp/device-capabilities
```

Three lines: device, current rate, supported rates.

### 2. Does macOS already do this for you?

> **This step changes a system setting and makes a noise.** It forces your
> default output device to a supported rate that deliberately does not match
> your source, watches for 8 seconds, then restores what it found. Expect a
> click at each end. Nothing is left changed.

**Start playing something first.** With nothing playing there is nothing for
macOS to correct *to*, so a negative result proves considerably less.

```
swiftc -O probes/does-macos-autoswitch.swift -o /tmp/does-macos-autoswitch
/tmp/does-macos-autoswitch
```

## Record your profile

Keep this. Phases 1 and 2 consume it.

```markdown
## My hardware profile
- macOS version:
- Default output device:
- Current rate when probed:
- Supported rates:
- Does anything auto-correct the rate? (yes / no)
```

## Acceptance criteria

- [ ] The profile above is filled in with values read from the probes on your
      machine, not copied from this document
- [ ] The auto-correct answer is `no`

**If the answer is `yes`, stop here.** Something on your system already follows
the source and lockstep has no job to do. Please
[tell us](https://github.com/ryanlindsey/lockstep/issues/new?template=probe-report.yml)
— that is a far more interesting result than the expected one.

**If the probe reported `INCONCLUSIVE`,** your device either advertised a rate
it would not actually hold or stopped reporting its rate part way through.
Nothing can be concluded either way. That is also worth reporting, and you
should test a different rate before continuing.

## What this changes downstream

- **Fewer than four supported rates:** the same-family fallback rule in phase 2
  will matter to you. When a source rate is unsupported, the correct choice is
  the nearest supported *integer multiple* — 44.1 → 88.2 → 176.4 — never a jump
  across families to 48. Integer-ratio conversion is far cleaner arithmetic than
  44.1↔48 conversion.
- **Both the 44.1 and 48 families in full,** as on the reference hardware: the
  fallback rule will never fire on your machine. Keep it for other people.
- **Exactly one supported rate:** there is nothing to switch. Stop here.
