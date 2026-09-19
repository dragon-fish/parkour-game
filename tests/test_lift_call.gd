extends ParkourTest

# A lift with a call button waits closed at its landing until the button is
# used; one without stands open. The car's own button does nothing while the
# doors are shut: nobody can be inside.

const DOOR_OPEN := Vector3(-0.76, 0.0, 0.0)

## A lift at the origin: a car, one landing door per stop, and optionally a
## call button. Car and doors stand beside the Lift, as the level's Movers do:
## the Lift's own children ride the car. Returns [holder, landing door, call
## zone or null, car zone, car].
func _lift(with_call: bool) -> Array:
	var holder := Node3D.new()
	var movers := Node3D.new()
	movers.name = "Movers"
	holder.add_child(movers)
	var car := AnimatableBody3D.new()
	car.name = "Car"
	movers.add_child(car)
	var bottom := Node3D.new()
	bottom.name = "Bottom"
	movers.add_child(bottom)
	var top := Node3D.new()
	top.name = "Top"
	top.position = Vector3(0.0, 10.0, 0.0)
	movers.add_child(top)
	var lift := Lift.new()
	var ride := UseZone.new()
	ride.name = "UseZone"
	lift.add_child(ride)
	var call: UseZone = null
	if with_call:
		call = UseZone.new()
		call.name = "CallZone"
		call.position = Vector3(3.0, 0.0, 0.0)
		lift.add_child(call)
		lift.call_zone = NodePath("CallZone")
	lift.car = NodePath("../Movers/Car")
	lift.stop_doors = [[NodePath("../Movers/Bottom")], [NodePath("../Movers/Top")]]
	lift.travel = Vector3(0.0, 10.0, 0.0)
	lift.travel_time = 0.2
	lift.door_open_offset = DOOR_OPEN
	lift.door_time = 0.1
	holder.add_child(lift)
	get_tree().root.add_child(holder)
	return [holder, bottom, call, ride, car]

func _is_open(door: Node3D) -> bool:
	return door.position.is_equal_approx(DOOR_OPEN)

func test_without_a_call_button_the_doors_stand_open() -> void:
	var parts := _lift(false)
	await step(1)
	assert_true(_is_open(parts[1]), "a lift without a call button waited closed")
	(parts[0] as Node).queue_free()

func test_the_call_button_opens_a_lift_that_waits_closed() -> void:
	var parts := _lift(true)
	await step(1)
	var door: Node3D = parts[1]
	assert_eq(door.position, Vector3.ZERO, "a lift with a call button stood open before it was called")
	var car: Node3D = parts[4]
	(parts[3] as UseZone).used.emit()
	await step(30)
	assert_eq(car.position, Vector3.ZERO, "the car left while its doors were shut")
	(parts[2] as UseZone).used.emit()
	await step(12)
	assert_true(_is_open(door), "the call button did not open the doors")
	var button: UseZone = parts[2]
	assert_eq(button.global_position, Vector3(3.0, 0.0, 0.0), "the call button rode the car")
	(parts[0] as Node).queue_free()
