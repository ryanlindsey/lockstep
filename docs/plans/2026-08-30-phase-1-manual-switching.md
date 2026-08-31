# lockstep Phase 1 — Implementation Plan (1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a complete, publishable guide to manual sample-rate switching — a stranger can clone the repo, probe their own hardware, and get a working menubar switcher.

**Architecture:** A documentation-first repo. Three self-contained Swift files (two probes, one reference implementation) talk to CoreAudio directly with no package structure, no Xcode project, and no dependencies. Everything else is prose: specs a reader's agent executes, decision records that show how each choice was settled, and a method doc describing the loop. Shortcuts pinned to the macOS menu bar supply the UI, so no app is built.

**Tech Stack:** Swift 6 via `swiftc` (no SPM, no Xcode project), CoreAudio, GitHub Actions, release-please, macOS Shortcuts.

**Spec:** `docs/design/2026-08-30-repo-design.md`

**Plan location note:** The writing-plans default is `docs/superpowers/plans/`. This repo uses `docs/plans/` to match the `docs/design/` convention chosen for the spec — a public repo shouldn't leak tooling names into its structure.

## Global Constraints

- **No third-party dependencies.** Foundation and CoreAudio only.
- **No Xcode project, no SPM manifest.** `swiftc` compiles single files.
- **No log scraping, no private APIs, no MediaRemote.** Public documented API only.
- **Every Swift file must compile clean under `swiftc -warnings-as-errors`, with zero output.** A *full compile*, not `-typecheck`. Verified: the `CFString` raw-pointer warning this rule exists to catch is emitted during lowering, so `-typecheck` exits 0 on code that carries it. Compiling is still not executing, so the never-execute rule below is unaffected.
- **CI compiles Swift; CI never executes it.** A GitHub runner has no USB DAC, so probe or `lockstep` output there would be meaningless.
- **The rate setter must read the rate back after setting it.** A `noErr` status is not proof the driver applied the change.
- **Probes are self-contained single files.** Deliberate duplication of ~40 lines of CoreAudio helpers across the three Swift files is an accepted, documented trade — a reader can copy one file and run it. Do not factor them into a shared file.
- **Conventional Commits.** The PR title is what release-please reads on squash-merge. `docs:` and `chore:` are changelog-only; `feat:` bumps the minor version. Shipping the phase specs is the `feat:`.
- **The Swift in this plan is authoritative.** Do not copy CoreAudio call shapes from anywhere else. The throwaway code that established them read the device name into a `CFString` variable — an ARC hazard that warns. The `Unmanaged<CFString>` pattern in Task 2 is the fix, and `-warnings-as-errors` in CI is what keeps it fixed.
- **Target:** macOS 12+ (`kAudioObjectPropertyElementMain`). Developed against macOS 26.6.2.

## A note on this plan's shape

The skill's default is to inline every artifact's full content into the plan. That default assumes the deliverable is code and the plan is scaffolding around it. Here the deliverable is largely prose, and inlining every document would make the plan a duplicate of the repo — two copies that drift.

So: **code and configuration appear in full** (Swift, YAML, JSON — these must be exact, and an executor cannot invent them). **Prose documents are specified** by exact path, required sections, the verbatim facts they must contain, and a checkable "done when." Nothing is left as "TBD"; every required fact is stated.

## File structure

| Path | Responsibility |
|---|---|
| `.gitignore` | Ignore `.DS_Store` and compiled binaries |
| `LICENSE` | MIT — already present, covers `probes/` and `reference/` |
| `LICENSE-docs` | CC BY 4.0 — covers `docs/` and `specs/` |
| `release-please-config.json` | Changelog sections including the custom `probe:` type |
| `.release-please-manifest.json` | Version state |
| `version.txt` | Version, maintained by release-please |
| `.github/dependabot.yml` | GitHub Actions version updates only |
| `.github/workflows/build.yml` | Compile all Swift on macos-latest, warnings are errors |
| `.github/workflows/links.yml` | Link rot check |
| `.github/workflows/release-please.yml` | Release automation |
| `.github/ISSUE_TEMPLATE/probe-report.yml` | Structured hardware evidence |
| `.github/ISSUE_TEMPLATE/spec-ambiguity.yml` | The bug class for a spec repo |
| `probes/device-capabilities.swift` | Read-only: device name, current rate, supported rates |
| `probes/does-macos-autoswitch.swift` | Forces a wrong rate, watches, restores |
| `probes/README.md` | How to run them, and why they're duplicated |
| `docs/decisions/0001..0007-*.md` | One decision each, with priors and evidence |
| `docs/decisions/README.md` | The narrated arc |
| `docs/method.md` | The six-step loop, agent-neutral |
| `specs/phase-0-probe-your-hardware.md` | Produces the reader's hardware profile |
| `specs/phase-1-manual-switching.md` | The buildable spec |
| `reference/lockstep.swift` | Phase-1 implementation |
| `reference/test-lockstep.sh` | Acceptance criteria as a runnable script |
| `reference/shortcuts/README.md` | Building and pinning the Shortcuts |
| `reference/README.md` | "You don't need this" |
| `AGENTS.md` | Agent contract, and the exemplar being taught |
| `CLAUDE.md` | One line: `@AGENTS.md` |
| `CONTRIBUTING.md` | The two contributions that make sense |
| `README.md` | Front door |

---

### Task 1: Licensing and release machinery

**Files:**
- Create: `.gitignore`, `LICENSE-docs`, `release-please-config.json`, `.release-please-manifest.json`, `version.txt`, `.github/dependabot.yml`, `.github/workflows/release-please.yml`

**Interfaces:**
- Consumes: nothing
- Produces: the `probe:` commit type, usable by every later task's commit messages

- [ ] **Step 1: Write `.gitignore`**

```
.DS_Store
.build/
*.o

# Compiled probe and reference binaries
/lockstep
/device-capabilities
/does-macos-autoswitch
```

- [ ] **Step 2: Verify it ignores what it should**

```bash
touch .DS_Store lockstep
git status --porcelain | grep -E '\.DS_Store|^\?\? lockstep' && echo "FAIL: not ignored" || echo "PASS"
rm -f .DS_Store lockstep
```
Expected: `PASS`

- [ ] **Step 3: Add `LICENSE-docs`**

Fetch the full CC BY 4.0 legal text from https://creativecommons.org/licenses/by/4.0/legalcode.txt and save it verbatim as `LICENSE-docs`. Prepend exactly these three lines:

```
Creative Commons Attribution 4.0 International

Applies to docs/ and specs/. Code in probes/ and reference/ is MIT — see LICENSE.

```

