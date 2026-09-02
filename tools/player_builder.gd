class_name PlayerBuilder
extends RefCounted

# Builds the player's node tree in memory. This is the ONE place the player
# scene's layout is defined; nothing else may duplicate it.
#
# Extracted from tools/build_player_scene.gd for exactly the reason
# ArenaBuilder was extracted from tools/build_main_scene.gd: only a MainLoop
# subclass can run via --script, and a generator that can only be run as a
# whole script cannot be called from a test. Splitting the tree-building out
# lets tests/test_generated_scenes.gd build a fresh player IN MEMORY and
# compare it against the committed scenes/player/player.tscn, without the
# comparison itself ever writing to that tracked file.
#
# NOT one-shot: this is re-run on every phase of the project, same as
# ArenaBuilder. Anything a human wires up by hand in the editor belongs IN
# THIS FILE, or the next regeneration silently discards it -- with ONE
# deliberate exception: the visible character body and everything that depends
# on it (its AnimationTree, CharacterAnimator). See BodyRoot's own comment
# below for why those specifically must NOT be built here, and
# scripts/player/player.gd's body_scene/_attach_body() for where they moved.

func build() -> CharacterBody3D:
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
	rig.position = Vector3(0.0, MovementConfig.new().camera.eye_height, 0.0)
	player.add_child(rig)
	rig.owner = player

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	cam.owner = player

	# Full-screen tint/desaturation/blur layer. Lives under CameraRig -- i.e.
	# on the PLAYER, not the level -- because these effects describe what
	# happened to the body (a hard landing, a fatal fall) and must survive a
	# level change without fighting the level's own WorldEnvironment for the
	# same knobs. Its ColorRect child is built by ScreenEffects._ready()
	# itself, not here, so there is nothing more to scaffold for it.
	var fx := CanvasLayer.new()
	fx.name = "ScreenEffects"
	fx.set_script(load("res://scripts/camera/screen_effects.gd"))
	rig.add_child(fx)
	fx.owner = player

	# The centre dot, on the player for the same reason ScreenEffects is: it
	# describes this player's view and should follow them across levels. Its
	# Control child is built by Crosshair._ready(), not here.
	var crosshair := CanvasLayer.new()
	crosshair.name = "Crosshair"
	crosshair.set_script(load("res://scripts/ui/crosshair.gd"))
	rig.add_child(crosshair)
	crosshair.owner = player

	# The one-line text layer (checkpoint saves), on the player for the same
	# reason the two above are. Its Label child is built by Subtitle._ready(),
	# not here.
	var subtitle := CanvasLayer.new()
	subtitle.name = "Subtitle"
	subtitle.set_script(load("res://scripts/ui/subtitle.gd"))
	rig.add_child(subtitle)

	var toast := CanvasLayer.new()
	toast.name = "Toast"
	toast.set_script(load("res://scripts/ui/toast.gd"))
	rig.add_child(toast)
	subtitle.owner = player
	toast.owner = player

	# Mount point for the visible character body. Reserved empty for the P5
	# procedural/attachable first-person body, and it MUST STAY that way in
	# this generator: a specific character model is a licensing decision
	# (see docs/asset-candidates.md), never a movement-prototype concern, and
	# the committed player.tscn has to work -- body-less -- on a machine that
	# has never seen whatever model an owner happens to be experimenting with
	# locally. A committed reference to res://scenes/player/whine_fox_player_
	# nohead.tscn used to live in exactly this spot; that model turned out to
	# be CC BY-NC-SA (NonCommercial + ShareAlike, both incompatible with this
	# project), and the reference broke every clone that did not also have
	# the untracked model on disk. See scripts/player/player.gd's body_scene
	# export and _attach_body() for the supported replacement: a body (and
	# the AnimationTree/CharacterAnimator wiring it needs -- see
	# _wire_body_animation() there) is now instanced under here at RUNTIME,
	# from a LOCAL, untracked override (e.g. an inherited scene of this
	# player.tscn that sets body_scene), never from an edit to this
	# generator or its output.
	var body_root := Node3D.new()
	body_root.name = "BodyRoot"
	# body_root.gd is an editor-only @tool script: it previews body_scene (and
	# body_mount_offset/body_mount_rotation_degrees) live in the editor so an
	# owner can actually SEE and align a model, without pulling any of
	# Player's own runtime logic into @tool execution -- see its own file
	# header. It is a strict no-op everywhere Engine.is_editor_hint() is
	# false, which covers both a real running game and this generator's own
	# headless run, so attaching it here changes nothing about player.tscn's
	# runtime behaviour.
	body_root.set_script(load("res://scripts/player/body_root.gd"))
	player.add_child(body_root)
	body_root.owner = player

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
	player.screen_effects = fx
	player.subtitle = subtitle
	player.toast = toast
	crosshair.player = player

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
	# ray and is invisible to vault_query() no matter how low the vault table's
	# own floor allows; it reads as "nothing ahead", not "too short to vault".
	# This is a real, intentional limit of a two-ray shin/chest rig, not a bug:
	# obstacles that short are already handled by the free step-up (see
	# Player.try_step_up and vault_query()'s own lower bound).
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
	# sneaking under the grab's own lower bound, not from ledge_max_height
	# rejecting the wall -- the upper bound had no real coverage. With this on,
	# the ray reports its own origin as the hit when it starts inside solid
	# geometry, which is what lets the height bounds actually reject it.
	surface.hit_from_inside = true
	probes.add_child(surface)
	surface.owner = player

	# Downward ray for vault_query()'s vault-over/vault-onto probe: fired from
	# just above the vaultable obstacle's own top, vault_over_probe_distance
	# further along than SurfaceDown's own forward reach, to tell whether the
	# far side has ground to land on or is just more of the same obstacle.
	# Like every other probe ray, its actual geometry is recomputed from the
	# live config on every query (see probes.gd's _query_vault_over()) -- the
	# values baked here are only the scene's initial state, derived from the
	# shipped defaults (the vault table's own 1.3 m ceiling, vault_reach 1.4,
	# vault_over_probe_distance 0.5, foot offset 0.9) for a sensible-looking
	# scene file, not because anything depends on them.
	var vault_over_down := RayCast3D.new()
	vault_over_down.name = "VaultOverDown"
	vault_over_down.position = Vector3(0.0, 0.7, -1.9)
	vault_over_down.target_position = Vector3(0.0, -1.7, 0.0)
	vault_over_down.enabled = true
	probes.add_child(vault_over_down)
	vault_over_down.owner = player

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

	# FORWARD rays, for the wall you are running AT rather than the one you are
	# running ALONG. The two side rays above cannot answer that question: aimed
	# straight out to left and right, a head-on approach points them along the
	# wall's own face, where they hit nothing. See Probes.wall_ahead_query().
	#
	# Both are positioned and aimed per query from the live config, like every
	# other ray here -- the geometry set below is a placeholder that the first
	# query overwrites, kept only so the committed scene is not full of zeroes.
	var wall_ahead_low := RayCast3D.new()
	wall_ahead_low.name = "WallAheadLow"
	wall_ahead_low.target_position = Vector3(0.0, 0.0, -0.6)
	wall_ahead_low.enabled = true
	probes.add_child(wall_ahead_low)
	wall_ahead_low.owner = player

	var wall_ahead_high := RayCast3D.new()
	wall_ahead_high.name = "WallAheadHigh"
	wall_ahead_high.target_position = Vector3(0.0, 0.0, -0.6)
	wall_ahead_high.enabled = true
	probes.add_child(wall_ahead_high)
	wall_ahead_high.owner = player

	player.probes = probes
	return player
