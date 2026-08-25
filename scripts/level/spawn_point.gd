@tool
class_name SpawnPoint
extends Marker3D

# The level's own respawn marker. The class exists so the respawn_gizmos
# editor plugin can recognise it and draw the purple capsule-and-arrow
# preview (clickable in the viewport, like any Marker3D).
#
# ⚠️ DIFFERENT SEMANTIC FROM A CHECKPOINT, drawn honestly by the gizmo: the
# respawn puts the BODY ORIGIN (capsule centre) at this node, so the preview
# capsule hangs 0.9 m BELOW the marker -- every existing level placed its
# marker under that convention (e.g. arena_builder's y = 1.0 over a floor
# top at 0.5). A Checkpoint instead respawns feet-at-origin. Do not "fix"
# either one to match the other without moving every placed marker.
