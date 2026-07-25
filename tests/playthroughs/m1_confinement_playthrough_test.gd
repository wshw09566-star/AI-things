extends GdUnitTestSuite

# M1 deterministic headless playthrough (DESIGN.md sections 1, 4 and 12).
# The scripted tape scans one corridor of the Sorting Hall, walks the surveyor,
# advances the patroller across the scanned corridor, and then aims it at an
# unscanned branch. The taught rule is the enforced rule: the entity halts at the
# boundary of scanned space instead of entering the dark, and the run ends on a
# stable state hash.

const LEG_MM := 6000
const CORRIDOR_TICKS := 900
const PLAYER_TICKS := 240
const CHARGE_TICKS := 300
const EXPECTED_STATE_HASH := "7eb78c43adf5a8a4"

func _wall_samples() -> PackedInt32Array:
	var samples := PackedInt32Array()
	for step in 40:
		var z_cm := 20 + step * 30
		samples.append(-210)
		samples.append(-135)
		samples.append(z_cm)
		samples.append(210)
		samples.append(150)
		samples.append(z_cm)
		samples.append(0)
		samples.append(150)
		samples.append(z_cm)
	return samples

# The whole scripted tape. Pure integer simulation, no scene tree, no renderer.
func _run_survey() -> Dictionary:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02", SurveySpace.STATUS_LIVE)
	var station_a := space.add_node(region, Vector3i(0, 0, 0), SurveySpace.KIND_STATION)
	var junction := space.add_node(region, Vector3i(0, 0, LEG_MM), SurveySpace.KIND_JUNCTION)
	var station_b := space.add_node(region, Vector3i(0, 0, 2 * LEG_MM), SurveySpace.KIND_STATION)
	var dark_ahead := space.add_node(region, Vector3i(0, 0, 3 * LEG_MM), SurveySpace.KIND_WAYPOINT)
	var dark_branch := space.add_node(region, Vector3i(LEG_MM, 0, 2 * LEG_MM), SurveySpace.KIND_WAYPOINT)
	space.add_edge(station_a, junction, "ROCK")
	space.add_edge(junction, station_b, "GRATE")
	space.add_edge(station_b, dark_ahead, "ROCK")
	space.add_edge(station_b, dark_branch, "SALT")
	space.scan_corridor([station_a, junction, station_b])

	var scanner := ScannerCore.new(19790417)
	var player := PlayerMotionState.new(Vector3i.ZERO, "ROCK")
	var samples := _wall_samples()
	var first_burst := {}
	var second_burst := {}
	for tick_index in CHARGE_TICKS:
		scanner.tick_charge(true, true)
	first_burst = scanner.burst(space, region, samples)
	for tick_index in CHARGE_TICKS:
		scanner.tick_charge(true, true)
	second_burst = scanner.burst(space, region, samples)

	for tick_index in PLAYER_TICKS:
		if tick_index == 120:
			player.set_stance(PlayerMotionState.STANCE_CROUCH)
			player.set_surface("GRATE")
			player.set_lean(900)
		player.tick(Vector3i(0, 0, 1))

	var patroller := EntityPatroller.new()
	var placed := patroller.place(space, station_a, [station_a, junction, station_b, dark_ahead, station_b, junction])
	var max_step_mm := 0
	var confined_every_tick := true
	var previous := patroller.position_mm(space)
	var visited: Array = []
	for tick_index in CORRIDOR_TICKS:
		var result := patroller.tick(space)
		max_step_mm = maxi(max_step_mm, int(result["moved_mm"]))
		max_step_mm = maxi(max_step_mm, SurveySpace.distance_mm(previous, patroller.position_mm(space)))
		previous = patroller.position_mm(space)
		if not patroller.is_confined(space):
			confined_every_tick = false
		if int(result["arrived_node"]) != -1:
			visited.append(int(result["arrived_node"]))
	return {
		"space": space,
		"scanner": scanner,
		"player": player,
		"patroller": patroller,
		"region": region,
		"station_a": station_a,
		"junction": junction,
		"station_b": station_b,
		"dark_ahead": dark_ahead,
		"dark_branch": dark_branch,
		"placed": placed,
		"max_step_mm": max_step_mm,
		"confined_every_tick": confined_every_tick,
		"visited": visited,
		"first_burst": first_burst,
		"second_burst": second_burst,
	}

