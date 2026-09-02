---
name: authoring-godot-scene-files
description: Use when hand-writing or scripting edits to .tscn / .tres / .import files, when a model imports as a T-pose or loses its materials, when "invalid UID" appears in the log, or when properties vanish after the Godot editor re-saves a scene.
---

# Authoring Godot scene files by hand

## Overview

Godot's text formats are editable by hand, and an agent working headlessly
often must. They are also full of traps that fail **silently**: the scene
still loads, nothing errors, and some behaviour is just gone.

Core principle: **a hand-authored scene file is not verified until something
loads it and reports what it found.**

## Quick reference

| Trap | Symptom | Rule |
|---|---|---|
| Invented `uid://` | `invalid UID: 'uid://mymat' - using text path instead`, later a red test suite | Never type a uid. Omit the field; Godot assigns one on import |
| Stale `.godot/uid_cache.bin` | The invalid-uid error survives fixing the file | Delete the cache and the affected `.godot/imported/*` and re-import |
| `script=` inside the node header | `Parse Error` on the line after the node | `script` is a property line, not a header field |
| Nested-array literal in a property | `Parse Error` | Packed arrays take flat args: `PackedStringArray("a", "b")` |
| `PackedStringArray` export | Editor re-save silently drops the whole line | Prefer `Array[String]` for exported lists |
| Import settings in `.import` | T-pose, grey model, wrong scale | `_subresources` (`retarget/bone_map`, material remaps) lives only here; back it up before a first-time import |
| Editor re-save generally | Any hand-written property may disappear | After editing a scene in the editor, run the structural test for it |

## The editor is not a safe round-trip

The Godot editor rewrites a scene it saves. It preserves what it understands
and drops what it thinks equals a script's default. A `PackedStringArray`
export came back empty from that round-trip in this repo — four spring-bone
groups lost every prefix, so a character lost all secondary motion, with no
error anywhere.

Two defences, both cheap:

1. **Type exports the editor round-trips reliably.** `Array[String]` over
   `PackedStringArray` for anything a scene sets.
2. **Warn when a config resolves to nothing.** A group that finds zero
   entries should say so:

```gdscript
if chains.is_empty():
    push_warning("%s found no chains for prefixes %s" % [name, chain_prefixes])
```

Silence is what made the failure expensive; the warning makes it a log line.

## Verify by loading, not by reading

A structural test is the only honest check. Keep it tolerant of machines
that lack the asset, so a clone still runs green:

```gdscript
func test_every_spring_group_finds_chains() -> void:
    if not ResourceLoader.exists(WRAPPER):
        pass_test("no local body wrapper to check")
        return
    var body: Node3D = (load(WRAPPER) as PackedScene).instantiate()
    add_child_autofree(body)
    await step(2)  # deferred builds have not run on frame 0
    for child in skeleton.get_children():
        if child is SpringBoneSimulator3D:
            assert_gt(child.setting_count, 0, "%s built no chains" % child.name)
```

## Keep asset-specific work out of the importer

`.import` is the fragile file: it is regenerated, often untracked, and one
first-time headless import can wipe `_subresources`. Put there **only** what
nothing else can hold — the bone map, external material remaps. Everything
else (materials, modifiers, attachment points, physics) belongs in a
**wrapper scene** that instances the model. The wrapper is an ordinary scene
file: it survives re-imports, and it is the single place to change the model.

## A crash on click is a UI path, not bad data

An editor that dies reliably when you click one property is accusing its own
inspector, not your file. Before touching the data, load the same scene with a
rendering run and see whether it is fine:

```sh
<engine> --path . --resolution 640x360 --quit-after 180 \
    --script res://tools/capture.gd -- <scene> <out.png> 60
```

If that renders, the resource is sound and the fault is in how the editor is
displaying it -- so the fix is to change the SHAPE of the display, not the
content.

**Known: nested resource inspectors crash on ShaderMaterial (Godot 4.7.1).**
Reaching a material through `MeshInstance3D -> Mesh -> Material` is three
inspector levels deep, and expanding that last one logs

```
Object was freed or unreferenced while a signal is being emitted from it
Cannot connect to 'property_list_changed': 'EditorInspector::_changed_callback'
```

then collapses the group; clicking again takes the editor down. It survives
restarts and deleting `.godot/editor/editor_layout.cfg`, because nothing is
cached -- the crash is the click.

**Put the material on the NODE instead**, where it is a top-level property:

```
[node name="Mesh" type="MeshInstance3D"]
mesh = SubResource("BoxMesh_floor")
material_override = ExtResource("1_mat")
```

Both spellings are legitimate API and mean different things -- `mesh.material`
belongs to the mesh and travels with it to every instance, `material_override`
belongs to this node. For a mesh used in one place they are equivalent, so
prefer the override and stay out of the nesting.

DO NOT go hunting through shader code for this. Two evenings were lost to
suspecting a shader edit, an import cache and an editor layout file in turn,
while the same scene rendered perfectly from the command line the whole time.

## Common mistakes

- **Typing a memorable uid** (`uid://beriulmatbody`). It parses, loads by
  path, and poisons every suite that touches the scene.
- **Trusting a passing test after an editor save.** The test that passes may
  not cover the property that vanished.
- **Reading the file to confirm a fix.** Load it and print what came back.
