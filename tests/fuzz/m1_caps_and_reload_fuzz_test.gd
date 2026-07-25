extends GdUnitTestSuite

# M1 fuzz regression (DESIGN.md sections 2, 6 and 12): cap saturation under
# injected small caps, and fixed-seed reload determinism with a mid-action save
# represented by partial scanner charge.

const FUZZ_SEED := 19771112
const BATCHES := 40
const BATCH_SAMPLES := 16
const GLOBAL_CAP := 64
const REGION_CAP := 40

func test_cap_saturation_accounts_for_every_sample() -> void:
	var space := SurveySpace.new(GLOBAL_CAP, REGION_CAP)
	var regions: Array = [space.add_region("CH-04"), space.add_region("CH-08")]
	var rng := RandomNumberGenerator.new()
	rng.seed = FUZZ_SEED
	var received_total := 0
	var stored_total := 0
	var refused_total := 0
	for batch_index in BATCHES:
		var region := int(regions[batch_index % regions.size()])
		var batch := PackedInt32Array()
		for sample_index in BATCH_SAMPLES:
			batch.append(rng.randi_range(-400, 400))
			batch.append(rng.randi_range(-140, 160))
			batch.append(rng.randi_range(0, 900))
			batch.append(rng.randi_range(0, 255))
		var result := space.store_points(region, batch)
		assert_bool(bool(result["ok"])).is_true()
		var accounted := int(result["stored"]) + int(result["duplicates"]) + int(result["region_capped"]) + int(result["global_capped"])
		assert_int(accounted).is_equal(int(result["received"]))
		received_total += int(result["received"])
		stored_total += int(result["stored"])
		refused_total += int(result["region_capped"]) + int(result["global_capped"])
		assert_int(space.region_point_total(region)).is_less_equal(REGION_CAP)
		assert_int(space.point_total()).is_less_equal(GLOBAL_CAP)
		assert_int(space.chunk_point_sum()).is_equal(space.point_total())
	assert_int(received_total).is_equal(BATCHES * BATCH_SAMPLES)
	assert_int(stored_total).is_equal(space.point_total())
	assert_int(space.point_total()).is_equal(GLOBAL_CAP)
	assert_int(refused_total).is_greater(0)

func test_cap_saturation_is_reproducible_for_a_fixed_seed() -> void:
	var texts := PackedStringArray()
	for run_index in 2:
		var space := SurveySpace.new(GLOBAL_CAP, REGION_CAP)
		var region := space.add_region("CH-04")
		var rng := RandomNumberGenerator.new()
		rng.seed = FUZZ_SEED
		for batch_index in 12:
			var batch := PackedInt32Array()
			for sample_index in BATCH_SAMPLES:
				batch.append(rng.randi_range(-400, 400))
				batch.append(rng.randi_range(-140, 160))
				batch.append(rng.randi_range(0, 900))
				batch.append(rng.randi_range(0, 255))
			space.store_points(region, batch)
		texts.append(space.canonical_text())
	assert_str(texts[0]).is_equal(texts[1])

func _fixture() -> Dictionary:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	var ids: Array = []
	for index in 3:
		ids.append(space.add_node(region, Vector3i(0, 0, index * 6000), SurveySpace.KIND_STATION))
	var dark := space.add_node(region, Vector3i(0, 0, 18000))
	space.add_edge(int(ids[0]), int(ids[1]))
	space.add_edge(int(ids[1]), int(ids[2]), "GRATE")
	space.add_edge(int(ids[2]), dark)
	space.scan_corridor(ids)
	var scanner := ScannerCore.new(FUZZ_SEED)
	var player := PlayerMotionState.new(Vector3i.ZERO, "SALT")
	var patroller := EntityPatroller.new()
	patroller.place(space, int(ids[0]), [ids[0], ids[1], ids[2], dark, ids[2], ids[1]])
	return {"space": space, "scanner": scanner, "player": player, "patroller": patroller, "region": region}

func _advance(state: Dictionary, ticks: int) -> void:
	var space: SurveySpace = state["space"]
	var scanner: ScannerCore = state["scanner"]
	var player: PlayerMotionState = state["player"]
	var patroller: EntityPatroller = state["patroller"]
	for tick_index in ticks:
		scanner.tick_charge(true, true)
		player.tick(Vector3i(0, 0, 1))
		patroller.tick(space)
		if scanner.can_burst():
			var samples := PackedInt32Array()
			for sample_index in 6:
				samples.append(sample_index * 25)
				samples.append(0)
				samples.append(tick_index * 3)
			scanner.burst(space, int(state["region"]), samples)

func test_fixed_seed_reload_replays_bit_identically() -> void:
	var state := _fixture()
	_advance(state, 170)
	var scanner: ScannerCore = state["scanner"]
	# A mid-action save at M1 is a partially charged scanner: not empty, not full.
	assert_int(scanner.charge_tenths).is_greater(0)
	assert_int(scanner.charge_tenths).is_less(ScannerCore.CHARGE_MAX_TENTHS)
	var saved := {
		"space": (state["space"] as SurveySpace).to_snapshot(),
		"scanner": scanner.to_snapshot(),
		"player": (state["player"] as PlayerMotionState).to_snapshot(),
		"patroller": (state["patroller"] as EntityPatroller).to_snapshot(),
		"region": int(state["region"]),
	}
	_advance(state, 150)
	var direct_hash := M1StateHash.of(state["space"], state["scanner"], state["player"], state["patroller"])
	var reloaded := {
		"space": SurveySpace.from_snapshot(saved["space"]),
		"scanner": ScannerCore.from_snapshot(saved["scanner"]),
		"player": PlayerMotionState.from_snapshot(saved["player"]),
		"patroller": EntityPatroller.from_snapshot(saved["patroller"]),
		"region": int(saved["region"]),
	}
	_advance(reloaded, 150)
	var reloaded_hash := M1StateHash.of(reloaded["space"], reloaded["scanner"], reloaded["player"], reloaded["patroller"])
	assert_str(reloaded_hash).is_equal(direct_hash)
	assert_str(M1StateHash.snapshot_text(reloaded["space"], reloaded["scanner"], reloaded["player"], reloaded["patroller"])).is_equal(M1StateHash.snapshot_text(state["space"], state["scanner"], state["player"], state["patroller"]))

func test_reload_keeps_the_entity_inside_scanned_space() -> void:
	var state := _fixture()
	_advance(state, 500)
	var patroller: EntityPatroller = state["patroller"]
	assert_bool(patroller.is_confined(state["space"])).is_true()
	assert_bool(patroller.halted_at_boundary).is_true()
	var reloaded_patroller := EntityPatroller.from_snapshot(patroller.to_snapshot())
	var reloaded_space := SurveySpace.from_snapshot((state["space"] as SurveySpace).to_snapshot())
	assert_bool(reloaded_patroller.is_confined(reloaded_space)).is_true()
	for tick_index in 60:
		var result := reloaded_patroller.tick(reloaded_space)
		assert_bool(bool(result["halted"])).is_true()
		assert_bool(reloaded_patroller.is_confined(reloaded_space)).is_true()

func test_hash_digest_is_stable_and_sensitive() -> void:
	assert_str(M1StateHash.fnv1a_64("")).is_equal("cbf29ce484222325")
	assert_str(M1StateHash.fnv1a_64("a")).is_equal("af63dc4c8601ec8c")
	assert_str(M1StateHash.fnv1a_64("hollow survey")).is_not_equal(M1StateHash.fnv1a_64("hollow surveys"))
	assert_str(M1StateHash.fnv1a_64("HOLLOW SURVEY")).has_length(16)
