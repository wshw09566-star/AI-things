extends GdUnitTestSuite

# DESIGN.md section 6: any parse, checksum, migration, or validation failure
# refuses the slot. Nothing is repaired silently and no partial graph escapes.

func _write(path: String, text: String) -> void:
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(text)
	writer.close()

func _joined(result: Dictionary) -> String:
	return "\n".join(PackedStringArray(result["errors"]))

func _refused(path: String) -> Dictionary:
	var result := SurveyFile.load_graph(path)
	assert_bool(bool(result["ok"])).is_false()
	assert_bool(result["graph"] == null).is_true()
	assert_str(String(result["message"])).is_equal(SurveyFile.DIEGETIC_ERROR)
	return result

func test_truncated_json_is_refused() -> void:
	var path := SurveyGraphFixture.temp_path("survey_truncated.svy")
	var text := SurveyFile.canonical_text(SurveyFile.stamp_checksum(SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph())))
	_write(path, text.substr(0, 120))
	assert_str(_joined(_refused(path))).contains("PARSE_FAILED")

func test_a_tampered_checksum_is_refused() -> void:
	var path := SurveyGraphFixture.temp_path("survey_checksum.svy")
	var envelope := SurveyFile.stamp_checksum(SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph()))
	(envelope["header"] as Dictionary)["tick"] = 999
	_write(path, SurveyFile.canonical_text(envelope))
	assert_str(_joined(_refused(path))).contains("CHECKSUM_MISMATCH")

func test_a_missing_snapshot_field_is_refused() -> void:
	var path := SurveyGraphFixture.temp_path("survey_missing_field.svy")
	var envelope := SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph())
	(envelope["entity"] as Dictionary).erase("suspicion_tenths")
	assert_bool(bool(SurveyFile.write_envelope(envelope, path)["ok"])).is_true()
	assert_str(_joined(_refused(path))).contains("entity.suspicion_tenths: missing required field")

func test_a_non_canonical_integer_is_refused() -> void:
	var path := SurveyGraphFixture.temp_path("survey_noncanonical.svy")
	var envelope := SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph())
	(envelope["header"] as Dictionary)["tick"] = "007"
	assert_bool(bool(SurveyFile.write_envelope(envelope, path)["ok"])).is_true()
	assert_str(_joined(_refused(path))).contains("non-canonical integer 007")

func test_a_json_number_where_a_decimal_string_belongs_is_refused() -> void:
	var path := SurveyGraphFixture.temp_path("survey_number.svy")
	var text := SurveyFile.canonical_text(SurveyFile.stamp_checksum(SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph())))
	_write(path, text.replace("\"tick\": \"600\"", "\"tick\": 600"))
	var errors := _joined(_refused(path))
	assert_bool(errors.contains("CHECKSUM_MISMATCH") or errors.contains("integer must be a decimal string")).is_true()

func test_duplicate_ids_and_broken_invariants_are_refused() -> void:
	var path := SurveyGraphFixture.temp_path("survey_duplicate.svy")
	var envelope := SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph())
	var nodes: Array = (envelope["graph"] as Dictionary)["nodes"]
	nodes.append((nodes[0] as Dictionary).duplicate(true))
	assert_bool(bool(SurveyFile.write_envelope(envelope, path)["ok"])).is_true()
	assert_str(_joined(_refused(path))).contains("appears twice")

func test_a_missing_slot_is_refused() -> void:
	var path := SurveyGraphFixture.temp_path("survey_absent.svy")
	assert_str(_joined(_refused(path))).contains("MISSING_SLOT")
