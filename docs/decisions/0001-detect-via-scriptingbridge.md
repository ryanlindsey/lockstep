# 0001 — Detect the source sample rate via ScriptingBridge

- Status: accepted
- Date: 2026-08-30
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

Prior art for this problem reads the sample rate by tailing the macOS unified
log and parsing what Apple Music writes there. That is fragile by construction,
which raised an obvious question: why would anyone do that when Music publishes
a `sample rate` property through its documented scripting interface?

The answer seemed equally obvious. The scripting property must not work for
*streamed* Apple Music catalogue tracks — fine for a local file, useless for
anything streamed, which is the case that actually matters. The existence of the
log-scraping tool was taken as evidence for this.

The inference was stated confidently. It was wrong.

## What we probed

One command, with a Hi-Res Lossless track playing:

```
osascript -e 'tell application "Music" to ¬
  (class of current track as text) & " | " & (sample rate of current track as text)'

URL track | 96000
```

`URL track` is the class Music uses for a **streamed catalogue track**, not a
local file. It reported the true 96 kHz rate.

Ten seconds of evidence displaced an architecture.

## Decision

Read `sample rate` from `current track` through ScriptingBridge. Public,
documented API. No log parsing, no private frameworks, no MediaRemote.

## Consequences

- No exposure to log-format changes between macOS releases, and none to
  `<private>` redaction blanking the values.
- No long-lived subprocess parsing text, and effectively no idle CPU cost.
- Costs one Automation permission prompt the first time it runs.
- An entire fallback detector, designed to work around a limitation that turned
  out not to exist, was deleted before it was ever built.

This is the clearest example in the repo of the loop described in
[the method](../method.md): name the assumption that would waste the most work
if wrong, and probe it *before* designing around it.
