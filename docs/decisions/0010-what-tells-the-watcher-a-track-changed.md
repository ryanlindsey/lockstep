# 0010 — What tells the watcher a track changed

- Status: accepted
- Date: 2026-09-04
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That the notification probably fires, and that a poll should be built in case it
does not. Design §12 said so in as many words:

> **Does `com.apple.Music.playerInfo` fire reliably on macOS 26?** Assumed, not
> verified — a `log stream` test was the wrong instrument, as distributed
> notifications are not `os_log` events. Phase 2 therefore specifies a 2 s poll
> while playing as a fallback, to be used only if the notification proves
> unreliable during implementation.

Read that back and the shape is plain: a question was left unanswered, and a
second mechanism was designed to hedge against the answer. That is the failure
[`docs/method.md`](../method.md) §3 names first — building both branches of a
question you could have answered in a minute. The design wrote the hedge; nobody
had yet spent the minute.

## What we probed

[`probes/does-music-notify.swift`](../../probes/does-music-notify.swift), run on
macOS 26.6.2 with Apple Music playing. Five tracks skipped in the first fifteen
seconds, then a pause, then a play.

```
$ swiftc -O probes/does-music-notify.swift -o /tmp/does-music-notify
$ /tmp/does-music-notify
watching com.apple.Music.playerInfo for 60 seconds
skip a few tracks, then pause, then play again

t+3.09s  notification 1
    Album = Happiness, Guaranteed
    Artist = Dom Dolla
    Composer = Dominic Matheson, William Jack Froggatt, Kaelyn Behr & Lachlan Bostock
    Genre = Dance
    Name = Strangers (feat. Mansionair)
    Player State = Playing
    Total Time = 217261

t+5.26s  notification 2
    ... Name = Guillotine, Player State = Playing
t+7.27s  notification 3
    ... Name = ATLAS, Player State = Playing
t+9.32s  notification 4
    ... Name = Violet City, Player State = Playing
t+11.46s  notification 5
    ... Name = We Could Leave, Player State = Playing

t+21.55s  notification 6
    ... Name = We Could Leave, Player State = Playing
t+21.66s  notification 7
    ... Name = We Could Leave, Player State = Paused

t+31.67s  notification 8
    ... Name = We Could Leave, Player State = Paused
t+31.67s  notification 9
    ... Name = We Could Leave, Player State = Playing


RESULT: 9 notifications in 60 seconds. The notification fires.
```

Five skips produced five notifications, each within about 100 ms of the skip.
The pause produced two and the play produced two — Music emits a state-change
pair, not a single edge.

The second probe,
[`probes/can-swift-read-music-rate.swift`](../../probes/can-swift-read-music-rate.swift),
ran immediately after:

```
route A  ScriptingBridge + KVC          playing, sampleRate = 44100
route B  ScriptingBridge + @objc proto  unavailable — does not compile
route C  osascript subprocess           playing | 44100

RESULT: route A works. Phase 2 reads Music in-process, no subprocess
per event. Copy routeKVC into reference/lockstep.swift.
```

## Decision

`DistributedNotificationCenter` on `com.apple.Music.playerInfo` is the trigger.
**No poll ships.** The 2 s polling fallback described in design §12 is not
built, because the question it hedged against has been answered.

The notification is coalesced by a 400 ms debounce before anything reads Music,
which is what turns nine notifications into the number of evaluations that
actually matter. The doubled pause and play notifications above are the concrete
reason the debounce is not optional: without it, one keypress is two
evaluations.

## Consequences

- The branch not taken is not in the codebase. There is no poll interval to
  tune, no "is the poll running" state, and no second code path that only
  executes on hardware nobody has.
- **The payload carries `Player State` but no sample rate.** That is the fact
  that decided the next question. The gate *could* read `Player State` straight
  out of `userInfo` and skip an Apple Event entirely — but the evaluation needs
  the track's sample rate regardless, and one ScriptingBridge call returns play
  state and rate together. Reading the state from the notification would buy
  nothing and would leave two sources of truth for "is it playing" that can
  disagree. `MusicSource.currentState()` is the only answer to both questions.
- The `userInfo` keys are `Album`, `Artist`, `Composer`, `Genre`, `Name`,
  `Player State` and `Total Time` — display metadata. Anything about *format*
  has to be asked for.
- Route B failing to compile is recorded in the probe file rather than in a
  decision of its own, because route A worked and nothing downstream changed.
  `@objc optional` protocol requirements are reachable only through the protocol
  existential, never through the concrete conforming type, so the
  `extension SBApplication: MusicScripting {}` route cannot work in principle
  and not merely on this toolchain.
- This is the first record in the log written *before* the thing it constrains
  existed. [0004](0004-macos-does-not-autoswitch.md) probed a question that
  should have been asked earlier; this one probed a question at the moment it
  was asked. The difference is the whole argument of
  [`docs/method.md`](../method.md).
