# 0005 — Ship scripts and Shortcuts, not a menu bar app

- Status: accepted
- Date: 2026-08-30
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That this needed to be a native macOS application: a SwiftUI `MenuBarExtra`, an
opt-in device allowlist with a settings pane, a switching-policy engine in its
own Swift package, Developer ID signing, notarisation, and an update mechanism.

Three sections of design were written on that basis — module boundaries, a pure
policy core, and the debounce and gating rules — before anyone checked how hard
the central operation actually was.

## What settled it

Three findings in quick succession:

1. Setting the rate is **one CoreAudio call**, public and unprivileged.
2. Shortcuts pin to the macOS menu bar natively, supplying the entire UI free.
3. The whole product ran end-to-end as a one-line shell pipeline — read the rate
   from Music, set it on the device — before any application existed.

## Decision

Two phases of small scripts, driven from pinned Shortcuts. No app.

## Consequences

- **Given up:** live status in the menu bar. Shortcuts can trigger but not
  display, so there is no always-visible rate indicator. Accepted, because once
  switching is automatic there is nothing to watch, and the pinned Shortcuts
  remain as the manual override.
- **Gained:** no notarisation, no Developer ID, no updater, no application
  lifecycle, no settings persistence. Roughly 150 lines instead of a project.
- The design work was not wasted. The switching rules — debounce, no-op guard,
  play-state gate, device allowlist — stopped being architecture and became
  acceptance criteria in
  [`specs/phase-1-manual-switching.md`](../../specs/phase-1-manual-switching.md)
  and, later, phase 2.
- This is the second failure mode named in [the method](../method.md): building
  the heavier artefact before checking whether the hard part was hard.
