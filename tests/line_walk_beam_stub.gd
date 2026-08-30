class_name LineWalkBeamStub
extends LineWalkMove

# Test-only stand-in for BalanceMove: a bare BALANCE-kind LineWalkMove with no
# pendulum of its own, kept around after BalanceMove was written so
# tests/test_line_walk.gd can still exercise LineWalkMove's own along/lateral
# projection at body_yaw_offset_deg = 0 in isolation -- a regression in the
# projection and a regression in the pendulum would otherwise both move the
# same displacement measurement, and a passing test could not tell which one
# had happened.
#
# Filename deliberately does NOT start with "test_": tests/test_runner.gd
# discovers every tests/test_*.gd file and tries to run it as a TestCase (see
# world_fixture.gd's own note on the same rule).

func kind() -> InterestLine.Kind:
	return InterestLine.Kind.BALANCE
