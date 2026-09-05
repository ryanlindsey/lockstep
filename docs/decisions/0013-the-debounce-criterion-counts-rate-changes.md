# 0013 — The debounce criterion counts rate changes, not evaluations

- Status: accepted
- Date: 2026-09-04
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That a 400 ms debounce turns a burst of track skips into one evaluation, and
that counting evaluations was simply a more precise way of saying what design §8
already said:

> Skipping five tracks in rapid succession produces **exactly one** rate change

The phase 2 plan restated that criterion as "exactly one evaluation — one `set`
or one `noop`, not five", and wrote the acceptance test to count `set` and
`noop` lines. It also warned, in advance, against exactly the change this record
makes: "do not loosen the assertion from 'exactly one' to 'at most one', because
'exactly one' is the criterion."

That warning was right about the failure it imagined — a log read racing a
debounce that is still writing — and wrong about this one.

## What we probed

`reference/test-lockstep-watch.sh` failed this criterion on three consecutive
runs against a healthy queue. Not flaky: deterministic. The watcher was then run
under a millisecond timestamper while a single `osascript` issued five skips:

```
260.220  >>> burst start
260.566  >>> burst end
260.560  2026-09-05T06:37:40Z  event  playerInfo
261.057  2026-09-05T06:37:41Z  noop   already at 44100 Hz
261.057  2026-09-05T06:37:41Z  event  playerInfo
261.514  2026-09-05T06:37:41Z  noop   already at 44100 Hz
```

The five skips took 346 ms — comfortably inside the 400 ms window. The
notifications did not. Music's first `playerInfo` arrived at 260.560 and its
last at 261.057, **497 ms apart**, and 497 ms is wider than the debounce by
design. The second notification arrived at the same millisecond the first
evaluation ran, so it could not have been coalesced into it.

This is not a timing accident that a longer window would fix reliably, and it is
not a defect in the debounce. Music's emissions trail the skips that caused
them. No debounce narrower than that trail can collapse a burst into one
evaluation, and widening the debounce to cover it has a real cost: the debounce
delays *every* track change, so a 1 s window means every new track plays its
first second at the previous track's rate. That is the exact defect lockstep
exists to remove.

Note what the two evaluations actually did: `noop`, `noop`. **Zero rate
changes.** The device was never touched. The criterion was failing on a run
where the behaviour it describes was perfect.

## Decision

The criterion counts rate changes, which is what design §8 said:

- **At most one `set` line** for a burst of five skips. One when the rate needs
  changing, zero when it does not — never five.
- **Fewer than five evaluations**, which is the part that shows something
  coalesced at all.

The debounce stays at 400 ms. The no-op guard, not the debounce, is what makes a
trailing evaluation harmless, and criterion 4 already tests that guard directly.

## Consequences

- The plan's restatement conflated two different quantities: how often the
  watcher *thought about* the device, and how often it *changed* it. Only the
  second is audible, and only the second was ever in design §8. A reader of the
  acceptance test can now see which one is being asserted and why.
- "At most one" rather than "exactly one" is not a weaker claim here, it is the
  correct one. Five consecutive 44.1 kHz tracks on a device already at 44.1 kHz
  should produce **zero** rate changes, and a criterion demanding exactly one
  would fail a correctly behaving implementation.
- The same investigation found a second trap and fixed it in the test rather
  than in a record: the test skips about nine tracks, so running it against a
  single album runs off the end of the queue part way through. Music stops, and
  every criterion after that point fails for reasons unrelated to lockstep. Two
  of the runs that produced the confusing early evidence for this record were
  that, not this. The test now refuses to start without a deep enough queue.
- This is the third record in this phase written against a document rather than
  against a belief — [0011](0011-fallback-works-in-both-directions.md) against
  the design, [0012](0012-device-names-are-matched-trimmed.md) against the spec,
  and this one against the plan. All three were found by running the thing. That
  is either the strongest evidence in this repo that the loop is worth running,
  or the strongest evidence that three documents in a row were written with more
  confidence than their authors had earned. It is both.
