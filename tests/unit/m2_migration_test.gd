extends GdUnitTestSuite

# DESIGN.md section 3.4: pure vN to vN+1 migrations with a fixture per version,
# and unknown future versions refused rather than guessed at.

func test_a_v0_fixture_migrates_to_v1_on_load() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var fixture := SurveyGraphFixture.v0_envelope(graph)
	assert_bool((fixture["graph"] as Dictionary).has("regions")).is_true()
	assert_bool(fixture.has("audio")).is_false()
	var path := SurveyGraphFixture.temp_path("survey_v0_fixture.svy")
	var written := SurveyFile.write_envelope(fixture, path)
	assert_str(String(written["error"])).is_equal("")
	var loaded := SurveyFile.load_graph(path)
	assert_array(loaded["errors"]).is_empty()
	assert_bool(bool(loaded["ok"])).is_true()
	var migrated: SurveyGraphV1 = loaded["graph"]
	assert_int(migrated.version).is_equal(1)
	assert_int(migrated.tick).is_equal(0)
	assert_array(migrated.audible_events).is_empty()
	assert_str(String(migrated.pending["action"])).is_equal("NONE")
	for region_id in migrated.sorted_region_ids():
		var region: Dictionary = migrated.regions[region_id]
		assert_str(String(region["status"])).is_equal(SurveyGraphV1.STATUS_LIVE)
		assert_bool(region["erase_deadline_tick"] == null).is_true()
		assert_str(String(region["name"])).is_equal(String(region["chamber_code"]))
	assert_int(migrated.nodes.size()).is_equal(graph.nodes.size())
	assert_int(migrated.point_total()).is_equal(graph.point_total())

func test_migrations_are_pure_functions() -> void:
	var fixture := SurveyGraphFixture.v0_envelope(SurveyGraphFixture.small_graph())
	var before := SurveyCanonicalJson.stringify(SurveyCanonicalJson.encode(fixture))
	var upgraded := SurveyMigrations.v0_to_v1(fixture)
	assert_str(SurveyCanonicalJson.stringify(SurveyCanonicalJson.encode(fixture))).is_equal(before)
	assert_str(String((upgraded["header"] as Dictionary)["version"])).is_equal("1")
	assert_bool(upgraded.has("audio")).is_true()

func test_unknown_future_versions_fail_closed() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var envelope := SurveyFile.envelope_from_graph(graph)
	(envelope["header"] as Dictionary)["version"] = "2"
	var path := SurveyGraphFixture.temp_path("survey_future.svy")
	assert_bool(bool(SurveyFile.write_envelope(envelope, path)["ok"])).is_true()
	var loaded := SurveyFile.load_graph(path)
	assert_bool(bool(loaded["ok"])).is_false()
	assert_bool(loaded["graph"] == null).is_true()
	assert_str("\n".join(PackedStringArray(loaded["errors"]))).contains("UNKNOWN_FUTURE_VERSION")

func test_the_registry_reports_a_missing_upgrade_instead_of_guessing() -> void:
	var errors: Array = []
	var migrated := SurveyMigrations.migrate({"header": {"version": "-1"}}, errors)
	assert_dict(migrated).is_empty()
	assert_str("\n".join(PackedStringArray(errors))).contains("UNKNOWN_VERSION")
