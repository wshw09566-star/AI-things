extends GdUnitTestSuite

# M2 SurveyGraphV1 schema: strict typed records, station metadata iff STATION,
# normalized edges with integer permille cost, monotonic ids, sorted iteration,
# merged duplicate cells, and decimal-string encoding of authoritative integers.

func test_typed_records_and_station_metadata_follow_the_kind() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var region := SurveyGraphFixture.region_id_of(graph)
	var station_ids := graph.station_node_ids()
	assert_int(station_ids.size()).is_equal(2)
	for node_id in graph.sorted_node_ids():
		var node: Dictionary = graph.nodes[node_id]
		assert_int(typeof(node["pos"])).is_equal(TYPE_VECTOR3I)
		assert_int(typeof(node["scanned"])).is_equal(TYPE_BOOL)
		if String(node["kind"]) == SurveyGraphV1.KIND_STATION:
			assert_int(typeof(node["station"])).is_equal(TYPE_DICTIONARY)
		else:
			assert_bool(node["station"] == null).is_true()
	assert_int(graph.add_node(region, Vector3i.ZERO, SurveyGraphV1.KIND_WAYPOINT, false, {"station_no": "S-0001"})).is_equal(-1)
	assert_int(graph.add_node(region, Vector3i.ZERO, "CAVERN")).is_equal(-1)
	assert_int(graph.add_region("CH-03", "Sump", -1)).is_equal(-1)

func test_edges_are_normalized_with_integer_permille_cost() -> void:
	var graph := SurveyGraphV1.new()
	var region := graph.add_region("CH-02", "Sorting Hall", 0)
	var far := graph.add_node(region, Vector3i(0, 0, 6000))
	var near := graph.add_node(region, Vector3i(0, 0, 0))
	var edge_id := graph.add_edge(far, near, "GRATE")
	var edge: Dictionary = graph.edges[edge_id]
	assert_int(int(edge["a"])).is_equal(mini(far, near))
	assert_int(int(edge["b"])).is_equal(maxi(far, near))
	assert_int(int(edge["length_mm"])).is_equal(6000)
	assert_int(int(edge["cost"])).is_equal(6600)
	assert_int(graph.add_edge(near, far, "ROCK")).is_equal(edge_id)
	assert_int(graph.add_edge(near, near)).is_equal(-1)
	assert_int(graph.add_edge(near, far, "MARBLE")).is_equal(-1)

func test_ids_are_monotonic_and_never_reused_after_erasure() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var region := SurveyGraphFixture.region_id_of(graph)
	var highest_node := int(graph.sorted_node_ids()[graph.sorted_node_ids().size() - 1])
	assert_bool(graph.erase_region(region, 600)).is_true()
	assert_int(graph.nodes.size()).is_equal(0)
	assert_int(graph.tombstones.size()).is_equal(1)
	var fresh := graph.add_region("CH-02", "Rescan", 4)
	assert_int(fresh).is_greater(region)
	var node_id := graph.add_node(fresh, Vector3i.ZERO)
	assert_int(node_id).is_greater(highest_node)
	var report := SurveyValidator.validate(graph)
	assert_bool(bool(report["ok"])).is_true()

func test_iteration_is_sorted_by_id() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var ids := graph.sorted_node_ids()
	var expected := ids.duplicate()
	expected.sort()
	assert_array(ids).is_equal(expected)
	var serialized: Array = graph.to_json_dict()["nodes"]
	var previous := 0
	for record in serialized:
		assert_int(int((record as Dictionary)["id"])).is_greater(previous)
		previous = int((record as Dictionary)["id"])

func test_duplicate_cells_merge_into_one_chunk() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var region := SurveyGraphFixture.region_id_of(graph)
	assert_int(graph.chunks.size()).is_equal(1)
	assert_int(graph.region_point_total(region)).is_equal(3)
	assert_int(graph.point_total()).is_equal(3)
	var chunk: Dictionary = graph.chunks[int(graph.sorted_chunk_ids()[0])]
	assert_int(int(chunk["count"]) * 4).is_equal((chunk["points"] as PackedInt32Array).size())

func test_caps_account_for_every_received_point() -> void:
	var graph := SurveyGraphV1.new(1, 4, 2)
	var region := graph.add_region("CH-02", "Sorting Hall", 0)
	var result := graph.store_points(region, PackedInt32Array([0, 0, 0, 10, 1, 0, 0, 10, 2, 0, 0, 10]))
	assert_int(int(result["received"])).is_equal(3)
	assert_int(int(result["stored"])).is_equal(2)
	assert_int(int(result["region_capped"])).is_equal(1)
	assert_int(int(result["stored"]) + int(result["region_capped"]) + int(result["global_capped"])).is_equal(3)

func test_authoritative_integers_serialize_as_canonical_decimal_strings() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var encoded: Dictionary = SurveyCanonicalJson.encode(SurveyFile.envelope_from_graph(graph))
	var header: Dictionary = encoded["header"]
	assert_int(typeof(header["tick"])).is_equal(TYPE_STRING)
	assert_bool(SurveyIntCodec.is_canonical(String(header["tick"]))).is_true()
	var chunk: Dictionary = (encoded["graph"]["chunks"] as Array)[0]
	assert_int(typeof(chunk["cell"])).is_equal(TYPE_STRING)
	assert_bool(SurveyIntCodec.is_canonical(String(chunk["cell"]))).is_true()
	var node: Dictionary = (encoded["graph"]["nodes"] as Array)[0]
	assert_int(typeof(node["id"])).is_equal(TYPE_STRING)
	assert_bool(SurveyIntCodec.is_canonical("007")).is_false()
	assert_bool(SurveyIntCodec.is_canonical("-0")).is_false()
	assert_bool(SurveyIntCodec.is_canonical("+7")).is_false()
	assert_bool(SurveyIntCodec.is_canonical("-12")).is_true()
	var errors: Array = []
	assert_int(SurveyIntCodec.decode("1234567890123456", "probe", errors)).is_equal(1234567890123456)
	assert_int(errors.size()).is_equal(0)

func test_coverage_bitset_is_msb_first_with_a_fixed_length() -> void:
	var cells := SurveyCoverageBitset.empty(16)
	assert_int(Marshalls.base64_to_raw(cells).size()).is_equal(2)
	cells = SurveyCoverageBitset.set_bit(cells, 16, 0)
	assert_int(int(Marshalls.base64_to_raw(cells)[0])).is_equal(128)
	cells = SurveyCoverageBitset.set_bit(cells, 16, 15)
	assert_int(int(Marshalls.base64_to_raw(cells)[1])).is_equal(1)
	assert_int(SurveyCoverageBitset.popcount(cells, 16)).is_equal(2)
	assert_bool(SurveyCoverageBitset.get_bit(cells, 15)).is_true()
	var errors: Array = []
	SurveyCoverageBitset.decode(cells, 16, "cells", errors)
	assert_int(errors.size()).is_equal(0)
	SurveyCoverageBitset.decode(cells, 12, "cells", errors)
	assert_int(errors.size()).is_greater(0)
