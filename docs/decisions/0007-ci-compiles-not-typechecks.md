# 0007 — CI compiles rather than typechecks

- Status: accepted
- Date: 2026-08-30
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That `swiftc -typecheck -warnings-as-errors` was the right CI check: it catches
warnings, it is faster than a full build, and it leaves no artefacts behind.

The warning it existed to catch is the one the first draft of this code carried
— reading a device name into a `CFString` variable and handing CoreAudio a raw
pointer to it, which is an ARC hazard.

This belief was written into the implementation plan as an explicit guarantee.
It survived a self-review pass. It was reviewed and merged.

## What we probed

The same file, carrying the naive `CFString` read, compiled both ways:

```
=== naive CFString under -typecheck -warnings-as-errors ===
exit 0 — CI would NOT catch it

=== naive CFString under a full compile ===
warning: forming 'UnsafeMutableRawPointer' to a variable of type 'CFString';
this is likely incorrect because 'CFString' may contain an object reference.
exit non-zero — CAUGHT
```

The warning is emitted during lowering, after type checking has finished.
`-typecheck` never sees it.

## Decision

`build.yml` performs a full compile into a temporary directory. Never
`-typecheck`. Compiling is not executing, so the rule that CI must never *run*
these binaries is unaffected.

## Consequences

- CI is marginally slower. In exchange the guarantee is real rather than merely
  stated.
- **The trap deserves naming, because it will look like an improvement.**
  Reverting to `-typecheck` is faster, appears equivalent, and keeps the build
  green — while silently removing the only protection against the regression the
  job was written to prevent. If you arrived here because you were about to make
  that change: this is why not.
- This is the only record whose wrong prior came from an approved, merged plan
  rather than from early design. The other six document decisions made before
  building. This one documents the plan itself being wrong, caught during
  execution by the same loop the repo teaches — which is a better argument for
  the loop than any of them.
