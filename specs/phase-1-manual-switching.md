# Phase 1 — Manual switching from the menu bar

## Goal

A single compiled binary, plus Shortcuts pinned to the macOS menu bar, that set
the default output device's sample rate in one click — replacing the round-trip
through Audio MIDI Setup.

## Prerequisites

- [Phase 0](phase-0-probe-your-hardware.md) complete, with a filled-in hardware
  profile
- Xcode Command Line Tools installed — `swiftc --version` should answer

## Constraints

Stated as prohibitions, because that is what an implementer actually needs:

- **No third-party dependencies.** Foundation and CoreAudio only.
- **No Xcode project and no SPM manifest.** One `.swift` file, compiled with
  `swiftc`.
- **No log scraping, no private APIs, no MediaRemote.** Public documented API
  only — see [decision 0001](../docs/decisions/0001-detect-via-scriptingbridge.md).
- **Must compile clean under `swiftc -warnings-as-errors`.** A full compile, not
  `-typecheck`, and the difference is not cosmetic — see
  [decision 0007](../docs/decisions/0007-ci-compiles-not-typechecks.md).
- **The rate setter must read the rate back after setting it.** A `noErr` status
  is not proof the driver applied the change. This is the rule the auto-switch
  probe originally broke, and the reason it now reports `INCONCLUSIVE`.
- **Do not switch bit depth** — see
  [decision 0002](../docs/decisions/0002-match-rate-only.md).

## Build

### The binary

One executable, `lockstep`, with this contract:

| Invocation | Behaviour | Exit |
|---|---|---|
| `lockstep` | Print device name, current rate, supported rates | 0 |
| `lockstep <rate>` | Set default output to `<rate>` Hz, read it back, confirm | 0 on verified success |
| `lockstep <unsupported-rate>` | Print supported rates to stderr, change nothing | 1 |
| `lockstep <non-numeric>` | Print usage to stderr | 1 |
| `lockstep --help` / `-h` | Print usage | 0 |

The no-argument output format is load-bearing — the acceptance tests parse it:

```
device:    CA DacMagic 200M 2.0
current:   96000 Hz
supported: 44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
```

Label at the start of the line, value after. Keep that shape.

### The menu bar

Shortcuts supplies the UI, so no application is built. For each rate you
actually use, create a Shortcut containing a single **Run Shell Script** action
that invokes the binary, then tick **Pin in Menu Bar** in its inspector. Full
walkthrough in [`reference/shortcuts/README.md`](../reference/shortcuts/README.md).

Create Shortcuts only for rates your own device reported in phase 0.

## Acceptance criteria

- [ ] `lockstep 96000` sets the default output device to 96 kHz and prints
      confirmation
- [ ] `lockstep 1234` exits non-zero, prints the supported rates, and leaves the
      device unchanged
- [ ] `lockstep` with no argument prints device name, current rate, and
      supported rates
- [ ] A Shortcut pinned in the menu bar performs a switch in one click

Substitute a rate your device actually supports if it does not do 96 kHz.

## Verification

```
swiftc -O path/to/your/lockstep.swift -o /tmp/lockstep
./reference/test-lockstep.sh /tmp/lockstep
```

Every line must read `PASS`, ending `all acceptance criteria pass`.

**This runs against real hardware and is audible** — it changes the rate twice
and restores it. It cannot run in CI: a build runner has no DAC, so every result
there would be meaningless. CI compiles this code and never executes it.

## Known limitations

- **Changing the rate mid-stream causes a brief dropout.** CoreAudio reconfigures
  its IO underneath a running application. This is inherent to the problem rather
  than to this implementation, and every tool solving it behaves the same way.
- **No live status in the menu bar.** Shortcuts can trigger but not display, so
  there is no always-visible rate indicator — see
  [decision 0005](../docs/decisions/0005-scripts-not-an-app.md). Phase 2 removes
  the need to look.
- **Nothing here detects what is playing.** Phase 1 is a faster manual switch,
  not automation. You still choose the rate.
