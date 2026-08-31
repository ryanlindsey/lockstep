# lockstep

**A DAC that follows the music.** macOS does not change your output device's
sample rate to match what is playing. A 44.1 kHz track sent to a DAC sitting at
96 kHz gets resampled, and correcting it means a trip through Audio MIDI Setup
every time the material changes.

lockstep is about 150 lines of Swift and a few pinned Shortcuts that make the
device follow the source instead.

## What this repo actually is

Two things, in priority order:

1. **A worked example of spec-driven development in the open** — the specs, the
   [decision log](docs/decisions/) with its dead ends intact, and the
   [probes](probes/) that settled each choice.
2. **An executable guide** — point your own agent at [`specs/`](specs/) and build
   it for your own hardware.

It is deliberately **not** a distributable utility. There is no download, no
installer, no release binary. [`reference/`](reference/) exists to prove the
specs produce working code, not to be installed.

## Start here

1. Read [`docs/method.md`](docs/method.md) — the loop, in six steps.
2. Run [`specs/phase-0-probe-your-hardware.md`](specs/phase-0-probe-your-hardware.md)
   against your own machine. **Do this before anything else** — your DAC is not
   the author's, and what it reports changes what you should build.
3. Build from [`specs/phase-1-manual-switching.md`](specs/phase-1-manual-switching.md)
   with whatever agent you use.

### Before you invest any time in this

Phase 0 asks one question that can end the exercise: **does anything on your
system already correct the sample rate?** If it does, lockstep has no job on your
machine and you should stop. That probe takes under a minute, and it is the first
thing this repo asks you to run for exactly that reason.

On the reference hardware — macOS 26.6.2, Cambridge Audio DacMagic 200M — the
answer was no. The device was forced to 192 kHz under a 44.1 kHz track and held
there, uncorrected, for the full eight seconds.

## What's here

| Path | What it is |
|---|---|
| [`specs/`](specs/) | The phase specs. The thing you build from |
| [`probes/`](probes/) | Runnable programs, each answering one question about your hardware |
| [`docs/method.md`](docs/method.md) | The loop, agent-neutral |
| [`docs/decisions/`](docs/decisions/) | Eight decision records, priors and dead ends intact |
| [`docs/design/`](docs/design/) · [`docs/plans/`](docs/plans/) | How this repo itself was designed and built |
| [`reference/`](reference/) | What the specs produced. You do not need it |
| [`AGENTS.md`](AGENTS.md) | The machine-readable contract |

## The decision log

[`docs/decisions/`](docs/decisions/) is the part worth reading even if you never
build any of this.

Each record carries a field standard ADRs leave out — **what we believed going
in** — because a record stating only its conclusion teaches that conclusion and
nothing else. Most of them describe a belief that turned out to be wrong.

The clearest example: this project began by reasoning that Apple Music could not
report the sample rate of *streamed* tracks, since the existing tools for this
problem go to the trouble of scraping system logs instead. An architecture was
designed around that limitation, fallback detector and all.

One line of `osascript` disproved it in about ten seconds
([0001](docs/decisions/0001-detect-via-scriptingbridge.md)). The fallback was
deleted before it was ever built. That is the repo's whole argument, in one
record.

## Agent-agnostic

The method names no tool. The machine-readable contract lives in
[`AGENTS.md`](AGENTS.md), and any tool-specific file here is a one-line pointer
to it — never content of its own.

## Status

| Phase | State |
|---|---|
| **0** — probe your hardware | Complete |
| **1** — manual switching from the menu bar | Complete |
| **2** — automatic switching | Not yet written |

## Contributing

Two kinds of contribution make sense here: [probe reports](https://github.com/ryanlindsey/lockstep/issues/new?template=probe-report.yml)
from hardware that is not the author's, and
[spec ambiguities](https://github.com/ryanlindsey/lockstep/issues/new?template=spec-ambiguity.yml)
where two readers' agents would build different things. See
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Licence

Two, because this repo ships two kinds of work.

- **Code** — [`probes/`](probes/) and [`reference/`](reference/) — MIT, see [`LICENSE`](LICENSE)
- **Prose** — `docs/` and `specs/` — CC BY 4.0, see [`LICENSE-docs`](LICENSE-docs)
