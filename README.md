# Parkour Game

A first-person parkour movement prototype in **Godot 4.7**, rebuilt against
measurements of *Mirror's Edge* (2008) rather than against a feel someone
remembers. Running, jumping, sliding, vaulting, wall running, ledge grabs and
the skill roll, with the numbers behind each one written down beside the code
that uses them.

The interesting part of this repository is not the movement code — it is
**why every value is what it is**. `docs/feel-backlog.md` records what was
measured in the original, what was reproduced, what was deliberately *not*
reproduced, and what is still a guess. The code comments carry the same
distinction: ✅ marks something confirmed by measurement, ⚠️ marks something
inferred.

## Running it

Open the project in Godot 4.7 and press F5, or:

```
godot --path . res://scenes/main.tscn
```

The test suite:

```
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

(`tests/legacy/` is the archived pre-rebuild suite and is not part of the run.)

## Character models and animations

**No character model is tracked here.** `Player.body_scene` is an optional
runtime mount point: with nothing attached, the game runs and the whole test
suite passes. Attaching one is a matter of pointing a `BodyProfile` at a model
and one or more animation libraries — see `scripts/player/body_profile.gd`, and
`scenes/player/body_alignment.tscn` for the workbench that lines a new body up
against the collision capsule.

The free tiers of Quaternius' Universal Animation Library are tracked (CC0).
The paid full tiers are not redistributed — see
`assets/animations/FULL-LIBRARY.md` for where to buy them and how to drop them
in. Every animation route is a priority list, so a body without them keeps the
placeholder rather than breaking.

## Licence

**Dual-licensed: `AGPL-3.0-only`, or separate commercial terms.** Two grants,
and you pick one — the second is not an exception bolted onto the first.

- `LICENSE` — the GNU AGPL, version 3 only. You may use, study, modify and
  redistribute this, **including commercially**. What the licence asks in
  return is that the **Corresponding Source** of the covered work travels with
  it, under the same terms. Section 13 adds a second trigger: modify the
  program and let people use your modified version **over a network**, and
  those users must be offered the source too, even if you never distribute a
  copy.
- `COMMERCIAL-LICENSING.md` — if you cannot meet those conditions, most often
  because you want to ship something closed-source, a separate licence is
  available from the copyright holder.

**The AGPL asks for source, not for money.** Selling an AGPL build is fine.
Needing to avoid the copyleft is what needs the other licence.

Contributions: opening a pull request grants the copyright holder copyright and
patent licences broad enough to sublicense your contribution under any terms,
including proprietary ones — which is what keeps the commercial half possible.
**You keep your copyright and your attribution.** The full wording, and the
reasoning, are in `CONTRIBUTING.md`.

Third-party components and runtime assets keep their own terms, and a
commercial licence to this code does not reach them; see `NOTICE.md`.
