@tool
class_name StatusSpec
extends Resource

# One line a level author fills in on a ModifierVolume: which effect, its
# payload, and how long it lasts. Which payload field an effect reads is
# documented once, above Status.Effect.
#
# @tool so the inspector shows what a row is without opening it. Nothing here
# may touch the scene tree, a Player or a status list: this code runs in the
# editor, where none of those exist, and a setter that errors there makes the
# resource unusable.

@export var effect: Status.Effect = Status.Effect.SPEED_CAP:
	set(value):
		effect = value
		# Both are needed: the first re-runs _validate_property() so the
		# irrelevant payload fields disappear, the second redraws the array
		# row's own label.
		notify_property_list_changed()
		_refresh_name()
## Ceiling factor for SPEED_CAP. Left at 0 by every other effect.
@export var amount: float = 0.0:
	set(value):
		amount = value
		_refresh_name()
## InterestLine.tag for BLOCK_INTEREST_LINE. Left empty by every other effect.
@export var subject: StringName = &"":
	set(value):
		subject = value
		_refresh_name()
## FORCE_VIEW only.
@export var view: Status.View = Status.View.FIRST:
	set(value):
		view = value
		_refresh_name()
## How long this lasts. INF means "until something removes it".
@export var seconds: float = INF:
	set(value):
		seconds = value
		_refresh_name()

## One line describing this entry, for a human reading a list of them.
##
## Shown as the array row's own label in the inspector: without it every row
## reads "StatusSpec" and a volume with four entries has to be opened four
## times to find out what it does.
func summary() -> String:
	var effect_name: String = Status.Effect.keys()[effect]
	var payload := ""
	match effect:
		Status.Effect.SPEED_CAP:
			payload = " %.2f" % amount
		Status.Effect.FORCE_VIEW:
			payload = " %s" % Status.View.keys()[view]
		Status.Effect.BLOCK_INTEREST_LINE:
			payload = " %s" % subject
	# String.num(), not a "%.3g" format: GDScript's format operator has no `g`
	# conversion and leaves the specifier in the string verbatim.
	var span := " (until removed)" if is_inf(seconds) else " (%s s)" % String.num(seconds, 3)
	return "%s%s%s" % [effect_name, payload, span]

func _refresh_name() -> void:
	resource_name = summary()

## Hides the payload fields an effect does not read. The schema above
## Status.Effect is the authority; this keeps the inspector honest about it,
## so an author cannot fill in a number that will be ignored.
func _validate_property(property: Dictionary) -> void:
	var used := ""
	match effect:
		Status.Effect.SPEED_CAP:
			used = "amount"
		Status.Effect.FORCE_VIEW:
			used = "view"
		Status.Effect.BLOCK_INTEREST_LINE:
			used = "subject"
	if property.name in ["amount", "subject", "view"] and property.name != used:
		property.usage &= ~PROPERTY_USAGE_EDITOR
