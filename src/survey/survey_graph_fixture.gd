class_name SurveyGraphFixture
extends RefCounted

# One small authoritative graph shared by the M2 suites and the round-trip
# playthrough: two stations, a junction, one unscanned branch, half coverage,
# duplicate 4 m cells merged into one chunk, a two-event audible queue, an
# interrupted scan burst, and the entity parked mid-edge.

const TEMP_DIR := "user://m2_survey_tests"

static func temp_path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var path := "%s/%s" % [TEMP_DIR, name]
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	return path

static func small_graph() -> SurveyGraphV1:
	var graph := SurveyGraphV1.new(19790417)
	graph.tick = 600
	graph.playtime_ms = 10000
	graph.act = 1
	var region := graph.add_region("CH-02", "Sorting Hall", 16)
	var station_a := graph.add_node(region, Vector3i(0, 0, 0), SurveyGraphV1.KIND_STATION)
	var junction := graph.add_node(region, Vector3i(0, 0, 6000), SurveyGraphV1.KIND_JUNCTION)
	var station_b := graph.add_node(region, Vector3i(0, 0, 12000), SurveyGraphV1.KIND_STATION)
	var dark := graph.add_node(region, Vector3i(6000, 0, 12000), SurveyGraphV1.KIND_WAYPOINT)
	graph.add_edge(station_a, junction, "ROCK")
	graph.add_edge(junction, station_b, "GRATE")
	graph.add_edge(station_b, dark, "SALT")
	graph.scan_path([station_a, junction, station_b])
	for cell in 8:
		graph.mark_cell_scanned(region, cell)
	graph.store_points(region, PackedInt32Array([10, 20, 30, 128, 11, 21, 31, 200]))
	graph.store_points(region, PackedInt32Array([12, 22, 32, 64]))
	graph.push_audible_event(Vector3i(0, 0, 3000), 10, 9000, 590)
	graph.push_audible_event(Vector3i(0, 0, 4000), 12, 11000, 600)
	graph.player["pos_mm"] = Vector3i(0, 0, 1500)
	graph.player["charge_tenths"] = 750
	graph.player["inventory"] = ["TRIPOD", "PLOT_SHEET"]
	graph.scanner["seed"] = 19790417
	graph.scanner["charge_tenths"] = 750
	graph.scanner["charge_accumulator"] = 30
	graph.scanner["rng_state"] = 4242
	graph.pending = {"action": "SCAN_BURST", "elapsed_ticks": 12, "params": {"region": "1"}}
	graph.rng = {"gen_stream": 19790417, "sim_stream": [1234567890123, 987654321]}
	var entity := SurveyGraphV1.default_entity()
	entity["present"] = true
	entity["state"] = "Survey"
	entity["edge_id"] = graph.edge_between(station_a, junction)
	entity["edge_from"] = station_a
	entity["edge_to"] = junction
	entity["edge_t_mm"] = 2400
	entity["accumulator"] = 20
	entity["route"] = [station_a, junction, station_b]
	entity["visit_counts"] = [[station_a, 2], [station_b, 1]]
	entity["route_memory"] = [[station_a, station_b], [station_b, station_a]]
	entity["suspicion_tenths"] = 355
	entity["timers_ticks"] = {"state": 42, "wait": 0, "retry": 0}
	graph.entity = entity
	graph.rebuild_caches()
	return graph

static func region_id_of(graph: SurveyGraphV1) -> int:
	return int(graph.sorted_region_ids()[0])

# The pre-review v0 envelope of DESIGN.md 15.1 defects 2 and 6: no region erase
# status, no audible queue, no pending action, no tick clock.
static func v0_envelope(graph: SurveyGraphV1) -> Dictionary:
	var envelope := SurveyFile.envelope_from_graph(graph)
	var header: Dictionary = envelope["header"]
	header["version"] = "0"
	header.erase("tick")
	header.erase("act")
	header.erase("playtime_ms")
	envelope["header"] = header
	var graph_data: Dictionary = envelope["graph"]
	graph_data["version"] = "0"
	var regions: Array = graph_data["regions"]
	for item in regions:
		var region: Dictionary = item
		region.erase("status")
		region.erase("erase_deadline_tick")
		region.erase("complete")
		region.erase("name")
	envelope["graph"] = graph_data
	envelope.erase("audio")
	envelope.erase("pending")
	envelope.erase("rng")
	return envelope
