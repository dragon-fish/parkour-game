extends SceneTree

# Generates scenes/player/player.tscn. Scenes are built in code rather than by
# hand so the whole project is reproducible without an editor session.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_player_scene.gd
#
# One-shot scaffolding: once the .tscn exists it is the source of truth, and
# re-running this would discard any later edits made in the editor.

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

	# Reserved for the P5 procedural first-person body. Empty for now, but
	# present so adding a skeleton later does not restructure the scene.
	var body_root := Node3D.new()
	body_root.name = "BodyRoot"
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

	player.probes = probes

	DirAccess.make_dir_recursive_absolute("res://scenes/player")
	var packed := PackedScene.new()
	var pack_error := packed.pack(player)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)
