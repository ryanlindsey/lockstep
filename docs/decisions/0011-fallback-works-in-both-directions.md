# 0011 — The same-family fallback divides as well as multiplies

- Status: accepted
- Date: 2026-09-04
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That the fallback rule was settled, because the design document states it.
Design §8:

> **Fallback rule:** if a source rate is unsupported, choose the nearest
> supported *integer multiple* (44.1 → 88.2 → 176.4), never crossing families to
> 48. Does not trigger on the reference hardware; matters for readers with
> limited devices.

Multiplication only. That sentence was written while thinking about a device
with *gaps* in a family — one that offers 44.1 and 176.4 but not 88.2 — where
climbing to the next multiple is exactly right.

## What we probed

Nothing, and nothing could be probed here. The rule cannot fire on the reference
hardware: the DacMagic reports both families in full, so every source rate is
supported exactly and the fallback never runs. A probe would have returned
"did not trigger" and taught nothing.

What exposed it instead was reading the rule against the device
[`specs/phase-0-probe-your-hardware.md`](../../specs/phase-0-probe-your-hardware.md)
already warns readers about: a cheap USB dongle reporting only 44100 and 48000.
Play a 96 kHz Hi-Res track through it and work the rule as written:

- 96000 exactly — not supported.
- Upward multiples: 192000, 384000, 768000 — none supported.
- Nothing left. The rule returns nothing and the device stays wherever it was.

Wherever it was is quite possibly 44100, left over from the previous track. So
the rule as written hands a 96 kHz source to a device running at 44.1 kHz — a
non-integer resample across families, which is the single worst outcome
available and precisely the thing lockstep exists to prevent. The
"never crossing families" clause was doing its job; the "multiple" clause was
quietly undoing it.

48000 was available the whole time. 96 → 48 is a 2:1 decimation and stays inside
the 48 family.

## Decision

Try, in order, and stop at the first supported rate:

1. The source rate exactly.
2. Upward multiples: ×2, ×4, ×8.
3. Downward divisors: ÷2, ÷4.

All within the source's own family. If nothing in the family matches, change
nothing and log a `skip` naming the rate and the device.

Upward is tried before downward because integer upsampling discards nothing
while decimation discards the top octave. Given a choice, take the one that
throws away no information; given no such choice, a same-family decimation still
beats a cross-family resample.

Doing nothing remains better than doing the wrong thing: a stale rate is
recoverable by the next track, and the phase-1 Shortcuts are still there. A
wrong rate is a resample on every sample.

## Consequences

- The prohibition that actually mattered in design §8 — never cross families —
  is unchanged and is now the only thing the rule enforces about family.
- The reference hardware exercises none of this. It is verified by reading, not
  by running, and that is stated here rather than implied by silence. A reader
  with a two-rate device is the one who will find out if it is wrong, which is
  what [`probes/README.md`](../../probes/README.md) asks them to report.
- **This is the first record in the log written against the design document
  rather than against a belief someone held before it.** The earlier records
  correct priors; this one corrects a specification that had already been
  reviewed and merged. It is here because
  [`AGENTS.md`](../../AGENTS.md)'s rule requires it: the design said multiply,
  the implementation also divides, and that difference is architectural rather
  than cosmetic. A spec is not exempt from being wrong just because it is the
  source of truth — it is the source of truth about what was decided, which is
  why changing it leaves a record.
