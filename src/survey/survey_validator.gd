class_name SurveyValidator
extends RefCounted

# DESIGN.md section 3.3 invariants V1 to V10, asserted on load and after every
# mutation batch, plus the section 2 point cap accounting. Every failure is
# reported as a prefixed string so a refused save names the invariant it broke.

static func validate(graph: SurveyGraphV1) -> Dictionary:
	var errors: Array = []
	_v1_edges(graph, errors)
	_v2_nodes(graph, errors)
	_v3_entity_position(graph, errors)
	_v4_completion(graph, errors)
	_v5_tombstones(graph, errors)
	_v6_chunks(graph, errors)
	_v7_scanned(graph, errors)
	_v8_next_ids(graph, errors)
	_v9_entity_route(graph, errors)
	_v10_snapshots(graph, errors)
	_caps(graph, errors)
	_erase_metadata(graph, errors)
	return {"ok": errors.is_empty(), "errors": errors}

static func _v1_edges(graph: SurveyGraphV1, errors: Array) -> void:
	for edge_id in graph.sorted_edge_ids():
		var edge: Dictionary = graph.edges[edge_id]
		var a := int(edge["a"])
		var b := int(edge["b"])
		if not graph.nodes.has(a) or not graph.nodes.has(b):
			errors.append("V1: edge %d references a missing node" % int(edge_id))
			continue
		if a >= b:
			errors.append("V1: edge %d endpoints are not normalized (a < b)" % int(edge_id))
		var surface := String(edge["surface"])
		if not SurveyGraphV1.SURFACE_PERMILLE.has(surface):
			errors.append("V1: edge %d has unknown surface %s" % [int(edge_id), surface])
			continue
		var expected := (int(edge["length_mm"]) * int(SurveyGraphV1.SURFACE_PERMILLE[surface])) / 1000
		if int(edge["cost"]) != expected:
			errors.append("V1: edge %d cost %d is not the integer permille cost %d" % [int(edge_id), int(edge["cost"]), expected])

static func _v2_nodes(graph: SurveyGraphV1, errors: Array) -> void:
	for node_id in graph.sorted_node_ids():
		var node: Dictionary = graph.nodes[node_id]
		if not graph.regions.has(int(node["region_id"])):
			errors.append("V2: node %d references missing region %d" % [int(node_id), int(node["region_id"])])
		var is_station := String(node["kind"]) == SurveyGraphV1.KIND_STATION
		var has_station: bool = node["station"] != null
		if is_station != has_station:
			errors.append("V2: node %d station metadata must exist iff kind is STATION" % int(node_id))

static func _v3_entity_position(graph: SurveyGraphV1, errors: Array) -> void:
	if not bool(graph.entity["present"]):
		return
	if not SurveyGraphV1.ENTITY_STATES.has(String(graph.entity["state"])):
		errors.append("V3: entity state %s is not one of the five states" % String(graph.entity["state"]))
	var node_id := int(graph.entity["node_id"])
	var edge_id := int(graph.entity["edge_id"])
	if node_id != -1 and edge_id != -1:
		errors.append("V3: entity cannot be at a node and on an edge at once")
		return
	if node_id != -1:
		if not graph.is_node_traversable(node_id):
			errors.append("V3: entity node %d is not scanned live space" % node_id)
		return
	if edge_id == -1:
		errors.append("V3: a present entity needs a node or an edge position")
		return
	if not graph.is_edge_traversable(edge_id):
		errors.append("V3: entity edge %d is not scanned live space" % edge_id)
		return
	var length := int((graph.edges[edge_id] as Dictionary)["length_mm"])
	var offset := int(graph.entity["edge_t_mm"])
	if offset < 0 or offset > length:
		errors.append("V3: entity edge offset %d is outside edge %d" % [offset, edge_id])

static func _v4_completion(graph: SurveyGraphV1, errors: Array) -> void:
	var report := graph.completion()
	var tenths := int(report["percent_tenths"])
	if tenths < 0 or tenths > 1000:
		errors.append("V4: completion %d tenths is outside [0,100]%%" % tenths)
	if int(report["denominator"]) == 0 and tenths != 0:
		errors.append("V4: an empty live denominator must read exactly 0%")
	for region_id in graph.sorted_region_ids():
		var region: Dictionary = graph.regions[region_id]
		var scanned := SurveyCoverageBitset.popcount(String(region["cells"]), int(region["cell_total"]))
		if scanned > int(region["cell_total"]):
			errors.append("V4: region %d coverage exceeds its cell total" % int(region_id))
		if bool(region["complete"]) != SurveyCompletion.region_complete(region):
			errors.append("V4: region %d cached complete flag is stale" % int(region_id))

