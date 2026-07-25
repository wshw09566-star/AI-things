extends GdUnitTestSuite

# DESIGN.md section 6: the canonical byte stream and its FNV-1a 64 checksum must
# not depend on Dictionary insertion order, and the checksum is taken with the
# checksum field zeroed so it can be verified in place.

func _reordered(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var keys := source.keys()
			keys.reverse()
			var out := {}
			for key in keys:
				out[key] = _reordered(source[key])
			return out
		TYPE_ARRAY:
			var list: Array = []
			for item in value:
				list.append(_reordered(item))
			return list
	return value

func test_canonical_text_is_insertion_order_independent() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var envelope := SurveyFile.envelope_from_graph(graph)
	var shuffled: Dictionary = _reordered(envelope)
	assert_str(SurveyFile.canonical_text(shuffled)).is_equal(SurveyFile.canonical_text(envelope))
	assert_str(SurveyFile.checksum_of(shuffled)).is_equal(SurveyFile.checksum_of(envelope))

func test_canonical_text_is_ascii_sorted_and_newline_terminated() -> void:
	var text := SurveyFile.canonical_text(SurveyFile.envelope_from_graph(SurveyGraphFixture.small_graph()))
	assert_bool(text.ends_with("\n")).is_true()
	assert_bool(text.contains("\r")).is_false()
	for index in text.length():
		assert_int(text.unicode_at(index)).is_less(128)
	assert_int(text.find("\"audio\"")).is_less(text.find("\"graph\""))
	assert_int(text.find("\"graph\"")).is_less(text.find("\"header\""))

func test_checksum_is_stable_and_content_sensitive() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var stamped := SurveyFile.stamp_checksum(SurveyFile.envelope_from_graph(graph))
	var errors: Array = []
	assert_bool(SurveyFile.verify_checksum(stamped, errors)).is_true()
	assert_array(errors).is_empty()
	assert_str(String((SurveyFile.stamp_checksum(stamped)["header"] as Dictionary)["checksum"])).is_equal(String((stamped["header"] as Dictionary)["checksum"]))
	assert_int(String((stamped["header"] as Dictionary)["checksum"]).length()).is_equal(16)
	var mutated := SurveyGraphFixture.small_graph()
	mutated.tick = 601
	assert_str(SurveyFile.checksum_of(SurveyFile.envelope_from_graph(mutated))).is_not_equal(SurveyFile.checksum_of(SurveyFile.envelope_from_graph(graph)))

func test_graph_state_hash_tracks_authoritative_state_only() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var before := graph.state_hash()
	graph.rebuild_caches()
	assert_str(graph.state_hash()).is_equal(before)
	graph.push_audible_event(Vector3i(0, 0, 5000), 15, 14000, 610)
	assert_str(graph.state_hash()).is_not_equal(before)
