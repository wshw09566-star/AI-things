extends GdUnitTestSuite

func test_project_identity_and_point_budget() -> void:
	assert_str(ProjectSettings.get_setting("application/config/name")).is_equal("HOLLOW SURVEY")
	assert_int(720).is_greater(0).is_less_equal(1000)

func test_fixed_seed_is_deterministic() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 19790417
	second.seed = 19790417
	for sample in 16:
		assert_float(first.randf()).is_equal(second.randf())
