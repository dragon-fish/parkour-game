class_name SoftLandingConfig
extends MoveConfig

# [ME:CONFIRMED 12 §12.5] TdMove_SoftLanding's own CDO carries almost nothing
# either: PawnPhysics, ControllerState, and a look constraint. Every probe is
# off, which is what the neutral MoveConfig defaults already give -- a body on
# its way down with no say in the matter has no business grabbing a ledge, and
# declaring that here would be declaring a default.
#
# NO LOOK CONSTRAINT, though the CDO carries one (yaw +/-27.5 degrees). Input
# is gated for the whole state, so the view already does not respond; a clamp
# on top of that is inert. Same reading as FallUncontrolledMove's own note on
# where the view actually stops.
#
# NO FIELDS, deliberately. A soft landing is not a variation on the fall, it
# is the same fall with a different ending, and the ending is LandingMove's to
# describe -- so every dial this move could carry already lives there.
