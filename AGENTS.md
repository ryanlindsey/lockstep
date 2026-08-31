# AGENTS.md — lockstep

**lockstep** keeps a macOS output device's sample rate matched to what is
playing, so nothing gets resampled on its way to a DAC.

This repo is two things, in priority order:

1. **A worked example of spec-driven development in the open** — the specs, the
   decision log including its dead ends, and the probes that settled each
   choice.
2. **An executable guide** — a reader points their own agent at `specs/` and
   builds lockstep for their own hardware.

It is deliberately **not** a distributable macOS utility. `reference/` exists to
prove the specs produce working code, not to be installed.

## Stack

Swift 6 compiled with `swiftc`. CoreAudio and Foundation. macOS Shortcuts for
the menu bar. No SPM manifest, no Xcode project, no third-party dependencies.
Target macOS 12+ (`kAudioObjectPropertyElementMain`); developed against 26.6.2.

## Constraints

Prohibitions, because that is what is actually useful:

- **No third-party dependencies.** Foundation and CoreAudio only.
- **No Xcode project, no SPM manifest.** `swiftc` compiles single files.
- **No log scraping, no private APIs, no MediaRemote.** Public documented API
  only.
- **Every Swift file must compile clean under `swiftc -warnings-as-errors`.**
  A *full compile*, never `-typecheck`: the `CFString` raw-pointer warning this
  rule exists to catch is emitted during lowering, so `-typecheck` exits 0 on
  code that carries it. See
  [0007](docs/decisions/0007-ci-compiles-not-typechecks.md).
- **CI compiles Swift; CI never executes it.** A runner has no USB DAC, so any
  probe or `lockstep` output there would be meaningless.
- **The rate setter must read the rate back after setting it.** A `noErr` status
  is not proof the driver applied the change.
- **Probes are self-contained single files.** The ~40 duplicated lines of
  CoreAudio helpers across the three Swift files are a deliberate, documented
  trade so a reader can copy one file and run it. **Do not factor them into a
  shared module.**
- **Do not switch bit depth.** See
  [0002](docs/decisions/0002-match-rate-only.md).
- **A guardrail, because it is tempting and was explicitly rejected:** do not add
  a CI job that points an agent at the specs to check they build. It is
  non-deterministic, costs money per run, and would hard-code one agent into a
  repo whose premise is agent-agnosticism. The compile job gives most of the
  confidence with none of the contradiction.

## Layout

| Path | Contains | Does not contain |
|---|---|---|
| `specs/` | Phase specs a reader's agent executes | Implementation |
| `probes/` | Self-contained programs that answer one question each | Shared modules |
| `reference/` | What the specs produce, for comparison | Anything the specs do not describe |
| `docs/decisions/` | One decision per file, with priors and evidence | Narrative that belongs in the README |
| `docs/method.md` | The loop, agent-neutral | Any specific tool's name |
| `docs/design/`, `docs/plans/` | How this repo itself was designed and built | — |

## Commands

```bash
# What CI runs. Compile every Swift file; warnings are errors.
set -e; out="$(mktemp -d)"
for file in probes/*.swift reference/*.swift; do
  swiftc -warnings-as-errors -o "$out/$(basename "$file" .swift)" "$file"
done

# Build and exercise the reference implementation (real hardware, audible)
swiftc -O reference/lockstep.swift -o /tmp/lockstep
./reference/test-lockstep.sh /tmp/lockstep

# The probes (the second one changes a system setting and is audible)
swiftc -O probes/device-capabilities.swift -o /tmp/device-capabilities && /tmp/device-capabilities
swiftc -O probes/does-macos-autoswitch.swift -o /tmp/does-macos-autoswitch && /tmp/does-macos-autoswitch
```

## Conventions

Conventional Commits. **The PR title is what release-please reads on
squash-merge** — a title without a recognised `type:` prefix is silently
skipped: no version bump, no changelog entry.

| Type | Effect |
|---|---|
| `feat` | Spec changes — minor bump |
| `fix` | Corrections — patch bump |
| `probe` | New hardware evidence — changelog only |
| `docs` | Documentation — changelog only |
| `chore` | Hidden |

## The rule that matters most

**The specs are the source of truth. Changing an architectural choice requires
adding a decision file in the same PR.**

That makes this repo self-enforcing: the thing it teaches is the thing it
requires. If you are about to change an approach and cannot articulate what you
believed going in, you do not yet understand the change well enough to make it.
