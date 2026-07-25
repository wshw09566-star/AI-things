extends GdUnitTestSuite

# DESIGN.md section 3.3 invariants V1 to V10 plus cap accounting and erase
# metadata. Every case mutates the shared fixture into exactly one illegal state
# and asserts the validator names that invariant.

func _errors(graph: SurveyGraphV1) -> String:
	var report := SurveyValidator.validate(graph)
	var joined := PackedStringArray()
	for message in report["errors"]:
		joined.append(String(message))
	return "\n".join(joined)

func test_the_fixture_satisfies_every_invariant() -> void:
	var report := SurveyValidator.validate(SurveyGraphFixture.small_graph())
	assert_array(report["errors"]).is_empty()
	assert_bool(bool(report["ok"])).is_true()

func test_v1_rejects_denormalized_endpoints_and_wrong_costs() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var edge_id := int(graph.sorted_edge_ids()[0])
	var edge: Dictionary = graph.edges[edge_id]
	var a := int(edge["a"])
	edge["a"] = int(edge["b"])
	edge["b"] = a
	assert_str(_errors(graph)).contains("V1: edge %d endpoints are not normalized" % edge_id)
	var other := SurveyGraphFixture.small_graph()
	(other.edges[edge_id] as Dictionary)["cost"] = 1
	assert_str(_errors(other)).contains("V1: edge %d cost" % edge_id)

func test_v2_rejects_missing_regions_and_stray_station_metadata() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var node_id := int(graph.sorted_node_ids()[0])
	(graph.nodes[node_id] as Dictionary)["region_id"] = 99
	assert_str(_errors(graph)).contains("V2: node %d references missing region 99" % node_id)
	var other := SurveyGraphFixture.small_graph()
	(other.nodes[node_id] as Dictionary)["station"] = null
	assert_str(_errors(other)).contains("V2: node %d station metadata" % node_id)

func test_v3_rejects_an_entity_off_scanned_live_space() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var edge_id := int(graph.entity["edge_id"])
	(graph.edges[edge_id] as Dictionary)["scanned"] = false
	assert_str(_errors(graph)).contains("V3: entity edge %d is not scanned live space" % edge_id)
	var other := SurveyGraphFixture.small_graph()
	other.entity["edge_t_mm"] = 999999
	assert_str(_errors(other)).contains("V3: entity edge offset")

func test_v4_rejects_stale_completion_caches() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var region_id := SurveyGraphFixture.region_id_of(graph)
	(graph.regions[region_id] as Dictionary)["complete"] = true
	assert_str(_errors(graph)).contains("V4: region %d cached complete flag is stale" % region_id)

func test_v5_rejects_ids_that_are_live_and_tombstoned() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var node_id := int(graph.sorted_node_ids()[0])
	graph.tombstones.append({
		"region_id": 77,
		"chamber_code": "CH-09",
		"erased_tick": 10,
		"erased_day": 1,
		"node_ids": [node_id],
		"edge_ids": [],
		"chunk_ids": [],
		"cell_total": 4,
	})
	assert_str(_errors(graph)).contains("V5: node %d is both live and tombstoned" % node_id)

func test_v6_rejects_broken_chunk_bookkeeping() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var chunk_id := int(graph.sorted_chunk_ids()[0])
	(graph.chunks[chunk_id] as Dictionary)["count"] = 99
	assert_str(_errors(graph)).contains("V6: chunk %d count 99" % chunk_id)
	var other := SurveyGraphFixture.small_graph()
	var region_id := SurveyGraphFixture.region_id_of(other)
	(other.regions[region_id] as Dictionary)["chunk_ids"] = []
	assert_str(_errors(other)).contains("V6: chunk %d is not listed in region %d" % [chunk_id, region_id])

func test_v7_rejects_a_scanned_edge_with_an_unscanned_endpoint() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var node_id := int(graph.sorted_node_ids()[0])
	(graph.nodes[node_id] as Dictionary)["scanned"] = false
	assert_str(_errors(graph)).contains("V7: scanned edge")

func test_v8_rejects_next_ids_that_could_be_reused() -> void:
	var graph := SurveyGraphFixture.small_graph()
	graph.next_ids["node"] = 1
	assert_str(_errors(graph)).contains("V8: next node id 1")

func test_v9_rejects_a_route_that_leaves_scanned_live_space() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var route: Array = graph.entity["route"]
	var dark := int(graph.sorted_node_ids()[3])
	route.append(dark)
	graph.entity["route"] = route
	assert_str(_errors(graph)).contains("V9: route node %d is not scanned live space" % dark)

func test_v10_rejects_unordered_queues_and_missing_snapshot_fields() -> void:
	var graph := SurveyGraphFixture.small_graph()
	var events: Array = graph.audible_events
	var first: Dictionary = events[0]
	var second: Dictionary = events[1]
	events[0] = second
	events[1] = first
	assert_str(_errors(graph)).contains("V10: audible event queue is not ordered")
	var other := SurveyGraphFixture.small_graph()
	other.entity.erase("suspicion_tenths")
	assert_str(_errors(other)).contains("V10: entity.suspicion_tenths is missing")
	var third := SurveyGraphFixture.small_graph()
	third.pending["action"] = "DIG"
	assert_str(_errors(third)).contains("V10: pending action DIG")

func test_caps_and_erase_metadata_are_asserted() -> void:
	var graph := SurveyGraphFixture.small_graph()
	graph.caps["region"] = 1
	assert_str(_errors(graph)).contains("CAP: region")
	var other := SurveyGraphFixture.small_graph()
	var region_id := SurveyGraphFixture.region_id_of(other)
	(other.regions[region_id] as Dictionary)["status"] = SurveyGraphV1.STATUS_PENDING_ERASE
	assert_str(_errors(other)).contains("ERASE: region %d needs erase_deadline_tick" % region_id)
	assert_bool(other.set_region_status(region_id, SurveyGraphV1.STATUS_PENDING_ERASE, 900)).is_true()
	assert_array(SurveyValidator.validate(other)["errors"]).is_empty()
	assert_bool(other.set_region_status(region_id, SurveyGraphV1.STATUS_PENDING_ERASE, -1)).is_false()
