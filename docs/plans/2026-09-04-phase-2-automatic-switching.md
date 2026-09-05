# lockstep Phase 2 — Implementation Plan (2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `lockstep --watch`, kept alive by a launchd agent, follows Apple Music's sample rate onto an allowlisted output device — so the reader stops choosing the rate.

**Architecture:** One new mode on the existing binary, not a second program. `DistributedNotificationCenter` on `com.apple.Music.playerInfo` wakes a 400 ms debounce; the coalesced evaluation reads Music's play state and track rate through ScriptingBridge, checks the default output device against an allowlist passed on the command line, and sets the rate only when it differs. A LaunchAgent plist holds the allowlist and keeps the process running. Everything phase 1 built — `setRate`, `supports`, `supportedRanges` — is reused unchanged.

**Tech Stack:** Swift 6 via `swiftc` (no SPM, no Xcode project), CoreAudio, ScriptingBridge, launchd, macOS Shortcuts (unchanged, now the manual override).

**Spec:** `docs/design/2026-08-30-repo-design.md` §8 "Phase 2 — automatic switching", §3 (allowlist, source seam), §12 (the open questions this phase must close).

## Global Constraints

- **No third-party dependencies.** System frameworks only — Foundation, CoreAudio, and now ScriptingBridge. **This widens the phase-1 wording** (`AGENTS.md` currently says "Foundation and CoreAudio only") and Task 6 updates it. ScriptingBridge ships with macOS; the prohibition is on third-party code, not on Apple's.
- **No Xcode project, no SPM manifest.** `swiftc` compiles single files.
- **No log scraping, no private APIs, no MediaRemote.** Public documented API only.
- **Every Swift file must compile clean under `swiftc -warnings-as-errors`, with zero output.** A *full compile*, never `-typecheck` — see [0007](../decisions/0007-ci-compiles-not-typechecks.md).
- **CI compiles Swift; CI never executes it.** A runner has no USB DAC and no Apple Music.
- **The rate setter must read the rate back after setting it.** A `noErr` status is not proof the driver applied the change.
- **Probes are self-contained single files.** The duplicated CoreAudio helpers stay duplicated. Do not factor them into a shared module.
- **Do not switch bit depth** — see [0002](../decisions/0002-match-rate-only.md).
- **The specs are the source of truth. Changing an architectural choice requires adding a decision file in the same PR.** This phase makes three such choices and this plan schedules all three records.
- **Conventional Commits, and the PR title is what release-please reads on squash-merge.** The whole phase lands as one PR titled `feat: add phase 2 — automatic switching`.
- **Target:** macOS 12+ (`kAudioObjectPropertyElementMain`). Developed against macOS 26.6.2.

## A note on this plan's shape

Same as phase 1's, and for the same reason: **code and configuration appear in full** (Swift, plist, shell, YAML — an executor cannot invent these and they must be exact). **Prose documents are specified** by path, required sections, the verbatim facts they must contain, and a checkable "done when". Inlining the spec and the decision records would make this plan a second copy of the repo, and the two would drift.

Nothing is left as "TBD". Where an outcome genuinely depends on a probe, both branches are written out and the branch condition is stated as a command.

## What phase 2 inherits unresolved

Design §12 leaves three questions open and defers them here. Task 1 closes the first two before any of the switching logic is designed around them — that ordering is the repo's whole argument, and reversing it would be the failure `docs/method.md` names first.

| Open question | Closed by | If the answer is the unexpected one |
|---|---|---|
| Does `com.apple.Music.playerInfo` fire reliably on macOS 26? | `probes/does-music-notify.swift` | The trigger becomes a 2 s poll while playing. Design §12 pre-authorises this. Record it in 0010. |
| Can a *compiled Swift binary* read Music's rate, or was that only ever true of `osascript`? | `probes/can-swift-read-music-rate.swift` | The source reads via an `osascript` subprocess per event. Record it in 0012. |
| Does an Apple Event from a launchd agent get TCC approval? | Task 5, step 4 | Not pre-answered. It is the most likely source of a fourth decision record, and Task 5 says what to do either way. |

**Do not build both branches.** `docs/method.md` §3 names that specific temptation: "building both branches of a question you could have answered in a minute." Run the probe, take one path, record why.

## File structure

| Path | Responsibility |
|---|---|
| `probes/does-music-notify.swift` | Create — does `playerInfo` fire, how fast, what does it carry |
| `probes/can-swift-read-music-rate.swift` | Create — which of three routes reaches Music's rate from compiled Swift |
| `probes/README.md` | Modify — a phase-2 section; the phase-0 sections are untouched |
| `docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md` | Create — config is an argument, not a file |
| `docs/decisions/0010-what-tells-the-watcher-a-track-changed.md` | Create — notification vs poll, decided by the probe |
| `docs/decisions/0011-fallback-works-in-both-directions.md` | Create — extending design §8's integer-multiple rule downward |
| `docs/decisions/0012-reading-music-from-a-compiled-binary.md` | Create **only if** route A fails in Task 1 |
| `docs/decisions/README.md` | Modify — count, arc, table |
| `specs/phase-2-automatic-switching.md` | Create — the buildable spec |
| `reference/lockstep.swift` | Modify — `--watch`, the source seam, allowlist, debounce, gate, fallback |
| `reference/test-lockstep-watch.sh` | Create — phase-2 acceptance criteria as a runnable script |
| `reference/launchd/me.ryanlindsey.lockstep.plist` | Create — the agent template |
| `reference/launchd/README.md` | Create — install, load, verify, uninstall |
| `reference/README.md` | Modify — `--watch` in the invocation table, pointer to `launchd/` |
| `reference/shortcuts/README.md` | Modify — the Shortcuts are now the override, not the mechanism |
| `README.md` | Modify — status table, and what phase 2 is |
| `AGENTS.md` | Modify — ScriptingBridge, launchd, the new commands |
| `.github/workflows/build.yml` | Modify — `bash -n` the second test script |

---

### Task 1: The phase-2 probes

Two questions, two files, run on real hardware before a line of switching logic is designed.

**Files:**
- Create: `probes/does-music-notify.swift`
- Create: `probes/can-swift-read-music-rate.swift`
- Modify: `probes/README.md`

**Interfaces:**
- Consumes: nothing. These are self-contained by rule.
- Produces: two facts consumed by Task 2 (the decision records) and Task 4 (the implementation) — whether `com.apple.Music.playerInfo` is delivered, and which of routes A/B/C reads Music's sample rate from a compiled binary. **Route A's KVC calls are copied verbatim into `reference/lockstep.swift` in Task 4**, so the probe is where they get proven.

- [ ] **Step 1: Write `probes/does-music-notify.swift`**

```swift
// does-music-notify.swift
//
// Answers one question: is com.apple.Music.playerInfo delivered on this macOS,
// and does its payload already carry what phase 2 needs?
//
// Design §12 assumed the notification fires and never checked. Phase 2's whole
// trigger mechanism rests on it, so it gets checked before anything is built on
// top of it.
//
// Read-only. It observes; it changes nothing and makes no sound.
//
//   swiftc -O probes/does-music-notify.swift -o /tmp/does-music-notify
//   /tmp/does-music-notify
//
// Start Music playing first, then skip a few tracks, then pause, then play.
// With nothing playing there is nothing to be notified about.
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import Foundation

// Line-buffer stdout so each notification appears as it arrives rather than in
// one block at exit. A probe you cannot watch in real time is much less useful
// when the thing you are checking is timing.
setvbuf(stdout, nil, _IOLBF, 0)

let started = Date()
var count = 0

print("watching com.apple.Music.playerInfo for 60 seconds")
print("skip a few tracks, then pause, then play again")
print("")

DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.apple.Music.playerInfo"),
    object: nil,
    queue: .main
) { note in
    count += 1
    print(String(format: "t+%.2fs  notification %d", Date().timeIntervalSince(started), count))
    let payload = note.userInfo ?? [:]
    if payload.isEmpty {
        print("    (no userInfo)")
    }
    for (key, value) in payload.sorted(by: { "\($0.key)" < "\($1.key)" }) {
        print("    \(key) = \(value)")
    }
    print("")
}

DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    print("")
    guard count > 0 else {
        print("RESULT: nothing fired in 60 seconds.")
        print("Either Music was not running, or com.apple.Music.playerInfo is not")
        print("delivered here. Phase 2 needs the polling trigger instead — see")
        print("docs/decisions/0010-what-tells-the-watcher-a-track-changed.md.")
        exit(1)
    }
    print("RESULT: \(count) notifications in 60 seconds. The notification fires.")
    print("")
    print("Read the keys above, not this sentence: if one of them carries the")
    print("play state, the gate can read it without an Apple Event. If one")
    print("carries a sample rate, the ScriptingBridge query is unnecessary.")
    exit(0)
}

RunLoop.main.run()
```

