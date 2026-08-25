@tool
class_name SpawnPoint
extends Marker3D

# The level's own respawn marker, now wearing the same editor preview as a
# Checkpoint -- in purple -- so the two read as the same idea at a glance.
#
# ⚠️ DIFFERENT SEMANTIC, SHOWN HONESTLY: the respawn puts the BODY ORIGIN
# (capsule centre) at this node, so the preview capsule hangs 0.9 m BELOW
# the marker -- every existing level placed its marker under that
# convention (e.g. arena_builder's y = 1.0 over a floor top at 0.5).
# A Checkpoint instead respawns feet-at-origin. Do not "fix" either one to
# match the other without moving every placed marker.

func _ready() -> void:
	if Engine.is_editor_hint():
		RespawnPreview.build(self, Color(0.75, 0.4, 1.0), -0.9)
