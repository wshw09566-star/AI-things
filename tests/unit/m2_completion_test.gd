extends GdUnitTestSuite

# DESIGN.md section 2 with correction 15.1.1: integer numerator and denominator,
# a zero live denominator defined as exactly 0%, and an integer 100% gate.

func test_partial_coverage_is_an_integer_ratio() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var report := graph.completion()
	assert_int(int(report["numerator"])).is_equal(8)
	assert_int(int(report["denominator"])).is_equal(16)
	assert_int(int(report["percent_tenths"])).is_equal(500)
	assert_bool(bool(report["complete"])).is_false()
	assert_str(SurveyCompletion.percent_text(report)).is_equal("50.0%")

func test_full_coverage_gates_on_integers() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var region_id := SurveyGraphFixture.region_id_of(graph)
	for cell in 16:
		graph.mark_cell_scanned(region_id, cell)
	var report := graph.completion()
	assert_int(int(report["numerator"])).is_equal(int(report["denominator"]))
	assert_int(int(report["percent_tenths"])).is_equal(1000)
	assert_bool(bool(report["complete"])).is_true()
	assert_bool(bool((graph.regions[region_id] as Dictionary)["complete"])).is_true()

func test_zero_live_denominator_is_exactly_zero_percent() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var region_id := SurveyGraphFixture.region_id_of(graph)
	graph.entity = SurveyGraphV1.default_entity()
	assert_bool(graph.erase_region(region_id, 600)).is_true()
	var report := graph.completion()
	assert_int(int(report["denominator"])).is_equal(0)
	assert_int(int(report["percent_tenths"])).is_equal(0)
	assert_bool(bool(report["complete"])).is_false()
	assert_str(SurveyCompletion.percent_text(report)).is_equal("0.0%")
	assert_array(SurveyValidator.validate(graph)["errors"]).is_empty()

func test_region_completion_uses_the_92_percent_rule() -> void:
	var graph := SurveyGraphV1.new()
	var region_id := graph.add_region("CH-05", "Pillar Field", 16)
	for cell in 14:
		graph.mark_cell_scanned(region_id, cell)
	assert_bool(SurveyCompletion.region_complete(graph.regions[region_id])).is_false()
	graph.mark_cell_scanned(region_id, 14)
	assert_bool(SurveyCompletion.region_complete(graph.regions[region_id])).is_true()
	assert_int(int(graph.completion()["percent_tenths"])).is_equal(937)

func test_empty_region_never_reads_complete() -> void:
	var graph := SurveyGraphV1.new()
	var region_id := graph.add_region("DR-01", "Drift", 0)
	assert_bool(SurveyCompletion.region_complete(graph.regions[region_id])).is_false()
	assert_int(int(graph.completion()["percent_tenths"])).is_equal(0)
