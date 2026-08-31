# 0008 — Acceptance criteria are not coverage

- Status: accepted
- Date: 2026-08-31
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That phase 1 was finished and verified. The evidence looked strong:

- nine acceptance criteria, each a command with an expected result, all passing
  against real hardware
- every Swift file compiling clean under `swiftc -warnings-as-errors`
- both CI jobs green
- a CI guard tested in *both* directions — the `CFString` hazard was
  deliberately reintroduced into a throwaway copy to confirm the build rejected
  it

That is more verification than a change of this size usually gets, and the work
was merged on the strength of it.

## What we probed

A code review run after the merge asked what happens with input nobody had
thought about. Running the shipped binary:

```
lockstep inf   -> exit 133   (SIGTRAP)
lockstep 1e30  -> exit 133   (SIGTRAP)
```

`Double("inf")` parses successfully, is greater than zero, and passes the
argument guard. The unsupported-rate path then formats it with `Int(...)`, which
traps on a non-finite `Double`. The CLI contract in
[`specs/phase-1-manual-switching.md`](../../specs/phase-1-manual-switching.md)
promises exit 1.

The same review found two more of the same shape: a membership test that
rejected valid rates on devices reporting a continuous range rather than
discrete ones, and a probe that counted a *failed* rate read as evidence of
auto-switching.

## Decision

Fix the crash, and record the pattern rather than just the bug.

## Consequences

- `lockstep` now guards on `.isFinite` and formats with `%.0f` instead of
  `Int(...)`. The probe follows the same rule even where its values cannot
  currently be non-finite — they come from the device's own rate list — because
  this crash was built on exactly that kind of assumption.
- **The lesson is about coverage, not about this bug.** Acceptance criteria test
  the contract you thought of. They are silent about the inputs you did not
  think of, and they pass just as loudly either way. Nine green criteria said
  nothing whatsoever about `lockstep inf`.
- This is the third instance of one shape in this repo. The plan was wrong
  ([0007](0007-ci-compiles-not-typechecks.md)). The probe was wrong
  ([0004](0004-macos-does-not-autoswitch.md)). Now the code was wrong — and it
  was wrong *after* passing every check the first two records exist to describe.
- The honest reading is not that the verification was too small and should have
  been bigger. It is that verification and review answer different questions.
  Verification asks whether the thing does what you said. Review asks what you
  failed to say. Running one does not excuse skipping the other.