- [ ] **Step 4: Write `release-please-config.json`**

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "simple",
      "changelog-sections": [
        { "type": "feat",  "section": "Spec changes" },
        { "type": "fix",   "section": "Corrections" },
        { "type": "probe", "section": "New evidence" },
        { "type": "docs",  "section": "Documentation" },
        { "type": "chore", "hidden": true }
      ]
    }
  }
}
```

- [ ] **Step 5: Write `.release-please-manifest.json` and `version.txt`**

`.release-please-manifest.json`:
```json
{ ".": "0.0.0" }
```

`version.txt`:
```
0.0.0
```

- [ ] **Step 6: Validate the JSON parses**

```bash
python3 -m json.tool release-please-config.json > /dev/null && \
python3 -m json.tool .release-please-manifest.json > /dev/null && echo "PASS"
```
Expected: `PASS`

- [ ] **Step 7: Write `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
```

- [ ] **Step 8: Write `.github/workflows/release-please.yml`**

```yaml
name: release-please

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

- [ ] **Step 9: Commit**

```bash
git add .gitignore LICENSE-docs release-please-config.json \
        .release-please-manifest.json version.txt .github/
git commit -m "chore: add licensing, release-please, and dependabot config"
```

---

### Task 2: The probes

**Files:**
- Create: `probes/device-capabilities.swift`, `probes/does-macos-autoswitch.swift`, `probes/README.md`

**Interfaces:**
- Consumes: nothing
- Produces: `device-capabilities` output format consumed by `specs/phase-0-probe-your-hardware.md` (Task 4) and quoted verbatim in decision 0004 (Task 3). The CoreAudio helper shapes here — `address(_:)`, `defaultOutputDevice()`, `name(of:)`, `currentRate(of:)`, `supportedRates(of:)` — are reused verbatim in `reference/lockstep.swift` (Task 5).

- [ ] **Step 1: Write `probes/device-capabilities.swift`**

```swift
// device-capabilities.swift
//
// Reports the current default output device and every sample rate it supports.
// Read-only: this probe never changes a setting.
//
//   swiftc -O probes/device-capabilities.swift -o /tmp/device-capabilities
//   /tmp/device-capabilities
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import CoreAudio
import Foundation

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

func defaultOutputDevice() -> AudioDeviceID? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
    guard status == noErr, device != 0 else { return nil }
    return device
}

// Read as Unmanaged<CFString>, not CFString. Unmanaged is a trivial type, so
// forming a pointer to it is safe; pointing CoreAudio at a CFString variable
// directly is an ARC hazard and warns.
func name(of device: AudioDeviceID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var unmanaged: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &unmanaged)
    guard status == noErr, let cfName = unmanaged?.takeRetainedValue() else {
        return "(unknown)"
    }
    return cfName as String
}

func currentRate(of device: AudioDeviceID) -> Double? {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var rate = Float64(0)
    var size = UInt32(MemoryLayout<Float64>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate)
    return status == noErr ? rate : nil
}

func supportedRates(of device: AudioDeviceID) -> [Double] {
    var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioValueRange>.size
    guard count > 0 else { return [] }
    var ranges = [AudioValueRange](
        repeating: AudioValueRange(mMinimum: 0, mMaximum: 0), count: count)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ranges) == noErr else {
        return []
    }
    // Most USB DACs report discrete rates (mMinimum == mMaximum). A few report a
    // continuous span; show both ends so the reader can see which they have.
    return ranges
        .flatMap { $0.mMinimum == $0.mMaximum ? [$0.mMinimum] : [$0.mMinimum, $0.mMaximum] }
        .sorted()
}

guard let device = defaultOutputDevice() else {
    FileHandle.standardError.write(Data("no default output device\n".utf8))
    exit(1)
}

let rates = supportedRates(of: device)
print("device:    \(name(of: device))  (id \(device))")
print("current:   \(currentRate(of: device).map { String(format: "%.0f Hz", $0) } ?? "unknown")")
print("supported: \(rates.isEmpty ? "none reported" : rates.map { String(format: "%.0f", $0) }.joined(separator: ", "))")
```

- [ ] **Step 2: Verify it compiles with zero warnings**

```bash
swiftc -warnings-as-errors -o /tmp/device-capabilities probes/device-capabilities.swift && echo "PASS"
```
Expected: `PASS` with no other output. If the `CFString` warning appears, the `Unmanaged` pattern in `name(of:)` was not followed.

- [ ] **Step 3: Run it and confirm real output**

```bash
swiftc -O probes/device-capabilities.swift -o /tmp/device-capabilities && /tmp/device-capabilities
```
Expected: three lines — `device:`, `current:`, `supported:` — naming your real output device with a non-empty rate list. On the development machine this reports `CA DacMagic 200M 2.0` and rates `44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000`.

- [ ] **Step 4: Write `probes/does-macos-autoswitch.swift`**

```swift
// does-macos-autoswitch.swift
//
// Answers one question: does anything in macOS correct the output device's
// sample rate to match what is playing? If something does, lockstep is
// unnecessary and you should stop here.
//
// THIS PROBE CHANGES A SETTING. It forces the default output device to a
// supported rate that deliberately does not match your source, watches for
// 8 seconds, then restores the rate it found. Expect a click or a brief
// dropout. Start playing something first — the result is only meaningful
// during playback.
//
//   swiftc -O probes/does-macos-autoswitch.swift -o /tmp/does-macos-autoswitch
//   /tmp/does-macos-autoswitch
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import CoreAudio
import Foundation

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

func defaultOutputDevice() -> AudioDeviceID? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
    guard status == noErr, device != 0 else { return nil }
    return device
}

func currentRate(of device: AudioDeviceID) -> Double? {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var rate = Float64(0)
    var size = UInt32(MemoryLayout<Float64>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate)
    return status == noErr ? rate : nil
}

func supportedRates(of device: AudioDeviceID) -> [Double] {
    var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioValueRange>.size
    guard count > 0 else { return [] }
    var ranges = [AudioValueRange](
        repeating: AudioValueRange(mMinimum: 0, mMaximum: 0), count: count)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ranges) == noErr else {
        return []
    }
    return ranges
        .flatMap { $0.mMinimum == $0.mMaximum ? [$0.mMinimum] : [$0.mMinimum, $0.mMaximum] }
        .sorted()
}

@discardableResult
func forceRate(_ target: Double, on device: AudioDeviceID) -> Bool {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var value = Float64(target)
    let status = AudioObjectSetPropertyData(
        device, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    return status == noErr
}

guard let device = defaultOutputDevice(), let original = currentRate(of: device) else {
    FileHandle.standardError.write(Data("no default output device\n".utf8))
    exit(1)
}

// Pick a supported rate that is deliberately wrong: the highest available,
// unless we are already there, in which case the lowest.
let rates = supportedRates(of: device)
guard rates.count > 1, let highest = rates.last, let lowest = rates.first else {
    FileHandle.standardError.write(
        Data("device reports fewer than two rates; nothing to test\n".utf8))
    exit(1)
}
let wrong = (original == highest) ? lowest : highest

print("original rate: \(Int(original)) Hz")
print("forcing:       \(Int(wrong)) Hz  (deliberately wrong)")
guard forceRate(wrong, on: device) else {
    FileHandle.standardError.write(Data("could not set the rate; aborting\n".utf8))
    exit(1)
}

print("watching for 8 seconds…")
var corrected = false
for tick in 1...16 {
    usleep(500_000)
    let now = currentRate(of: device) ?? 0
    print(String(format: "  t+%.1fs: %.0f Hz", Double(tick) * 0.5, now))
    if now != wrong { corrected = true; break }
}

forceRate(original, on: device)
print("restored to \(Int(original)) Hz")
print("")
print(corrected
    ? "RESULT: something corrected the rate — lockstep may be unnecessary on this system."
    : "RESULT: nothing corrected the rate — macOS does not follow the source. lockstep has a job.")
```