- [ ] **Step 2: Verify it compiles with zero warnings**

Run:

```bash
swiftc -warnings-as-errors -o /tmp/does-music-notify probes/does-music-notify.swift
```

Expected: exit 0, no output at all. Any output is a failure — see [0007](../decisions/0007-ci-compiles-not-typechecks.md) for why this is a full compile and not `-typecheck`.

- [ ] **Step 3: Run it with Music playing**

Start Apple Music playing, then:

```bash
swiftc -O probes/does-music-notify.swift -o /tmp/does-music-notify
/tmp/does-music-notify
```

Skip five tracks in the first fifteen seconds, pause, wait, play again. **Record the actual output** — it is the evidence in decision 0010, and 0010 requires the real text, not a summary.

Expected on the reference hardware: `RESULT: n notifications in 60 seconds. The notification fires.`

- [ ] **Step 4: Write `probes/can-swift-read-music-rate.swift`**

```swift
// can-swift-read-music-rate.swift
//
// Answers one question: can a compiled Swift binary read Apple Music's play
// state and the current track's sample rate — and by which route?
//
// Decision 0001 proved the property exists and reports true rates for streamed
// tracks. It proved that with osascript. "A single .swift file compiled with
// swiftc can read it" is a different claim, and phase 2 depends on the second
// one, so it is probed rather than assumed.
//
// Three routes, in the order phase 2 would prefer them:
//
//   A  ScriptingBridge + KVC          no header, no protocols, no subprocess
//   B  ScriptingBridge + @objc proto  the single-file stand-in for a generated header
//   C  osascript subprocess           known to work; here as the control
//
// C exists so a failure in A or B is distinguishable from Music being closed or
// Automation being denied. If C fails too, the problem is not the route.
//
// Read-only. It asks Music questions and changes nothing. Expect one Automation
// permission prompt the first time — grant it.
//
//   swiftc -O probes/can-swift-read-music-rate.swift -o /tmp/can-swift-read-music-rate
//   /tmp/can-swift-read-music-rate
//
// Start Music playing something first.
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import Foundation
import ScriptingBridge

// 'kPSP' — MusicEPlSPlaying, from Music's sdef. Player state comes back as a
// four-character code wrapped in an NSNumber.
let musicPlaying: UInt32 = 0x6B50_5350

// --- route A: ScriptingBridge + KVC -----------------------------------------
// SBObject dispatches valueForKey: against the application's sdef, so scripting
// properties can be read by the names it declares — `player state` is
// "playerState", `sample rate` is "sampleRate". No generated header required,
// which matters because a single file compiled with swiftc has nowhere to put
// one.
func routeKVC() -> String {
    guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else {
        return "no SBApplication for com.apple.Music"
    }
    // Never launch Music just to ask it a question.
    guard music.isRunning else { return "Music is not running" }
    guard let state = (music.value(forKey: "playerState") as? NSNumber)?.uint32Value else {
        return "playerState unreadable"
    }
    guard state == musicPlaying else {
        return String(format: "playerState = 0x%08X (not playing)", state)
    }
    guard let track = music.value(forKey: "currentTrack") as? SBObject else {
        return "currentTrack unreadable"
    }
    guard let hz = (track.value(forKey: "sampleRate") as? NSNumber)?.intValue else {
        return "sampleRate unreadable"
    }
    return "playing, sampleRate = \(hz)"
}

// --- route B: ScriptingBridge + an @objc protocol ----------------------------
@objc protocol MusicTrackScripting {
    @objc optional var sampleRate: Int { get }
}

@objc protocol MusicScripting {
    @objc optional var playerState: UInt32 { get }
    @objc optional var currentTrack: MusicTrackScripting { get }
}

extension SBApplication: MusicScripting {}

func routeProtocol() -> String {
    guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else {
        return "no SBApplication for com.apple.Music"
    }
    guard music.isRunning else { return "Music is not running" }
    guard let state = music.playerState else { return "playerState unreadable" }
    guard state == musicPlaying else {
        return String(format: "playerState = 0x%08X (not playing)", state)
    }
    guard let hz = music.currentTrack?.sampleRate ?? nil else { return "sampleRate unreadable" }
    return "playing, sampleRate = \(hz)"
}

// --- route C: osascript, the control ----------------------------------------
func routeOsascript() -> String {
    let script = """
    tell application "Music"
      if it is running then
        (player state as text) & " | " & (sample rate of current track as text)
      else
        "not running"
      end if
    end tell
    """
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
    } catch {
        return "could not run osascript: \(error.localizedDescription)"
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        return "osascript exited \(task.terminationStatus)"
    }
    return String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// --- report ------------------------------------------------------------------
let kvc = routeKVC()
let proto = routeProtocol()
let shell = routeOsascript()

print("route A  ScriptingBridge + KVC          \(kvc)")
print("route B  ScriptingBridge + @objc proto  \(proto)")
print("route C  osascript subprocess           \(shell)")
print("")

let kvcWorks = kvc.hasPrefix("playing, sampleRate =")
let protoWorks = proto.hasPrefix("playing, sampleRate =")
let shellWorks = shell.contains("|")

if !shellWorks {
    print("RESULT: even the control failed. Music is probably not playing, or")
    print("Automation permission was denied. Fix that and run this again —")
    print("nothing can be concluded about routes A and B until C works.")
    exit(1)
}
if kvcWorks {
    print("RESULT: route A works. Phase 2 reads Music in-process, no subprocess")
    print("per event. Copy routeKVC into reference/lockstep.swift.")
    exit(0)
}
if protoWorks {
    print("RESULT: route A failed, route B works. Phase 2 uses the @objc protocol")
    print("declarations. Record why A failed in decision 0012.")
    exit(0)
}
print("RESULT: only route C works. Phase 2 must shell out to osascript once per")
print("evaluation. That is a departure from design §8, which specified")
print("ScriptingBridge — record it in decision 0012 before implementing it.")
exit(0)
```

**If route B fails to compile rather than fails to run, that is itself the probe result.** Comment out `routeProtocol` and its two protocol declarations, note the exact compiler error, and report route B as unavailable. Do not spend time making it compile — its purpose is to answer whether it is available, and "it is not" is a complete answer.

- [ ] **Step 5: Verify it compiles with zero warnings**

Run:

```bash
swiftc -warnings-as-errors -o /tmp/can-swift-read-music-rate probes/can-swift-read-music-rate.swift
```

Expected: exit 0, no output.

- [ ] **Step 6: Run it with Music playing**

```bash
swiftc -O probes/can-swift-read-music-rate.swift -o /tmp/can-swift-read-music-rate
/tmp/can-swift-read-music-rate
```

Grant the Automation prompt if it appears. **Record the exact three route lines and the RESULT line** — they are the evidence in decisions 0010 and, if needed, 0012.

Expected on the reference hardware: `RESULT: route A works.`

- [ ] **Step 7: Add a phase-2 section to `probes/README.md`**

