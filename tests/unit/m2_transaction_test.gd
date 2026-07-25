extends GdUnitTestSuite

# DESIGN.md section 6 transactional write: sibling temp file, flush, close,
# verify, one atomic rename, one kept .bak generation, and a refused slot that
# falls back to the bound copy. A partial .tmp is never loaded.

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func test_save_writes_atomically_and_leaves_no_temp_file() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var path := SurveyGraphFixture.temp_path("survey_transaction.svy")
	var result := SurveyFile.save_graph(graph, path)
	assert_str(String(result["error"])).is_equal("")
	assert_bool(bool(result["ok"])).is_true()
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()
	assert_bool(FileAccess.file_exists(path + ".bak")).is_false()
	assert_int(String(result["checksum"]).length()).is_equal(16)
	var loaded := SurveyFile.load_graph(path)
	assert_array(loaded["errors"]).is_empty()
	assert_bool(bool(loaded["ok"])).is_true()
	var restored: SurveyGraphV1 = loaded["graph"]
	assert_str(restored.state_hash()).is_equal(graph.state_hash())

func test_second_save_keeps_exactly_one_bak_generation() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var path := SurveyGraphFixture.temp_path("survey_bak.svy")
	assert_bool(bool(SurveyFile.save_graph(graph, path)["ok"])).is_true()
	var first_text := _read(path)
	graph.tick = 900
	var second := SurveyFile.save_graph(graph, path)
	assert_bool(bool(second["ok"])).is_true()
	assert_str(String(second["bak"])).is_equal(path + ".bak")
	assert_str(_read(path + ".bak")).is_equal(first_text)
	assert_str(_read(path)).is_not_equal(first_text)
	graph.tick = 1200
	assert_bool(bool(SurveyFile.save_graph(graph, path)["ok"])).is_true()
	assert_bool(FileAccess.file_exists(path + ".bak")).is_true()
	assert_bool(FileAccess.file_exists(path + ".bak.bak")).is_false()
	var reloaded := SurveyFile.load_graph(path)
	assert_bool(bool(reloaded["ok"])).is_true()
	assert_int((reloaded["graph"] as SurveyGraphV1).tick).is_equal(1200)

func test_a_corrupt_slot_is_refused_and_the_bak_is_offered() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var path := SurveyGraphFixture.temp_path("survey_recovery.svy")
	assert_bool(bool(SurveyFile.save_graph(graph, path)["ok"])).is_true()
	graph.tick = 720
	assert_bool(bool(SurveyFile.save_graph(graph, path)["ok"])).is_true()
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string("{ this is not a survey file")
	writer.close()
	var refused := SurveyFile.load_graph(path)
	assert_bool(bool(refused["ok"])).is_false()
	assert_str(String(refused["message"])).is_equal(SurveyFile.DIEGETIC_ERROR)
	assert_bool(bool(refused["bak_available"])).is_true()
	var recovered := SurveyFile.load_slot(path)
	assert_bool(bool(recovered["ok"])).is_true()
	assert_bool(bool(recovered["used_bak"])).is_true()
	assert_int((recovered["graph"] as SurveyGraphV1).tick).is_equal(600)

func test_temp_and_bak_paths_are_never_written_as_slots() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var path := SurveyGraphFixture.temp_path("survey_suffix.svy")
	assert_str(String(SurveyFile.save_graph(graph, path + ".tmp")["error"])).is_equal("REFUSED_SLOT_SUFFIX")
	assert_str(String(SurveyFile.save_graph(graph, path + ".bak")["error"])).is_equal("REFUSED_SLOT_SUFFIX")
	var writer := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	writer.store_string(SurveyFile.canonical_text(SurveyFile.stamp_checksum(SurveyFile.envelope_from_graph(graph))))
	writer.close()
	var refused := SurveyFile.load_graph(path + ".tmp")
	assert_bool(bool(refused["ok"])).is_false()
	assert_str("\n".join(PackedStringArray(refused["errors"]))).contains("PARTIAL_WRITE_REFUSED")

func test_an_invalid_graph_is_never_written() -> void:
	var graph := SurveyGraphFixture.small_graph()
	graph.next_ids["node"] = 1
	var path := SurveyGraphFixture.temp_path("survey_invalid.svy")
	var result := SurveyFile.save_graph(graph, path)
	assert_bool(bool(result["ok"])).is_false()
	assert_str(String(result["error"])).contains("INVALID_GRAPH: V8")
	assert_bool(FileAccess.file_exists(path)).is_false()