- [ ] **Step 5: Verify it compiles with zero warnings**

```bash
swiftc -warnings-as-errors -o /tmp/does-macos-autoswitch probes/does-macos-autoswitch.swift && echo "PASS"
```
Expected: `PASS` with no other output.

- [ ] **Step 6: Run it with music playing**

```bash
swiftc -O probes/does-macos-autoswitch.swift -o /tmp/does-macos-autoswitch && /tmp/does-macos-autoswitch
```
Expected: the forced rate holds across all 16 ticks, then `RESULT: nothing corrected the rate…`, and the device is restored to its original rate. Confirm afterwards with `/tmp/device-capabilities` that `current:` matches the original.

- [ ] **Step 7: Write `probes/README.md`**

Required sections and content:
- **What these are for** — one paragraph: probes settle assumptions before you design around them; run them on *your* hardware because the answers differ from the author's.
- **`device-capabilities.swift`** — read-only, safe to run any time. Build and run commands as in Step 3. State that its output is what `specs/phase-0-probe-your-hardware.md` asks you to record.
- **`does-macos-autoswitch.swift`** — **must carry a clear warning that it changes a system setting and will cause an audible click**, that music should be playing for the result to mean anything, and that it restores the original rate when it finishes.
- **Why these files duplicate each other** — a short, explicit note: each probe is self-contained so a reader can copy one file and run it; the ~40 duplicated lines of CoreAudio helpers are an accepted trade, not an oversight, and must not be factored into a shared file.
- **Reporting your results** — link to the `probe-report` issue template (Task 8 creates it at `.github/ISSUE_TEMPLATE/probe-report.yml`; link to `https://github.com/ryanlindsey/lockstep/issues/new?template=probe-report.yml`).

Done when: a reader who has never seen the repo can run both probes correctly from this file alone, and knows before running the second one that it will make a noise.

- [ ] **Step 8: Commit**

```bash
git add probes/
git commit -m "probe: add device-capabilities and does-macos-autoswitch"
```

---

### Task 3: The decision log

**Files:**
- Create: `docs/decisions/README.md`, `docs/decisions/0001-detect-via-scriptingbridge.md`, `docs/decisions/0002-match-rate-only.md`, `docs/decisions/0003-jxa-cannot-reach-coreaudio.md`, `docs/decisions/0004-macos-does-not-autoswitch.md`, `docs/decisions/0005-scripts-not-an-app.md`, `docs/decisions/0006-build-rather-than-adopt.md`, `docs/decisions/0007-ci-compiles-not-typechecks.md`

**Interfaces:**
- Consumes: probe output formats from Task 2 (0004 quotes `does-macos-autoswitch` output)
- Produces: decision filenames linked from `docs/method.md` (Task 7) and `README.md` (Task 9). Use exactly the filenames above; later tasks link to them.

- [ ] **Step 1: Write every ADR to this exact template**

```markdown
# NNNN — <title>

- Status: accepted
- Date: 2026-08-30
- Decided by: <human | agent-proposed → human-accepted | human-overrode-agent>
- Superseded by: —

## What we believed going in

## What we probed

## Decision

## Consequences
```

`What we probed` must contain the actual command and its actual output, in a fenced block. Where a decision was settled by argument rather than evidence, retitle that section `## What settled it` and say plainly that no probe was run.

- [ ] **Step 2: Write the six records with this content**

**0001 — Detect via ScriptingBridge, not log scraping.** *Decided by: agent-proposed → human-accepted.*
- Believed going in: the existing prior-art tool scrapes `log stream`, therefore Music's AppleScript `sample rate` property must be insufficient for *streamed* catalog tracks. State this belief plainly and attribute it — it was confidently held and it was wrong.
- Probed: `osascript` against Music while a Hi-Res Lossless track played. Output to quote verbatim: `class: URL track` and `sample rate: 96000`. The `URL track` class is the point — that is a streamed catalog track, not a local file.
- Decision: read `sample rate` from `current track` via ScriptingBridge. Public, documented API.
- Consequences: eliminates log-format churn across OS releases, `<private>` redaction, and a long-lived parsing subprocess. Costs one Automation permission prompt at first run. **This is the repo's best worked example of probing an assumption instead of designing around it** — say so, and link to `../method.md`.

**0002 — Match sample rate only; pin bit depth at maximum.** *Decided by: agent-proposed → human-accepted.*
- Believed going in: both bit depth and sample rate must match the source.
- What settled it: argument, not probe. CoreAudio mixes everything to 32-bit float internally; a 16-bit source rendered through a 24-bit device format is bit-transparent. Only a sample-rate mismatch causes a real resample.
- Decision: vary sample rate per track; set bit depth to the device maximum once and never touch it.
- Consequences: halves the detection problem and removes a class of failure. **Note the downstream payoff:** two decisions later this was the only reason the JXA route was worth evaluating at all — nominal sample rate is a bare `Float64`, whereas bit depth would have required an `AudioStreamBasicDescription`, which `CoreAudio.bridgesupport` does not expose. A scope cut opened a door somewhere unrelated.

**0003 — JXA cannot reach CoreAudio; use Swift.** *Decided by: agent-proposed → human-accepted.*
- Believed going in: `CoreAudio.bridgesupport` exists, so a pure-JXA solution needing no compiler should work.
- Probed: two steps. First, a discovery script showed `AudioObjectGetPropertyData`, `AudioObjectSetPropertyData` and `AudioObjectHasProperty` all exposed as functions, but `$.AudioObjectPropertyAddress` was `undefined`. Second, calling with a struct literal returned status `1852797029` (`0x6E6F7065`) with `size=0`. Quote both.
- Decision: Swift via `/usr/bin/swift` and `swiftc`.
- Consequences: not "pure built-in," but Apple's own toolchain and no third-party code. **Record the second reason for rejection:** the surviving JXA workaround would have been hand-packing 12 struct bytes into an `NSMutableData` and passing raw pointers — and even had it worked, it would have produced exactly the fragile, unreadable code this project exists to avoid. Winning that way would have lost.