Insert a new `## Phase 2 probes` heading **after** the `does-macos-autoswitch.swift` section and **before** `## Why these two files repeat each other`. Rename that last heading to `## Why these files repeat each other` and change "Both files carry their own copy" to "Each file carries its own copy" — there are four Swift files now, not three.

The new section documents both probes with, for each: the one question it answers, the exact two-line compile-and-run block, the precondition (Music playing), and what each RESULT means. It must state:

- `does-music-notify.swift` is read-only and silent; `can-swift-read-music-rate.swift` is read-only and costs one Automation prompt.
- Both need Music **playing**, not merely open.
- A zero-notification result is not a bug report — it changes which trigger phase 2 builds, and is worth a probe report.

Done when: both new probes appear with runnable commands, the duplication section counts four files, and `grep -c '```' probes/README.md` returns an even number.

- [ ] **Step 8: Commit**

```bash
git add probes/does-music-notify.swift probes/can-swift-read-music-rate.swift probes/README.md
git commit -m "probe: does Music notify, and can compiled Swift read its rate

Closes the two questions design §12 left open for phase 2, before any
switching logic is designed around either answer."
```

---

### Task 2: The decisions the probes settle

Three records, written now because the choices are made now. `probe:` bumps nothing and `docs:` bumps nothing; the `feat:` arrives in Task 3.

**Files:**
- Create: `docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md`
- Create: `docs/decisions/0010-what-tells-the-watcher-a-track-changed.md`
- Create: `docs/decisions/0011-fallback-works-in-both-directions.md`
- Modify: `docs/decisions/README.md`

**Interfaces:**
- Consumes: the recorded output of both probes from Task 1.
- Produces: the settled facts Task 3's spec states as constraints and Task 4 implements — allowlist via `--devices`, the trigger mechanism, and a fallback that divides as well as multiplies.

- [ ] **Step 1: Write all three to the repo's existing ADR template**

Every record uses exactly this shape, which is the one already in `docs/decisions/`:

```markdown
# NNNN — <title>

- Status: accepted
- Date: 2026-09-04
- Decided by: <human | agent-proposed → human-accepted | human-overrode-agent>
- Superseded by: —

## What we believed going in

## What we probed

## Decision

## Consequences
```

`What we believed going in` is not optional and is not a restatement of the decision. A record whose prior turned out correct still records the prior — see `docs/decisions/README.md` on why.

- [ ] **Step 2: Write 0009 — the allowlist lives in the launchd plist**

`Decided by: human`. There is no probe here; this is an argument, like [0002](../decisions/0002-match-rate-only.md), and the record must say so under `What we probed` rather than inventing evidence.

Required content:

- **Believed going in:** a device allowlist is user configuration, and user configuration lives in a config file — `~/.config/lockstep/devices`, one name per line, re-read per evaluation so edits take effect without reloading the agent.
- **What we probed:** nothing. Argument only. The counter-argument is that a config file adds a format to document, a missing-file rule to define, a parser to test, and a second place configuration can live — for a list that changes when the reader buys a DAC. The agent already needs a plist, and the plist already has a `ProgramArguments` array.
- **Decision:** the allowlist is `--devices "Name A,Name B"`, a comma-separated argument, and it lives in the LaunchAgent's `ProgramArguments`. `--watch` with no `--devices`, or with an empty list, exits 1 rather than watching every device. That is what design §3's "opt-in" means mechanically: opt-in that silently defaults to everything is not opt-in.
- **Consequences:** one configuration surface, no file format, no missing-file rule. Editing the allowlist means editing the plist and reloading the agent — `launchctl bootout` then `bootstrap`, two commands, documented in `reference/launchd/README.md`. A device name containing a comma cannot be expressed; no such device is known and the limitation is stated in the spec rather than engineered around. Explicit failure on a missing `--devices` costs one line and removes the "why is it changing my laptop speakers" question entirely.

- [ ] **Step 3: Write 0010 — what tells the watcher a track changed**

`Decided by: agent-proposed → human-accepted`.

Required content:

- **Believed going in:** quote design §12 as written — "**Does `com.apple.Music.playerInfo` fire reliably on macOS 26?** Assumed, not verified — a `log stream` test was the wrong instrument, as distributed notifications are not `os_log` events." Say plainly that the design specified a 2 s polling fallback *in case*, which is the shape `docs/method.md` §3 warns about: designing both branches of a question nobody had asked yet.
- **What we probed:** `probes/does-music-notify.swift`, with the **actual recorded output from Task 1 step 3** — the command, the notification count, the timings, and the userInfo keys. Not a summary.
- **Decision, if the notification fired:** `DistributedNotificationCenter` on `com.apple.Music.playerInfo` is the trigger. **No poll ships.** The fallback described in design §12 is not built, because the question it hedged against has now been answered.
- **Decision, if it did not fire:** a 2 s poll while playing is the trigger, and the notification observer is not built. State the poll interval, and state that the poll runs only while Music reports playing so an idle machine costs nothing.
- **Consequences (either way):** the branch not taken is not in the codebase. Also record what the userInfo actually contained: if it carries `Player State`, note that the gate *could* read it without an Apple Event and that phase 2 deliberately does not — the evaluation needs the track's sample rate regardless, so one ScriptingBridge call answers both questions and having two sources of truth for "is it playing" is worth less than it costs.

- [ ] **Step 4: Write 0011 — the fallback works in both directions**

`Decided by: agent-proposed → human-accepted`. Argument, not probe — it does not fire on the reference hardware, which reports both families in full.

Required content:

- **Believed going in:** design §8 states the rule as "the nearest supported *integer multiple* (44.1 → 88.2 → 176.4), never crossing families to 48". Multiplication only. That was written thinking about a device with *gaps* in a family.
- **What we probed:** nothing on this hardware — the rule cannot fire here. The case that exposed it is the one `specs/phase-0-probe-your-hardware.md` already warns about: a dongle reporting only 44.1 and 48 kHz, playing a 96 kHz Hi-Res track. Upward multiples of 96 are 192, 384, 768 — none supported. The rule as written returns nothing, and the device stays wherever it was, quite possibly at 44.1 for a 96 kHz source.
- **Decision:** try exact, then upward multiples (×2, ×4, ×8), then downward divisors (÷2, ÷4), all within the source's own family. 96 → 48 is a 2:1 decimation and stays in the 48 family. If nothing in the family matches, change nothing and log a skip — a wrong rate is worse than a stale one.
- **Consequences:** upward is tried first because integer upsampling discards nothing while decimation does. Crossing families is still forbidden, which is the part of design §8 that mattered. This record exists because the repo's own rule requires it — the design document said multiply, the implementation also divides, and the difference is architectural rather than cosmetic. Note that this is the first record in the log written against the *design document* rather than against a belief held before it.

- [ ] **Step 5: Update `docs/decisions/README.md`**

Four edits:

1. Opening line: "Eight records" → "Eleven records" (twelve if 0012 is written in Task 4 — leave this edit until Task 4 completes if that is in doubt, but do not forget it).
2. `## The arc`: add a closing paragraph for phase 2. It must say that phase 2 opened by closing the two questions phase 1's design left open, and that both were closed by probe before the switching logic existed — the first time in this repo that the loop ran *ahead* of the mistake instead of catching one. If 0010 recorded the unexpected answer, say that instead and say it plainly.
3. `## The records` table: three (or four) new rows with `Decided by` matching the records.
4. The link-reference block at the bottom: add `[0009]`, `[0010]`, `[0011]` (and `[0012]`).

Done when: `grep -c '^| \[00' docs/decisions/README.md` equals the number of files matching `docs/decisions/[0-9]*.md`.

- [ ] **Step 6: Check every link resolves**

Run:

```bash
docker run --rm -v "$PWD:/w" -w /w lycheeverse/lychee --no-progress --offline './**/*.md'
```

If Docker is unavailable, check by hand:

