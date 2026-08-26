---
name: godot-ui-layout-traps
description: Use when building Godot UI from code and a panel lands in the top-left corner or is invisible, when clicks do nothing but the keyboard works, when a hidden CanvasLayer still swallows input, or when a decoration draws on top of the text it should sit behind.
---

# Godot UI layout traps

## Overview

Four Godot UI behaviours produce bugs that look like design mistakes rather
than API mistakes. Each one has bitten this repo at least once, and two of
them bit twice.

## Quick reference

| Symptom | Cause | Fix |
|---|---|---|
| Panel hangs off the top-left; only part is on screen | `set_anchors_preset()` sets anchors but **not** offsets, so the node keeps size 0×0 | `set_anchors_and_offsets_preset()` |
| Mouse does nothing, keyboard works | A full-rect root `Control` defaults to `MOUSE_FILTER_STOP` and eats the clicks | `mouse_filter = Control.MOUSE_FILTER_IGNORE` on containers |
| Hidden menu still handles Up/Down/Enter | `CanvasLayer.visible` does **not** cascade to child `Control`s | Flip every child's `visible` too; gate input on `is_visible_in_tree()` |
| Backdrop draws over the labels | A `top_level` canvas item draws above the whole subtree | Make decorations plain local children in draw order |

## The one that hides itself

`set_anchors_preset(PRESET_FULL_RECT)` looks right and behaves right *as a
scene root*, because Godot gives a root `Control` the viewport rect for
free. The bug only appears once the same node becomes a **child** — its size
stays 0×0, and anything centred inside it centres on the corner.

That is why it survived one round of verification here: the settings page
was checked in a standalone preview scene, where it was the root. The real
hosts (pause menu, main menu) parent it, and there it lived in the corner.

**Rule: verify UI inside its real host, not in a preview scene where it is
the root.**

## Visibility has two truths

```gdscript
# CanvasLayer is not a CanvasItem: this flag renders, and nothing else.
func _set_shown(on: bool) -> void:
    visible = on            # rendering
    _backdrop.visible = on  # every child, for every script-side check
    _menu_list.visible = on
```

And every input handler on a UI node gates on the honest one:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
```

Without both halves, a menu nobody can see keeps consuming Enter — which
reads as "the game randomly starts a level".

## Common mistakes

- **Verifying a headless build for a layering question.** Draw order needs a
  rendered frame; see `verifying-visuals-headlessly`.
- **Using `visible` where `is_visible_in_tree()` is meant.** The first is a
  local flag, the second is the question you actually have.
- **Reaching for `top_level` to escape a container.** It escapes draw order
  too.
