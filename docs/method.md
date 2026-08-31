# The method

A loop, not a workflow. It names no tool and requires none — adapt it to
whatever you use rather than adopting it.

Every step below is illustrated with what actually happened while building
lockstep, including the parts that went wrong. The records in
[`decisions/`](decisions/) are the primary evidence; this page is the shape they
form.

## 1. Classify how much ceremony the work needs

Before asking a single question, decide roughly how much process the work
deserves — and say so out loud, so it can be corrected.

Three rough sizes are enough: a **feasibility question** whose output is an
answer rather than code; a **bounded change** to something that already exists;
and **architectural** work — new projects, new subsystems, anything that changes
how the pieces fit together.

Getting this wrong is expensive in both directions. Too little ceremony and you
build the wrong thing carefully. Too much and you write three sections of
architecture for something that turns out to be a hundred lines.

> **What happened here.** This project changed classification twice. It began as
> architectural — a native menu bar application. It became a feasibility
> question when someone asked whether built-in tools could do the job at all.
> The answer to that question deleted most of the architecture. Classification
> is not something you decide once.

## 2. Name the assumption that would waste the most work if wrong

Not every unknown. The one that, if it went the other way, would invalidate most
of what you are about to do.

There is usually exactly one, and it is usually not the part that looks most
technically interesting.

> **What happened here.** Everything depended on a single question: can the
> source sample rate be read at all? The detector, the fallback, the policy
> engine, the entire shape of the application were downstream of it. The
> interesting-looking problems — debounce, device allowlists, avoiding audible
> glitches — were downstream too, and none of them mattered until that one was
> settled.

## 3. Probe it as cheaply as correctness allows — before designing around it

Write the smallest thing that answers the question. Not a prototype, not a spike
you keep. Something you throw away once it has told you what you needed.

The temptation is to design a system that works whether the assumption holds or
not. That feels like prudence. Usually it is building both branches of a
question you could have answered in a minute.

> **What happened here.** The assumption was that Apple Music could not report
> the sample rate of streamed tracks — inferred from the fact that existing
> tools go to the trouble of scraping system logs instead. An architecture with
> a fallback detector was proposed to work around it.
>
> One line of `osascript` disproved it in about ten seconds
> ([0001](decisions/0001-detect-via-scriptingbridge.md)). The fallback was
> deleted before it was built.

Probes are worth keeping as artefacts even when the code is throwaway. This repo
ships two in [`probes/`](../probes/), because a reader's hardware answers
differently from the author's.

## 4. Record the decision — including what you believed going in

A record that states only its conclusion teaches that conclusion and nothing
else. What makes it transferable is the prior: what you thought before the
evidence arrived, and what changed.

Writing that down is uncomfortable, which is a fair sign it is worth doing.

> **What happened here.** Every record in [`decisions/`](decisions/) carries a
> `What we believed going in` section, and most describe a belief that was
> wrong. One describes a belief that survived a self-review pass and a merged
> pull request before execution caught it
> ([0007](decisions/0007-ci-compiles-not-typechecks.md)).

## 5. Implement against acceptance criteria, not against a description

A description can be satisfied by arguing. A criterion is a command with an
expected result.

If a criterion contains "should feel", "reliably", "properly", or "as expected",
it is a description wearing a criterion's clothes. Rewrite it as something a
machine can check.

> **What happened here.** The switching rules designed for the abandoned
> application — debounce, no-op guard, play-state gate, device allowlist — did
> not survive as architecture. They survived as acceptance criteria, which is a
> more useful form: *skipping five tracks in rapid succession produces exactly
> one rate change.*

## 6. Verify with commands, not assertions

Run the thing. Read the output. "It should work" and "it works" are different
claims, and only one of them has evidence behind it.

This applies to your own tooling. A check that passes on correct code proves
nothing about whether it would catch the failure it exists to prevent — so test
it in both directions.

> **What happened here.** `lockstep` reads the sample rate back after setting
> it, because a `noErr` status is not proof the driver applied anything. The CI
> guard was verified by reintroducing the bug it exists to catch and confirming
> the build failed. And the auto-switch probe was hardened once it turned out to
> conflate *the device left the forced rate* with *something corrected it* — a
> distinction that decides whether a reader is told they need this tool at all.

## Where this went wrong

A method page that reports only successes launders its evidence exactly the way
a decision record without priors does. Two failures, both real, both expensive.

### Designing around an unprobed assumption

The claim that Music could not report streamed sample rates was reasoned from
circumstantial evidence — prior art exists that does something harder — and then
treated as settled. An architecture was proposed to accommodate it: a source
protocol, a primary detector, a fallback detector behind the same seam.

A ten-second probe disproved the premise and deleted the fallback
([0001](decisions/0001-detect-via-scriptingbridge.md)).

The failure was not the wrong guess. Wrong guesses are free. The failure was
designing around the guess before checking it, when checking cost ten seconds.

### Building the heavier artefact before checking the hard part was hard

Three sections of design were written for a native macOS application: module
boundaries around a pure policy core, a switching-rules engine, error handling,
signing and update strategy.

Then someone checked how you actually set a sample rate. It is one CoreAudio
call. Shortcuts already pin to the menu bar, supplying the UI for free. The
application became about a hundred and fifty lines of script
([0005](decisions/0005-scripts-not-an-app.md)).

That design work was not entirely wasted — the rules became acceptance criteria.
But three sections of architecture were written before anyone spent five minutes
establishing that the central operation was difficult. It was not.

## On tools

This loop names no agent, and the repo's machine-readable contract lives in
[`AGENTS.md`](../AGENTS.md). Any tool-specific file here is a pointer to that
file and never content of its own.

That is deliberate, and it is the only claim to agent-agnosticism worth making:
not that the method is portable in principle, but that this repo contains
nothing one particular tool must read.
