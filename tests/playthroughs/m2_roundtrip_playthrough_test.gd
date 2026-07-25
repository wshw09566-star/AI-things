extends GdUnitTestSuite

# M2 deterministic round-trip playthrough (DESIGN.md sections 3, 6 and 12).
# A small graph is surveyed with a partial charge, duplicate 4 m cells, and the
# entity left mid-edge. The state is written to a temp .svy, read back, and both
# the original and the reloaded state are driven for 180 further ticks on the same
# scripted tape. Reload is behaviourally identical, so the canonical hashes match.

const LEG_MM := 6000
const CONTINUE_TICKS := 180
const CROUCH_TICK := 120
const SAVE_TICK := 600

func _survey() -> Dictionary:
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
	var player := PlayerMotionState.new(Vector3i.ZERO, "ROCK")
	# Two bursts into the same 4 m cell: the duplicate cell must merge into one
	# chunk instead of shadowing the first batch.
	scanner.charge_for_ticks(360)
	scanner.burst(space, region, PackedInt32Array([10, 20, 30, 110, 120, 130]))
	scanner.charge_for_ticks(360)
	scanner.burst(space, region, PackedInt32Array([210, 220, 230]))
	# Partial charge: the surveyor is mid-recharge when the file is written.
	scanner.charge_for_ticks(37)
	for tick_index in 90:
		player.tick(Vector3i(0, 0, 1))
	var patroller := EntityPatroller.new()
	patroller.place(space, station_a, [station_a, junction, station_b, junction])
	for tick_index in 40:
		patroller.tick(space)
	return {"space": space, "scanner": scanner, "player": player, "patroller": patroller, "region": region}

# The scripted tape both runs replay after the load.
func _continue(bundle: Dictionary) -> void:
	var space: SurveySpace = bundle["space"]
	var scanner: ScannerCore = bundle["scanner"]
	var player: PlayerMotionState = bundle["player"]
	var patroller: EntityPatroller = bundle["patroller"]
	for tick_index in CONTINUE_TICKS:
		if tick_index == CROUCH_TICK:
			player.set_stance(PlayerMotionState.STANCE_CROUCH)
		patroller.tick(space)
		if tick_index < 90:
			player.tick(Vector3i(0, 0, 1))
			scanner.tick_charge(true, false)
		else:
			scanner.tick_charge(true, true)

func test_m2_survey_save_load_and_replay_are_identical() -> void:
	var survey := _survey()
	var graph := SurveyM1Adapter.graph_from_m1(survey["space"], survey["scanner"], survey["player"], survey["patroller"], 19790417, SAVE_TICK, {int(survey["region"]): 16})
	for cell in 8:
		graph.mark_cell_scanned(int(survey["region"]), cell)
	assert_array(SurveyValidator.validate(graph)["errors"]).is_empty()
	assert_int(graph.chunks.size()).is_equal(1)
	assert_int(graph.point_total()).is_equal(3)
	assert_int(int(graph.completion()["percent_tenths"])).is_equal(500)
	assert_int(int(graph.entity["edge_t_mm"])).is_greater(0)
	assert_int(int(graph.scanner["charge_accumulator"])).is_greater(0)

	var path := SurveyGraphFixture.temp_path("m2_roundtrip.svy")
	var written := SurveyFile.save_graph(graph, path)
	assert_str(String(written["error"])).is_equal("")
	var loaded := SurveyFile.load_graph(path)
	assert_array(loaded["errors"]).is_empty()
	var restored: SurveyGraphV1 = loaded["graph"]
	assert_str(restored.state_hash()).is_equal(graph.state_hash())

	var before_save := SurveyM1Adapter.m1_from_graph(graph)
	var after_load := SurveyM1Adapter.m1_from_graph(restored)
	assert_str(SurveyM1Adapter.state_hash(after_load)).is_equal(SurveyM1Adapter.state_hash(before_save))

	_continue(before_save)
	_continue(after_load)
	var continued_hash := SurveyM1Adapter.state_hash(before_save)
	assert_str(SurveyM1Adapter.state_hash(after_load)).is_equal(continued_hash)

	var graph_before := SurveyM1Adapter.graph_from_m1(before_save["space"], before_save["scanner"], before_save["player"], before_save["patroller"], 19790417, SAVE_TICK + CONTINUE_TICKS, {int(survey["region"]): 16})
	var graph_after := SurveyM1Adapter.graph_from_m1(after_load["space"], after_load["scanner"], after_load["player"], after_load["patroller"], 19790417, SAVE_TICK + CONTINUE_TICKS, {int(survey["region"]): 16})
	assert_array(SurveyValidator.validate(graph_after)["errors"]).is_empty()
	assert_str(graph_after.state_hash()).is_equal(graph_before.state_hash())
	print("M2 ROUNDTRIP PASS %s" % continued_hash)
