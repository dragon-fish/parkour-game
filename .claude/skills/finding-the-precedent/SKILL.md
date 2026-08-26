---
name: finding-the-precedent
description: Use when about to write a new mechanism — a probe, a detector, a curve, a state, a helper — when a hand-rolled implementation keeps needing patches, or when a comment describes behaviour the code no longer has.
---

# Find the precedent before inventing

## Overview

Almost every new requirement in a mature codebase has a **sibling that was
already solved**, and most engine-level problems (collision, character
control, physics, rendering) have a standard community answer. Writing a new
mechanism without checking both is how a codebase grows two half-right
versions of the same idea.

Check **two places, in this order**: this repository, then the engine's
community.

## Search the repo first

Before writing a probe, a check, or a curve, grep for the shape of the
problem. In this repo a new raycast was written to answer "is there room to
stand here?" — and it did not work — while `StandClearance` (a `ShapeCast3D`
on the player) had been answering exactly that for crouch-recovery all
along.

Ask literally: *who here has already solved a problem of this shape?* Then
copy its mechanism **and its parameter names**, so the two read as siblings
rather than as strangers.

## Then search the community

If the problem belongs to the engine rather than to your game, someone has
hit it. A hand-written stair-step routine here was structurally unlike the
standard approach — it lifted in place and relied on the next frame to carry
the body, which guarantees a floating frame. Rounds of patching went into it
before a search turned up the community's three-phase sweep.

Signals that it is time to search: the problem is generic (collision,
controller, physics, pipeline), or **you have debugged your own version
twice without locating the cause**.

This is not premature optimisation. Sharing or merging systems for
performance can wait for a stable design; *not writing code that already
exists* is cheapest exactly at the moment before you write it.

## Interrogate old comments

A comment is evidence about the past, not about the code in front of you. A
stale note here still argued for a "straight line" approach that had been
replaced by a closed-form Bézier — and it sent an implementation the wrong
way. **Confirm a comment against the code it describes before acting on it**,
and rewrite it into a tombstone (what it used to be, what replaced it) when
it turns out to be stale.

## Common mistakes

- **Inventing because searching feels slow.** One grep is cheaper than one
  review round.
- **Copying the precedent's shape but renaming everything.** Names are half
  of what makes the pair recognisable later.
- **Announcing "there was no precedent" without saying where you looked.**
  Say what you searched, so the claim can be checked.