func test_m1_confinement_playthrough() -> void:
	var run := _run_survey()
	var space: SurveySpace = run["space"]
	var patroller: EntityPatroller = run["patroller"]
	var player: PlayerMotionState = run["player"]
	var scanner: ScannerCore = run["scanner"]

	assert_bool(bool(run["placed"])).is_true()
	assert_bool(bool(run["confined_every_tick"])).is_true()
	assert_int(int(run["max_step_mm"])).is_less_equal(EntityPatroller.MAX_STEP_MM)

	# The corridor was scanned and persists; the second burst is all duplicates.
	assert_int(int(run["first_burst"]["stored"])).is_equal(120)
	assert_int(int(run["second_burst"]["duplicates"])).is_equal(120)
	assert_int(space.point_total()).is_equal(120)
	assert_int(space.chunk_point_sum()).is_equal(120)
	assert_int(scanner.burst_count).is_equal(2)

	# The surveyor walked, crouched and left audible footsteps.
	assert_int(player.pos.z).is_greater(6000)
	assert_int(player.lean_mm).is_equal(PlayerMotionState.LEAN_LIMIT_MM)
	assert_array(player.events).is_not_empty()

	# The entity walked the scanned corridor to the far station and stopped dead
	# at the boundary rather than following the route into unscanned space.
	assert_array(run["visited"]).is_equal([run["junction"], run["station_b"]])
	assert_int(patroller.at_node_id).is_equal(int(run["station_b"]))
	assert_int(patroller.position_mm(space).z).is_equal(2 * LEG_MM)
	assert_bool(patroller.halted_at_boundary).is_true()
	assert_int(patroller.boundary_halts).is_greater(0)
	assert_bool(space.is_node_scanned(int(run["dark_ahead"]))).is_false()
	assert_bool(space.is_node_scanned(int(run["dark_branch"]))).is_false()

	var state_hash := M1StateHash.of(space, scanner, player, patroller)
	print("M1 CONFINEMENT PASS entity=%d halts=%d points=%d hash=%s" % [patroller.at_node_id, patroller.boundary_halts, space.point_total(), state_hash])
	assert_str(state_hash).has_length(16)
	assert_str(state_hash).is_equal(EXPECTED_STATE_HASH)

func test_playthrough_state_hash_is_reproducible() -> void:
	var first := _run_survey()
	var second := _run_survey()
	var first_hash := M1StateHash.of(first["space"], first["scanner"], first["player"], first["patroller"])
	var second_hash := M1StateHash.of(second["space"], second["scanner"], second["player"], second["patroller"])
	assert_str(second_hash).is_equal(first_hash)
	assert_str(M1StateHash.snapshot_text(second["space"], second["scanner"], second["player"], second["patroller"])).is_equal(M1StateHash.snapshot_text(first["space"], first["scanner"], first["player"], first["patroller"]))

func test_playthrough_survives_save_load_replay() -> void:
	var run := _run_survey()
	var space: SurveySpace = run["space"]
	var patroller: EntityPatroller = run["patroller"]
	var restored_space := SurveySpace.from_snapshot(space.to_snapshot())
	var restored_patroller := EntityPatroller.from_snapshot(patroller.to_snapshot())
	var restored_scanner := ScannerCore.from_snapshot((run["scanner"] as ScannerCore).to_snapshot())
	var restored_player := PlayerMotionState.from_snapshot((run["player"] as PlayerMotionState).to_snapshot())
	for tick_index in 120:
		patroller.tick(space)
		restored_patroller.tick(restored_space)
	assert_str(M1StateHash.of(restored_space, restored_scanner, restored_player, restored_patroller)).is_equal(M1StateHash.of(space, run["scanner"], run["player"], patroller))
