extends GdUnitTestSuite

# M1 PlayerMotionState: exact integer speeds, clamped lean, and deterministic
# footstep and surface events.

func test_walk_speed_is_exactly_2600_mm_per_second() -> void:
	var player := PlayerMotionState.new()
	var total := 0
	for tick_index in 60:
		var moved := player.tick(Vector3i(0, 0, 1))
		assert_int(moved).is_less_equal(44)
		total += moved
	assert_int(total).is_equal(2600)
	assert_int(player.pos.z).is_equal(2600)
	assert_int(player.accumulator).is_equal(0)

func test_crouch_speed_is_exactly_1200_mm_per_second() -> void:
	var player := PlayerMotionState.new()
	assert_str(player.toggle_crouch()).is_equal(PlayerMotionState.STANCE_CROUCH)
	var total := 0
	for tick_index in 60:
		total += player.tick(Vector3i(1, 0, 0))
	assert_int(total).is_equal(1200)
	assert_int(player.pos.x).is_equal(1200)
	assert_str(player.toggle_crouch()).is_equal(PlayerMotionState.STANCE_WALK)
	assert_bool(player.set_stance("SPRINT")).is_false()

func test_lean_is_clamped_and_yaw_relative() -> void:
	var player := PlayerMotionState.new()
	assert_int(player.set_lean(900)).is_equal(PlayerMotionState.LEAN_LIMIT_MM)
	assert_int(player.set_lean(-900)).is_equal(-PlayerMotionState.LEAN_LIMIT_MM)
	assert_int(player.set_lean(120)).is_equal(120)
	assert_int(player.effective_pos().x).is_equal(120)
	player.set_yaw(9000)
	assert_int(player.effective_pos().z).is_equal(120)
	player.set_yaw(18000)
	assert_int(player.effective_pos().x).is_equal(-120)
	assert_int(player.set_yaw(-9000)).is_equal(27000)
	assert_int(player.effective_pos().z).is_equal(-120)

func test_footstep_events_are_deterministic_per_surface() -> void:
	var player := PlayerMotionState.new(Vector3i.ZERO, "GRATE")
	for tick_index in 60:
		player.tick(Vector3i(0, 0, 1))
	var events := player.drain_events()
	assert_array(events).has_size(3)
	assert_int(int(events[0]["radius_mm"])).is_equal(14000)
	assert_int(int(events[0]["loudness_tenths"])).is_equal(15)
	assert_int(int(events[2]["index"])).is_equal(3)
	assert_array(player.events).is_empty()

func test_crouch_reduces_footstep_reach_by_the_specified_rock_ratio() -> void:
	var player := PlayerMotionState.new(Vector3i.ZERO, "ROCK")
	player.set_stance(PlayerMotionState.STANCE_CROUCH)
	var event := player.footstep_event()
	assert_int(int(event["radius_mm"])).is_equal(4000)
	assert_int(int(event["loudness_tenths"])).is_equal(4)
	player.set_stance(PlayerMotionState.STANCE_WALK)
	var loud := player.footstep_event()
	assert_int(int(loud["radius_mm"])).is_equal(9000)
	assert_int(int(loud["loudness_tenths"])).is_equal(10)

func test_rail_and_rubble_resolve_to_rock_step_values() -> void:
	var player := PlayerMotionState.new()
	assert_bool(player.set_surface("RAIL")).is_true()
	assert_str(player.surface).is_equal("ROCK")
	assert_bool(player.set_surface("RUBBLE")).is_true()
	assert_bool(player.set_surface("CARPET")).is_false()
	assert_str(PlayerMotionState.resolve_surface("WATER")).is_equal("WATER")

func test_direction_must_be_a_cardinal_unit_vector() -> void:
	var player := PlayerMotionState.new()
	assert_int(player.tick(Vector3i.ZERO)).is_equal(0)
	assert_int(player.tick(Vector3i(1, 0, 1))).is_equal(0)
	assert_int(player.tick(Vector3i(2, 0, 0))).is_equal(0)
	assert_int(player.pos.x).is_equal(0)
	assert_int(player.tick(Vector3i(-1, 0, 0))).is_equal(43)

func test_snapshot_round_trip_preserves_motion_and_events() -> void:
	var player := PlayerMotionState.new(Vector3i.ZERO, "SALT")
	for tick_index in 100:
		player.tick(Vector3i(0, 0, 1))
	var restored := PlayerMotionState.from_snapshot(player.to_snapshot())
	assert_str(restored.canonical_text()).is_equal(player.canonical_text())
	for tick_index in 50:
		player.tick(Vector3i(0, 0, 1))
		restored.tick(Vector3i(0, 0, 1))
	assert_str(restored.canonical_text()).is_equal(player.canonical_text())