static func _v5_tombstones(graph: SurveyGraphV1, errors: Array) -> void:
	for tombstone in graph.tombstones:
		var record: Dictionary = tombstone
		var region_id := int(record["region_id"])
		if graph.regions.has(region_id):
			errors.append("V5: region %d is both live and tombstoned" % region_id)
		for node_id in record["node_ids"]:
			if graph.nodes.has(int(node_id)):
				errors.append("V5: node %d is both live and tombstoned" % int(node_id))
		for edge_id in record["edge_ids"]:
			if graph.edges.has(int(edge_id)):
				errors.append("V5: edge %d is both live and tombstoned" % int(edge_id))
		for chunk_id in record["chunk_ids"]:
			if graph.chunks.has(int(chunk_id)):
				errors.append("V5: chunk %d is both live and tombstoned" % int(chunk_id))

static func _v6_chunks(graph: SurveyGraphV1, errors: Array) -> void:
	var cells_seen := {}
	for chunk_id in graph.sorted_chunk_ids():
		var chunk: Dictionary = graph.chunks[chunk_id]
		var region_id := int(chunk["region_id"])
		if not graph.regions.has(region_id):
			errors.append("V6: chunk %d references missing region %d" % [int(chunk_id), region_id])
			continue
		var listed: Array = graph.regions[region_id]["chunk_ids"]
		if not listed.has(int(chunk_id)):
			errors.append("V6: chunk %d is not listed in region %d" % [int(chunk_id), region_id])
		var points: PackedInt32Array = chunk["points"]
		if int(chunk["count"]) * 4 != points.size():
			errors.append("V6: chunk %d count %d does not match %d stored integers" % [int(chunk_id), int(chunk["count"]), points.size()])
		var key := "%d:%d" % [region_id, int(chunk["cell"])]
		if cells_seen.has(key):
			errors.append("V6: region %d has two chunks for cell %d" % [region_id, int(chunk["cell"])])
		cells_seen[key] = true
	for region_id in graph.sorted_region_ids():
		for chunk_id in graph.regions[region_id]["chunk_ids"]:
			if not graph.chunks.has(int(chunk_id)):
				errors.append("V6: region %d lists missing chunk %d" % [int(region_id), int(chunk_id)])

static func _v7_scanned(graph: SurveyGraphV1, errors: Array) -> void:
	var erased := {}
	for tombstone in graph.tombstones:
		erased[int((tombstone as Dictionary)["region_id"])] = true
	for node_id in graph.sorted_node_ids():
		var node: Dictionary = graph.nodes[node_id]
		if erased.has(int(node["region_id"])):
			errors.append("V7: node %d belongs to erased region %d" % [int(node_id), int(node["region_id"])])
	for edge_id in graph.sorted_edge_ids():
		if not graph.is_edge_scanned(int(edge_id)):
			continue
		var edge: Dictionary = graph.edges[edge_id]
		if not graph.is_node_scanned(int(edge["a"])) or not graph.is_node_scanned(int(edge["b"])):
			errors.append("V7: scanned edge %d has an unscanned endpoint" % int(edge_id))

static func _v8_next_ids(graph: SurveyGraphV1, errors: Array) -> void:
	var highest := {"node": 0, "edge": 0, "region": 0, "chunk": 0}
	for node_id in graph.nodes.keys():
		highest["node"] = maxi(int(highest["node"]), int(node_id))
	for edge_id in graph.edges.keys():
		highest["edge"] = maxi(int(highest["edge"]), int(edge_id))
	for region_id in graph.regions.keys():
		highest["region"] = maxi(int(highest["region"]), int(region_id))
	for chunk_id in graph.chunks.keys():
		highest["chunk"] = maxi(int(highest["chunk"]), int(chunk_id))
	for tombstone in graph.tombstones:
		var record: Dictionary = tombstone
		highest["region"] = maxi(int(highest["region"]), int(record["region_id"]))
		for node_id in record["node_ids"]:
			highest["node"] = maxi(int(highest["node"]), int(node_id))
		for edge_id in record["edge_ids"]:
			highest["edge"] = maxi(int(highest["edge"]), int(edge_id))
		for chunk_id in record["chunk_ids"]:
			highest["chunk"] = maxi(int(highest["chunk"]), int(chunk_id))
	for kind in ["node", "edge", "region", "chunk"]:
		if int(graph.next_ids[kind]) <= int(highest[kind]):
			errors.append("V8: next %s id %d is not above the highest used id %d" % [kind, int(graph.next_ids[kind]), int(highest[kind])])

