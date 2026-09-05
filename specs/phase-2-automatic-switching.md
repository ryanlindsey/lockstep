# Phase 2 — Automatic switching

## Goal

A launchd agent that keeps your output device's sample rate matched to whatever
Apple Music is playing, without you touching anything — and the phase 1
Shortcuts still in the menu bar as the override for everything Music does not
know about.

## Prerequisites

- [Phase 1](phase-1-manual-switching.md) complete, with a working `lockstep`
  binary. The walkthrough below assumes it at `~/bin/lockstep`
- Apple Music as the source. It is the only source phase 2 reads
- Both phase 2 probes run on your own machine, with their answers recorded —
  [`probes/README.md`](../probes/README.md) says what each result means

Run the probes first, and read what they tell you rather than what this document
expects them to say. If `does-music-notify.swift` reports zero notifications on
your system, the trigger described below is the wrong one for your machine and
you should build a 2 s poll instead — see
[decision 0010](../docs/decisions/0010-what-tells-the-watcher-a-track-changed.md)
for why the poll is not in this spec.

## Constraints

Stated as prohibitions, because that is what an implementer actually needs:

- **System frameworks only.** Foundation, CoreAudio, and now ScriptingBridge.
  This widens phase 1's "Foundation and CoreAudio only": the prohibition is on
  third-party code, not on Apple's, and ScriptingBridge ships with macOS.
- **One file.** `--watch` is a mode on the phase 1 binary, not a second program.
  No Xcode project, no SPM manifest.
- **No log scraping, no private APIs, no MediaRemote.** Public documented API
  only — see
  [decision 0001](../docs/decisions/0001-detect-via-scriptingbridge.md).
- **Must compile clean under `swiftc -warnings-as-errors`.** A full compile, not
  `-typecheck`, and the difference is not cosmetic — see
  [decision 0007](../docs/decisions/0007-ci-compiles-not-typechecks.md).
- **The rate setter must read the rate back after setting it.** `--watch` reuses
  phase 1's setter unchanged; do not write a second one.
- **Never launch Music to ask it a question.** Check that it is running first.
  An audio utility that opens Music because it was curious is a bug, and a
  launchd agent that does it at login is a worse one.
- **Do not act on a device you were not told about.** The allowlist is
  mandatory — see
  [decision 0009](../docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md).
- **Do not switch bit depth** — see
  [decision 0002](../docs/decisions/0002-match-rate-only.md).

## Build

### The CLI contract

Phase 1's invocations are unchanged. `--watch` adds three rows:

| Invocation | Behaviour | Exit |
|---|---|---|
| `lockstep --watch --devices "A,B"` | Follow Music; set the rate when A or B is the default output | runs until killed |
| `lockstep --watch` | Print that `--devices` is required, to stderr | 1 |
| `lockstep --watch --devices ""` | Same | 1 |

`--help` gains a `--watch` line.

`--devices` takes one comma-separated string. Surrounding whitespace around each
name is trimmed; empty entries are dropped. A list that is empty after that is
treated as a missing list, not as an empty allowlist.

### The log format

Load-bearing, exactly as phase 1's no-argument output is —
[`reference/test-lockstep-watch.sh`](../reference/test-lockstep-watch.sh) parses
it with `awk`:

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

Two banner lines at startup, then one line per event: an ISO-8601 UTC timestamp,
two spaces, one of five verbs padded to five characters, two spaces, the reason.

The five verbs are `event`, `skip`, `set`, `noop` and `error`. **The verb is the
second whitespace-separated field**, which is how the acceptance test reads it.
Keep that shape.

Stdout must be line-buffered. launchd redirects it to a file, and a
block-buffered stream holds hours of events in memory before any of them reach
the log — including the events a test is sitting there waiting to read.

### The rules

**400 ms debounce, superseded rather than queued.** Each notification cancels the
pending evaluation and schedules a new one, so a run of notifications collapses,
and the evaluation that finally runs reads the track playing at that moment
rather than the one that triggered it.

The debounce is not a nicety. Music emits a *pair* of notifications for a pause
and another pair for a play — one carrying the old state and one the new. One
keypress without a debounce is two evaluations.

**It does not collapse a burst to exactly one evaluation, and it is not supposed
to.** Music's `playerInfo` emissions trail the skips that caused them by about
500 ms — wider than the window — so five rapid skips typically produce two
evaluations. Widening the debounce to cover the trail would delay *every* track
change by that much, which is the defect lockstep exists to remove. The thing
that must be exactly one is the **rate change**, and the no-op guard below is
what guarantees it. See
[decision 0013](../docs/decisions/0013-the-debounce-criterion-counts-rate-changes.md).

**Play-state gate.** Act only when Music reports playing. Paused, stopped, and
not running are all skips with a reason.

**Order matters, and the order is:** is Music playing → is this device
allowlisted → what rate is the track → does the device need changing. Deciding
the device before the rate keeps the skip reason independent of timing; ask
about the rate first and a device outside the allowlist gets reported as
"Music reports no sample rate" whenever an evaluation lands mid-track-change.

**Device allowlist.** Re-read the default output device on every evaluation; it
changes underneath a long-running agent, which is the entire reason the
allowlist exists. A device not in the list is skipped, and the log names it.

Match names with surrounding whitespace trimmed on **both** sides, and log the
name exactly as the driver reports it. Drivers pad their names: the reference
DAC calls itself `CA DacMagic 200M 2.0 `, with a trailing space, and an exact
match against a name a reader copied by eye fails forever while printing a
log line that looks correct. See
[decision 0012](../docs/decisions/0012-device-names-are-matched-trimmed.md).
Trimming is not case folding and not substring matching — a different name is
still a different device.

