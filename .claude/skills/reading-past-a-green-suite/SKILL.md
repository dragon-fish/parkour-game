---
name: reading-past-a-green-suite
description: Use when a test run passes and you are about to treat that as proof - a runner's pass/fail tally does not necessarily cover every way production code can fail
---

# Reading past a green suite

## Overview

A test runner reports what it was configured to count. The set of ways
production code can be wrong is larger, and the gap is invisible from the
summary line — which says `1078 passing` either way.

Before a green run is allowed to mean "the code is correct", you have to know
what your runner does **not** count. That is a property of the configuration,
not of the tests, so no amount of writing better tests closes it.

## This project's gap

`.gutconfig.json` sets:

```json
"failure_error_types": ["gut", "push_error"]
```

GUT's own default is `["engine", "gut", "push_error"]`. The dropped category,
`engine`, is where **every GDScript runtime error lands** — a missing
Dictionary key, a method call on null, a bad cast. Such an error:

- prints `SCRIPT ERROR:` and a full backtrace to stdout,
- **aborts the function it happened in**,
- and does not fail the test.

An aborted function is indistinguishable from a function that returned early.
So a test whose assertions still hold after the abort passes, and the summary
line is green.

`tools/run_tests.ts` forwards the engine's exit code and never inspects the
output, so nothing downstream catches it either.

**DO NOT "fix" this by putting `engine` back.** It was removed to silence a
flaky Jolt physics warning coming out of the C++ side, and GUT classifies
genuine engine errors and GDScript errors into the same bucket — it cannot
tell them apart. Restoring the category brings the flake back. The trade-off
is the repo author's to revisit, not a passing agent's.

## What to do instead

**Grep the run's output.** A green summary plus a clean `SCRIPT ERROR` grep is
proof; a green summary alone is not.

```sh
bun tools/run_tests.ts some_filter 2>&1 | grep -n "SCRIPT ERROR" || echo clean
```

Do this on the final run of any task, not only when something looks wrong.

**Prefer asserting a consequence over asserting an absence.** A test written as
"this does not crash" cannot fail here, because the crash is not counted. A
test written as "after this call, X is true" fails, because the abort prevents
X from ever being set. When a guard's whole job is to prevent a crash, assert
the observable thing the guarded code goes on to do.

**Mutation is the only honest check.** Break the production code in the way the
test claims to catch, run it, and look at the result — including the output,
not only the tally. Three separate tests in this repo were found vacuous this
way, one of which still passed after its own subject was deleted.

## Common mistakes

- **Reporting "tests pass" after a run nobody read.** The tally is a summary of
  the assertions, not of the run.
- **Trusting a test whose name begins "does not crash" / "handles null".**
  Under this configuration those names describe something the runner cannot
  observe.
- **Concluding a mutation "was not caught" without reading stdout.** It may have
  been caught loudly and just not counted — which is a different finding, and
  points at the configuration rather than at the test.
