# lockstep — design

**Date:** 2026-08-30
**Status:** approved
**Repo:** https://github.com/ryanlindsey/lockstep

## 1. Problem

macOS does not follow an audio source's sample rate. When Apple Music plays a
44.1 kHz track through a USB DAC set to 96 kHz, CoreAudio resamples. Correcting
it means a manual round-trip through Audio MIDI Setup, per album.

Verified on this hardware (macOS 26.6.2, Cambridge Audio DacMagic 200M): the
device was forced to 192 kHz during 44.1 kHz playback and polled for 8 seconds.
It stayed at 192 kHz. Nothing in macOS 26 corrects this.

## 2. What this repo is

Two products in one repo, in this priority order:

1. **A worked example of spec-driven, agentic development in the open** — the
   specs, the decision log including its dead ends, and the probes that settled
   each decision.
2. **An executable guide** — a reader points their own agent at `specs/` and
   builds `lockstep` for their own hardware.

It is deliberately *not* a distributable macOS utility. A reader who only wants
their DAC fixed is better served by running the reference implementation, but
that is a side effect, not the goal.

## 3. Decisions fixed before design

| Decision | Choice |
|---|---|
| Automation level | Automatic switching, with manual override as escape hatch |
| Sources | Apple Music now, behind a source seam so others can be added |
| Devices | Opt-in allowlist, phase 2 only; manual invocation is explicit intent and needs no guard |
| Distribution | Public GitHub repo; scripts, not a notarized app |
| Bit depth | Match sample rate only; pin depth at device maximum |
| What ships | Specs + reference implementation, clearly separated |
| Process trail | Specs + decision log including dead ends |
| Prescriptiveness | Artifacts plus a described loop, agent-neutral |

## 4. Technical findings that constrain everything downstream

- **Detection.** Apple Music exposes `sample rate` (`pSRt`, Hz) on the current
  track via ScriptingBridge, and it reports the true rate for *streamed* catalog
  tracks (`class: URL track`), not just local files. Confirmed: a streamed
  Hi-Res Lossless track returned `96000`. This is public, documented API and
  replaces the log-scraping approach used by prior art.
- **Application.** `kAudioDevicePropertyNominalSampleRate` via
  `AudioObjectSetPropertyData` sets the rate. Confirmed `noErr`, with the change
  observed and held. No entitlements, no permissions prompt, no private API.
- **JXA is not viable.** `CoreAudio.bridgesupport` exposes the functions but not
  the `AudioObjectPropertyAddress` struct constructor; passing a struct literal
  returned status `0x6E6F7065` with size 0. Swift via `/usr/bin/swift` is the
  route.
- **Bit depth is sonically irrelevant.** CoreAudio mixes to 32-bit float; a
  16-bit source through a 24-bit device is bit-transparent. Only sample rate
  mismatch causes a real resample.
- **Reference hardware supports** 44100, 48000, 88200, 96000, 176400, 192000,
  352800, 384000, 705600, 768000. A reader's device will differ; this is why
  phase 0 exists.

## 5. Repo structure

```
lockstep/
├── README.md                    problem, method, how to use this repo
├── AGENTS.md                    agent contract — and the exemplar being taught
├── CLAUDE.md                    one line: @AGENTS.md
├── CONTRIBUTING.md              the two contributions that make sense
├── LICENSE                      MIT — covers reference/ and probes/
├── LICENSE-docs                 CC BY 4.0 — covers docs/ and specs/
├── .gitignore
├── .github/
│   ├── dependabot.yml           github-actions ecosystem only
│   ├── ISSUE_TEMPLATE/
│   │   ├── probe-report.yml     DAC model, macOS version, probe output
│   │   └── spec-ambiguity.yml   ambiguity is the bug class for a spec repo
│   └── workflows/
│       ├── build.yml            compile reference/ and probes/ on macos-latest
│       ├── links.yml            link checker
│       └── release-please.yml
├── release-please-config.json
├── .release-please-manifest.json
├── version.txt                  maintained by release-please
├── docs/
│   ├── method.md                the loop, agent-neutral
│   ├── design/
│   │   └── 2026-08-30-repo-design.md       this document
│   └── decisions/
│       ├── README.md            the arc, narrated
│       └── 0001..0006-*.md      one decision per file
├── probes/
│   ├── README.md
│   ├── device-capabilities.swift
│   └── does-macos-autoswitch.swift
├── specs/
│   ├── phase-0-probe-your-hardware.md
│   ├── phase-1-manual-switching.md
│   └── phase-2-automatic-switching.md
└── reference/
    ├── README.md                "you don't need this — it's what the specs produced"
    ├── lockstep.swift
    └── shortcuts/README.md
```

