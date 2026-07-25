extends GdUnitTestSuite

# M1 EntityPatroller: scanned-space confinement, boundary halt, integer speed
# ceiling, and the no-teleport per-tick distance bound.

const LEG_MM := 6000

func _fixture() -> Dictionary:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	var ids: Array = []
	for index in 4:
		var kind := SurveySpace.KIND_STATION if index % 2 == 0 else SurveySpace.KIND_JUNCTION
		ids.append(space.add_node(region, Vector3i(0, 0, index * LEG_MM), kind))
	var branch := space.add_node(region, Vector3i(LEG_MM, 0, 2 * LEG_MM))
	for index in 3:
		space.add_edge(int(ids[index]), int(ids[index + 1]))
	space.add_edge(int(ids[2]), branch, "SALT")
	space.scan_corridor([ids[0], ids[1], ids[2]])
	return {"space": space, "region": region, "ids": ids, "branch": branch}

func test_route_requires_existing_adjacent_legs() -> void:
	var fixture := _fixture()
	var space: SurveySpace = fixture["space"]
	var ids: Array = fixture["ids"]
	var patroller := EntityPatroller.new()
	assert_bool(patroller.place(space, int(ids[0]), [ids[0], ids[2]])).is_false()
	assert_bool(patroller.place(space, int(ids[0]), [ids[0]])).is_false()
	assert_bool(patroller.place(space, int(ids[3]), [ids[3], ids[2]])).is_false()
	assert_bool(patroller.place(space, int(ids[0]), [ids[0], ids[1], 9999])).is_false()
	assert_bool(patroller.place(space, int(ids[0]), [ids[0], ids[1]])).is_true()
	assert_int(patroller.at_node_id).is_equal(int(ids[0]))

func test_speed_never_exceeds_1700_mm_per_second_and_never_teleports() -> void:
	var fixture := _fixture()
	var space: SurveySpace = fixture["space"]
	var ids: Array = fixture["ids"]
	var patroller := EntityPatroller.new()
	assert_bool(patroller.place(space, int(ids[0]), [ids[0], ids[1]])).is_true()
	var total := 0
	var previous := patroller.position_mm(space)
	for tick_index in 60:
		var result := patroller.tick(space)
		var moved := int(result["moved_mm"])
		assert_int(moved).is_less_equal(EntityPatroller.MAX_STEP_MM)
		var current := patroller.position_mm(space)
		assert_int(SurveySpace.distance_mm(previous, current)).is_less_equal(EntityPatroller.MAX_STEP_MM)
		previous = current
		total += moved
	assert_int(total).is_equal(1700)

func test_unplaced_patroller_holds_still() -> void:
	var fixture := _fixture()
	var patroller := EntityPatroller.new()
	var result := patroller.tick(fixture["space"])
	assert_str(String(result["reason"])).is_equal("UNPLACED")
	assert_int(int(result["moved_mm"])).is_equal(0)
	assert_bool(patroller.is_confined(fixture["space"])).is_false()

func test_patroller_halts_at_the_scanned_boundary() -> void:
	var fixture := _fixture()
	var space: SurveySpace = fixture["space"]
	var ids: Array = fixture["ids"]
	var patroller := EntityPatroller.new()
	patroller.place(space, int(ids[0]), [ids[0], ids[1], ids[2], ids[3], ids[2], ids[1]])
	var halted := false
	for tick_index in 600:
		var result := patroller.tick(space)
		assert_bool(patroller.is_confined(space)).is_true()
		if bool(result["halted"]):
			halted = true
			assert_str(String(result["reason"])).is_equal("SCANNED_BOUNDARY")
	assert_bool(halted).is_true()
	assert_bool(patroller.halted_at_boundary).is_true()
	assert_int(patroller.at_node_id).is_equal(int(ids[2]))
	assert_int(patroller.arrivals).is_equal(2)
	assert_int(patroller.position_mm(space).z).is_equal(2 * LEG_MM)

func test_patroller_refuses_an_unscanned_branch() -> void:
	var fixture := _fixture()
	var space: SurveySpace = fixture["space"]
	var ids: Array = fixture["ids"]
	var patroller := EntityPatroller.new()
	patroller.place(space, int(ids[2]), [ids[2], fixture["branch"]])
	var result := patroller.tick(space)
	assert_bool(bool(result["halted"])).is_true()
	assert_int(int(result["moved_mm"])).is_equal(0)
	assert_int(patroller.at_node_id).is_equal(int(ids[2]))
	space.mark_node_scanned(int(fixture["branch"]))
	space.mark_edge_scanned(space.edge_between(int(ids[2]), int(fixture["branch"])))
	assert_int(int(patroller.tick(space)["moved_mm"])).is_greater(0)

func test_pending_erasure_stops_the_patroller() -> void:
	var fixture := _fixture()
	var space: SurveySpace = fixture["space"]
	var ids: Array = fixture["ids"]
	var patroller := EntityPatroller.new()
	patroller.place(space, int(ids[0]), [ids[0], ids[1]])
	assert_int(int(patroller.tick(space)["moved_mm"])).is_greater(0)
	space.set_region_status(int(fixture["region"]), SurveySpace.STATUS_PENDING_ERASE)
	for tick_index in 400:
		patroller.tick(space)
	assert_bool(patroller.halted_at_boundary).is_true()

func test_snapshot_round_trip_resumes_mid_leg() -> void:
	var fixture := _fixture()
	var space: SurveySpace = fixture["space"]
	var ids: Array = fixture["ids"]
	var patroller := EntityPatroller.new()
	patroller.place(space, int(ids[0]), [ids[0], ids[1], ids[2], ids[1]])
	for tick_index in 100:
		patroller.tick(space)
	assert_int(patroller.edge_t_mm).is_greater(0)
	var restored := EntityPatroller.from_snapshot(patroller.to_snapshot())
	assert_str(restored.canonical_text()).is_equal(patroller.canonical_text())
	for tick_index in 100:
		patroller.tick(space)
		restored.tick(space)
	assert_str(restored.canonical_text()).is_equal(patroller.canonical_text())