```bash
grep -oh '](\.\{0,2\}/[^)]*\.md[^)]*)' docs/decisions/*.md specs/*.md \
  | sed 's/^](//; s/)$//; s/#.*//' | sort -u \
  | while read -r p; do [ -e "docs/decisions/$p" ] || [ -e "$p" ] || echo "BROKEN: $p"; done
```

Expected: no `BROKEN` lines. `links.yml` runs lychee on every PR and will catch what this misses.

- [ ] **Step 7: Commit**

```bash
git add docs/decisions/
git commit -m "docs: record the three decisions phase 2 makes

0009 puts the allowlist in the launchd plist, 0010 settles the trigger
from probe evidence, 0011 extends the design's fallback rule downward."
```

---

### Task 3: The phase-2 spec

The deliverable of this repo. Everything else exists to prove it produces working code.

**Files:**
- Create: `specs/phase-2-automatic-switching.md`
- Modify: `specs/phase-1-manual-switching.md` (one line in Known limitations)

**Interfaces:**
- Consumes: decisions 0009, 0010, 0011 from Task 2.
- Produces: the CLI contract and log format Task 4 implements and Task 4's test script parses. **The `--watch` log format defined here is load-bearing** — `reference/test-lockstep-watch.sh` reads it with `awk`, exactly as phase 1's test reads the no-argument output.

- [ ] **Step 1: Write `specs/phase-2-automatic-switching.md`**

Same seven sections as phase 0 and phase 1, in the same order — **Goal → Prerequisites → Constraints → Build → Acceptance criteria → Verification → Known limitations**. Match the existing specs' voice: second person, prohibitions rather than principles, commands rather than descriptions.

Required content, section by section. Decision records are named below as repo-root paths; from `specs/` the link is `../docs/decisions/<file>`, and from `reference/launchd/` it is `../../docs/decisions/<file>`. `links.yml` runs lychee on every markdown file in the repo and will fail the PR on a path that does not resolve.

**Goal.** One verifiable sentence: a launchd agent keeps your output device's rate matched to what Apple Music is playing, without you touching anything, and the phase-1 Shortcuts remain as the override.

**Prerequisites.** Phase 1 complete with a working `lockstep` binary at `~/bin/lockstep`. Apple Music as the source. Both phase-2 probes run, with their answers recorded — and a pointer to the fact that a zero-notification result changes what you build.

**Constraints.** As prohibitions:
- System frameworks only — Foundation, CoreAudio, ScriptingBridge. Note explicitly that this widens phase 1's "Foundation and CoreAudio only" and that ScriptingBridge is Apple's, not a dependency.
- One file. `--watch` is a mode on the phase-1 binary, not a second program.
- No log scraping, no private APIs, no MediaRemote — link `docs/decisions/0001-detect-via-scriptingbridge.md`.
- Must compile clean under `swiftc -warnings-as-errors`, full compile — link `docs/decisions/0007-ci-compiles-not-typechecks.md`.
- The rate setter still reads back after setting. `--watch` reuses phase 1's `setRate` unchanged.
- **Never launch Music to ask it a question.** Check `isRunning` first. An audio utility that opens Music because it was curious is a bug.
- **Do not act on a device you were not told about** — link `docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md`.
- Do not switch bit depth — link `docs/decisions/0002-match-rate-only.md`.

**Build.** Three parts.

*The CLI contract*, extending phase 1's table:

| Invocation | Behaviour | Exit |
|---|---|---|
| `lockstep --watch --devices "A,B"` | Follow Music; set the rate when A or B is the default output | runs until killed |
| `lockstep --watch` | Print that `--devices` is required, to stderr | 1 |
| `lockstep --watch --devices ""` | Same | 1 |

State that the phase-1 invocations are unchanged, and that `--help` gains the `--watch` line.

*The log format*, stated as load-bearing exactly the way phase 1 states its no-argument format:

```
allowlist: CA DacMagic 200M 2.0
watching:  com.apple.Music.playerInfo, 400 ms debounce
2026-09-04T14:03:11Z  event  playerInfo
2026-09-04T14:03:11Z  skip   Music is not playing
2026-09-04T14:03:12Z  set    44100 Hz — verified
2026-09-04T14:03:20Z  noop   already at 44100 Hz
2026-09-04T14:03:31Z  skip   MacBook Pro Speakers is not in the allowlist
2026-09-04T14:03:40Z  set    88200 Hz — verified  (source 44100 Hz unsupported)
```

Two banner lines, then one line per event: an ISO-8601 UTC timestamp, two spaces, one of five verbs — `event`, `skip`, `set`, `noop`, `error` — padded to five characters, two spaces, then the reason. **The verb is the second whitespace-separated field**, which is how the acceptance test reads it. Say so.

*The rules*, each with its reason:
- **400 ms debounce, superseded not queued.** Five skips fire five notifications and produce one evaluation, and that evaluation reads the track playing when it runs.
- **Play-state gate.** Act only when Music reports playing.
- **Device allowlist.** Re-read the default output device on every evaluation; a device not named is skipped by name in the log.
- **No-op guard.** If the device already reports the target, issue no set call. State the reason this is a correctness rule and not an optimisation: setting the rate mid-stream causes an audible dropout, and if Music emits a `playerInfo` in response to that dropout, the no-op guard is the thing that stops the loop.
- **Same-family fallback**, both directions — link `docs/decisions/0011-fallback-works-in-both-directions.md`. Give the worked example: 96 kHz source, 44.1/48-only device, result 48 kHz.
- **The source seam.** A `NowPlayingSource` protocol with `MusicSource` as its only conformance, in the same file, about five lines. Quote design §8's framing so it is not mistaken for package architecture: "at this size the seam is a naming convention that marks where a second source would attach, nothing more." Note the one departure — the method returns play state *and* rate together rather than design's "current source rate, or nil", because the gate needs both and two Apple Events to answer one question is worse than a two-field struct.

*The agent.* A LaunchAgent at `~/Library/LaunchAgents/me.ryanlindsey.lockstep.plist`, label `me.ryanlindsey.lockstep`, holding the binary path, `--watch`, and the allowlist. Point at `reference/launchd/README.md` for the walkthrough and state the two rules that bite: **launchd does not expand `~` or `$HOME`** — every path is absolute — and **the first run triggers an Automation prompt**, which a background agent may not be able to show, so run `lockstep --watch` once in a terminal to grant it before loading the agent.

**Acceptance criteria.** Design §8's five, as checkboxes, each phrased as a command with an expected result:

- [ ] Skipping five tracks in rapid succession produces exactly one evaluation — one `set` or one `noop`, not five
- [ ] With Music paused, no `set` line appears regardless of track state
- [ ] With the default output set to a device not in the allowlist, no `set` line appears and a `skip` names the device
- [ ] When the device already matches the source, the line is `noop` and no set call is issued
- [ ] `lockstep --watch` with no `--devices` exits 1 and changes nothing
- [ ] The launchd agent survives logout and login

State plainly that the last one **cannot be scripted** — it requires an actual logout — and give the manual check: `launchctl print gui/$(id -u)/me.ryanlindsey.lockstep`, comparing the PID before and after.

**Verification.**

```
swiftc -O reference/lockstep.swift -o /tmp/lockstep
./reference/test-lockstep-watch.sh /tmp/lockstep
```

Every line must read `PASS`, ending `all acceptance criteria pass`. Carry phase 1's warning forward: this runs against real hardware, is audible, drives Music, and cannot run in CI.

**Known limitations.** At minimum:
- Apple Music only. The seam exists; no second source ships — design §11.
- Nothing outside Music is followed. A browser playing 48 kHz video gets whatever rate Music last set. The Shortcuts remain the override for exactly this.
- Changing the rate mid-stream is still audible. Inherent to the problem — carried forward from phase 1.
- A device name containing a comma cannot be expressed in `--devices` — `docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md`.
- Editing the allowlist means reloading the agent.
- The device is never reset when Music stops. Whatever the last track needed is where it stays, which is the correct behaviour for a device that only matters while something is playing.
- The log grows without bound. A few lines per track change; rotation is not built.
- No re-evaluation on device change. Plugging the DAC back in mid-track does nothing until the next Music event.

