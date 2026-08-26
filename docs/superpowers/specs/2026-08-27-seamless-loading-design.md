# Seamless loading — design

The rule this serves is in [docs/seamless-loading.md](../../seamless-loading.md)
and is not restated here. In one line: **nothing dead on screen, and nothing
that drops a frame, while the player cannot act.**

## Scope

**In:** the ordinary path — main menu → 开始游戏 → a level. The run-up show
must cover *all* of the real loading, so that the curtain is a visual effect
and not a wait.

**Out, and deliberately:** the first-launch tutorial (the crouched silhouette
standing up in the void, geometry arriving around a player who can already
walk). ✅ THE OWNER placed it: "我刚刚说的这一套是第一次进入游戏的新手教学关卡，
它是一次性的… 后面再进入就是正常的现在的逻辑." That is CONTENT which happens to
embody the same rule, and it needs its own spec. It is also the strongest
version of this design — it has no transition at all — so nothing here should
make it harder to build later.

**Also out:** level → level, respawn, and the death curtain. The death sequence's
"you cannot act" is authored, not incidental.

## Where it stands, measured

From a click on 开始游戏 (real run, the `[load]` prints):

| Stage | Cost | Covered by the run? |
| --- | --- | --- |
| Threaded load of the level + dependency tree | ~80 ms | **yes** — `_poll_loading` holds the curtain, and the run clip loops |
| `Arena._ready()` — body, animation graph, course, markers | **255 ms** (was 2489) | **no** — runs after the scene swap |
| First frames actually drawn — pipeline compilation | instrumented, unread | **no** |
| Curtain: 0.7 s fade in, 0.6 s lift | 1.3 s | it *is* the dead time |

Two of the four are outside the show, and the third is the curtain itself.

## Design

### 1. The level is built while the menu is still running

After the threaded load resolves — with the run-up still playing — the level is
instantiated and added to the tree **next to** the menu rather than in place of
it. `Arena._ready()` therefore runs during the show. This is the whole idea; the
rest of the design is what it takes to be safe.

Checked, not assumed: two scenes can be alive at once, `current_scene` is a
writable convenience pointer, and `change_scene_to_packed` frees the outgoing
scene because it chooses to, not because Godot requires it.

### 2. The level says when it is playable

A narrow autoload — one signal, `level_ready(level: Node)` — that `Arena` emits
at the end of its own setup. The curtain listens with `CONNECT_ONE_SHOT`, which
is the `once()` in ✅ the owner's own sketch of this ("让加载窗口去监听
`once('player:spawn', …)`").

Narrow on purpose. A general `EventBus` starts rotting at its third signal;
this one exists because a level genuinely should not know a transition exists.

### 3. The curtain becomes a wipe

Once `level_ready` has arrived, promotion is: set `current_scene`, unlock the
level, free the menu. All of that is one frame's work, so the curtain covers a
swap rather than a load. Its timings come down accordingly — but **only because
the dead time shrank, never to shave seconds off a show that is doing its job.**

### 4. Pipelines are warmed inside the show

A material compiles its pipeline the first time it is genuinely drawn, so a
level that is loaded and hidden is still not ready. While the run-up plays and
the level is already built, it is rendered for a few frames into a
`SubViewport` nobody sees, so the compilation lands inside the show.

This is the part with the least evidence behind it: the cost is unknown, because
every measurement so far has been headless and headless has no renderer. **The
first-draw numbers from a real run decide whether this section is a priority or
a footnote**, and it is written last for that reason.

## The hard parts

| Problem | Answer |
| --- | --- |
| Menu and level share one `World3D`, so the level renders into the menu's view and its bodies live in the menu's physics space | The level is built inside a `SubViewport` with `own_world_3d`, which also gives §4 somewhere to draw. Promotion re-parents it into the root world. ⚠️ **Re-parenting rebuilds every physics body**, which could hand back the cost we just moved — measure it before committing, and fall back to "same world, hidden root, no warming" if it does |
| `Arena._ready()` grabs the pointer (`Input.mouse_mode = CAPTURED`) | It already guards on `capture_mouse`; the transition builds the level with that off and enables it at promotion |
| The level ticks physics and moves behind the menu | `process_mode = DISABLED` on the level root until promotion |
| The level's audio starts under the menu's music | Muted on its own bus until promotion |
| The player is live and taking input behind the curtain | Already fixed: `lock_input()` for the curtain's duration, which gates movement AND `apply_look` |

## Not in v1

- Slicing `Arena._ready()` across frames. At 255 ms it does not break the
  invariant; the instrumentation stays so that a future level which does break
  it says so.
- Keeping the run-up show alive across the swap (an autoload-hosted show). That
  machinery exists to survive a scene change, and §1 removes the need. It comes
  back if level → level is ever in scope.
- Streaming. The levels here are hand-authored and discrete, as Mirror's Edge's
  own are.

## How we will know it worked

- **The frame rule:** `PauseUi` already times the first twenty frames of a new
  level and prints any over 50 ms. Zero of those, from click to playable.
- **The dead-screen rule:** the curtain may only start after `level_ready`. That
  is a code path, and a test can assert the ordering without measuring time.
- **The funnel:** the unskippable stretch between clicking 开始游戏 and having
  control, reported by the existing `[load]` prints. It is recorded, not
  targeted — ✅ "漏斗不是计算绝对时间长短，你得考虑体感时间."

## Open questions for the owner

1. **Does the run-up become interruptible?** A first-time player wants the whole
   show; a twentieth-time player may not. This is a design call, not a
   performance one, and it is the one place where absolute seconds legitimately
   matter.
2. **What plays if a level ever loads slower than the show is choreographed
   for?** The run clip loops and the camera holds, which is survivable but not
   authored. It only becomes real with a much larger level.
