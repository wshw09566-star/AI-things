extends GdUnitTestSuite

# Producer-owned fallback after BUG HUNTER refusal. These attacks are cumulative
# and intentionally use only public M2 seams. ENGINEER review is required before
# the M2 QA gate.

func _reordered(value: Variant, reverse: bool) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var keys := source.keys()
			keys.sort()
			if reverse:
				keys.reverse()
			var out := {}
			for key in keys:
				out[key] = _reordered(source[key], not reverse)
			return out
		TYPE_ARRAY:
			var out: Array = []
			for item in value:
				out.append(_reordered(item, not reverse))
			return out
	return value

func _write(path: String, text: String) -> void:
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(text)
	writer.close()

func test_decimal_integer_corpus_rejects_syntax_and_int64_overflow() -> void:
	for invalid in ["", "+1", "01", "-0", "1e3", " 1", "1 ", "--1"]:
		assert_bool(SurveyIntCodec.is_canonical(invalid)).is_false()
	for overflow in ["9223372036854775808", "-9223372036854775809", "999999999999999999999999"]:
		var errors: Array = []
		assert_int(SurveyIntCodec.decode(overflow, "probe", errors)).is_equal(0)
		assert_str("\n".join(PackedStringArray(errors))).contains("outside signed 64-bit range")
	for valid in ["0", "1", "-1", "9223372036854775807", "-9223372036854775808"]:
		var errors: Array = []
		SurveyIntCodec.decode(valid, "probe", errors)
		assert_array(errors).is_empty()

func test_canonical_checksum_survives_128_insertion_order_permutations() -> void:
	var envelope := SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph())
	var expected_text := SurveyFile.canonical_text(envelope)
	var expected_checksum := SurveyFile.checksum_of(envelope)
	for index in 128:
		var reordered: Dictionary = _reordered(envelope, (index & 1) == 0)
		assert_str(SurveyFile.canonical_text(reordered)).is_equal(expected_text)
		assert_str(SurveyFile.checksum_of(reordered)).is_equal(expected_checksum)

func test_checksum_detects_mutations_in_every_authoritative_section() -> void:
	var base := SurveyFile.stamp_checksum(SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph()))
	var variants: Array = []
	var header := base.duplicate(true); (header["header"] as Dictionary)["tick"] = 601; variants.append(header)
	var graph := base.duplicate(true); ((graph["graph"] as Dictionary)["caps"] as Dictionary)["global"] = 1; variants.append(graph)
	var player := base.duplicate(true); (player["player"] as Dictionary)["lean_mm"] = 1; variants.append(player)
	var scanner := base.duplicate(true); (scanner["scanner"] as Dictionary)["rng_state"] = 1; variants.append(scanner)
	var entity := base.duplicate(true); (entity["entity"] as Dictionary)["suspicion_tenths"] = 0; variants.append(entity)
	var pending := base.duplicate(true); (pending["pending"] as Dictionary)["elapsed_ticks"] = 13; variants.append(pending)
	var rng := base.duplicate(true); (rng["rng"] as Dictionary)["gen_stream"] = 1; variants.append(rng)
	var audio := base.duplicate(true); (audio["audio"] as Dictionary)["next_seq"] = 99; variants.append(audio)
	for mutated in variants:
		var errors: Array = []
		assert_bool(SurveyFile.verify_checksum(mutated, errors)).is_false()
		assert_str("\n".join(PackedStringArray(errors))).contains("CHECKSUM_MISMATCH")

func test_both_corrupt_primary_and_backup_fail_closed() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var path := SurveyGraphFixture.temp_path("m2_both_corrupt.svy")
	assert_bool(bool(SurveyFile.save_graph(graph, path)["ok"])).is_true()
	graph.tick = 601
	assert_bool(bool(SurveyFile.save_graph(graph, path)["ok"])).is_true()
	_write(path, "{broken primary")
	_write(path + ".bak", "{broken backup")
	var result := SurveyFile.load_slot(path)
	assert_bool(bool(result["ok"])).is_false()
	assert_bool(bool(result["used_bak"])).is_true()
	assert_bool(result["graph"] == null).is_true()
	assert_bool((result["slot_errors"] as Array).size() > 0).is_true()
	assert_bool((result["errors"] as Array).size() > 0).is_true()

func test_one_hundred_fixed_seed_save_load_roundtrips_are_stable() -> void:
	for index in 100:
		var graph := SurveyGraphFixture.small_graph()
		graph.tick += index
		graph.scanner["rng_state"] = 4242 + index
		graph.rng["sim_stream"] = [1234567890123 + index, 987654321 - index]
		var before := graph.state_hash()
		var path := SurveyGraphFixture.temp_path("m2_fuzz_%03d.svy" % index)
		assert_bool(bool(SurveyFile.save_graph(graph, path)["ok"])).is_true()
		var loaded := SurveyFile.load_graph(path)
		assert_bool(bool(loaded["ok"])).is_true()
		assert_str((loaded["graph"] as SurveyGraphV1).state_hash()).is_equal(before)
	print("M2 SAVE FUZZ PASS 100")
