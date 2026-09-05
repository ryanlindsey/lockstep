# 0009 — The device allowlist lives in the launchd plist, not a config file

- Status: accepted
- Date: 2026-09-04
- Decided by: human
- Superseded by: —

## What we believed going in

That a device allowlist is user configuration, and user configuration lives in a
config file. The shape was already sketched: `~/.config/lockstep/devices`, one
device name per line, blank lines and `#` comments ignored, re-read on every
evaluation so an edit takes effect without reloading the agent. It reads like
the obvious design because it is the one every other tool has.

## What we probed

Nothing. This is an argument, like [0002](0002-match-rate-only.md), and saying
so is more useful than dressing it up as an experiment.

The argument against the config file is that it is not one decision, it is five.
A file format to document. A missing-file rule to define — is no file "watch
nothing" or "watch everything"? A parser to write, and therefore to get wrong.
A second place configuration can live, so every future question about behaviour
starts with "which one is it reading?". And a reload story, because a file
re-read per evaluation is a syscall per track change forever.

All of that for a list that changes when the reader buys a DAC.

Meanwhile the agent already needs a plist, because launchd is what keeps
`--watch` running. That plist already has a `ProgramArguments` array, which is
already a list of strings, which is already the thing a reader has to edit once
to put their own username and binary path in. The configuration surface exists
whether or not a second one is added next to it.

## Decision

The allowlist is `--devices "Name A,Name B"` — a single comma-separated
command-line argument — and it lives in the LaunchAgent's `ProgramArguments`.

`--watch` with no `--devices`, or with an empty list, prints the usage to stderr
and exits 1. It does not watch every device.

That last sentence is what design §3's "opt-in" means mechanically. Opt-in that
silently defaults to everything is not opt-in; it is a default with a flag
bolted on. A reader who forgets the argument gets a loud failure at load time
rather than a utility quietly retuning their laptop speakers.

## Consequences

- One configuration surface. No file format, no missing-file rule, no parser, no
  precedence between two sources.
- Changing the allowlist means editing the plist and reloading the agent:
  `launchctl bootout` then `launchctl bootstrap`. Two commands, written out in
  full in [`reference/launchd/README.md`](../../reference/launchd/README.md).
  This is the real cost of the decision and it is paid roughly once per DAC.
- A device whose name contains a comma cannot be expressed. No such device is
  known. The limitation is stated in
  [`specs/phase-2-automatic-switching.md`](../../specs/phase-2-automatic-switching.md)
  rather than engineered around, because an escaping rule is exactly the kind of
  format this decision exists to avoid inventing.
- Failing explicitly on a missing `--devices` costs one `guard` and removes the
  "why is it changing my laptop speakers" question entirely.
