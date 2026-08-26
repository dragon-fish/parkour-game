---
name: tuning-dials-not-rules
description: Use when someone will judge a result by eye — animation, camera, feel, timing, layout — and you are tempted to derive the value from geometry or add another special case, or when deciding whether a constant deserves a unit test.
---

# Give a dial, not another rule

## Overview

When a person says "I'll look at it and tell you if it should be higher",
they are asking for **a number they can turn**, not a cleverer derivation.
Every derived rule adds an intermediate they cannot reach but that changes
what they see — and rules interact, so "why did it do that this time?"
stops being answerable without an investigation.

## The signal

**Three rules is a stop sign, not a reason to add a fourth.**

A real example from this repo, in order: one apex height per animation
variant → a minimum arch for low obstacles → a branch selecting the shape by
slope → a fallback for when it degenerates to a straight line. Four rules
choosing between three shapes, and *no single rule explained what was on
screen*. The verdict was "your multi-segment curves are ugly and don't fit
the animation". It collapsed to one Bézier plus one dial — and the dial did
not even need different values per variant.

When you notice the third rule going in, stop and ask: **can this be one
shape plus one parameter?**

## Where derivation still earns its place

Derive things the person **cannot observe** — picking a variant from
obstacle geometry, resolving a bone index, choosing which surface to probe.
Anything they can see at a glance (height, distance, duration, speed) should
be a number in a file.

## A dial must be honest

If they type `1.90`, the result must measure 1.90. A quadratic Bézier does
not pass through its control point, so an "apex" dial once gave 1.43 for a
typed 1.90 — worse than no dial, because they kept tuning against a lie.

**Before shipping a parameter, measure once that what goes in equals what
comes out.** Then write the accepted value and its working range beside it
(`1.25–1.8 m verified by eye`), or the next reader inherits a magic number
with no provenance.

## What to test, and what not to

The line is **"would a change here be a defect?"** — not "will it change?"

| Don't test | Do test |
|---|---|
| Camera lift of 0.15 m | Camera ends up below the floor |
| A blend time of 0.3 s | Two states with no edge between them (a `travel()` teleports) |
| An animation speed factor | A move with no animation route, so it plays a standing pose |
| Per-model mount offsets | A self-loop restarting a clip 60 times a second |

Asserting on taste values turns every tuning pass into a test-editing pass:
the test becomes a tax, and it protects nothing — a wrong value is visible
at a glance and is not a bug.

## Common mistakes

- **Deriving the very number they offered to give you.** "Peak height must
  clear the obstacle by X, work out the algorithm" means X is an input.
- **Leaving taste assertions red in the suite.** A red suite hides real
  regressions; delete them or fix them, do not live with them.
- **Shipping the dial without stating its range.** A number with no
  provenance gets "cleaned up" by the next person.
