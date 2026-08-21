# Third-party components

The MIT licence in `LICENSE` covers this repository's own code, scenes and
documentation. It does not extend to the components below, which keep their
own terms.

## Vendored addons

Each ships its licence beside its source; those files are authoritative.

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
committed. The short version worth repeating here: a licence that forbids
commercial use, or that requires derivative works to carry the same licence,
cannot be redistributed under MIT — and a downstream user is not free to
re-license someone else's work to make it fit.

## Reference material

`docs/mirrors-edge-deep-research/` and the measurements throughout
`docs/feel-backlog.md` describe observed behaviour of Mirror's Edge (2008),
recorded from a legally owned copy for the purpose of studying its movement
design. They contain no DICE or EA assets, and none may be added.
