# Contributing

This is a worked example rather than a product, so the list of useful
contributions is short — deliberately.

## The two that matter

### Probe reports

Your hardware is not the author's. A compatibility record built from evidence
rather than anecdote is genuinely useful, and it is the reason
[`probes/`](probes/) ships as runnable code instead of a paragraph describing
what was found.

Run both probes, then
[open a probe report](https://github.com/ryanlindsey/lockstep/issues/new?template=probe-report.yml).

Especially valuable:

- A device that **auto-corrects** its rate — that would mean lockstep has no job
  on your system, which is a more interesting result than the expected one.
- A device that reports `INCONCLUSIVE` — it advertised a rate it would not hold.
- A device with an unusual set of supported rates, particularly one missing a
  whole family.

### Spec ambiguities

Ambiguity is the bug class for a spec repo. If two readers' agents build
different things from the same paragraph, that paragraph is broken.

If your agent produced something the spec did not intend,
[report the passage](https://github.com/ryanlindsey/lockstep/issues/new?template=spec-ambiguity.yml)
— quote it, give both readings, and say what got built. That is a defect report,
not a complaint.

## If you open a pull request

**The PR title is what release-please reads on squash-merge.** A title without a
recognised `type:` prefix is silently skipped — no version bump, no changelog
entry, no error.

| Type | Use for | Effect |
|---|---|---|
| `feat` | Spec changes | Minor bump |
| `fix` | Corrections to spec or code | Patch bump |
| `probe` | New hardware evidence | Changelog only |
| `docs` | Documentation | Changelog only |
| `chore` | Tooling, config | Hidden |

And the rule from [`AGENTS.md`](AGENTS.md):

> The specs are the source of truth. Changing an architectural choice requires
> adding a decision file in the same PR.

A decision file records what you believed going in, what settled it, the
decision, and its consequences. See [`docs/decisions/`](docs/decisions/) for
seven worked examples — including several where the belief turned out to be
wrong, which are the useful ones.

## What this repo is not looking for

Refactoring that removes the deliberate duplication between the probe files —
see the constraint in [`AGENTS.md`](AGENTS.md) and the note in
[`probes/README.md`](probes/README.md). Each probe is self-contained on purpose.