static func _v9_entity_route(graph: SurveyGraphV1, errors: Array) -> void:
	if not bool(graph.entity["present"]):
		return
	var route: Array = graph.entity["route"]
	for node_id in route:
		if not graph.is_node_traversable(int(node_id)):
			errors.append("V9: route node %d is not scanned live space" % int(node_id))
	for index in maxi(0, route.size() - 1):
		var edge_id := graph.edge_between(int(route[index]), int(route[index + 1]))
		if edge_id == -1 or not graph.is_edge_traversable(edge_id):
			errors.append("V9: route leg %d-%d is not a scanned live edge" % [int(route[index]), int(route[index + 1])])
	var anchor := int(graph.entity["node_id"])
	if anchor == -1:
		var edge_id := int(graph.entity["edge_id"])
		if graph.edges.has(edge_id):
			anchor = int((graph.edges[edge_id] as Dictionary)["a"])
	if anchor == -1:
		return
	for node_id in graph.scanned_component(anchor):
		if not graph.is_node_scanned(int(node_id)):
			errors.append("V9: entity component contains unscanned node %d" % int(node_id))

static func _v10_snapshots(graph: SurveyGraphV1, errors: Array) -> void:
	_require_keys(graph.player, SurveyGraphV1.default_player(), "player", errors)
	_require_keys(graph.scanner, SurveyGraphV1.default_scanner(), "scanner", errors)
	_require_keys(graph.entity, SurveyGraphV1.default_entity(), "entity", errors)
	_require_keys(graph.pending, SurveyGraphV1.default_pending(), "pending", errors)
	if not SurveyGraphV1.PENDING_ACTIONS.has(String(graph.pending["action"])):
		errors.append("V10: pending action %s is not one of the four actions" % String(graph.pending["action"]))
	if int(graph.pending["elapsed_ticks"]) < 0:
		errors.append("V10: pending elapsed_ticks must not be negative")
	var previous_tick := -1
	var previous_seq := 0
	var seen := {}
	for event in graph.audible_events:
		var record: Dictionary = event
		var born := int(record["born_tick"])
		var seq := int(record["seq"])
		if seen.has(seq):
			errors.append("V10: audible event sequence %d is duplicated" % seq)
		seen[seq] = true
		if born < previous_tick or (born == previous_tick and seq <= previous_seq):
			errors.append("V10: audible event queue is not ordered by (born_tick, seq)")
		if seq >= graph.next_event_seq:
			errors.append("V10: audible event sequence %d is not below next_seq" % seq)
		previous_tick = born
		previous_seq = seq
	var last_tick := -1
	var last_region := -1
	for tombstone in graph.tombstones:
		var record: Dictionary = tombstone
		var erased := int(record["erased_tick"])
		var region_id := int(record["region_id"])
		if erased < last_tick or (erased == last_tick and region_id <= last_region):
			errors.append("V10: tombstones are not ordered by (erased_tick, region_id)")
		last_tick = erased
		last_region = region_id

static func _require_keys(section: Dictionary, template: Dictionary, field: String, errors: Array) -> void:
	for key in template.keys():
		if not section.has(String(key)):
			errors.append("V10: %s.%s is missing from the snapshot" % [field, String(key)])

static func _caps(graph: SurveyGraphV1, errors: Array) -> void:
	var total := 0
	for region_id in graph.sorted_region_ids():
		var stored := graph.region_point_total(int(region_id))
		total += stored
		if stored > int(graph.caps["region"]):
			errors.append("CAP: region %d stores %d points above the %d cap" % [int(region_id), stored, int(graph.caps["region"])])
	if total != graph.point_total():
		errors.append("CAP: per-region point totals do not sum to the global total")
	if total > int(graph.caps["global"]):
		errors.append("CAP: %d stored points exceed the global cap %d" % [total, int(graph.caps["global"])])

static func _erase_metadata(graph: SurveyGraphV1, errors: Array) -> void:
	for region_id in graph.sorted_region_ids():
		var region: Dictionary = graph.regions[region_id]
		var pending_erase := String(region["status"]) == SurveyGraphV1.STATUS_PENDING_ERASE
		var has_deadline: bool = region["erase_deadline_tick"] != null
		if pending_erase != has_deadline:
			errors.append("ERASE: region %d needs erase_deadline_tick iff it is PENDING_ERASE" % int(region_id))
	for tombstone in graph.tombstones:
		var record: Dictionary = tombstone
		if int(record["cell_total"]) < 0:
			errors.append("ERASE: tombstone %d has a negative cell total" % int(record["region_id"]))
		for field in ["node_ids", "edge_ids", "chunk_ids"]:
			var ids: Array = record[field]
			var sorted_ids: Array = ids.duplicate()
			sorted_ids.sort()
			if ids != sorted_ids:
				errors.append("ERASE: tombstone %d %s is not sorted" % [int(record["region_id"]), field])
