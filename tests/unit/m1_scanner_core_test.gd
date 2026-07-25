extends GdUnitTestSuite

# M1 ScannerCore: integer charge economy, burst cost, region persistence,
# duplicate suppression, explicit cap results, and fixed-seed determinism.

func _space_with_region() -> Array:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	return [space, region]

func _wall_samples(count: int) -> PackedInt32Array:
	var samples := PackedInt32Array()
	for index in count:
		samples.append(-210)
		samples.append(0)
		samples.append(20 + index * 30)
	return samples

func test_charge_up_rate_is_exact_and_capped() -> void:
	var scanner := ScannerCore.new()
	assert_int(scanner.charge_for_ticks(60)).is_equal(50)
	assert_int(scanner.charge_for_ticks(240)).is_equal(250)
	assert_int(scanner.charge_for_ticks(6000)).is_equal(ScannerCore.CHARGE_MAX_TENTHS)

func test_charge_up_needs_deployed_tripod_and_stillness() -> void:
	var scanner := ScannerCore.new()
	assert_int(scanner.charge_for_ticks(120, false, true)).is_equal(0)
	assert_int(scanner.charge_for_ticks(120, true, false)).is_equal(0)
	scanner.charge_for_ticks(30)
	var partial := scanner.charge_tenths
	scanner.tick_charge(true, false)
	assert_int(scanner.charge_accumulator).is_equal(0)
	assert_int(scanner.charge_tenths).is_equal(partial)

func test_burst_costs_25_and_refuses_without_charge() -> void:
	var fixture := _space_with_region()
	var space: SurveySpace = fixture[0]
	var scanner := ScannerCore.new()
	var empty := scanner.burst(space, int(fixture[1]), _wall_samples(4))
	assert_bool(bool(empty["ok"])).is_false()
	assert_str(String(empty["reason"])).is_equal("INSUFFICIENT_CHARGE")
	scanner.charge_for_ticks(300)
	assert_int(scanner.charge_tenths).is_equal(250)
	var fired := scanner.burst(space, int(fixture[1]), _wall_samples(4))
	assert_bool(bool(fired["ok"])).is_true()
	assert_int(int(fired["charge_tenths"])).is_equal(0)
	assert_int(int(fired["stored"])).is_equal(4)
	assert_int(scanner.burst_count).is_equal(1)
	assert_str(String(scanner.burst(space, int(fixture[1]), _wall_samples(4))["reason"])).is_equal("INSUFFICIENT_CHARGE")

func test_bursts_persist_in_region_and_suppress_duplicates() -> void:
	var fixture := _space_with_region()
	var space: SurveySpace = fixture[0]
	var region := int(fixture[1])
	var scanner := ScannerCore.new()
	scanner.charge_for_ticks(1200)
	var first := scanner.burst(space, region, _wall_samples(12))
	var second := scanner.burst(space, region, _wall_samples(12))
	assert_int(int(first["stored"])).is_equal(12)
	assert_int(int(second["stored"])).is_equal(0)
	assert_int(int(second["duplicates"])).is_equal(12)
	assert_int(space.region_point_total(region)).is_equal(12)
	assert_int(space.point_total()).is_equal(12)

func test_cap_result_is_explicit_under_injected_caps() -> void:
	var space := SurveySpace.new(8, 5)
	var region := space.add_region("CH-04")
	var scanner := ScannerCore.new()
	scanner.charge_for_ticks(1200)
	var fired := scanner.burst(space, region, _wall_samples(9))
	assert_bool(bool(fired["at_cap"])).is_true()
	assert_int(int(fired["stored"])).is_equal(5)
	assert_int(int(fired["region_capped"])).is_equal(4)
	assert_int(int(fired["received"])).is_equal(9)
	assert_int(space.point_total()).is_equal(5)

func test_invalid_sample_batch_keeps_charge() -> void:
	var fixture := _space_with_region()
	var scanner := ScannerCore.new()
	scanner.charge_for_ticks(300)
	var bad := scanner.burst(fixture[0], int(fixture[1]), PackedInt32Array([1, 2]))
	assert_str(String(bad["reason"])).is_equal("INVALID_SAMPLES")
	assert_int(scanner.charge_tenths).is_equal(250)
	assert_int(scanner.burst_count).is_equal(0)

func test_same_seed_produces_identical_intensity_stream() -> void:
	var texts := PackedStringArray()
	for run in 2:
		var space := SurveySpace.new()
		var region := space.add_region("CH-02")
		var scanner := ScannerCore.new(1979)
		scanner.charge_for_ticks(1200)
		scanner.burst(space, region, _wall_samples(6))
		scanner.burst(space, region, _wall_samples(6))
		texts.append(space.canonical_text() + "\n" + scanner.canonical_text())
	assert_str(texts[0]).is_equal(texts[1])

func test_snapshot_round_trip_resumes_the_same_stream() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	var scanner := ScannerCore.new(4242)
	scanner.charge_for_ticks(700)
	var mid := scanner.to_snapshot()
	scanner.burst(space, region, _wall_samples(5))
	var direct := scanner.canonical_text()
	var restored := ScannerCore.from_snapshot(mid)
	var other_space := SurveySpace.new()
	var other_region := other_space.add_region("CH-02")
	restored.burst(other_space, other_region, _wall_samples(5))
	assert_str(restored.canonical_text()).is_equal(direct)
	assert_str(other_space.canonical_text()).is_equal(space.canonical_text())