- [ ] **Step 2: Confirm the acceptance criteria are mechanical**

Read each criterion and check it against `docs/method.md` §5: "If a criterion contains 'should feel', 'reliably', 'properly', or 'as expected', it is a description wearing a criterion's clothes."

```bash
grep -nE 'should feel|reliabl|properly|as expected|works well' specs/phase-2-automatic-switching.md
```

Expected: no matches. If one appears, rewrite the criterion as something `test-lockstep-watch.sh` can check.

- [ ] **Step 3: Update phase 1's Known limitations**

In `specs/phase-1-manual-switching.md`, the last bullet currently reads "**Nothing here detects what is playing.** Phase 1 is a faster manual switch, not automation. You still choose the rate." Append a sentence pointing at the now-written phase 2 spec. Leave the two bullets above it alone — the "Phase 2 removes the need to look" line is still true and now resolves to a real document.

- [ ] **Step 4: Commit — this is the version-bumping commit**

```bash
git add specs/
git commit -m "feat: add the phase 2 spec — automatic switching"
```

---

### Task 4: `--watch` in the reference implementation

**Files:**
- Modify: `reference/lockstep.swift` (import block at line 16; insert the phase-2 section after `formatted` at line 116; replace `usage` at lines 118-125; insert the `--watch` branch after `let arguments` at line 132)
- Create: `reference/test-lockstep-watch.sh`
- Create (conditional): `docs/decisions/0012-reading-music-from-a-compiled-binary.md`

**Interfaces:**
- Consumes: phase 1's `address`, `defaultOutputDevice`, `name(of:)`, `currentRate(of:)`, `supportedRanges(of:)`, `supports(_:_:)`, `setRate(_:on:)`, `formatted(_:)`, `die(_:)` — all unchanged, none re-implemented. Also `routeKVC`'s body from `probes/can-swift-read-music-rate.swift`, proven in Task 1.
- Produces: the log format Task 4's own test parses and `reference/launchd/README.md` (Task 5) tells the reader to `tail`. Verb is field 2; timestamp is field 1.

- [ ] **Step 1: Add the ScriptingBridge import**

At `reference/lockstep.swift:16`, the import block becomes:

```swift
import CoreAudio
import Foundation
import ScriptingBridge
```

- [ ] **Step 2: Add the phase-2 section after `formatted` (currently line 116)**

Insert this block between `formatted(_:)` and the `usage` string:

```swift
// --- phase 2: watching -------------------------------------------------------

// Line-buffer stdout. launchd redirects it to a file, and a block-buffered
// stream holds hours of events in memory before any of them reach the log —
// including the events an acceptance test is sitting there waiting to read.
// This is one line and it is not optional.
func lineBufferStdout() {
    setvbuf(stdout, nil, _IOLBF, 0)
}

let timestamps = ISO8601DateFormatter()

// One line per event: timestamp, verb, reason. The verb is the second
// whitespace-separated field, which is how test-lockstep-watch.sh reads it.
// Keep that shape — see specs/phase-2-automatic-switching.md.
func log(_ verb: String, _ reason: String) {
    let padded = verb.padding(toLength: 5, withPad: " ", startingAt: 0)
    print("\(timestamps.string(from: Date()))  \(padded)  \(reason)")
}

// The source seam. One protocol, one conformance, in this file, five lines.
// It marks where a second source would attach and is not package architecture —
// see docs/design/2026-08-30-repo-design.md §8. It returns play state and rate
// together because the gate needs both, and asking Music twice to answer one
// question costs an Apple Event for nothing.
struct SourceState {
    let isPlaying: Bool
    let rate: Double?
}

protocol NowPlayingSource {
    func currentState() -> SourceState?
}

// 'kPSP' — MusicEPlSPlaying. Player state arrives as a four-character code in
// an NSNumber.
let musicPlaying: UInt32 = 0x6B50_5350

struct MusicSource: NowPlayingSource {
    // SBObject dispatches valueForKey: against Music's sdef, so `player state`
    // and `sample rate` are readable by name with no generated header — which
    // matters, because a single file compiled with swiftc has nowhere to put
    // one. Proven by probes/can-swift-read-music-rate.swift before it was
    // written here.
    func currentState() -> SourceState? {
        guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else { return nil }
        // Never launch Music just to ask it a question.
        guard music.isRunning else { return nil }
        guard let state = (music.value(forKey: "playerState") as? NSNumber)?.uint32Value,
              state == musicPlaying else {
            return SourceState(isPlaying: false, rate: nil)
        }
        guard let track = music.value(forKey: "currentTrack") as? SBObject,
              let hz = (track.value(forKey: "sampleRate") as? NSNumber)?.intValue,
              hz > 0 else {
            return SourceState(isPlaying: true, rate: nil)
        }
        return SourceState(isPlaying: true, rate: Double(hz))
    }
}

// Same family only. 44.1 kHz material belongs at 44.1, 88.2 or 176.4; converting
// it to 48 is the awkward resample lockstep exists to avoid. Multiples are tried
// before divisors because integer upsampling discards nothing and decimation
// does — see docs/decisions/0011-fallback-works-in-both-directions.md.
func chooseRate(for source: Double, from ranges: [AudioValueRange]) -> Double? {
    if supports(source, ranges) { return source }
    for factor in [2.0, 4.0, 8.0] where supports(source * factor, ranges) {
        return source * factor
    }
    for divisor in [2.0, 4.0] where supports(source / divisor, ranges) {
        return source / divisor
    }
    return nil
}

// Comma-separated, and it lives in the LaunchAgent's ProgramArguments — see
// docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md. Returns nil for
// a missing or empty list, which the caller turns into an exit rather than into
// "watch everything".
func allowlist(from arguments: [String]) -> [String]? {
    guard let flag = arguments.firstIndex(of: "--devices") else { return nil }
    let value = arguments.index(after: flag)
    guard value < arguments.endIndex else { return nil }
    let names = arguments[value]
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    return names.isEmpty ? nil : names
}

func evaluate(_ source: NowPlayingSource, allowing allowed: [String]) {
    guard let state = source.currentState() else {
        log("skip", "Music is not running")
        return
    }
    guard state.isPlaying else {
        log("skip", "Music is not playing")
        return
    }
    guard let sourceRate = state.rate else {
        log("skip", "Music reports no sample rate for the current track")
        return
    }
    // Re-read the device every time. The default output changes underneath a
    // long-running agent — that is the whole point of the allowlist.
    guard let device = defaultOutputDevice() else {
        log("error", "no default output device")
        return
    }
    let deviceName = name(of: device)
    guard allowed.contains(deviceName) else {
        log("skip", "\(deviceName) is not in the allowlist")
        return
    }
    let ranges = supportedRanges(of: device)
    guard let target = chooseRate(for: sourceRate, from: ranges) else {
        log("skip", "\(String(format: "%.0f", sourceRate)) Hz has no same-family match on \(deviceName)")
        return
    }
    // The no-op guard is a correctness rule, not an optimisation: a set call is
    // an audible dropout, and if Music emits a playerInfo in response to one,
    // this is the line that stops the loop.
    if let now = currentRate(of: device), now == target {
        log("noop", "already at \(String(format: "%.0f", target)) Hz")
        return
    }
    switch setRate(target, on: device) {
    case .verified(let rate):
        let note = rate == sourceRate
            ? ""
            : "  (source \(String(format: "%.0f", sourceRate)) Hz unsupported)"
        log("set", "\(String(format: "%.0f", rate)) Hz — verified\(note)")
    case .failed(let reason):
        log("error", reason)
    }
}

// 400 ms, superseded rather than queued. Five skips fire five notifications;
// only the last evaluation should run, and it should read the track that is
// actually playing by the time it does.
let debounceSeconds = 0.4
var generation = 0

func scheduleEvaluation(_ source: NowPlayingSource, allowing allowed: [String]) {
    generation += 1
    let mine = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds) {
        guard mine == generation else { return }
        evaluate(source, allowing: allowed)
    }
}

func watch(allowing allowed: [String]) {
    lineBufferStdout()
    let source = MusicSource()
    print("allowlist: \(allowed.joined(separator: ", "))")
    print("watching:  com.apple.Music.playerInfo, \(Int(debounceSeconds * 1000)) ms debounce")

    DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name("com.apple.Music.playerInfo"),
        object: nil,
        queue: .main
    ) { _ in
        log("event", "playerInfo")
        scheduleEvaluation(source, allowing: allowed)
    }

    // Evaluate once at startup, so logging in mid-track does not leave the
    // device mismatched until the next track boundary.
    scheduleEvaluation(source, allowing: allowed)
    RunLoop.main.run()
}
```