**`probes/` is first-class, not an appendix.** The method's central claim is
*probe the risky assumption before designing around it*; shipping runnable
probes makes that executable rather than preached. It is also required for
correctness — a reader whose DAC supports only 44.1/48 gets a different answer
and therefore needs a different fallback rule.

**`reference/` is deliberately demoted.** Its README states plainly that the
reader does not need it, and that it exists to prove the specs are buildable and
to give the reader something to diff their agent's output against.

## 6. Scaffolding

**Dual license.** MIT is wrong for prose and CC BY 4.0 is wrong for code, and
this repo ships both. `LICENSE` (MIT) covers `reference/` and `probes/`;
`LICENSE-docs` (CC BY 4.0) covers `docs/` and `specs/`. README states the split.
GitHub license detection reads the root `LICENSE` and will report MIT.

**release-please**, `release-type: simple` (a `version.txt`, no language
manifest). Versioned specs are meaningful: a reader needs to be able to say
which spec version they built from. Changelog sections:

```json
{ "type": "feat",  "section": "Spec changes" },
{ "type": "fix",   "section": "Corrections" },
{ "type": "probe", "section": "New evidence" },
{ "type": "docs",  "section": "Documentation" },
{ "type": "chore", "hidden": true }
```

`probe:` is changelog-only (no version bump) and gives new hardware evidence a
permanent public record.

**CI compiles `reference/` and `probes/` on `macos-latest`; it never executes
them.** A runner has no USB DAC, so probe output there would be meaningless.
Compilation is the standing proof the specs still produce working code against
current SDKs. No swiftformat/swiftlint — ~150 lines does not justify it.

**Explicitly rejected: a CI job that points an agent at the specs to verify they
build.** Non-deterministic, costly per run, and it would hard-code one agent
into a repo whose premise is agent-agnosticism.

**Skipped:** `CODE_OF_CONDUCT.md` (ceremony at this size) and `SECURITY.md`
(no security surface).

**Not files:** repo description and topics — `macos`, `coreaudio`, `dac`,
`audio`, `spec-driven-development`, `agents`.

## 7. Decision log

Standard ADR with two added fields:

```markdown
# 0003 — JXA cannot reach CoreAudio

- Status: accepted
- Date: 2026-08-30
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in
## What we probed          (exact command, actual output, link to probes/)
## Decision
## Consequences
```

**"What we believed going in"** is the field standard ADRs lack; recording the
wrong prior is what makes the log teach judgment rather than report conclusions.

**"Decided by"** takes one of `human`, `agent-proposed → human-accepted`, or
`human-overrode-agent`. The mix is the honest texture of agentic work.

| # | Decision | Believed going in | What settled it |
|---|---|---|---|
| 0001 | Detect via ScriptingBridge, not log scraping | The AppleScript property must be insufficient for streamed tracks | Probe: `URL track` reported `sample rate: 96000`. Belief was wrong |
| 0002 | Match rate only; pin bit depth at max | Both depth and rate must match | Argument, not probe: CoreAudio mixes to 32-bit float, so 16-into-24 is bit-transparent |
| 0003 | JXA is dead; use Swift | BridgeSupport exists, so pure-JXA should work | Probe: struct constructor `undefined`; call returned `0x6E6F7065`, size 0 |
| 0004 | The problem is real | macOS 26 might already fix this | Probe: forced 192 kHz under 44.1 kHz playback, held 8 s, no correction |
| 0005 | Scripts + Shortcuts, not an app | This needs a notarized SwiftUI `MenuBarExtra` app with an updater | The write path was one CoreAudio call; the product ran as a one-line pipeline |
| 0006 | Build rather than adopt prior art | Adopting the existing tool is the cheap first move | Architectural: a log-scraping detector versus a public documented API |

**0006 is written on architectural grounds only** — the fragility and CPU cost
that follow from log scraping versus a documented API. Not on code-quality
grounds: it is more useful to a reader as a transferable distinction, and a
public repo that opens by criticising another developer's freely-given work
invites an argument this project has no interest in.

**0002 gets a callout in `docs/decisions/README.md`.** Pinning bit depth was a
YAGNI call about audio quality, and two decisions later it was the only reason
the JXA route was worth evaluating at all — nominal sample rate is a bare
`Float64`, while bit depth would have required an `AudioStreamBasicDescription`
the bridge does not expose. A scope cut opening a door elsewhere can only be
shown with a real trail.

**0001 keeps the wrong inference intact** — reasoning from prior art's existence
that the AppleScript route must fail, demolished by a ten-second probe. It is
the best worked example of probing rather than designing around an assumption.

