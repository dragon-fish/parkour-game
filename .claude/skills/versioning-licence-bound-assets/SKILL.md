---
name: versioning-licence-bound-assets
description: Use when a project depends on assets that must not be redistributed — paid packs, licence-restricted models, personal media — and they still need version history, cross-machine sync, or per-asset tuning that the public repo should keep.
---

# Versioning assets you may not redistribute

## Overview

A licence that forbids public redistribution does not forbid **backup**. The
working setup separates three things that usually get tangled: the asset,
the generic code that drives it, and the numbers that adapt one to the
other.

## The layering

| Layer | Example | Tracked publicly? |
|---|---|---|
| Generic mechanism | `spring_chains.gd`, `matcap_toon.gdshader` | Yes — nothing licence-bound about a technique |
| Per-asset parameters | `tuning/<model>.json` (mount scale, eye offset) | Yes — knowledge about a *shape* of model, useful to anyone |
| Asset + wrapper scene | the `.fbx`, its textures, `<model>_body.tscn` | No — `.gitignore` names them |

The payoff: someone cloning the public repo gets every mechanism and every
tuning number, and needs only to supply their own model. The person with the
licensed asset keeps a single place to change it (the wrapper scene).

`.gitignore` is the boundary between the layers, so write it by exact path
and say **why** each entry is excluded, in the file itself.

## Backup without publishing: the overlay repo

A second, private repository whose **work tree is the project directory**,
tracking only the ignored files:

```bash
git --git-dir="$HOME/repos/project-private.git" \
    --work-tree="$HOME/repos/project" add -f assets/models/<name> ...
```

Details that matter:

- **The public repo's `.gitignore` also binds the overlay**, and it outranks
  the overlay's own `info/exclude`. Directory-level ignores cannot be undone
  by a negation, so the overlay must `git add -f` an explicit list. Keep that
  list in a `sync.sh` beside the overlay's git dir, and add to it whenever a
  new private path appears.
- **Put LFS patterns in the overlay's `info/attributes`**, not in a tracked
  `.gitattributes` — otherwise the public repo inherits rules for files it
  will never hold.
- **Restoring on a new machine** is a clone of each, then
  `git --git-dir=<private> --work-tree=<project> checkout -f master`.

## Import settings are part of the asset

Regenerated files like Godot's `.import` usually sit outside version
control, yet may hold irreplaceable work (a hand-written bone map, material
remaps). Whatever backs up the asset must back those up too — otherwise a
routine re-import silently costs an afternoon, and the symptom (a character
in T-pose) points nowhere near the cause.

## Common mistakes

- **Encrypting the asset and committing it publicly.** An encrypted copy is
  still a copy distributed from a public host.
- **Letting the private list live only in a shell history.** It belongs in a
  script, next to the repo it serves.
- **Tracking the wrapper scene "because it is just config".** A scene that
  instances an untracked asset cannot load without it; keep it on the same
  side of the line as the asset, and keep the *numbers* on the public side.