**No-op guard.** If the device already reports the target rate, issue no set
call at all. This is a correctness rule, not an optimisation: a set call is an
audible dropout, and if Music emits a `playerInfo` in response to that dropout,
the no-op guard is the thing that stops the loop.

**Same-family fallback, both directions.** Try the source rate exactly, then
upward multiples (×2, ×4, ×8), then downward divisors (÷2, ÷4) — never crossing
families. If nothing in the family matches, change nothing and log a skip. See
[decision 0011](../docs/decisions/0011-fallback-works-in-both-directions.md).

Worked example: a 96 kHz source on a dongle that reports only 44100 and 48000.
96000 is unsupported; 192000, 384000 and 768000 are unsupported; 48000 is
supported, and 96 → 48 is a 2:1 decimation inside the 48 family. Result: 48000.
Multiplying alone would have found nothing and left the device at 44.1 kHz for a
96 kHz source, which is the worst available outcome.

**The source seam.** A `NowPlayingSource` protocol with `MusicSource` as its
only conformance, in the same file, about five lines. Design §8 names it so it
is not mistaken for package architecture: "at this size the seam is a naming
convention that marks where a second source would attach, nothing more."

One departure from the design: the method returns play state *and* rate
together, rather than the design's "current source rate, or nil". The gate needs
both, and asking Music twice to answer one question costs an Apple Event for
nothing. A two-field struct is cheaper than a second round trip.

### The agent

A LaunchAgent at `~/Library/LaunchAgents/me.ryanlindsey.lockstep.plist`, label
`me.ryanlindsey.lockstep`, holding the binary path, `--watch`, and the
allowlist. Full walkthrough — install, verify, change the allowlist, uninstall —
in [`reference/launchd/README.md`](../reference/launchd/README.md).

Two rules bite, and both bite silently:

- **launchd does not expand `~` or `$HOME`.** Every path in the plist is
  absolute, including the log paths. A `~` in `ProgramArguments` produces a job
  that respawns every ten seconds and never runs.
- **The first run triggers an Automation permission prompt**, and a background
  agent may have no way to show it. Run `lockstep --watch --devices "..."` once
  in a terminal, accept the prompt, and Ctrl-C it *before* loading the agent.
  Skip this and every log line reads `skip   Music is not running` while Music
  is plainly running.

## Acceptance criteria

- [ ] Skipping five tracks in rapid succession produces at most one `set` line —
      one rate change when the rate needs changing, zero when it does not, never
      five — and fewer than five evaluations
- [ ] With Music paused, no `set` line appears regardless of track state
- [ ] With the default output set to a device not in the allowlist, no `set`
      line appears and a `skip` line names the device
- [ ] When the device already matches the source, the line is `noop` and no set
      call is issued
- [ ] `lockstep --watch` with no `--devices` exits 1 and changes nothing
- [ ] The launchd agent survives logout and login

**The last one cannot be scripted.** It requires an actual logout, not a
`kickstart` and not a `bootout`/`bootstrap` cycle — both of those restart the
job without ending the login session, which is the thing being tested. Check it
by hand:

```
launchctl print "gui/$(id -u)/me.ryanlindsey.lockstep" | awk '/pid = /{print $3}'
```

Note the PID, log out, log back in, and run it again. A **different** PID is a
pass. The same PID means the session did not actually end. No job at all means
`RunAtLoad` or the bootstrap did not persist.

## Verification

```
swiftc -O reference/lockstep.swift -o /tmp/lockstep
./reference/test-lockstep-watch.sh /tmp/lockstep
```

Every line must read `PASS`, ending `all acceptance criteria pass`. One line may
read `SKIP` — see below.

**This runs against real hardware, drives Apple Music, and is audible.** It
skips tracks, pauses, plays, and changes your device's sample rate, then
restores the rate and the play state it found. It cannot run in CI: a runner has
no DAC and no Music, so every result there would be meaningless. CI compiles
this code and never executes it.

The no-op criterion depends on two consecutive tracks sharing a sample rate,
which the test cannot arrange. When they differ it reports `SKIP` rather than
passing silently. **A `SKIP` means that criterion is unverified, not satisfied.**

**Play from a large playlist, not a single album.** The test skips about nine
tracks. Run it against one album and Music reaches the end of the queue part way
through and stops, after which every remaining criterion fails for reasons that
have nothing to do with lockstep. The test checks the queue depth before it
starts and refuses rather than producing that result.

## Known limitations

- **Apple Music only.** The seam exists; no second source ships — design §11.
- **Nothing outside Music is followed.** A browser playing a 48 kHz video gets
  whatever rate Music last set. The phase 1 Shortcuts remain the override for
  exactly this, and that is a permanent limitation rather than a temporary one.
- **Changing the rate mid-stream still causes a brief dropout.** Inherent to the
  problem, carried forward from phase 1.
- **A device name containing a comma cannot be expressed** in `--devices` — see
  [decision 0009](../docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md).
  No such device is known.
- **Editing the allowlist means reloading the agent** — `launchctl bootout` then
  `bootstrap`. There is no config file to edit and no reload on change.
- **The device is never reset when Music stops.** Whatever the last track needed
  is where it stays. That is correct for a device that only matters while
  something is playing, but it does mean the rate you see at rest is a leftover.
- **The log grows without bound.** A few lines per track change. No rotation is
  built; delete the file when it annoys you.
- **No re-evaluation on device change.** Plugging the DAC back in mid-track does
  nothing until Music next emits an event. The trigger is Music, not CoreAudio.