**0004 — macOS does not auto-switch; the problem is real.** *Decided by: agent-proposed → human-accepted.*
- Believed going in: possibly macOS 26 already does this. Two consecutive observations had shown the DAC's rate matching the source with no intervention, which looked like evidence of automatic correction.
- Probed: forced the device to 192 kHz while a 44.1 kHz track played, polled every 500 ms for 8 seconds. Quote the run: the rate held at 192000 for all sixteen ticks. The earlier "matches" were manual work by the author, not automation.
- Decision: proceed — the problem exists on macOS 26.6.2.
- Consequences: **this is the probe that could have ended the project**, and it cost under a minute. Say that explicitly; checking whether the problem still exists before building anything is the cheapest step available. It is now shipped as `probes/does-macos-autoswitch.swift` so every reader can run it against their own system first.

**0005 — Scripts and Shortcuts, not an app.** *Decided by: agent-proposed → human-accepted.*
- Believed going in: this needs a native SwiftUI `MenuBarExtra` app with an opt-in device list, Developer ID signing, notarization, and an update mechanism. Three full design sections were written on that assumption.
- What settled it: the write path turned out to be a single `AudioObjectSetPropertyData` call; Shortcuts pin to the macOS menu bar natively, supplying the UI for free; and the entire product ran end-to-end as a one-line shell pipeline before any app existed.
- Decision: two phases of scripts plus pinned Shortcuts. No app.
- Consequences: gives up live status display in the menu bar — Shortcuts can trigger but not display. Accepted, because automatic switching means there is nothing to watch. Gains: no notarization, no updater, no app lifecycle, roughly 150 lines total. **This is the second failure mode the method doc names:** building the heavier artifact before checking whether the hard part was actually hard.

**0006 — Build rather than adopt prior art.** *Decided by: human-overrode-agent.*
- Believed going in: the agent recommended installing the existing prior-art tool first and living with it for a week — a thirty-minute test that could have replaced the whole project.
- What settled it: the author declined. **Write this entry on architectural grounds only:** a detector built on log scraping versus one built on a public documented API, and the fragility, redaction exposure, and continuous CPU cost that follow from the former.
- Explicitly do **not** write it on code-quality grounds, and do not name shortcomings of the other project. It is more useful to a reader as a transferable distinction, and a public repo that opens by criticising another developer's freely-given work invites an argument this project has no interest in having.
- Consequences: be honest that hardware-level problems — DAC relock clicks, devices misreporting supported rates, dropouts on format change — are inherent to changing sample rates on real USB hardware and are inherited by *any* implementation, including this one. Adopting a different detector does not avoid them.

**0007 — CI compiles rather than typechecks.** *Decided by: agent-proposed → human-accepted.*
- Believed going in: `swiftc -typecheck -warnings-as-errors` would catch the `CFString` raw-pointer warning. This was written into the approved plan as an explicit guarantee, and it survived a self-review pass before being merged.
- Probed, during execution rather than design: the same naive `CFString` read was compiled both ways. Under `-typecheck` it emitted no warning and exited 0. Under a full compile it emitted `warning: forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'` and, with `-warnings-as-errors`, exited non-zero. Quote both results.
- Decision: `build.yml` performs a full compile into a temporary directory. Never `-typecheck`. Compiling is still not executing, so the never-execute rule is unaffected.
- Consequences: CI is slightly slower, and in exchange the guarantee is real. **State the trap plainly:** reverting to `-typecheck` looks like a harmless speed-up, keeps the build green, and silently removes the only protection against the regression it was written to prevent.
- Worth noting in the narrated README: this is the only record whose wrong prior came from an approved, merged plan rather than from early design. The loop caught the plan, not just the idea.

- [ ] **Step 3: Write `docs/decisions/README.md`**

