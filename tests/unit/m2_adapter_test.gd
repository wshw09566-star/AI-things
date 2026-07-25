extends GdUnitTestSuite

# The M1 seam: SurveySpace, ScannerCore, PlayerMotionState and EntityPatroller go
# through explicit adapters into the M2 schema and back, and the deterministic M1
# state hash survives graph -> save -> load -> graph.

const LEG_MM := 6000

func _m1_bundle() -> Dictionary:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02", SurveySpace.STATUS_LIVE)
	var station_a := space.add_node(region, Vector3i(0, 0, 0), SurveySpace.KIND_STATION)
	var junction := space.add_node(region, Vector3i(0, 0, LEG_MM), SurveySpace.KIND_JUNCTION)
	var station_b := space.add_node(region, Vector3i(0, 0, 2 * LEG_MM), SurveySpace.KIND_STATION)
	var dark := space.add_node(region, Vector3i(LEG_MM, 0, 2 * LEG_MM), SurveySpace.KIND_WAYPOINT)
	space.add_edge(station_a, junction, "ROCK")
	space.add_edge(junction, station_b, "GRATE")
	space.add_edge(station_b, dark, "SALT")
	space.scan_corridor([station_a, junction, station_b])
	var scanner := ScannerCore.new(19790417)
	scanner.charge_for_ticks(360)
	scanner.burst(space, region, PackedInt32Array([10, 20, 30, 110, 120, 130]))
	scanner.charge_for_ticks(90)
	var player := PlayerMotionState.new(Vector3i.ZERO, "ROCK")
	for tick_index in 45:
		player.tick(Vector3i(0, 0, 1))
	var patroller := EntityPatroller.new()
	patroller.place(space, station_a, [station_a, junction, station_b, junction])
	for tick_index in 40:
		patroller.tick(space)
	return {"space": space, "scanner": scanner, "player": player, "patroller": patroller, "region": region}

func test_the_adapter_produces_a_valid_graph() -> void:
	var bundle := _m1_bundle()
	var graph := SurveyM1Adapter.graph_from_m1(bundle["space"], bundle["scanner"], bundle["player"], bundle["patroller"], 19790417, 600, {int(bundle["region"]): 16})
	var report := SurveyValidator.validate(graph)
	assert_array(report["errors"]).is_empty()
	assert_bool(bool(graph.entity["present"])).is_true()
	assert_int(int(graph.entity["edge_id"])).is_not_equal(-1)
	assert_int(int(graph.entity["edge_t_mm"])).is_greater(0)
	assert_int(graph.point_total()).is_equal(2)
	assert_int(graph.audible_events.size()).is_greater(0)
	assert_int(int(graph.scanner["charge_tenths"])).is_equal(bundle["scanner"].charge_tenths)

func test_graph_to_m1_round_trip_preserves_the_state_hash() -> void:
	var bundle := _m1_bundle()
	var graph := SurveyM1Adapter.graph_from_m1(bundle["space"], bundle["scanner"], bundle["player"], bundle["patroller"], 19790417, 600)
	var first := SurveyM1Adapter.m1_from_graph(graph)
	var second := SurveyM1Adapter.m1_from_graph(SurveyM1Adapter.graph_from_m1(first["space"], first["scanner"], first["player"], first["patroller"], 19790417, 600))
	assert_str(SurveyM1Adapter.state_hash(second)).is_equal(SurveyM1Adapter.state_hash(first))
	var space: SurveySpace = first["space"]
	assert_int(space.point_total()).is_equal(bundle["space"].point_total())
	assert_int(space.chunk_point_sum()).is_equal(bundle["space"].chunk_point_sum())
	assert_bool(space.is_edge_traversable(space.edge_between(1, 2))).is_true()
	var patroller: EntityPatroller = first["patroller"]
	assert_bool(patroller.is_confined(space)).is_true()

func test_save_and_load_keeps_the_m1_state_hash() -> void:
	var bundle := _m1_bundle()
	var graph := SurveyM1Adapter.graph_from_m1(bundle["space"], bundle["scanner"], bundle["player"], bundle["patroller"], 19790417, 600, {int(bundle["region"]): 16})
	var path := SurveyGraphFixture.temp_path("survey_adapter.svy")
	assert_bool(bool(SurveyFile.save_graph(graph, path)["ok"])).is_true()
	var loaded := SurveyFile.load_graph(path)
	assert_array(loaded["errors"]).is_empty()
	var restored: SurveyGraphV1 = loaded["graph"]
	assert_str(restored.state_hash()).is_equal(graph.state_hash())
	assert_str(SurveyM1Adapter.state_hash(SurveyM1Adapter.m1_from_graph(restored))).is_equal(SurveyM1Adapter.state_hash(SurveyM1Adapter.m1_from_graph(graph)))