## 8. The specs

Each phase spec is: **Goal** (one verifiable sentence) → **Prerequisites** →
**Constraints** (as prohibitions) → **Build** → **Acceptance criteria** →
**Verification** (exact commands and expected output) → **Known limitations**.

### Phase 0 — probe your hardware

Runs `probes/`, produces a filled-in hardware profile that phases 1 and 2
consume. A numbered phase rather than a README suggestion, so it cannot be
skipped, and so the reader runs the method's core loop on their own machine
before reading any prose about it.

### Phase 1 — manual switching from the menu bar

A compiled `lockstep` binary plus Shortcuts pinned in the menu bar.

Acceptance criteria:
- `lockstep 96000` sets the default output device to 96 kHz and prints confirmation
- `lockstep 1234` exits non-zero, prints supported rates, leaves the device unchanged
- `lockstep` with no argument prints device name, current rate, and supported rates
- A Shortcut pinned in the menu bar performs a switch in one click

### Phase 2 — automatic switching

`lockstep --watch`, driven by `DistributedNotificationCenter` on
`com.apple.Music.playerInfo` plus a ScriptingBridge query, kept alive by a
launchd agent.

Acceptance criteria:
- Skipping five tracks in rapid succession produces **exactly one** rate change
- With Music paused, no rate change occurs regardless of track state
- With default output set to a device not in the allowlist, no rate change occurs
- When the device already matches the source, no set call is issued
- The launchd agent survives logout and login

These encode the switching rules as tests: 400 ms debounce and coalescing,
play-state gate, device allowlist, no-op guard.

**The source seam, concretely.** Phase 2 defines a `NowPlayingSource` protocol
(one method: current source rate, or nil) with `MusicSource` as its only
conformance, in the same file. Roughly five lines. It is named here so it is
not mistaken for package architecture: at this size the seam is a naming
convention that marks where a second source would attach, nothing more.

**Fallback rule:** if a source rate is unsupported, choose the nearest supported
*integer multiple* (44.1 → 88.2 → 176.4), never crossing families to 48. Does
not trigger on the reference hardware; matters for readers with limited devices.

## 9. `AGENTS.md`

Source of truth for agent instructions. `CLAUDE.md` is a one-line pointer to it;
any agent-specific file in this repo is a thin adapter, never content. That is
what agent-agnosticism means mechanically rather than as a README claim.

Contents: what the repo is; the stack; constraints as prohibitions (no
third-party dependencies; no log scraping or private APIs; no Xcode project,
`swiftc` only; probes compiled in CI but never executed; the rate setter must
verify after setting rather than trusting the status code); layout and the
purpose of each directory; commands; conventional-commit and PR-title rules.

Borrowed from `sightlap`: **the specs are the source of truth; changing an
architectural choice requires adding a decision file in the same PR.** This
makes the repo self-enforcing — the thing it teaches is the thing it requires.

## 10. `docs/method.md`

Six steps, agent-neutral, with this project as the running example at each:

1. Classify how much ceremony the work needs
2. Name the assumption that would waste the most work if wrong
3. Probe it as cheaply as correctness allows, *before* designing around it
4. Record the decision, including what you believed going in
5. Implement against acceptance criteria
6. Verify with commands, not assertions

It closes by naming the two failure modes this project actually hit: designing
around an unprobed assumption (0001), and building the heavier artifact before
checking whether the hard part was hard (0005 — three design sections for a
native app before discovering the write path was a single CoreAudio call). A
method doc that reports only successes launders the evidence the same way an ADR
without priors does.

## 11. Out of scope

- A native menubar app, notarization, and an update mechanism (superseded by 0005)
- Live status display in the menu bar — Shortcuts can trigger but not display.
  Accepted trade: automatic switching means there is nothing to watch, and the
  pinned Shortcuts remain as override
- Sources other than Apple Music; the seam exists, no second source ships
- Bit-depth switching (superseded by 0002)

## 12. Open questions

- **Does Music renegotiate the device rate at a track boundary?** Unknown, not
  blocking. Observable once phase 1 is in use; if it does, phase 2's trigger
  logic may simplify.
- **Does `com.apple.Music.playerInfo` fire reliably on macOS 26?** Assumed, not
  verified — a `log stream` test was the wrong instrument, as distributed
  notifications are not `os_log` events. Phase 2 therefore specifies a 2 s poll while
  playing as a fallback, to be used only if the notification proves
  unreliable during implementation.
- **`reference/lockstep.swift` has a known compiler warning** reading the device
  name `CFString` through a raw pointer. It works, but it must be fixed before
  shipping as reference code.