Required content:
- A one-paragraph explanation of the two non-standard ADR fields and why they exist: `What we believed going in` (standard ADRs record the conclusion and launder away the author's wrong prior, which is the part that teaches judgment) and `Decided by` (the human/agent mix is the honest texture of this kind of work).
- **The narrated arc**, in order, as prose rather than a list: the project began as a native menubar app; a probe disproved the agent's confident assumption about detection (0001); a YAGNI call on bit depth (0002) later turned out to be the only thing that made another route evaluable (0003); a premise check nearly ended the project (0004); and the app collapsed into roughly a hundred lines of script (0005).
- A table of all seven with links.
- Done when: a reader who reads only this file understands both what was decided and where the reasoning went wrong, and can find any individual record.

- [ ] **Step 4: Check every link resolves**

```bash
for f in docs/decisions/*.md; do
  grep -oE '\]\([^)]+\.md\)' "$f" | tr -d '](' | tr -d ')' | while read -r link; do
    target="$(dirname "$f")/$link"
    [ -f "$target" ] || echo "BROKEN: $f -> $link"
  done
done; echo "link check done"
```
Expected: `link check done` with no `BROKEN` lines.

- [ ] **Step 5: Commit**

```bash
git add docs/decisions/
git commit -m "docs: add decision log with the dead ends intact"
```

---

### Task 4: Phase 0 and Phase 1 specs

**Files:**
- Create: `specs/phase-0-probe-your-hardware.md`, `specs/phase-1-manual-switching.md`

**Interfaces:**
- Consumes: probe binaries and output format from Task 2
- Produces: the acceptance criteria that `reference/lockstep.swift` (Task 5) must satisfy, and that `reference/test-lockstep.sh` asserts. The CLI contract defined here — `lockstep` with no arguments, `lockstep <rate>`, `lockstep --help`, exit codes — is binding on Task 5.

- [ ] **Step 1: Write `specs/phase-0-probe-your-hardware.md`**

Structure, in this order: **Goal** → **Why this is a numbered phase** → **Steps** → **Record your profile** → **Acceptance criteria** → **What this changes downstream**.

Required content:
- Goal, one verifiable sentence: you have a written hardware profile listing your default output device and every sample rate it supports.
- Why numbered: your DAC is not the author's. A device supporting only 44.1 and 48 kHz needs a different fallback rule than one supporting ten rates. A reader who skips this builds against the wrong constraints. It also puts the reader through the method's core loop on their own machine before they read any prose about it.
- Steps: build and run `probes/device-capabilities.swift`, then build and run `probes/does-macos-autoswitch.swift` with music playing. Give the exact `swiftc` and run commands from Task 2, Steps 3 and 6.
- A fill-in profile block the reader keeps:

```markdown
## My hardware profile
- macOS version:
- Default output device:
- Current rate when probed:
- Supported rates:
- Does anything auto-correct the rate? (yes / no)
```

- Acceptance criteria: the profile is filled in with real values; the auto-correct answer is `no` (**if it is `yes`, stop — lockstep has no job on that system**).
- What this changes downstream: if your device reports fewer than four rates, the same-family fallback rule in phase 2 will matter to you; if it reports the 44.1 and 48 families in full, it will not.

- [ ] **Step 2: Write `specs/phase-1-manual-switching.md`**

Structure: **Goal** → **Prerequisites** → **Constraints** → **Build** → **Acceptance criteria** → **Verification** → **Known limitations**.

Required content:
- Goal: a single compiled binary plus Shortcuts pinned to the menu bar that set the default output device's sample rate in one click.
- Prerequisites: phase 0 complete, with a filled-in hardware profile. Xcode Command Line Tools (`swiftc`) present.
- Constraints, stated as prohibitions, copied from this plan's Global Constraints: no third-party dependencies; no Xcode project or SPM manifest; `swiftc` only; no log scraping or private APIs; must compile clean under `-warnings-as-errors`; **the rate setter must read the rate back after setting rather than trusting the status code**.
- Build: describe the CLI contract precisely, because it is what the reader's agent implements —
  - `lockstep` (no arguments) prints device name, current rate, and supported rates; exit 0.
  - `lockstep <rate>` sets the default output device to `<rate>` Hz, reads it back, prints confirmation; exit 0 on verified success.
  - `lockstep <unsupported-rate>` prints the supported rates to stderr, changes nothing, exit 1.
  - `lockstep <non-numeric>` prints usage to stderr, exit 1.
  - `lockstep --help` / `-h` prints usage; exit 0.
- Acceptance criteria, verbatim as a checklist:
  - `lockstep 96000` sets the default output device to 96 kHz and prints confirmation
  - `lockstep 1234` exits non-zero, prints the supported rates, and leaves the device unchanged
  - `lockstep` with no argument prints device name, current rate, and supported rates
  - A Shortcut pinned in the menu bar performs a switch in one click
- Verification: point at `reference/test-lockstep.sh` and state that it must be run on a machine with a real output device, never in CI.
- Known limitations: changing the rate mid-stream causes a brief dropout, inherent to CoreAudio reconfiguring IO under a running app and not specific to this implementation; there is no live status display in the menu bar, because Shortcuts can trigger but not display.

- [ ] **Step 3: Confirm the acceptance criteria are mechanical**

Read both specs and check each acceptance criterion is a command with an observable result, not a judgement. Any criterion containing "should feel", "reliably", "properly", or "as expected" is a plan failure — rewrite it as a command and an expected exit code.

- [ ] **Step 4: Commit — this is the version-bumping commit**

```bash
git add specs/
git commit -m "feat: add phase 0 and phase 1 specs"
```
Note: `feat:` here is deliberate and is the only `feat:` in this plan. It is what makes release-please cut the first minor version.

---

### Task 5: The reference implementation

**Files:**
- Create: `reference/lockstep.swift`, `reference/test-lockstep.sh`, `reference/README.md`, `reference/shortcuts/README.md`

**Interfaces:**
- Consumes: the CLI contract and acceptance criteria from `specs/phase-1-manual-switching.md` (Task 4); the CoreAudio helper shapes from Task 2
- Produces: a `lockstep` binary that `.github/workflows/build.yml` (Task 6) compiles and `README.md` (Task 9) links to

- [ ] **Step 1: Write `reference/lockstep.swift`**

```swift
// lockstep.swift
//
// Sets the default output device's sample rate — and verifies it took.
//
//   swiftc -O reference/lockstep.swift -o ~/bin/lockstep
//
//   lockstep            print device, current rate, and supported rates
//   lockstep 96000      set the rate to 96 kHz
//   lockstep --help     usage
//
// This is the reference implementation. You do not need it — it is what the
// specs in ../specs/ produce. See ./README.md.
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import CoreAudio
import Foundation

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

func defaultOutputDevice() -> AudioDeviceID? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
    guard status == noErr, device != 0 else { return nil }
    return device
}

// Read as Unmanaged<CFString>, not CFString. Unmanaged is a trivial type, so
// forming a pointer to it is safe; pointing CoreAudio at a CFString variable
// directly is an ARC hazard and warns.
func name(of device: AudioDeviceID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var unmanaged: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &unmanaged)
    guard status == noErr, let cfName = unmanaged?.takeRetainedValue() else {
        return "(unknown)"
    }
    return cfName as String
}

func currentRate(of device: AudioDeviceID) -> Double? {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var rate = Float64(0)
    var size = UInt32(MemoryLayout<Float64>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate)
    return status == noErr ? rate : nil
}

func supportedRates(of device: AudioDeviceID) -> [Double] {
    var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioValueRange>.size
    guard count > 0 else { return [] }
    var ranges = [AudioValueRange](
        repeating: AudioValueRange(mMinimum: 0, mMaximum: 0), count: count)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ranges) == noErr else {
        return []
    }
    return ranges
        .flatMap { $0.mMinimum == $0.mMaximum ? [$0.mMinimum] : [$0.mMinimum, $0.mMaximum] }
        .sorted()
}

enum SetResult {
    case verified(Double)
    case failed(String)
}

func setRate(_ target: Double, on device: AudioDeviceID) -> SetResult {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var value = Float64(target)
    let status = AudioObjectSetPropertyData(
        device, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    guard status == noErr else {
        return .failed("CoreAudio rejected the change (status \(status))")
    }
    // A noErr status is not proof. CoreAudio can report success for a change the
    // driver has not applied, and a USB DAC needs a moment to relock its clock.
    // Poll for up to a second, then report what the device actually says.
    for _ in 0..<20 {
        usleep(50_000)
        if let now = currentRate(of: device), now == target {
            return .verified(now)
        }
    }
    let observed = currentRate(of: device).map { String(format: "%.0f", $0) } ?? "unknown"
    return .failed("device reports \(observed) Hz after the change")
}

func formatted(_ rates: [Double]) -> String {
    rates.map { String(format: "%.0f", $0) }.joined(separator: ", ")
}

let usage = """
usage: lockstep [<sample-rate> | --help]

  lockstep            print the default output device, its current rate,
                      and every rate it supports
  lockstep 96000      set the default output device to 96000 Hz
  lockstep --help     print this message
"""

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("lockstep: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard let device = defaultOutputDevice() else {
    die("no default output device")
}

if arguments.isEmpty {
    let available = supportedRates(of: device)
    print("device:    \(name(of: device))")
    print("current:   \(currentRate(of: device).map { String(format: "%.0f Hz", $0) } ?? "unknown")")
    print("supported: \(available.isEmpty ? "none reported" : formatted(available))")
    exit(0)
}

if arguments[0] == "--help" || arguments[0] == "-h" {
    print(usage)
    exit(0)
}

guard let target = Double(arguments[0]), target > 0 else {
    die("not a sample rate: \(arguments[0])\n\n\(usage)")
}

let rates = supportedRates(of: device)
guard rates.contains(target) else {
    die("\(name(of: device)) does not support \(Int(target)) Hz\nsupported: \(formatted(rates))")
}

switch setRate(target, on: device) {
case .verified(let rate):
    print("\(name(of: device)) → \(Int(rate)) Hz")
case .failed(let reason):
    die(reason)
}
```

- [ ] **Step 2: Verify it compiles with zero warnings**

```bash
swiftc -warnings-as-errors -o /tmp/lockstep reference/lockstep.swift && echo "PASS"
```
Expected: `PASS` with no other output.

- [ ] **Step 3: Write the failing acceptance test at `reference/test-lockstep.sh`**

```bash
#!/usr/bin/env bash
# Exercises the phase-1 acceptance criteria against a real output device.
#
#   swiftc -O reference/lockstep.swift -o /tmp/lockstep
#   ./reference/test-lockstep.sh /tmp/lockstep
#
# Requires real audio hardware. This cannot run in CI — a GitHub runner has no
# DAC, so every result would be meaningless.

set -uo pipefail

BIN="${1:-/tmp/lockstep}"
fails=0

report() {
  if [ "$1" -eq 0 ]; then
    echo "PASS  $2"
  else
    echo "FAIL  $2"
    fails=$((fails + 1))
  fi
}

if [ ! -x "$BIN" ]; then
  echo "no lockstep binary at $BIN — build it first" >&2
  exit 1
fi

# --- criterion 3: no argument prints device, current rate, supported rates ---
status_output="$("$BIN")"
echo "$status_output" | grep -q '^device:'    ; report $? "no-arg output names the device"
echo "$status_output" | grep -q '^current:'   ; report $? "no-arg output reports the current rate"
echo "$status_output" | grep -q '^supported:' ; report $? "no-arg output lists supported rates"

original="$(echo "$status_output" | awk '/^current:/ {print $2}')"
supported="$(echo "$status_output" | sed -n 's/^supported: *//p')"

# --- criterion 2: an unsupported rate fails cleanly and changes nothing ---
"$BIN" 1234 >/dev/null 2>&1
[ $? -ne 0 ]; report $? "unsupported rate exits non-zero"

after="$("$BIN" | awk '/^current:/ {print $2}')"
[ "$after" = "$original" ]; report $? "unsupported rate left the device unchanged"

# --- criterion 1: a supported rate is set and verified ---
target="$(echo "$supported" | tr ',' '\n' | tr -d ' ' | grep -v "^${original}\$" | head -1)"
if [ -z "$target" ]; then
  echo "SKIP  device reports only one rate; nothing to switch to"
else
  "$BIN" "$target" >/dev/null 2>&1
  [ $? -eq 0 ]; report $? "setting a supported rate exits zero"

  now="$("$BIN" | awk '/^current:/ {print $2}')"
  [ "$now" = "$target" ]; report $? "device actually reports the new rate ($target Hz)"

  "$BIN" "$original" >/dev/null 2>&1
  restored="$("$BIN" | awk '/^current:/ {print $2}')"
  [ "$restored" = "$original" ]; report $? "restored the original rate ($original Hz)"
fi

# --- non-numeric argument ---
"$BIN" banana >/dev/null 2>&1
[ $? -ne 0 ]; report $? "non-numeric argument exits non-zero"

echo
if [ "$fails" -eq 0 ]; then
  echo "all acceptance criteria pass"
else
  echo "$fails failing"
  exit 1
fi
```

- [ ] **Step 4: Run it and watch it fail before the binary exists**

```bash
rm -f /tmp/lockstep
chmod +x reference/test-lockstep.sh
./reference/test-lockstep.sh /tmp/lockstep
```
Expected: `no lockstep binary at /tmp/lockstep — build it first`, exit 1.

- [ ] **Step 5: Build and run it for real**

```bash
swiftc -O reference/lockstep.swift -o /tmp/lockstep
./reference/test-lockstep.sh /tmp/lockstep
```
Expected: every line `PASS`, ending `all acceptance criteria pass`. You will hear a click as the device changes rate twice.

- [ ] **Step 6: Write `reference/README.md`**

Required content, in this order:
- **"You do not need this."** Open with it. This directory exists for two reasons only: to prove the specs in `../specs/` produce working code, and to give you something to diff your agent's output against if you get stuck. Building it yourself from the specs is the point of the repo.
- Build and install: `swiftc -O reference/lockstep.swift -o ~/bin/lockstep`.
- The CLI contract, matching `specs/phase-1-manual-switching.md` exactly.
- How to run the acceptance tests, and the explicit warning that they change your device's rate twice and are audible.
- A pointer to `shortcuts/README.md` for the menu bar half.

- [ ] **Step 7: Write `reference/shortcuts/README.md`**

Required content:
- What this achieves: a real macOS menu bar UI with no app, no notarization, and nothing to maintain.
- Step-by-step for **one** Shortcut, precisely enough to follow without screenshots: open Shortcuts → File → New Shortcut → add the **Run Shell Script** action → set the script to `$HOME/bin/lockstep 96000` → rename the Shortcut to `DAC → 96 kHz` → in the shortcut's details pane (the ⓘ inspector) tick **Pin in Menu Bar**.
- Then: repeat per rate you actually use, taking the rates from your phase-0 hardware profile. Suggest 44100, 48000, 96000, 192000 as a starting set, and say plainly that a reader should only create Shortcuts for rates their own device reported.
- A note that the Shortcuts appear under the Shortcuts icon in the menu bar, not as their own icon.
- Known limitation, repeated from the spec: Shortcuts can trigger but not display, so there is no live rate indicator. Phase 2 removes the need to look.

- [ ] **Step 8: Commit**

```bash
git add reference/
git commit -m "docs: add phase-1 reference implementation and acceptance tests"
```

---

### Task 6: CI

**Files:**
- Create: `.github/workflows/build.yml`, `.github/workflows/links.yml`

**Interfaces:**
- Consumes: all `.swift` files from Tasks 2 and 5; all `.md` files written so far
- Produces: the green-check contract every later task must keep

- [ ] **Step 1: Write `.github/workflows/build.yml`**

```yaml
name: build

on:
  push:
    branches: [main]
  pull_request:

jobs:
  compile:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      # Compile only. Never execute: a GitHub runner has no USB DAC, so any
      # probe or lockstep output here would be meaningless.
      # A full compile, not -typecheck. The CFString raw-pointer warning this
      # job exists to catch is emitted during lowering, so -typecheck misses it.
      - name: Compile every Swift file, warnings are errors
        run: |
          set -e
          out="$(mktemp -d)"
          for file in probes/*.swift reference/*.swift; do
            echo "==> $file"
            swiftc -warnings-as-errors -o "$out/$(basename "$file" .swift)" "$file"
          done

      - name: Shell scripts parse
        run: bash -n reference/test-lockstep.sh
```

- [ ] **Step 2: Reproduce the CI check locally before pushing**

```bash
set -e; out="$(mktemp -d)"
for file in probes/*.swift reference/*.swift; do
  echo "==> $file"; swiftc -warnings-as-errors -o "$out/$(basename "$file" .swift)" "$file"; done
bash -n reference/test-lockstep.sh && echo "PASS"
```
Expected: each filename echoed, no warnings, `PASS`.

- [ ] **Step 3: Write `.github/workflows/links.yml`**

```yaml
name: links

on:
  push:
    branches: [main]
  pull_request:
  schedule:
    - cron: "0 9 * * 1"

jobs:
  lychee:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: lycheeverse/lychee-action@v2
        with:
          args: --no-progress --verbose --accept 200,206,429 './**/*.md'
          fail: true
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/
git commit -m "ci: compile swift on macos and check links"
```

---

### Task 7: The method doc

**Files:**
- Create: `docs/method.md`

**Interfaces:**
- Consumes: decision filenames from Task 3 — link to `decisions/0001-detect-via-scriptingbridge.md` and `decisions/0005-scripts-not-an-app.md` by those exact names
- Produces: the loop `README.md` (Task 9) summarises in three lines

- [ ] **Step 1: Write the six-step loop**

Each step gets a short prose paragraph and a worked example drawn from this project. Steps, in order and with these names:

1. **Classify how much ceremony the work needs.** Example: this project changed classification twice — a feasibility question became an architectural design, then collapsed back to a spike when "can built-in tools do this?" was asked.
2. **Name the assumption that would waste the most work if wrong.** Example: everything depended on whether the source sample rate could be read at all.
3. **Probe it as cheaply as correctness allows, before designing around it.** Example: one `osascript` line settled it in ten seconds.
4. **Record the decision, including what you believed going in.**
5. **Implement against acceptance criteria**, not against a description.
6. **Verify with commands, not assertions.** Example: `setRate` reads the rate back because a `noErr` status is not evidence.

- [ ] **Step 2: Write the closing section, "Where this went wrong"**

This section is required, not optional. A method doc that reports only successes launders the evidence the same way an ADR without priors does. Name both failures concretely:

- **Designing around an unprobed assumption.** The agent reasoned from prior art's existence that the AppleScript route must be insufficient, and proposed an architecture with a fallback detector to work around it. A ten-second probe disproved the premise. Link to `decisions/0001-detect-via-scriptingbridge.md`.
- **Building the heavier artifact before checking whether the hard part was hard.** Three design sections were written for a native SwiftUI menubar app — module boundaries, a policy engine, switching rules — before anyone checked that setting the rate was a single CoreAudio call. It was. The app became roughly a hundred lines of script. Link to `decisions/0005-scripts-not-an-app.md`.

- [ ] **Step 3: Add the agent-agnosticism statement**

A short closing paragraph: this loop names no tool and requires none. The repo's machine-readable contract lives in `AGENTS.md`; any agent-specific file in this repo is a thin pointer to it and never content. Readers should adapt the loop to whatever they use rather than adopting a workflow.

- [ ] **Step 4: Verify no tool names leaked in**

```bash
grep -inE 'claude|cursor|copilot|codex|chatgpt|gemini|aider' docs/method.md || echo "PASS: agent-neutral"
```
Expected: `PASS: agent-neutral`. The doc must not name a specific agent anywhere.

- [ ] **Step 5: Commit**

```bash
git add docs/method.md
git commit -m "docs: add the method loop and where it went wrong"
```

---

### Task 8: Agent contract and participation

**Files:**
- Create: `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/probe-report.yml`, `.github/ISSUE_TEMPLATE/spec-ambiguity.yml`

**Interfaces:**
- Consumes: the Global Constraints from this plan, copied verbatim into `AGENTS.md`
- Produces: `probe-report.yml`, linked from `probes/README.md` (Task 2, Step 7)

- [ ] **Step 1: Write `AGENTS.md`**

Required sections, in this order:
- **What this repo is** — two products in priority order: a worked example of spec-driven development in the open, and an executable guide. Explicitly not a distributable utility.
- **Stack** — Swift 6 via `swiftc`, CoreAudio, no SPM manifest, no Xcode project, no third-party dependencies.
- **Constraints, as prohibitions** — copy the Global Constraints section of this plan verbatim. These are the lines an agent actually needs.
- **Layout** — one line per directory saying what belongs there and what does not. State that `probes/` files are deliberately self-contained and their duplication must not be refactored away.
- **Commands** — the compile loop from Task 6 Step 2, the build commands, and `reference/test-lockstep.sh`.
- **A guardrail worth stating**, because it is tempting and was explicitly rejected in the design: do not add a CI job that points an agent at the specs to check they build. It is non-deterministic, costs real money per run, and would hard-code one agent into a repo whose premise is agent-agnosticism. The compile job gives most of the confidence with none of the contradiction.
- **Conventions** — Conventional Commits; the PR title is what release-please reads on squash-merge; `feat`/`fix`/`perf` bump the version, `docs`/`chore`/`probe` do not.
- **The borrowed rule, stated prominently:** *the specs are the source of truth; changing an architectural choice requires adding a decision file in the same PR.* Note in one line that this makes the repo self-enforcing — the thing it teaches is the thing it requires.

- [ ] **Step 2: Write `CLAUDE.md`**

Exactly one line, no heading, no other content:

```
@AGENTS.md
```

- [ ] **Step 3: Verify CLAUDE.md carries no content of its own**

```bash
[ "$(wc -l < CLAUDE.md)" -le 1 ] && grep -q '^@AGENTS.md$' CLAUDE.md && echo "PASS"
```
Expected: `PASS`. If this file ever grows content, agent-agnosticism has been broken — the content belongs in `AGENTS.md`.

- [ ] **Step 4: Write `CONTRIBUTING.md`**

Required content:
- The two contributions that make sense here, and why the list is short: this is a worked example, not a product. **Probe reports** — your hardware is not the author's, and a compatibility record built from evidence is genuinely useful. **Spec ambiguities** — if two readers' agents build different things from one paragraph, that paragraph is broken.
- Link both issue templates.
- The Conventional Commits rule, with the specific warning that **a PR title without a recognised `type:` prefix is silently skipped by release-please** — no version bump, no changelog entry.
- The available types and what each does: `feat` (spec changes, minor bump), `fix` (corrections, patch), `probe` (new evidence, changelog only), `docs`, `chore` (hidden).
- The rule from `AGENTS.md`: an architectural change needs a decision file in the same PR.

- [ ] **Step 5: Write `.github/ISSUE_TEMPLATE/probe-report.yml`**

```yaml
name: Probe report
description: Report what the probes found on your hardware
title: "probe: <device> on macOS <version>"
labels: ["probe-report"]
body:
  - type: markdown
    attributes:
      value: |
        Run both probes in `probes/` first. This builds a compatibility record
        from evidence rather than anecdote — thank you.
  - type: input
    id: device
    attributes:
      label: Output device
      description: Exactly as device-capabilities reports it
      placeholder: CA DacMagic 200M 2.0
    validations:
      required: true
  - type: input
    id: macos
    attributes:
      label: macOS version
      placeholder: "26.6.2"
    validations:
      required: true
  - type: textarea
    id: capabilities
    attributes:
      label: device-capabilities output
      description: Paste all three lines
      render: text
    validations:
      required: true
  - type: dropdown
    id: autoswitch
    attributes:
      label: Did anything correct the rate automatically?
      options:
        - "No — the forced rate held for the full 8 seconds"
        - "Yes — something corrected it"
    validations:
      required: true
  - type: textarea
    id: notes
    attributes:
      label: Anything else worth recording
      description: Clicks, dropouts, rates the device claims but will not accept
```

- [ ] **Step 6: Write `.github/ISSUE_TEMPLATE/spec-ambiguity.yml`**

```yaml
name: Spec is ambiguous
description: A passage in a spec can be read two ways
title: "spec: <file> — <what is unclear>"
labels: ["spec-ambiguity"]
body:
  - type: markdown
    attributes:
      value: |
        Ambiguity is the bug class for a spec repo. If your agent built
        something different from what the spec intended, that is a defect
        in the spec — please report it.
  - type: dropdown
    id: which
    attributes:
      label: Which spec
      options:
        - specs/phase-0-probe-your-hardware.md
        - specs/phase-1-manual-switching.md
    validations:
      required: true
  - type: textarea
    id: passage
    attributes:
      label: The passage
      description: Quote it
      render: text
    validations:
      required: true
  - type: textarea
    id: readings
    attributes:
      label: The two readings
      description: What it could mean, and what you think it was meant to mean
    validations:
      required: true
  - type: textarea
    id: built
    attributes:
      label: What your agent actually built
```

- [ ] **Step 7: Validate the templates parse as YAML**

```bash
python3 -c "
import sys, yaml
for f in ['.github/ISSUE_TEMPLATE/probe-report.yml',
          '.github/ISSUE_TEMPLATE/spec-ambiguity.yml',
          '.github/workflows/build.yml',
          '.github/workflows/links.yml',
          '.github/workflows/release-please.yml',
          '.github/dependabot.yml']:
    yaml.safe_load(open(f))
    print('ok', f)
" 2>/dev/null || echo "pyyaml unavailable — verify by pushing and checking the Actions tab"
```
Expected: `ok` per file. If PyYAML is not installed, do not install it; push and confirm GitHub accepts the templates instead.

- [ ] **Step 8: Commit**

```bash
git add AGENTS.md CLAUDE.md CONTRIBUTING.md .github/ISSUE_TEMPLATE/
git commit -m "docs: add agent contract, contributing guide, and issue templates"
```

---

### Task 9: The front door

**Files:**
- Modify: `README.md` (currently a 10-byte stub from repo creation)

**Interfaces:**
- Consumes: every path created in Tasks 1–8. This task runs last because the README links to all of them.
- Produces: nothing downstream

- [ ] **Step 1: Write `README.md`**

Required sections, in this order:

- **One-line description and the problem**, in that order. The problem stated concretely: macOS does not follow an audio source's sample rate, so a 44.1 kHz track through a DAC set to 96 kHz gets resampled, and fixing it means a manual trip through Audio MIDI Setup per album.
- **What this repo is** — the two products in priority order, and the plain statement that it is not a distributable utility.
- **Start here** — a numbered path: read `docs/method.md`, run `specs/phase-0-probe-your-hardware.md` against your own hardware, then build from `specs/phase-1-manual-switching.md` with whatever agent you use.
- **The honest caveat, stated early:** if `does-macos-autoswitch` reports that something already corrects your rate, stop — this repo has no job on your system.
- **What's here** — the file-structure table, one line per directory.
- **The decision log** — link it, and pull out one concrete example to make it worth clicking: the agent's confident wrong inference in 0001, disproved by a ten-second probe.
- **Licensing** — MIT covers `probes/` and `reference/`; CC BY 4.0 covers `docs/` and `specs/`. Link both files.
- **Status** — phase 1 (manual switching) is complete; phase 2 (automatic switching) is not yet written.

- [ ] **Step 2: Verify every internal link resolves**

```bash
grep -oE '\]\(([^)h][^)]*)\)' README.md | sed 's/^](//; s/)$//' | while read -r link; do
  [ -e "${link%%#*}" ] || echo "BROKEN: $link"
done; echo "link check done"
```
Expected: `link check done` with no `BROKEN` lines.

- [ ] **Step 3: Run the full local CI check one more time**

```bash
set -e
out="$(mktemp -d)"
for file in probes/*.swift reference/*.swift; do swiftc -warnings-as-errors -o "$out/$(basename "$file" .swift)" "$file"; done
bash -n reference/test-lockstep.sh
python3 -m json.tool release-please-config.json > /dev/null
echo "ALL PASS"
```
Expected: `ALL PASS`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: write the front door"
```

- [ ] **Step 5: Set the repo description and topics**

```bash
gh repo edit --description "A DAC that follows the music. Spec-driven, built in the open, agent-agnostic."
gh repo edit --add-topic macos --add-topic coreaudio --add-topic dac \
             --add-topic audio --add-topic spec-driven-development --add-topic agents
```
These do more for discoverability than the repo name does, which is why the
name was chosen for memorability rather than search.

- [ ] **Step 6: Open the PR**

```bash
gh pr create --title "feat: add phase 1 — probes, specs, and manual switching" \
             --body "Implements docs/plans/2026-08-30-phase-1-manual-switching.md"
```
The title carries `feat:` because this PR ships the phase specs. On squash-merge that is what release-please reads to cut the first minor version.

---

## Done when

- `./reference/test-lockstep.sh` passes every criterion on real hardware
- Every Swift file compiles clean under `swiftc -warnings-as-errors` with no output
- A reader can go from a fresh clone to a working pinned menu bar Shortcut using only `README.md` → `specs/phase-0` → `specs/phase-1`
- `docs/decisions/` contains all seven records, each with a `What we believed going in` section that is actually filled in
- No file outside `AGENTS.md`'s pointer line names a specific agent
