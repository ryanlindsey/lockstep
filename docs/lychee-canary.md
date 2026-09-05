# lychee canary — temporary

This file exists for one CI run and is deleted in this same pull request.

It carries the exact link that fails on every release-please pull request, so
that the exclusion added here can be shown to work in both directions rather
than merely asserted:

[compare](https://github.com/ryanlindsey/lockstep/compare/v0.1.0...v0.1.1)

`v0.1.1` is unborn — the tag is created when the release PR merges. Without an
exclusion, lychee must fail on this file. With one, it must pass.
