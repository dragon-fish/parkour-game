@tool
class_name SpawnPoint
extends Marker3D

# The level's own respawn marker. The class exists so the respawn_gizmos
# editor plugin can recognise it and draw the purple capsule-and-arrow
# preview (clickable in the viewport, like any Marker3D).
#
# Origin = BODY CENTRE, the same convention Checkpoint uses -- one rule for
# both respawn nodes.