- [ ] **Step 3: Replace the `usage` string (currently lines 118-125)**

```swift
let usage = """
usage: lockstep [<sample-rate> | --watch --devices "<names>" | --help]

  lockstep            print the default output device, its current rate,
                      and every rate it supports
  lockstep 96000      set the default output device to 96000 Hz
  lockstep --watch --devices "CA DacMagic 200M 2.0"
                      follow Apple Music's sample rate, but only when one of
                      the named devices is the default output
  lockstep --help     print this message
"""
```

- [ ] **Step 4: Insert the `--watch` branch after `let arguments` (currently line 132)**

It goes **above** the existing `guard let device = defaultOutputDevice() else { die(...) }` at line 134, not below it. A watcher started at login before the DAC has enumerated must not die on the spot — it logs an error per evaluation and recovers when the device appears. The one-shot invocations below still need the guard, so it stays exactly where it is.

```swift
if arguments.first == "--watch" {
    guard let allowed = allowlist(from: arguments) else {
        die("""
            --watch requires --devices with at least one device name

            \(usage)
            """)
    }
    watch(allowing: allowed)
    exit(0)
}
```

- [ ] **Step 5: Verify it compiles with zero warnings**

```bash
swiftc -warnings-as-errors -o /tmp/lockstep-check reference/lockstep.swift
```

Expected: exit 0, no output.

**If concurrency diagnostics appear** — `generation`, `timestamps` or `debounceSeconds` reported as not concurrency-safe — the toolchain is defaulting to the Swift 6 language mode. Do **not** add `-swift-version 5` to CI. The fix is to move `generation` and the debounce into a `final class Debouncer` held as a single `let`, and to build the timestamp inside `log` rather than caching a formatter. Record it in a decision file if you take it: swapping the language mode to keep a build green is the shape [0007](../decisions/0007-ci-compiles-not-typechecks.md) exists to warn about.

**If `SBApplication.isRunning` or the KVC reads do not compile**, that contradicts Task 1's probe result. Re-run the probe before changing this code — the probe is the evidence and this file is downstream of it.

- [ ] **Step 6: Write the failing acceptance test at `reference/test-lockstep-watch.sh`**

```bash
#!/usr/bin/env bash
# Exercises the phase-2 acceptance criteria against real hardware and a real
# Apple Music.
#
#   swiftc -O reference/lockstep.swift -o /tmp/lockstep
#   ./reference/test-lockstep-watch.sh /tmp/lockstep
#
# This drives Music, changes your device's sample rate, and is audible. It
# restores the rate and the play state it found. It cannot run in CI — a runner
# has no DAC and no Music, so every result there would be meaningless.

set -uo pipefail

BIN="${1:-/tmp/lockstep}"
LOG="$(mktemp -t lockstep-watch)"
fails=0
watcher=""

report() {
  if [ "$1" -eq 0 ]; then
    echo "PASS  $2"
  else
    echo "FAIL  $2"
    fails=$((fails + 1))
  fi
}

cleanup() {
  [ -n "$watcher" ] && kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
}
trap cleanup EXIT

music() { osascript -e "tell application \"Music\" to $1" 2>/dev/null; }

# Count the evaluations logged since line $1: one per decision, whatever it was.
evaluations_since() {
  tail -n "+$1" "$LOG" | awk '$2=="set" || $2=="noop" {n++} END {print n+0}'
}
sets_since() {
  tail -n "+$1" "$LOG" | awk '$2=="set" {n++} END {print n+0}'
}
lines() { wc -l < "$LOG" | tr -d ' '; }

if [ ! -x "$BIN" ]; then
  echo "no lockstep binary at $BIN — build it first" >&2
  exit 1
fi

# --- criterion 5: --watch without --devices refuses to start -----------------
"$BIN" --watch >/dev/null 2>&1
[ $? -eq 1 ]; report $? "--watch without --devices exits 1"

# --- preconditions -----------------------------------------------------------
if [ "$(music 'player state as text')" != "playing" ]; then
  echo "Apple Music must be playing before this test runs" >&2
  exit 1
fi

status="$("$BIN")"
device="$(echo "$status" | sed -n 's/^device: *//p')"
original="$(echo "$status" | awk '/^current:/ {print $2}')"
if [ -z "$device" ] || [ -z "$original" ] || [ "$original" = "unknown" ]; then
  echo "cannot read the device or its rate from $BIN — aborting" >&2
  exit 1
fi

"$BIN" --watch --devices "$device" > "$LOG" 2>&1 &
watcher=$!
sleep 2
grep -q '^allowlist:' "$LOG"; report $? "the watcher prints its allowlist at startup"

# --- criterion 1: five rapid skips produce exactly one evaluation ------------
mark=$(( $(lines) + 1 ))
for _ in 1 2 3 4 5; do music 'next track'; done
sleep 4
[ "$(evaluations_since "$mark")" -eq 1 ]
report $? "five rapid skips produced exactly one evaluation"

# --- criterion 4: no set call when the device already matches ----------------
music 'next track'
sleep 4
now="$("$BIN" | awk '/^current:/ {print $2}')"
mark=$(( $(lines) + 1 ))
music 'next track'
sleep 4
after="$("$BIN" | awk '/^current:/ {print $2}')"
if [ "$now" = "$after" ]; then
  [ "$(sets_since "$mark")" -eq 0 ]
  report $? "no set call when the device already matches the source"
else
  echo "SKIP  consecutive tracks differed in rate; no-op guard not exercised"
fi

# --- criterion 2: paused means no rate change --------------------------------
music 'pause'
sleep 1
mark=$(( $(lines) + 1 ))
music 'next track'
sleep 4
[ "$(sets_since "$mark")" -eq 0 ]; report $? "no set call while Music is paused"
tail -n "+$mark" "$LOG" | grep -q 'not playing'
report $? "the log says why it skipped"
music 'play'
sleep 2

# --- criterion 3: a device outside the allowlist is skipped by name ----------
kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
LOG="$(mktemp -t lockstep-watch)"
"$BIN" --watch --devices "No Such Device" > "$LOG" 2>&1 &
watcher=$!
sleep 2
mark=$(( $(lines) + 1 ))
music 'next track'
sleep 4
[ "$(sets_since "$mark")" -eq 0 ]; report $? "no set call for a device outside the allowlist"
tail -n "+$mark" "$LOG" | grep -q "$device is not in the allowlist"
report $? "the log names the device it skipped"

# --- restore -----------------------------------------------------------------
kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
watcher=""
"$BIN" "$original" >/dev/null 2>&1
restored="$("$BIN" | awk '/^current:/ {print $2}')"
[ "$restored" = "$original" ]; report $? "restored the original rate ($original Hz)"

echo
if [ "$fails" -eq 0 ]; then
  echo "all acceptance criteria pass"
else
  echo "$fails failing"
  exit 1
fi
```

