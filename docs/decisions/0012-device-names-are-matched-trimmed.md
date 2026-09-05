# 0012 — Device names are matched trimmed, because drivers pad them

- Status: accepted
- Date: 2026-09-04
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That comparing device names was not a design question. The allowlist holds
strings, CoreAudio reports a string, `allowed.contains(deviceName)` answers the
question, and the only thing worth writing down was where the list lives
([0009](0009-allowlist-lives-in-the-launchd-plist.md)).

The spec went further and told readers the comparison was exact — "it must match
what `lockstep` itself prints, exactly" — on the reasoning that an exact match is
predictable and a fuzzy one is a source of surprise.

## What we probed

Nothing deliberately. The acceptance test found it, which is the only reason it
was found at all.

`test-lockstep-watch.sh` reported two failures on a build that compiled clean:
five rapid skips produced zero evaluations rather than one, and the log did not
name the device it skipped. Running the watcher by hand against its own default
output device printed this:

```
$ /tmp/lockstep --watch --devices "$(/tmp/lockstep | sed -n 's/^device: *//p')"
allowlist: CA DacMagic 200M 2.0
watching:  com.apple.Music.playerInfo, 400 ms debounce
2026-09-05T06:28:23Z  skip   CA DacMagic 200M 2.0  is not in the allowlist
```

The device is in the allowlist. It is the *only* thing in the allowlist, put
there by asking the binary for its own device's name. Read the two lines
together and the extra space before `is` gives it away — `cat -A` confirms it:

```
2026-09-05T06:29:35Z··skip···CA·DacMagic·200M·2.0··is·not·in·the·allowlist␊
```

**The DAC reports its own name as `CA DacMagic 200M 2.0 `, with a trailing
space.** `allowlist(from:)` trims each name it parses — it has to, so that
`--devices "A, B"` means what it looks like — and the trimmed allowlist entry
could never equal the untrimmed device name.

The effect was total: on the reference hardware, `--watch` skipped its own DAC
on every single evaluation and would have done so forever. It failed in the
quietest way available — a well-formed log line, naming the right device, giving
a reason that is false.

## Decision

Compare device names with surrounding whitespace trimmed on **both** sides. The
log continues to print the name exactly as the driver reports it, because a log
that silently tidies its input is a log that hides this class of bug.

The spec no longer tells readers the match is exact. It tells them the name is
matched ignoring surrounding whitespace, and says why.

## Consequences

- A reader who copies the device name out of `lockstep` — by eye, or with the
  `sed` one-liner in
  [`reference/launchd/README.md`](../../reference/launchd/README.md) — cannot be
  defeated by a character they cannot see.
- Trimming is not case folding and not substring matching. `CA DacMagic 200M
  2.0` and `ca dacmagic 200m 2.0` are still different devices, and a partial
  name still does not match. The change is the narrowest one that fixes the
  observed failure.
- This is the second time in this repo that a green compile and a confident
  reading of the code missed something only execution could show, after
  [0008](0008-acceptance-criteria-are-not-coverage.md). It is the opposite
  lesson from that one, and worth stating as a pair: 0008 found a crash the
  acceptance criteria did not think to ask about, and this record exists because
  an acceptance criterion asked about exactly the right thing and the
  implementation was wrong. Criteria are not coverage — and they are not nothing
  either.
- The same run exposed a second ordering defect, fixed alongside it and not
  worth its own record: the source-rate guard ran before the allowlist check, so
  a device outside the allowlist was reported as "Music reports no sample rate"
  whenever an evaluation landed mid-track-change. The device is now decided
  before the rate, which makes the skip reason independent of timing.
