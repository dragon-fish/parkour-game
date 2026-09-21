# Running the original's Kismet

Kismet is Unreal Engine 3's visual scripting, the ancestor of Blueprints: a
graph of events, actions, conditions and variables stored in the map package,
advanced by impulses. An event fires, its outputs activate the inputs wired to
them, and each node either finishes at once or is *latent* (a Delay, a
matinee, a streaming action) and fires later. Mirror's Edge scripts almost
everything a level does this way: which button opens which door, when a
stretch of the level loads, when steam stops hurting.

An imported chapter runs that graph as the original did.

## Why it is run and not read

The extractor began by reading single facts out of the graph: which touch
starts this matinee, which trigger ends the level, which button unloads that
stretch. Each of those walks treated the graph as though it held no state, and
each was wrong wherever it did:

- A `SeqAct_Gate` with `bOpen = False` is shut until something further along
  opens it. Walked through as a passage, Stormdrain's first steel-door button
  unloaded the floor the player was standing on.
- A `SeqAct_Switch` with `IncrementAmount = 0` is a router whose outlet is an
  Int some other node sets; with `bLooping` it alternates. Walked as "any of
  its outputs", a lever did both things at once.
- A streaming action's `Finished` sends a remote event that opens a gate that
  lets a door open: the signal flows DOWNSTREAM of the thing being asked
  about. Stormdrain's pillar hall door waits for the hall to be loaded.
- Steam across a corridor is a pain volume and a `DynamicBlockingVolume`,
  both switched by `SeqAct_ChangeCollision` on the valve's button. Nothing
  read them, so the steam never stopped and the chapter could not be finished.

Every such fact is a consequence of running the graph. So the graph is
exported whole and interpreted, and the hand-written stand-ins (a `Lift` state
machine, a matinee's flattened starts) give way chapter by chapter.

## The pieces

| | |
| --- | --- |
| `docs/mirrors-edge-deep-research/tools/level_extract/kismet.py` | Exports every streamed package's Kismet as plain data: `kismet.json`, beside the manifest. Decides nothing about what a node means. |
| `scripts/level/kismet/kismet_graph.gd` | That data as a resource (`<id>_kismet.res`), so it loads compressed with the level and stays out of scene text. |
| `scripts/level/kismet/kismet_runner.gd` | The interpreter. What a node class MEANS is one `match` arm in `_run()`. |
| `scripts/level/package_presence.gd` | Which packages are in the level. The runner's streaming actions call it; its `settled` is their `Finished`. |
| `tools/me_level/shell_builder.gd` `build_streaming()` | Builds both into the chapter GEOMETRY, which is rebuilt every time, with an Area3D or UseZone for every actor an event listens to and a body for every wall only Kismet switches. |

### The data

```jsonc
{
  "nodes": { "<package key>#<export index>": {
      "cls": "SeqAct_Gate", "package": "stormdrain_std-stdp_slc_spt", "name": "SeqAct_Gate_0",
      "sequence": "<id of the Sequence it sits in>", "comment": "the designer's own",
      "ins":  ["In", "Open", "Close", "Toggle"],
      "outs": [ { "name": "Out", "to": [["<node id>", <input index>]], "delay": 0.5 } ],
      "vars": { "Target": ["<variable id>"] },
      "props": { "bOpen": false, "AutoCloseCount": 1 }   // the original's names
  } },
  "vars":   { "<id>": { "cls": "SeqVar_Object", "actor": "<package key>.<actor name>" } },
  "actors": { "<package key>.<actor name>": { "cls": "Trigger", "package": "...", "trigger": { ... } } }
}
```

`props` holds ONLY what differs from the class default, as a cooked export
does. The defaults are UE3's and the runner supplies them: an event's
`MaxTriggerCount` is **1** (it fires once unless it says 0), a Gate is open, a
Delay is one second. Assuming zero for a missing property is the easiest way
to get a level subtly wrong.

### Finding what a node refers to

A Kismet variable names an actor; the level has nodes. Everything the builder
makes from an actor carries `me_actor = "<package key>.<actor name>"` (and
`me_package`, and on a Matinee node `me_matinee`). A shell is edited by hand
and is NOT rebuilt, so a shell older than those stamps gets them at load: the
build reads them off a shell made in memory (`ShellBuilder.origins()`), they
ride on the chapter geometry, and `PackagePresence` puts them on the real
shell's nodes by path.

### Lifetimes

- **A package's Kismet exists only while the package is loaded.** Unloading
  forgets its nodes' state and drops what they had pending; loading fires its
  `SeqEvent_LevelLoaded`. This is how the original re-arms a door.
- **A respawn** forgets everything, lets `PackagePresence` take the
  checkpoint's snapshot, then starts the level again and fires that
  checkpoint's `SeqEvt_TdCheckpointLoaded`, which is how the original puts a
  level back.

### What is implemented

Control flow: `Gate`, `Switch`, `RandomSwitch`, `Delay`, remote events,
sub-sequences and their ports, `SetBool/Int/Float/String`, `CompareBool/Int/
Float`, `IncrementInt/Float`, named variables, output `ActivateDelay`.

Events: `Touch`/`TdTouch` (with `UnTouched`), `Used`/`TdUsed`, `TakeDamage`,
`LevelLoaded`, `TdCheckpointLoaded`, `SequenceActivated`. This project has no
use key and no gun: a press is standing in a `UseZone` for its dwell, a
damaged actor is run into.

Effects: `MultiLevelStreaming`/`LevelStreaming` -> `PackagePresence`;
`Interp` -> the `Matinee` node of the same sequence, with the event track
fired from the runner's own clock (so a sequence with nothing to move still
takes its time); `Toggle`, `ToggleHidden`, `ChangeCollision`, `Destroy` -> the
actor's nodes; `TdInElevator` -> no jump, no crouch, walking pace, and the body stood up as
an ordinary walking one whatever it was doing when the ride began;
`TdFallOnBack` -> `Status.Effect.KNOCKDOWN`, which is `LayOnGroundMove`;
`Teleport` -> the player only, stood on the floor under the destination -- an
actor the level has built is asked where it is, any other is where the export
says (moved to where a sequence that drives it has put it by then).

**Everything else passes the signal straight on** -- its first output, and any
`Finished` -- which is right for the hundred kinds with nothing to act on here
(AI, sound, weapons, camera). Each is counted in `KismetRunner.unknown`, shown
on the debug HUD's `kismet` row, so what is missing is read off rather than
guessed at. Teaching the runner a class is one arm of `_run()` and a test in
`tests/test_kismet_runner.gd`.

### What it replaces, and what it does not yet

In a chapter that has a graph (`split_sections`):

- every `Matinee` the graph plays is taken over (`Matinee.take_over()`): its
  own trigger areas, followers and autostart were read out of the same graph
  and would fire a second time;
- no `Lift` is built. The lift's sequence is built like any other and the
  graph plays it -- button, doors, streaming, the rider's restrictions.

Still read out of the graph rather than run by it: the level's end
(`level_end`), breakable glass, what rides a mover, and the config's
`checkpoint_restores` and `teleports`. Each is a candidate to give way, one at
a time, and none needs the others to.

## Debugging a level

- HUD: `packages` (what is loaded, what changed it last) and `kismet` (timers
  waiting, sequences playing, loads in flight, kinds passed through).
- F3 draws every event zone, labelled "Kismet 事件".
- `KismetRunner.trace = true` prints every event and activation with the
  designer's comment. A chapter fires hundreds on one button; grep for the
  package you care about.
- `[presence]` lines in the log say what loaded, what unloaded, and the id of
  the streaming action that asked.
