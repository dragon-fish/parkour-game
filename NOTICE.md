# Third-party components

The GNU AGPL version 3 only (`AGPL-3.0-only`) in `LICENSE` covers this repository's own code, scenes and
documentation, and a commercial licence for the same is available from the
copyright holder (`COMMERCIAL-LICENSING.md`). Neither extends to the components
below, which keep their own terms — **a commercial licence to this code is not
a licence to anything on this page.**

## Vendored addons

Each ships its licence beside its source; those files are authoritative. All
three are MIT, which combines into an AGPL work without difficulty — permissive
terms travel into copyleft ones, not the other way round.

⚠️ That does not make them AGPL. The combined work may be distributed under the
AGPL; the MIT-originated parts remain under MIT, and **their original copyright
and licence notices must be preserved** wherever their own terms require it.
A commercial licence to this project does not permit stripping them.

| Path | Component | Licence |
| --- | --- | --- |
| `addons/gut/` | GUT (Godot Unit Test) | MIT — `addons/gut/LICENSE.md` |
| `addons/vrm/` | godot-vrm, by the V-Sekai team | MIT — `addons/vrm/LICENSE` |
| `addons/Godot-MToon-Shader/` | MToon shader for Godot | MIT — `addons/Godot-MToon-Shader/LICENSE` |

## Character models

**No character model is tracked in this repository**, and that is deliberate
rather than incidental. `Player.body_scene` is an optional runtime mount point:
with nothing attached, the game runs and the whole test suite passes. Models are
kept out of version control until one is found whose licence permits
redistribution under the terms above.

`docs/asset-candidates.md` records what has been evaluated and why none of it is
committed. The short version worth repeating here: a licence forbidding
commercial use cannot be redistributed under the AGPL either, because the AGPL
grants commercial use and a licence cannot hand on a right it never had.

⚠️ The move from MIT to AGPL changes this reasoning but not its conclusion. The
old objection to CC BY-NC-SA was that ShareAlike conflicted with a permissive
licence; under a copyleft licence that half no longer bites. **NonCommercial
still does**, and it is the half that always mattered.

## Animation libraries

`assets/animations/*_standard.glb` are the free tiers of Quaternius' Universal
Animation Library, CC0 1.0 — see `assets/animations/LICENSE.txt`. CC0 is a
public domain dedication, so these are tracked here without reservation.

The **paid** full tiers are deliberately NOT tracked, even though their licence
is the same CC0 and redistributing them would be legal: Quaternius sells those
tiers to fund the work. `assets/animations/FULL-LIBRARY.md` says where to buy
them and where to drop them in, and the game runs without them.

## Reference material

`docs/mirrors-edge-deep-research/` and the measurements throughout
`docs/feel-backlog.md` describe observed behaviour of Mirror's Edge (2008),
recorded from a legally owned copy for the purpose of studying its movement
design. They contain no DICE or EA assets, and none may be added.
