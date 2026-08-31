# Decision log

Eight records, one decision each, in a standard ADR shape with two extra fields.

**`What we believed going in`.** A conventional ADR records the context and the
conclusion, and quietly launders away what the author believed before the
evidence arrived. That prior is the part worth reading. Most of the records here
exist because a confidently-held belief turned out to be wrong, and without the
belief written down a record teaches nothing except its own answer.

**`Decided by`.** One of `human`, `agent-proposed → human-accepted`, or
`human-overrode-agent`. Working with an agent means decisions arrive from both
sides, and the mix is more honest than presenting a single voice. One record
here is a human overruling the agent's recommendation. Another is the agent
correcting the human's framing of the problem.

## The arc

The project began as a native macOS menu bar application. It ended as about a
hundred and fifty lines of script, and the path between those two points is why
this log exists.

It opened with a confident wrong answer. Reasoning from the existence of prior
art that scrapes system logs, the agent concluded that Apple Music could not
report the sample rate of *streamed* tracks through its documented scripting
interface, and proposed an architecture with a fallback detector to work around
that. One `osascript` line disproved it in about ten seconds ([0001]).

A scope cut came next, on unrelated grounds. Bit depth turned out to be
sonically irrelevant — CoreAudio mixes to 32-bit float, so a 16-bit source
through a 24-bit device loses nothing ([0002]). That was decided purely to avoid
pointless work. Two decisions later it turned out to be the only reason a
compiler-free approach was worth evaluating at all: sample rate is a bare
`Float64`, while bit depth is a struct the JavaScript bridge cannot build
([0003]). Scope cuts pay off in places you cannot predict, which is an argument
for making them early.

Then came the question that should have been first and was not: does this
problem still exist? macOS could have grown the feature. Forcing the device to a
wrong rate under playback and watching it stay wrong for eight seconds settled
it ([0004]) — and that probe now ships, so every reader can ask it of their own
system before building anything.

By that point three sections of application architecture had been written —
module boundaries, a pure policy core, debounce and gating rules — before anyone
had checked how hard the central operation was. It was one CoreAudio call.
Shortcuts already pin to the menu bar. The application collapsed into scripts
([0005]), and the architecture became acceptance criteria instead.

Two records concern what the project deliberately did not do. It chose
to build rather than adopt existing tools, on architectural grounds that are
stated and checkable ([0006]). And after the plan had been reviewed, merged and
started, execution discovered that its central CI guarantee did not work at all
— `-typecheck` cannot see the warning it was written to catch ([0007]). That one
looked like the strongest evidence here that the loop is worth running, because
what the loop caught was the plan.

Then phase 1 shipped, and a review found the code crashed on `lockstep inf`
([0008]) — after nine passing acceptance criteria, a clean warnings-as-errors
build, and green CI. Three records now describe one shape: the plan was wrong,
the probe was wrong, the code was wrong. The third is the uncomfortable one,
because it passed every check the first two exist to describe. Verification asks
whether the thing does what you said; review asks what you failed to say.

## The records

| # | Decision | Decided by |
|---|---|---|
| [0001](0001-detect-via-scriptingbridge.md) | Detect the source rate via ScriptingBridge | agent-proposed → human-accepted |
| [0002](0002-match-rate-only.md) | Match sample rate only; pin bit depth | agent-proposed → human-accepted |
| [0003](0003-jxa-cannot-reach-coreaudio.md) | JXA cannot reach CoreAudio; use Swift | agent-proposed → human-accepted |
| [0004](0004-macos-does-not-autoswitch.md) | macOS does not follow the source | agent-proposed → human-accepted |
| [0005](0005-scripts-not-an-app.md) | Ship scripts and Shortcuts, not an app | agent-proposed → human-accepted |
| [0006](0006-build-rather-than-adopt.md) | Build rather than adopt prior art | human-overrode-agent |
| [0007](0007-ci-compiles-not-typechecks.md) | CI compiles rather than typechecks | agent-proposed → human-accepted |
| [0008](0008-acceptance-criteria-are-not-coverage.md) | Acceptance criteria are not coverage | agent-proposed → human-accepted |

[0001]: 0001-detect-via-scriptingbridge.md
[0002]: 0002-match-rate-only.md
[0003]: 0003-jxa-cannot-reach-coreaudio.md
[0004]: 0004-macos-does-not-autoswitch.md
[0005]: 0005-scripts-not-an-app.md
[0006]: 0006-build-rather-than-adopt.md
[0007]: 0007-ci-compiles-not-typechecks.md
[0008]: 0008-acceptance-criteria-are-not-coverage.md
