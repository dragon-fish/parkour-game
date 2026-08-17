class_name TuningPreset
extends Resource

# On-disk shape for a saved F1 panel preset: an explicit path->value mapping
# rather than a serialized MovementConfig.
#
# ResourceSaver.save(config, path) was the original approach, but
# ResourceSaver omits any property whose value equals its DECLARED default --
# and a move's _init() can set a value that differs from what its base class
# declares (CrouchConfig sets speed_modifier = 0.4 in _init(), while
# MoveConfig declares the property with default 1.0). A preset in which the
# user tuned crouch speed to exactly 1.0 would then never be written to the
# .tres, and reloading it would silently restore 0.4 -- a tuned value lost
# with no error. Storing the whole set of tunables as one Dictionary keyed by
# dotted path sidesteps per-property default-skipping entirely: the only
# thing ResourceSaver can omit is the `values` Dictionary itself, and that
# only happens if it is empty.
@export var values: Dictionary = {}
