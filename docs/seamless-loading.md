# Seamless loading

> ✅ THE OWNER: "我的追求类似于影视里的「一镜到底」，或者说「无缝加载」，我们要用
> 任何生动的东西覆盖玩家无法交互的时间。" And, put as a rule: "白屏转场其实只是
> 视觉效果，而不能在白屏期间其实还在加载别的东西让画面卡住，游戏在任何时间都不能
> 冻结在一个毫无意义的画面上."

This is a standing product constraint, not a feature. It outranks how fast any
particular thing loads: a two-second wait the player spends watching a character
run is acceptable, and a two-second wait on a white rectangle is not.

## The invariant has two halves, and only one of them is a number

**1. No frame may exceed the frame budget while the player cannot act.**

Measurable, fails loudly, does not care why. `PauseUi`'s transition times its
first twenty frames and prints any over 50 ms; the `[load]` prints in
`MainMenu`, `Arena._ready()` and `Player._attach_body` cover the CPU side.

**2. No time may be spent on a screen with nothing alive on it.**

⚠️ THE SECOND HALF IS NOT A WEAKER VERSION OF THE FIRST, and leaving it out was
a real mistake in the first draft of this document. A white sheet fading in over
0.7 s does not drop a single frame. It passes the first rule perfectly and
violates the whole point, because what makes a wait unbearable is not its length
but the player's inability to tell whether the game is still there.

✅ THE OWNER: "过场动画和活着的在奔跑的角色占用4-5s，给人的体感时间其实比白屏卡住
3s要好接受得多，没有任何可见内容、游戏窗口卡住，天然就会让人焦虑，你得考虑心理学
因素."

So the two are ordered, not weighed. **Kill dead screen time first, even if it
costs absolute seconds.** A frozen or empty frame is a different KIND of thing
from a long one, and no amount of arithmetic converts between them.

### What that ordering rules out

A tempting reading of half one is that the choreography is the expensive part:
by the clock, 3.5 s of entrance and 1.6 s of run-up dwarf the 335 ms of actual
loading. That reading is wrong and this document exists partly to say so. The
choreography is CONTENT -- it is the first thing that tells a player this game
is alive -- and `LOAD_MIN_RUN` is not a tax on the player, it is the show
having room to land. What to shorten is the part where nothing is happening.

## What the reference games actually do

Destiny 2's ship flight and Assassin's Creed's Animus room are not loading
*screens*. They are small, always-resident places you genuinely occupy, while
the world you are going to streams in behind them. Three consequences follow,
and they are the ones worth copying:

1. **The transition is a place, not a movie.** It keeps running for exactly as
   long as it needs to, because nothing about it is on a timer.
2. **The world arrives around a player who already exists**, rather than the
   player being created once the world is finished.
3. **Nothing blocking runs on the frame thread**, ever. Assets are pre-cooked,
   instantiation is sliced, and graphics pipelines are warmed before they are
   needed rather than compiled on first sight.

A crossfade API would not have bought any of this. The web's View Transitions
guarantee visual continuity and nothing else — a page whose script blocks the
main thread freezes on a beautiful snapshot instead of a white one.

## Where this project stands

Measured end to end, from a click on 开始游戏:

| Stage | Covered by the run-up? | Cost |
| --- | --- | --- |
| Threaded load of the level and its dependency tree | **Yes** — `_poll_loading` holds the curtain until it finishes, and the run clip loops, so this scales with the level | ~80 ms |
| `Arena._ready()` — body, animation graph, course, markers | **No** — runs after the scene swap, behind the curtain | 2489 ms → **255 ms** |
| First frames actually drawn (pipeline compilation) | **No** | instrumented, not yet read |

The 2489 ms was never a cost of loading anything. `Player._ensure_clip_loops`
deep-copied a 253-animation library once per clip name, forty-five times over,
to set forty-five booleans. It survived a long time precisely because the white
curtain made it look like loading — which is the failure mode this document
exists to prevent, and an argument for stating the invariant in frames.

## The shape that makes it structurally true

Godot imposes none of the usual obstacles, and this was checked rather than
assumed:

- **Two scenes can be alive at once.** `current_scene` is a writable
  convenience pointer, not a limit; `change_scene_to_packed` frees the old
  scene because it chooses to, not because it must.
- **A `SubViewport` with `own_world_3d` isolates one from the other**, so a
  loading show and a live level do not share a physics space or a render pass.
- **A hidden `CanvasLayer` costs nothing.** A resident 2D transition shell
  measured 0.0 MB and draws nothing while invisible; `PauseUi` is already one.
  A resident 3D show is a different matter — the body plus its animation
  library measured **65.2 MB**, so the show's content is built per transition
  and freed after, while the shell stays.

So: an autoload shell holds the curtain and an empty `SubViewport`; a
transition fills that viewport with the show; the level is built alongside the
still-running menu; the level emits `level_ready` when it can be played; only
then does the curtain wipe. `CONNECT_ONE_SHOT` is the `once()` in that
sentence.

**Resident is not the same as warm.** A material's pipeline is compiled the
first time it is genuinely drawn, so keeping a scene loaded and hidden leaves
the GPU half of it unprepared. Warming means drawing it once — which the show
provides the window for.

## Consequences for ordinary work

- A curtain may only lift on a signal that the thing behind it is ready. Never
  on a timer, and never on "the load finished" when work remains after it.
- Anything unavoidably slow on the frame thread gets sliced across frames, so
  whatever is on screen keeps moving.
- When something feels slow, instrument inside the process before theorising.
  Every out-of-process probe used on this path disagreed with itself by 34x.
  See the `[load]` prints, which stay.
