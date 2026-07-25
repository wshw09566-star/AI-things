extends GdUnitTestSuite

# M1 SurveySpace: id monotonicity, integer costs, deterministic ordering, the
# scanned-edge invariant, point persistence, dedup, and the cap accounting rule.

func test_ids_are_monotonic_and_never_reused() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	var first := space.add_node(region, Vector3i.ZERO, SurveySpace.KIND_STATION)
	var second := space.add_node(region, Vector3i(0, 0, 6000))
	assert_int(region).is_equal(1)
	assert_int(first).is_equal(1)
	assert_int(second).is_equal(2)
	assert_int(int(space.next_ids["node"])).is_equal(3)
	space.nodes.erase(second)
	var third := space.add_node(region, Vector3i(0, 0, 12000))
	assert_int(third).is_equal(3)

func test_edge_normalizes_endpoints_and_uses_integer_cost() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	var a := space.add_node(region, Vector3i(0, 0, 6000))
	var b := space.add_node(region, Vector3i(0, 0, 0))
	var edge_id := space.add_edge(b, a, "GRATE")
	var edge: Dictionary = space.edges[edge_id]
	assert_int(int(edge["a"])).is_equal(mini(a, b))
	assert_int(int(edge["b"])).is_equal(maxi(a, b))
	assert_int(int(edge["length_mm"])).is_equal(6000)
	assert_int(int(edge["cost"])).is_equal(6600)
	assert_int(space.add_edge(a, b, "ROCK")).is_equal(edge_id)
	assert_int(space.add_edge(a, a)).is_equal(-1)
	assert_int(space.add_edge(a, b, "MARBLE")).is_equal(-1)

func test_diagonal_length_uses_integer_square_root() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("DR-01")
	var a := space.add_node(region, Vector3i.ZERO)
	var b := space.add_node(region, Vector3i(3000, 0, 4000))
	var edge_id := space.add_edge(a, b)
	assert_int(space.edge_length_mm(edge_id)).is_equal(5000)
	assert_int(SurveySpace.isqrt(0)).is_equal(0)
	assert_int(SurveySpace.isqrt(15)).is_equal(3)
	assert_int(SurveySpace.isqrt(16)).is_equal(4)

func test_neighbours_are_deterministically_sorted() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("CH-04")
	var hub := space.add_node(region, Vector3i.ZERO, SurveySpace.KIND_JUNCTION)
	var north := space.add_node(region, Vector3i(0, 0, 4000))
	var east := space.add_node(region, Vector3i(4000, 0, 0))
	var west := space.add_node(region, Vector3i(-4000, 0, 0))
	space.add_edge(hub, east)
	space.add_edge(hub, north)
	space.add_edge(hub, west)
	assert_array(space.neighbours(hub)).is_equal([north, east, west])
	assert_array(space.neighbours(hub)).is_equal(space.neighbours(hub))
	assert_array(space.neighbours(9999)).is_empty()

func test_edge_scan_requires_both_endpoints_scanned() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	var a := space.add_node(region, Vector3i.ZERO, SurveySpace.KIND_STATION)
	var b := space.add_node(region, Vector3i(0, 0, 6000))
	var edge_id := space.add_edge(a, b)
	space.mark_node_scanned(a)
	assert_bool(space.mark_edge_scanned(edge_id)).is_false()
	assert_bool(space.is_edge_scanned(edge_id)).is_false()
	space.mark_node_scanned(b)
	assert_bool(space.mark_edge_scanned(edge_id)).is_true()
	assert_bool(space.is_edge_traversable(edge_id)).is_true()
	space.set_region_status(region, SurveySpace.STATUS_PENDING_ERASE)
	assert_bool(space.is_edge_traversable(edge_id)).is_false()
	assert_bool(space.is_node_traversable(a)).is_false()

func test_scan_corridor_reports_nodes_and_edges() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	var ids: Array = []
	for index in 4:
		ids.append(space.add_node(region, Vector3i(0, 0, index * 6000)))
	for index in 3:
		space.add_edge(int(ids[index]), int(ids[index + 1]))
	var result := space.scan_corridor([ids[0], ids[1], ids[2]])
	assert_int(int(result["nodes"])).is_equal(3)
	assert_int(int(result["edges"])).is_equal(2)
	assert_array(space.scanned_node_ids()).is_equal([ids[0], ids[1], ids[2]])
	assert_array(space.scanned_edge_ids()).has_size(2)
	assert_array(space.scanned_neighbours(int(ids[2]))).is_equal([ids[1]])