```bash
chmod +x reference/test-lockstep-watch.sh
```

- [ ] **Step 7: Run it against the phase-1 binary and watch it fail**

Before rebuilding, run the test against a binary that has no `--watch`:

```bash
git stash push reference/lockstep.swift
swiftc -O reference/lockstep.swift -o /tmp/lockstep-old
git stash pop
./reference/test-lockstep-watch.sh /tmp/lockstep-old
```

Expected: `FAIL  --watch without --devices exits 1` — the old binary treats `--watch` as a non-numeric argument and also exits 1, so this may pass; the run must still fail overall at "the watcher prints its allowlist at startup", because there is no watcher. If the whole script passes against the phase-1 binary, the test is not testing anything and must be fixed before continuing.

- [ ] **Step 8: Build the real thing and run it for real**

With Music playing:

```bash
swiftc -O reference/lockstep.swift -o /tmp/lockstep
./reference/test-lockstep-watch.sh /tmp/lockstep
```

Expected: every line `PASS` (one may read `SKIP`), ending `all acceptance criteria pass`.

**This is where the plan is most likely to be wrong.** Two failures to expect, both with a stated remedy:

- **No `event` lines at all when run from a terminal.** The block-based observer does not take a suspension behaviour. Switch to the selector-based form — `addObserver(_:selector:name:object:suspensionBehavior:)` with `.deliverImmediately`, which needs an `@objc` method on an `NSObject` subclass. Record it in a decision file: it is a real architectural constraint, not a typo.
- **`skip Music is not running` when Music is plainly running.** The Automation permission was denied or never asked. Check System Settings → Privacy & Security → Automation, and re-run. If the prompt never appears for a binary at this path, that is the finding — record it, because it decides how Task 5's agent gets its approval.

- [ ] **Step 9: Write decision 0012 — only if route A failed in Task 1**

Skip this step entirely if `probes/can-swift-read-music-rate.swift` reported route A working. If it did not, write `docs/decisions/0012-reading-music-from-a-compiled-binary.md` using the same template as Task 2, with:

- **Believed going in:** design §8 specified ScriptingBridge, and decision 0001 was read as having settled the question. It settled a different question — 0001 proved the *property* reports true rates for streamed tracks, using `osascript`. Whether compiled Swift could reach it was never tested and was assumed.
- **What we probed:** the three-route probe, with its actual output pasted in.
- **Decision:** the route that worked.
- **Consequences:** if route C, state the per-event cost honestly — one `/usr/bin/osascript` process per evaluation, which at a few evaluations per hour is nothing, and say so rather than implying it is free. Note that the `NowPlayingSource` seam absorbs the change: only `MusicSource.currentState()` differs.

Then update `docs/decisions/README.md` (count, arc, table, link block) as Task 2 step 5 describes.

- [ ] **Step 10: Commit**

```bash
git add reference/lockstep.swift reference/test-lockstep-watch.sh docs/decisions/
git commit -m "feat: add lockstep --watch

Follows Apple Music's sample rate onto an allowlisted device: 400 ms
debounce, play-state gate, no-op guard, same-family fallback."
```

---

### Task 5: The launchd agent

**Files:**
- Create: `reference/launchd/me.ryanlindsey.lockstep.plist`
- Create: `reference/launchd/README.md`

**Interfaces:**
- Consumes: `lockstep --watch --devices` from Task 4, and the log format it writes to stdout.
- Produces: a loaded agent under the label `me.ryanlindsey.lockstep`, which the spec's last acceptance criterion checks with `launchctl print`.

- [ ] **Step 1: Write `reference/launchd/me.ryanlindsey.lockstep.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>me.ryanlindsey.lockstep</string>

  <!-- launchd does not expand ~ or $HOME. Replace YOUR-USERNAME in all three
       paths below with the output of `id -un`, and replace the device name
       with one your own hardware reported in phase 0. -->
  <key>ProgramArguments</key>
  <array>
    <string>/Users/YOUR-USERNAME/bin/lockstep</string>
    <string>--watch</string>
    <string>--devices</string>
    <string>CA DacMagic 200M 2.0</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <!-- Restart if it exits for any reason. launchd throttles respawns to one
       every ten seconds, which is what keeps a misconfigured agent — a wrong
       binary path, an empty allowlist — from spinning. -->
  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/Users/YOUR-USERNAME/Library/Logs/lockstep.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/YOUR-USERNAME/Library/Logs/lockstep.log</string>
</dict>
</plist>
```

- [ ] **Step 2: Verify the plist parses**

```bash
plutil -lint reference/launchd/me.ryanlindsey.lockstep.plist
```

Expected: `reference/launchd/me.ryanlindsey.lockstep.plist: OK`

- [ ] **Step 3: Install and load it**

```bash
mkdir -p ~/bin ~/Library/LaunchAgents
swiftc -O reference/lockstep.swift -o ~/bin/lockstep

sed "s|YOUR-USERNAME|$(id -un)|g" \
  reference/launchd/me.ryanlindsey.lockstep.plist \
  > ~/Library/LaunchAgents/me.ryanlindsey.lockstep.plist

# Edit the device name to one of yours before loading.
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/me.ryanlindsey.lockstep.plist
launchctl print "gui/$(id -u)/me.ryanlindsey.lockstep" | head -20
```

Expected: `state = running`, and a PID.

- [ ] **Step 4: Confirm the agent can actually reach Music**

This is the question Task 1 could not answer, because a probe run from a terminal inherits the terminal's Automation approval and a launchd agent does not.

With Music playing:

```bash
tail -f ~/Library/Logs/lockstep.log
```

Skip a track in Music. Expected: an `event` line, then within a second a `set`, `noop` or `skip`.

**If every line reads `skip Music is not running`,** the agent has no Apple Events approval. Grant it by running the same binary once from a terminal — `~/bin/lockstep --watch --devices "$(...)"`, accept the prompt, Ctrl-C — then `launchctl kickstart -k "gui/$(id -u)/me.ryanlindsey.lockstep"`. **If that does not work either,** the finding is real and architectural: write it up as a decision record, because it changes what a reader has to do to make phase 2 work at all, and the spec's Build section must say so.

- [ ] **Step 5: Verify it survives logout and login**

```bash
launchctl print "gui/$(id -u)/me.ryanlindsey.lockstep" | awk '/pid = /{print $3}'
```

Note the PID. Log out, log back in, run it again. Expected: `state = running` with a **different** PID. Same PID means the session did not actually end; a missing job means `RunAtLoad` or the bootstrap did not persist.

- [ ] **Step 6: Write `reference/launchd/README.md`**

Required content, in this order:

- **What this is** — the thing that keeps `--watch` running, and the place the allowlist lives (`docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md`).
- **Install** — the exact `mkdir`/`swiftc`/`sed`/`bootstrap` block from step 3, with the two edits called out: `YOUR-USERNAME` and the device name. State that the device name must match `lockstep`'s own `device:` line exactly, and give the command to read it (`lockstep | sed -n 's/^device: *//p'`).
- **Grant Automation once, from a terminal, before loading the agent** — with the reason: a background agent may have no way to show the prompt.
- **Verify** — `launchctl print`, and `tail -f ~/Library/Logs/lockstep.log`.
- **Change the allowlist** — edit the plist, then `launchctl bootout` and `bootstrap` again. Two commands, given in full.
- **Uninstall** — `launchctl bootout "gui/$(id -u)/me.ryanlindsey.lockstep"` then `rm` the plist. State that this leaves `~/bin/lockstep` and the Shortcuts working, because phase 1 is not undone by removing phase 2.
- **Troubleshooting**, as a table of symptom → cause → fix, covering at minimum: nothing in the log (agent not loaded, or stdout not line-buffered in a modified build); `skip Music is not running` (Automation denied); repeated startup banners ten seconds apart (the binary is exiting — wrong path, or an empty allowlist, and `KeepAlive` is doing its job); `error device reports N Hz after the change` (the DAC would not take the rate — the phase-1 read-back rule catching a real failure).
- **Why `launchctl bootstrap` and not `load`** — one line: `load`/`unload` are the deprecated spellings and give worse errors.

