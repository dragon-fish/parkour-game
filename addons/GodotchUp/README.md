# GodotchUp

Drag on a surface. A solid is laid flush against it.

Godot's 3D viewport has no drag-to-create gesture: every new node is born at
the world origin and dragged into place. This adds the gesture and stops
there — the solid comes out one grid step thick and **Godot's own handles**
pull it to height.

## Why another blockout addon

[Cyclops Level Builder](https://github.com/blackears/cyclopsLevelBuilder) is
the mature answer and does far more than this. It also locks the editor's
input up on macOS — [upstream #242][242] is open, its author has no Mac, and
two attempted fixes did not take. This was written on a Mac because of that,
and is a fraction of the size because it deliberately does one thing.

[242]: https://github.com/blackears/cyclopsLevelBuilder/issues/242

## Install

Copy `addons/GodotchUp/` into your project and enable **GodotchUp** in
*Project Settings → Plugins*. Godot 4.7.

## Use

A checkbox and a shape picker appear on the 3D viewport's toolbar.

| | |
|---|---|
| Tick the checkbox | drags now draw |
| Drag on any surface | box corner to corner; cylinder and sphere centre to rim |
| Release | the solid is created, selected, and the tool disarms |
| Any modifier held | the editor's own box select, unchanged |
| `Esc` / right click | cancel the drag |

`grid` snaps the drag, in metres; `0` disables snapping. `thick` is how thick a
new solid starts. Both are remembered per project.

The picker to the right chooses **CSG** or **Collision**:

- **CSG** — `CSGBox3D` / `CSGCylinder3D` / `CSGSphere3D`, collision on.
- **Collision** — a `CollisionShape3D`. Drawn onto an `Area3D` or a body it
  becomes that node's child; anywhere else it becomes a sibling of whatever is
  selected.

New nodes land beside the selection, never inside it, so a run of solids stays
in one place instead of nesting.

## Notes

- Surfaces are found by intersecting **mesh triangles**, not physics, so
  anything visible can be drawn on whether or not it has a collider. The
  editor runs no physics step, which is why a raycast would find nothing.
- Nothing under the cursor falls back to the world's `y = 0` plane. Laying out
  a floor plan on open ground is how a level starts.
- The tool disarms after every solid, because the next thing anyone does is
  pull the thing they just drew to height.

## Credits

The editor-viewport raycast follows the approach taken by **Godot 3D Cursor**
(Dev-Marco, ISC) — cull mesh instances against the ray, then intersect their
triangles. No code from it is included here.

MIT. See `LICENSE`.
