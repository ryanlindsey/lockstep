# 0003 — JXA cannot reach CoreAudio; use Swift

- Status: accepted
- Date: 2026-08-30
- Decided by: agent-proposed → human-accepted
- Superseded by: —

## What we believed going in

That a solution using only what is already on the machine would beat one needing
a compiler: no build step, no toolchain dependency, a script a reader could
paste and run.

`CoreAudio.framework` ships BridgeSupport metadata, and JavaScript for Automation
can call C functions through the Objective-C bridge. On paper, viable.

## What we probed

The bridge does expose the functions — but not the type they all require:

```
AudioObjectGetPropertyData: function
AudioObjectSetPropertyData: function
AudioObjectHasProperty:     function
AudioObjectPropertyAddress: undefined
```

Every CoreAudio property call takes an `AudioObjectPropertyAddress`, and there is
no constructor for it. Passing a plain object literal instead:

```
literal-as-struct status=1852797029 size=0 dev=undefined
```

`1852797029` is `0x6E6F7065`. The call did nothing at all.

## Decision

Swift, compiled with `swiftc`. Apple's own toolchain, no third-party code.

## Consequences

- Not "built-in only" in the purest sense — a reader needs the Xcode Command
  Line Tools. That is the cost, and it is stated in the specs.
- A compiled binary starts faster than an interpreted script, which matters when
  a Shortcut invokes it: no interpreter start-up between click and sound.
- **The surviving workaround was rejected on quality grounds, not only on
  failure.** JXA can still reach CoreAudio by hand-packing twelve struct bytes
  into an `NSMutableData` and passing raw pointers at it. That would probably
  work. It would also produce exactly the kind of clever, fragile, unreadable
  code this project exists to avoid. Winning that way would have lost.
