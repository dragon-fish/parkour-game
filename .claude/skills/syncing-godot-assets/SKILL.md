---
name: syncing-godot-assets
description: Use when moving, renaming, pulling or checking out Godot assets — a submodule sync, a first import on a new machine, an asset pack landing in the project — or when a model comes back T-posed, materials reset, or the log says "Unrecognized UID" after someone else's checkout.
---

# Syncing Godot assets without losing the import

## Overview

Godot keeps an asset's *settings* (retarget bone map, material remaps, LOD,
compression) in a sidecar `.import`, and its *identity* in a `uid://`. Both
are regenerated the moment the engine decides an asset is new. A file that
moves under a running editor, or arrives on a machine whose cache never saw
it, is "new" — and the settings that took an afternoon are gone, silently.
The symptom shows up far from the cause: a character in T-pose, a grey
model, an animation that no longer retargets.

Two rules prevent nearly all of it: **the editor is closed while files
move**, and **every asset carries a committed uid**.

## Ask the human to close the editor — then reopen it for them

An agent must not move, rename, or check out assets while the human has the
project open. The editor rescans on focus, rewrites `.import` files for
what it believes are new files, and reassigns uids — racing whatever the
agent is doing.

The exchange is short and belongs *before* the work:

> 这次要移动/拉取资产，麻烦先关掉 Godot 编辑器窗口，我做完再帮你打开。

Then, after the sync:

1. `<godot> --headless --path . --import` — a controlled import, with the
   log visible.
2. Verify the settings survived (see below).
3. Reopen the **editor** for them: `<godot> --path <project> --editor`.
   Reopening the editor is a courtesy; launching the *game* is not the same
   thing and stays the human's call — a running level may grab the pointer.

## Verify the import, do not assume it

```bash
# The settings that cost the most, and vanish the most quietly.
grep -c "retarget/bone_map"    path/to/model.fbx.import   # expect 1
grep -c "use_external/path"    path/to/model.fbx.import   # expect one per material
<godot> --headless --path . --import 2>&1 | grep -E "Unrecognized UID|ERROR"
```

A structural test is better than a grep, because it runs on every machine:
load the asset and assert the retargeted skeleton exists (`GeneralSkeleton`
for the humanoid profile), skipping when the asset is absent so a clone
without it still passes.

## Commit uids, not just paths

A hand-authored `.tres` / `.tscn` has **no uid** — Godot only writes one
when *it* saves the file. Anything referring to that resource by uid then
resolves through `.godot/uid_cache.bin`, which is machine-local and not
committed. On the next machine the reference dangles: `Unrecognized UID`,
a fallback to the path if one was recorded, and a re-import if one was not.

So: generate real uids and commit them.

```gdscript
# headless: give every hand-written .tres in a directory a portable uid
var id := ResourceUID.create_id()
var uid_text := ResourceUID.id_to_text(id)          # uid://b533qs2c1cgst
# insert `uid="<uid_text>"` into the resource's [gd_resource ...] header
ResourceUID.add_id(id, path)
```

**Never invent the uid string yourself.** A readable one (`uid://mymat`)
parses, loads by path, and then poisons every scene and test that touches
it with `invalid UID` — it must come from `create_id()`.

## What belongs in version control

| File | Commit? | Why |
|---|---|---|
| `*.import` | **Yes** | The only home for retarget/material settings; regenerating them means losing them |
| `*.gd.uid`, resource `uid=` headers | **Yes** | Identity that must be the same on every machine |
| `.godot/` | No | Cache, and `uid_cache.bin` inside it is machine-local by design |
| The asset itself | Wherever its licence allows | See `versioning-licence-bound-assets` |

## Checklist for a sync

- [ ] Ask the human to close the editor; wait for confirmation
- [ ] Back up the `.import` files you are about to disturb
- [ ] Move / pull / check out
- [ ] `--headless --import` once, read the log
- [ ] Check bone map, material remaps, no unrecognized uids
- [ ] Run the suite (or at least the asset's structural test)
- [ ] Reopen the editor for them, and say what to look at

## Common mistakes

- **Working while they watch the FileSystem dock.** The race is invisible
  until the character is a T-pose.
- **Trusting a green suite for a material regression.** Structural tests
  see the skeleton, not the shading; capture a frame.
- **Fixing "Unrecognized UID" by deleting the uid.** That trades a loud
  error for a silent re-import on the next machine. Give the resource a
  real uid instead.