func test_points_persist_and_deduplicate_by_spatial_cell() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("CH-02")
	var first := space.store_points(region, PackedInt32Array([0, 0, 0, 200, 5, 5, 5, 200, 0, 0, 10, 200]))
	assert_bool(bool(first["ok"])).is_true()
	assert_int(int(first["stored"])).is_equal(2)
	assert_int(int(first["duplicates"])).is_equal(1)
	var second := space.store_points(region, PackedInt32Array([0, 0, 0, 200]))
	assert_int(int(second["stored"])).is_equal(0)
	assert_int(int(second["duplicates"])).is_equal(1)
	assert_int(space.point_total()).is_equal(2)
	assert_int(space.region_point_total(region)).is_equal(2)
	assert_int(space.chunk_point_sum()).is_equal(2)
	assert_int(space.store_points(region, PackedInt32Array([1, 2, 3]))["received"]).is_equal(0)

func test_caps_account_for_every_received_sample() -> void:
	var space := SurveySpace.new(10, 6)
	var first_region := space.add_region("CH-02")
	var second_region := space.add_region("CH-04")
	var batch := PackedInt32Array()
	for index in 8:
		batch.append(index * 20)
		batch.append(0)
		batch.append(0)
		batch.append(255)
	var first := space.store_points(first_region, batch)
	assert_int(int(first["received"])).is_equal(8)
	assert_int(int(first["stored"])).is_equal(6)
	assert_int(int(first["region_capped"])).is_equal(2)
	assert_bool(bool(first["at_cap"])).is_true()
	var second := space.store_points(second_region, batch)
	assert_int(int(second["stored"])).is_equal(4)
	assert_int(int(second["global_capped"])).is_equal(4)
	assert_int(int(second["received"])).is_equal(int(second["stored"]) + int(second["duplicates"]) + int(second["region_capped"]) + int(second["global_capped"]))
	assert_int(space.point_total()).is_equal(10)
	assert_int(space.chunk_point_sum()).is_equal(10)
	assert_int(space.region_point_total(first_region)).is_less_equal(6)

func test_chunk_keys_are_non_negative_and_grid_aligned() -> void:
	var space := SurveySpace.new()
	var region := space.add_region("CH-04")
	space.store_points(region, PackedInt32Array([0, 0, 0, 100, 30, 0, 0, 100, 500, 0, 0, 100]))
	var chunk_ids := space.chunk_ids_for(region)
	assert_array(chunk_ids).has_size(2)
	assert_int(int(chunk_ids[0])).is_less(int(chunk_ids[1]))
	for chunk_id in chunk_ids:
		assert_int(int(space.chunks[chunk_id]["cell"])).is_greater_equal(0)
	assert_int(SurveySpace.cell_key(-1, -1, -1)).is_not_equal(SurveySpace.cell_key(0, 0, 0))
	assert_int(SurveySpace.floor_div(-1, 4000)).is_equal(-1)
	assert_int(SurveySpace.floor_div(-4000, 4000)).is_equal(-1)
	assert_int(SurveySpace.floor_div(4000, 4000)).is_equal(1)

func test_snapshot_round_trip_preserves_canonical_text() -> void:
	var space := SurveySpace.new(64, 32)
	var region := space.add_region("CH-02")
	var a := space.add_node(region, Vector3i.ZERO, SurveySpace.KIND_STATION)
	var b := space.add_node(region, Vector3i(0, 0, 6000), SurveySpace.KIND_JUNCTION)
	space.add_edge(a, b, "SALT")
	space.scan_corridor([a, b])
	space.store_points(region, PackedInt32Array([0, 0, 0, 128, 0, 0, 30, 128]))
	var restored := SurveySpace.from_snapshot(space.to_snapshot())
	assert_str(restored.canonical_text()).is_equal(space.canonical_text())
	restored.store_points(region, PackedInt32Array([0, 0, 60, 128]))
	assert_str(restored.canonical_text()).is_not_equal(space.canonical_text())
	assert_int(space.point_total()).is_equal(2)