Done when: every command in the file has been run on this machine, and the uninstall block leaves `launchctl print` reporting the job is gone.

- [ ] **Step 7: Commit**

```bash
git add reference/launchd/
git commit -m "feat: add the launchd agent that keeps --watch running"
```

---

### Task 6: Docs, CI, and the front door

Phase 2 is not finished while the repo still says it is not written.

**Files:**
- Modify: `.github/workflows/build.yml`
- Modify: `reference/README.md`
- Modify: `reference/shortcuts/README.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing downstream. This is the last task.

- [ ] **Step 1: Teach CI about the second test script**

In `.github/workflows/build.yml`, the final step becomes:

```yaml
      - name: Shell scripts parse
        run: |
          bash -n reference/test-lockstep.sh
          bash -n reference/test-lockstep-watch.sh
```

The compile step needs no change — it already globs `probes/*.swift reference/*.swift`, which picks up both new probes.

- [ ] **Step 2: Reproduce the CI check locally before pushing**

```bash
set -e
out="$(mktemp -d)"
for file in probes/*.swift reference/*.swift; do
  echo "==> $file"
  swiftc -warnings-as-errors -o "$out/$(basename "$file" .swift)" "$file"
done
bash -n reference/test-lockstep.sh
bash -n reference/test-lockstep-watch.sh
```

Expected: four `==>` lines, no warnings, exit 0.

- [ ] **Step 3: Update `reference/README.md`**

Three edits:
1. The invocation table gains the `--watch` row from the spec's CLI contract.
2. A new `## Watching` section after the existing example block: what `--watch` does in two sentences, a sample of the log format, and a pointer to `launchd/README.md`.
3. The `## Acceptance tests` section gains the `test-lockstep-watch.sh` invocation alongside the phase-1 one, carrying the same "audible, cannot run in CI" warning plus "and it drives Music".

- [ ] **Step 4: Update `reference/shortcuts/README.md`**

The final section currently ends: "Phase 2 removes the need to look: switching becomes automatic, and these Shortcuts stay as the manual override for when it is wrong or when you are playing something Music does not know about."

Phase 2 now exists, so rewrite that paragraph in the present tense and link `../../specs/phase-2-automatic-switching.md` and `../launchd/README.md`. Keep the point that the Shortcuts are still needed — they are the override for non-Music audio, which is a real limitation and not a temporary one.

- [ ] **Step 5: Update `README.md`**

Four edits:
1. Status table: phase 2 `Not yet written` → `Complete`.
2. `## Start here`: add step 4, building from the phase-2 spec, and say it depends on phase 1 being done.
3. The opening description — "about 150 lines of Swift and a few pinned Shortcuts" — is now wrong. Replace the count with what the file actually measures: `wc -l reference/lockstep.swift`. Mention the launchd agent.
4. `## What's here` table: `probes/` row now covers four probes; add nothing else — `reference/launchd/` lives under the existing `reference/` row.

- [ ] **Step 6: Update `AGENTS.md`**

Five edits:
1. **Stack:** add ScriptingBridge and launchd. The line currently reads "CoreAudio and Foundation."
2. **Constraints:** change "**No third-party dependencies.** Foundation and CoreAudio only." to name system frameworks generally and list Foundation, CoreAudio, ScriptingBridge — with the reason, that the prohibition is on third-party code rather than on Apple's.
3. **Constraints:** add "**Never launch Music to ask it a question.**" — check `isRunning` first.
4. **Commands:** add the phase-2 probe compile-and-run lines and `./reference/test-lockstep-watch.sh /tmp/lockstep`, with the note that it drives Music and is audible.
5. **Layout table:** `reference/` row is unchanged in meaning; no new row is needed.

Leave the guardrail paragraph about the agent-in-CI job exactly as it is. It is still the right call and still tempting.

- [ ] **Step 7: Verify the docs did not drift from the code**

```bash
# Every rate and invocation the READMEs claim should exist in the binary's usage.
/tmp/lockstep --help
grep -n 'watch' README.md AGENTS.md reference/README.md specs/phase-2-automatic-switching.md | head -40

# No document should still say phase 2 is unwritten.
grep -rn 'Not yet written\|phase 2 removes\|Phase 2 removes' --include='*.md' .
```

Expected: the last command returns nothing.

- [ ] **Step 8: Commit and open the PR**

```bash
git add .github/workflows/build.yml README.md AGENTS.md reference/README.md reference/shortcuts/README.md
git commit -m "docs: phase 2 is complete — update the front door and the contract"

gh pr create --title 'feat: add phase 2 — automatic switching' --body-file - <<'BODY'
`lockstep --watch` follows Apple Music's sample rate onto an allowlisted output
device, kept running by a launchd agent. The phase-1 Shortcuts stay as the
manual override.

**What the probes settled**

- `does-music-notify.swift` — <paste the RESULT line and the notification count>
- `can-swift-read-music-rate.swift` — <paste the RESULT line>

**Decisions added**

- 0009 — the allowlist lives in the launchd plist, not a config file
- 0010 — <the trigger the probe chose>
- 0011 — the same-family fallback divides as well as multiplies
<0012, only if route A failed>

**Verification**

`reference/test-lockstep-watch.sh` exercises all six acceptance criteria against
real hardware and a real Apple Music. It is audible and cannot run in CI — a
runner has no DAC and no Music. CI compiles the four Swift files and parses both
test scripts; it executes neither.

BODY
```

Add your own attribution trailers to the commits and the PR body — this plan deliberately carries none, because the session that executes it is not the session that wrote it.

The three `<...>` placeholders in that body are the only ones in this plan, and
they are deliberate: they hold the probe output, which does not exist until Task
1 has run on real hardware. Fill them from the recorded output, not from memory.

**The PR title is what release-please reads on squash-merge.** `feat:` bumps the minor version — 0.1.0 → 0.2.0, because `bump-minor-pre-major` is set. A title without a recognised type is silently skipped: no bump, no changelog entry.

---

## Where this plan is most likely to be wrong

Written down in advance, because [0007](../decisions/0007-ci-compiles-not-typechecks.md) and [0008](../decisions/0008-acceptance-criteria-are-not-coverage.md) are both records of a plan or an implementation being confidently wrong, and both would have been cheaper to catch if the author had listed what they were least sure of.

1. **The KVC reads in `MusicSource`.** Written from the ScriptingBridge contract, not from a run. Task 1's probe exists to settle this before Task 4 depends on it, and Task 4 step 5 says to re-run the probe rather than edit the implementation if they disagree.
2. **`DistributedNotificationCenter`'s block-based observer under launchd.** Suspension behaviour cannot be set on it. Task 4 step 8 names the symptom and the remedy.
3. **Apple Events from a background agent.** Task 5 step 4 is the first point at which this is testable, and it is late. If it fails outright, phase 2's Build section needs a step readers cannot skip.
4. **`grep`/`awk` on a log that a debounce is still writing.** The test sleeps 4 s after each trigger, against a 400 ms debounce and a 1 s worst-case read-back. If it proves flaky, lengthen the sleep — do not loosen the assertion from "exactly one" to "at most one", because "exactly one" is the criterion.
5. **The no-op criterion depends on two consecutive tracks sharing a rate**, which the test cannot arrange. It reports `SKIP` rather than passing silently. A `SKIP` here means the criterion is unverified, not satisfied.
6. **Every acceptance criterion in this plan tests the contract as understood today.** That is precisely the limit [0008](../decisions/0008-acceptance-criteria-are-not-coverage.md) records. Run a review pass over the shipped Swift after the tests are green; verification asks whether it does what you said, and it is silent about what you failed to say.
