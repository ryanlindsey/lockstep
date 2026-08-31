# 0006 — Build rather than adopt existing prior art

- Status: accepted
- Date: 2026-08-30
- Decided by: human-overrode-agent
- Superseded by: —

## What we believed going in

That the cheapest move was to build nothing at all. Free tools for this problem
already exist, and the agent's recommendation was explicit: install one, live
with it for a week, and only build if it failed in a specific, identifiable way.
Thirty minutes weighed against a project.

The author declined, and chose to build.

## What settled it

An architectural distinction — and it is the only ground this record stands on.

The established approach to detecting the source rate is to tail the macOS
unified log and parse what Apple Music writes there. This project reads a
documented scripting property instead ([0001](0001-detect-via-scriptingbridge.md)).
Those are not two implementations of one design. They are different designs with
different failure modes:

| | Log parsing | Scripting property |
|---|---|---|
| Breaks when Apple changes log text | Yes | No |
| Breaks under `<private>` redaction | Yes | No |
| Needs a long-lived parsing subprocess | Yes | No |
| Idle CPU cost | Continuous | Effectively none |
| Documented and supported | No | Yes |

That difference is worth building for. It is also worth being precise about what
it does **not** buy.

## Consequences

- **Hardware behaviour is inherited, not avoided.** Clicks and dropouts when a
  DAC relocks its clock, devices that advertise rates they will not hold, audio
  glitches on format change — these live in the hardware and in CoreAudio, not
  in the detection layer. Every implementation meets them, including this one.
  The hardening described in [0004](0004-macos-does-not-autoswitch.md) exists
  because of precisely one of them.
- The detection seam is deliberately thin, so swapping the detector is cheap if
  Apple ever removes the scripting property.
- **No claim is made here about the quality of any other project.** The
  distinction above is architectural, checkable, and the whole of the argument.
