extends SceneTree

# Generates scenes/player/player.tscn. Scenes are built in code rather than by
# hand so the whole project is reproducible without an editor session.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_player_scene.gd
#
# NOT one-shot: this is re-run on every phase of the project, same as
# tools/build_main_scene.gd. Anything a human wires up by hand in the editor
# (the character model, its AnimationTree -- see below) belongs IN THIS FILE,
# or the next regeneration silently discards it.

const OUTPUT := "res://scenes/player/player.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/player/player.gd"))

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	shape.shape = capsule
	player.add_child(shape)
	shape.owner = player

	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(load("res://scripts/camera/camera_rig.gd"))
	# Baked from MovementConfig's own default rather than a separate literal,
	# so this scaffold can never drift from the value CameraRig.setup() will
	# overwrite it with at runtime anyway. eye_height above the capsule centre
	# puts the view near the top of a 1.8 m body without clipping through the
	# collision shape; the F1 panel can tune it live from here.
	rig.position = Vector3(0.0, MovementConfig.new().eye_height, 0.0)
	player.add_child(rig)
	rig.owner = player

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	cam.owner = player

	# Mount point for the visible character body. Originally reserved empty
	# for the P5 procedural first-person body; now also where the
	# AnimationTree driving it lives (the body mesh itself is instanced
	# directly under the player root below, matching the owner's own
	# hand-wired arrangement -- see the AnimationTree's root_node/anim_player
	# NodePaths just below for why).
	var body_root := Node3D.new()
	body_root.name = "BodyRoot"
	player.add_child(body_root)
	body_root.owner = player

	# --- Character animation ---------------------------------------------
	#
	# Moved here from a hand-edited scenes/player/player.tscn: this file is
	# generator OUTPUT (see the module comment above), so a hand edit to it
	# is silently discarded the next time anyone regenerates the scene. This
	# block reproduces that hand-wiring so regeneration can no longer lose it.
	#
	# Three animations only (idle/run/jump) -- see
	# scripts/player/character_animator.gd for the driver that actually
	# selects between them at runtime; this block only builds the graph.
	var idle_anim := AnimationNodeAnimation.new()
	idle_anim.animation = &"idle"
	var jump_anim := AnimationNodeAnimation.new()
	jump_anim.animation = &"jump"
	var run_anim := AnimationNodeAnimation.new()
	run_anim.animation = &"run"

	var state_machine := AnimationNodeStateMachine.new()
	state_machine.add_node("idle", idle_anim)
	state_machine.add_node("jump", jump_anim)
	state_machine.add_node("run", run_anim)

	# advance_mode = ENABLED, deliberately NOT the AUTO the owner's hand-wired
	# graph used (advance_mode = 2 in the .tscn diff this block replaces).
	# Verified experimentally: with AUTO and no advance_condition set, a
	# transition fires the instant it is evaluated -- not when its animation
	# finishes -- so an AUTO Start->idle->run->End chain races itself to End
	# within a single physics frame regardless of what CharacterAnimator asks
	# for, making idle and run permanently unreachable. ENABLED transitions
	# never fire on their own; travel() calls from CharacterAnimator are the
	# only thing that ever moves this graph, which is the whole point of
	# giving it a driver.
	var start_to_idle := AnimationNodeStateMachineTransition.new()
	start_to_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	state_machine.add_transition("Start", "idle", start_to_idle)
	var idle_to_run := AnimationNodeStateMachineTransition.new()
	idle_to_run.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	state_machine.add_transition("idle", "run", idle_to_run)
	var run_to_end := AnimationNodeStateMachineTransition.new()
	run_to_end.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	state_machine.add_transition("run", "End", run_to_end)

	var anim_tree := AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.tree_root = state_machine
	# Every other system in this project (movement, camera, probes) runs
	# exclusively off _physics_process, which is also what tests/test_case.gd's
	# step() advances -- an AnimationTree left on its IDLE-process default
	# would never see a frame in a headless physics-only test loop (verified:
	# it simply never processes, so travel() calls have nothing to apply
	# them). PHYSICS keeps this node consistent with the rest of the project
	# and testable the same way.
	anim_tree.process_callback = AnimationTree.ANIMATION_PROCESS_PHYSICS
	# active defaults to true (verified), so this is a no-op today -- kept
	# explicit because "the tree actually plays" is load-bearing enough to
	# state rather than leave to a default a future Godot version could flip.
	anim_tree.active = true
	body_root.add_child(anim_tree)
	anim_tree.owner = player

	# Standing-clearance probe: a capsule the size of the STANDING body, tested
	# in place. A ray would miss geometry the capsule's radius would hit.
	# Duplicated from the body capsule (not a separate 1.8/0.4 literal) so the
	# probe can never silently drift out of sync with the actual body size.
	var clearance := ShapeCast3D.new()
	clearance.name = "StandClearance"
	clearance.shape = capsule.duplicate()
	clearance.target_position = Vector3.ZERO
	clearance.enabled = true
	player.add_child(clearance)
	clearance.owner = player

	player.camera_rig = rig

	# Probe rig. Heights are expressed relative to the body origin, which sits
	# at the capsule centre — feet are 0.9 m below it.
	#
	# Every ray's LENGTH, and SurfaceDown's whole vertical placement, is
	# recomputed from the live MovementConfig on every query (see probes.gd's
	# _aim_forward()/_query_surface()), because the F1 tuning panel writes into
	# that config while the game runs. The values baked here are therefore only
	# the scene's initial state, never the values the queries actually use —
	# they are written to match the shipped defaults so the scene file reads
	# sensibly in an editor, not because anything depends on them.
	var probes := Node3D.new()
	probes.name = "Probes"
	probes.set_script(load("res://scripts/player/probes.gd"))
	player.add_child(probes)
	probes.owner = player

	# Forward ray at shin height: does something block the way at all?
	# World y = feet + 0.35 (body origin sits at feet + 0.9). An obstacle
	# shorter than that -- a kerb, a low curb -- passes entirely under this
	# ray and is invisible to vault_query() no matter how low vault_max_height
	# allows; it reads as "nothing ahead", not "too short to vault". This is a
	# real, intentional limit of a two-ray shin/chest rig, not a bug: obstacles
	# that short are already walkable over.
	var vault_low := RayCast3D.new()
	vault_low.name = "VaultLow"
	vault_low.position = Vector3(0.0, -0.55, 0.0)
	vault_low.target_position = Vector3(0.0, 0.0, -1.4)
	vault_low.enabled = true
	probes.add_child(vault_low)
	vault_low.owner = player

	# Forward ray at chest height: if THIS hits too, the obstacle is a wall,
	# not something to vault.
	var vault_high := RayCast3D.new()
	vault_high.name = "VaultHigh"
	vault_high.position = Vector3(0.0, 0.45, 0.0)
	vault_high.target_position = Vector3(0.0, 0.0, -1.4)
	vault_high.enabled = true
	probes.add_child(vault_high)
	vault_high.owner = player

	# Downward ray from above and ahead: finds the top surface to land on.
	#
	# The start height is load-bearing, which is exactly why probes.gd derives
	# it from the config at query time rather than trusting what is baked here.
	# Heights in MovementConfig are measured from the FEET, which sit 0.9 m
	# below this origin, so a ledge at the configured maximum of 2.8 m sits at
	# +1.9 m here. An origin BELOW the highest reachable ledge means tall ledges
	# are silently never detected — and the panel can drive ledge_max_height to
	# three times its default, so a fixed origin would put the knob past the
	# ray's sight without any sign that it had stopped working. The values here
	# are what probes.gd's derivation produces at the shipped defaults.
	var surface := RayCast3D.new()
	surface.name = "SurfaceDown"
	surface.position = Vector3(0.0, 2.2, -1.0)
	surface.target_position = Vector3(0.0, -3.2, 0.0)
	surface.enabled = true
	# Without this, a wall/overhang tall enough to swallow this ray's ORIGIN
	# (world y = feet + 3.1 -- e.g. anything with a surface above feet + 3.1
	# directly ahead) is invisible to the ray entirely: RayCast3D does not
	# report a hit for a shape it starts inside by default, so the ray simply
	# passes through the wall and reports whatever is below it (the floor, or
	# nothing), and vault_query()/ledge_query() would then reason about THAT
	# surface instead of correctly finding no valid vault/ledge. Verified: with
	# this off, an 8 m wall's "no ledge" result came from the floor at y=0
	# sneaking under ledge_min_height, not from ledge_max_height rejecting the
	# wall -- the upper bound had no real coverage. With this on, the ray
	# reports its own origin as the hit when it starts inside solid geometry,
	# which is what lets the height bounds actually reject it.
	surface.hit_from_inside = true
	probes.add_child(surface)
	surface.owner = player

	# Side rays for wall detection, at chest height so a low kerb never counts
	# as a wall. Local +X is the body's right.
	var wall_left := RayCast3D.new()
	wall_left.name = "WallLeft"
	wall_left.position = Vector3(0.0, 0.2, 0.0)
	wall_left.target_position = Vector3(-0.75, 0.0, 0.0)
	wall_left.enabled = true
	probes.add_child(wall_left)
	wall_left.owner = player

	var wall_right := RayCast3D.new()
	wall_right.name = "WallRight"
	wall_right.position = Vector3(0.0, 0.2, 0.0)
	wall_right.target_position = Vector3(0.75, 0.0, 0.0)
	wall_right.enabled = true
	probes.add_child(wall_right)
	wall_right.owner = player

	player.probes = probes

	# The visible mesh: instanced directly under the player root (a sibling of
	# BodyRoot, not a child of it) because that is where the owner's own
	# hand-wired copy put it -- reproduced as-is rather than moved under
	# BodyRoot, which would only have changed the AnimationTree's
	# root_node/anim_player NodePaths for no behavioural gain.
	var body_scene: PackedScene = load("res://scenes/player/whine_fox_player_nohead.tscn")
	var body := body_scene.instantiate() as Node3D
	body.name = "wine_fox"
	body.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.85626817, 0.1185838))
	player.add_child(body)
	body.owner = player
	# An instantiated sub-scene keeps its own internal ownership; marking only
	# the instance root is what makes it serialise as an instance rather than
	# an expanded copy (same reasoning as arena_builder.gd's Player instance).

	# NodePaths computed rather than hardcoded so they can never drift from
	# the actual hierarchy built above.
	anim_tree.root_node = anim_tree.get_path_to(body)
	anim_tree.anim_player = anim_tree.get_path_to(body.get_node("AnimationPlayer"))

	# Drives the state machine above from the player's real movement state
	# every physics tick -- see scripts/player/character_animator.gd.
	var animator := Node.new()
	animator.name = "CharacterAnimator"
	animator.set_script(load("res://scripts/player/character_animator.gd"))
	body_root.add_child(animator)
	animator.owner = player
	animator.anim_tree = anim_tree
	animator.player = player

	DirAccess.make_dir_recursive_absolute("res://scenes/player")
	var packed := PackedScene.new()
	var pack_error := packed.pack(player)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)
