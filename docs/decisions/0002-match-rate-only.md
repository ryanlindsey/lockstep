# 0002 — Match sample rate only; pin bit depth at the device maximum

- Status: accepted
- Date: 2026-08-30
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That bit depth and sample rate both had to follow the source. That is what you
do by hand in Audio MIDI Setup — the format popup sets the pair together — and
seeing the wrong numbers there feels like it must matter.

## What settled it

An argument, not a probe. Worth stating plainly: not every decision needs
evidence, and dressing this one up as an experiment would be dishonest.

CoreAudio mixes all audio to 32-bit float internally and renders to the device's
physical format on the way out. A 16-bit source rendered through a device set to
24-bit is **bit-transparent** — the samples are left-shifted and nothing is
lost. A sample-rate mismatch is different in kind: it forces a real resample,
which is lossy arithmetic.

So matching depth per track is effort with no audible payoff, while matching
rate is the entire point.

## Decision

Vary sample rate per track. Set bit depth to the device maximum once, and never
touch it again.

## Consequences

- Halves the detection problem and removes a whole class of failure.
- A display can still *show* a source's native depth if that is ever wanted.
  Showing is not switching.
- A payoff nobody predicted: two decisions later this was the only reason
  [0003](0003-jxa-cannot-reach-coreaudio.md) was worth evaluating at all.
  Nominal sample rate is a bare `Float64`; bit depth would have required an
  `AudioStreamBasicDescription`, which the JavaScript bridge cannot construct.
  A scope cut made on audio-quality grounds opened a door somewhere unrelated —
  which is an argument for making such cuts early.
