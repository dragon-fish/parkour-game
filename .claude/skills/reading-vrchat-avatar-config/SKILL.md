---
name: reading-vrchat-avatar-config
description: Use when a bought or downloaded VRChat/Unity avatar needs its settings recovered in another engine — jiggle physics, collider shapes and sizes, bone constraints, viewpoint height, which chain collides with what — or when tempted to eyeball a value the author already tuned. Covers reading `.unitypackage` and `.prefab` files directly.
---

# Reading a VRChat avatar's own configuration

## Overview

A bought avatar arrives fully tuned — for Unity. The settings are not lost,
they are sitting in plain YAML inside the archive, and reading them beats
guessing every time. The author sized a head collider against *this* skull;
tuning it by eye means working against the same skull with less information.

**But not everything transfers.** The split is sharp, and knowing which side
a value falls on is most of the work — see *What transfers* below.

## Cracking the archive

A `.unitypackage` is a gzipped tar. Each asset is one directory named by its
GUID, holding `asset` (the bytes), `asset.meta` (import settings) and
`pathname` (its original path). Build the map first, then read what you need:

```python
import tarfile, re
t = tarfile.open("avatar.unitypackage", "r:gz")
paths = {m.name.split("/")[0]: t.extractfile(m).read().decode("utf8").split("\n")[0]
         for m in t.getmembers() if m.name.endswith("/pathname")}
guid = next(g for g, p in paths.items() if p.endswith(".prefab"))
prefab = t.extractfile(guid + "/asset").read().decode("utf8", "replace")
blocks = re.split(r"\n--- ", prefab)          # one Unity object each
```

Every block starts `!u!<classId> &<fileID>`. Resolve `m_GameObject` through
the `!u!1` (GameObject) blocks to get the name a component is attached to —
without that step you have parameters belonging to nothing.

## Where each kind of setting lives

| Want | Where | How to recognise it |
|---|---|---|
| Materials, colour | `Material/*.mat` | See `porting-unity-materials` |
| Jiggle physics | `.prefab`, MonoBehaviour, VRCPhysBone script GUID | has a `pull:` field |
| **Colliders** | same GUID, same file | has **no** `pull:` — `shapeType` 0/1/2 = Sphere/Capsule/Plane |
| Which chain hits which collider | that bone's own `colliders:` list | fileIDs into the collider components |
| Bone constraints | Unity classes `1773428102` / `1818360609` / `895512359` | Parent / Rotation / Aim constraint |
| Viewpoint, visemes | VRCAvatarDescriptor MonoBehaviour | `ViewPosition`, `VisemeBlendShapes` |

Collider and physics components share one script GUID. The `pull:` field is
what separates them, and skipping that check silently mixes the two lists.

## What transfers and what does not

**Geometry transfers. Dials do not.**

Take: collider shape, radius, height, offset; joint radii; viewpoint height;
the chain-to-collider mapping. These are measurements of a specific model,
and they are worth more than anything tuned by eye.

Leave: VRCPhysBone's `pull` / `spring` / `stiffness` / `immobile`. That is a
pull-toward-rest plus spring-back model; Godot's `SpringBoneSimulator3D` has
`stiffness` / `drag` / `gravity`. **The dials are not isomorphic**, and
carrying the numbers across one-for-one produces something that resembles
neither engine's result. Port the *feel* by eye; port the *sizes* by file.

## Two traps

**A field that looks like a switch may not be one.** `_UseOutline: 0` sat in
five materials that visibly had outlines — the shader variant decided, not
the field. Before trusting any boolean, ask what actually reads it.

**Decoration is not body.** Every PhysBone on a VRChat avatar hangs off hair,
wings, skirt hems, ears. The body's own joints carry **no angular limits**,
because VRChat has no ragdoll — so an avatar cannot hand over a ragdoll's
joint cones. It *can* hand over the collider capsules mounted on arms, legs
and head, which is exactly the sizing a ragdoll otherwise derives from bone
length and gets wrong.

## Common mistakes

- **Reading parameters without resolving the owner GameObject.** A table of
  numbers with no bone names attached cannot be checked or used.
- **Eyeballing a value the file already holds.** Head collider radius, hem
  stiffness, viewpoint height — all shipped.
- **Assuming the bone names match.** The prefab says `UpperArm.L`; the same
  rig imported through a bone map is `LeftUpperArm`. Read the names off the
  imported skeleton, not the prefab.
