class_name LineWalkBeamStub
extends LineWalkMove

# Test-only stand-in for BalanceMove, which does not exist yet (a later
# task). Exercises LineWalkMove's own along/lateral projection at
# body_yaw_offset_deg = 0 -- the beam half of the tier -- without depending on
# BalanceMove's pendulum.
#
# Filename deliberately does NOT start with "test_": tests/test_runner.gd
# discovers every tests/test_*.gd file and tries to run it as a TestCase (see
# world_fixture.gd's own note on the same rule).

func kind() -> InterestLine.Kind:
	return InterestLine.Kind.BALANCE
