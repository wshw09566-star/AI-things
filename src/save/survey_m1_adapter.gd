class_name SurveyM1Adapter
extends RefCounted

# Explicit adapter between the M1 classes and the M2 authoritative graph. M1 keeps
# its authority (spatial truth, cap accounting, motion law, confinement); M2 owns
# the versioned schema and the survey file. Nothing here duplicates an M1 rule: it
# only maps the M1 snapshots onto the section 3.1 records and back, so the
# deterministic M1 state hash survives save -> load -> continue.

static func graph_from_m1(space: SurveySpace, scanner: ScannerCore, player: PlayerMotionState, patroller: EntityPatroller, seed_value: int, tick: int, cell_totals: Dictionary = {}) -> SurveyGraphV1:
	var graph := SurveyGraphV1.new(seed_value, int(space.global_cap), int(space.region_cap))
	graph.tick = maxi(0, tick)
	graph.playtime_ms = maxi(0, tick) * 1000 / 60
	for region_id in SurveySpace.sorted_int_keys(space.regions):
		var source: Dictionary = space.regions[region_id]
		var cell_total := int(cell_totals.get(int(region_id), 0))
		graph.regions[int(region_id)] = {
			"id": int(region_id),
			"chamber_code": String(source["chamber_code"]),
			"name": "Region %d" % int(region_id),
			"cell_total": cell_total,
			"cells": SurveyCoverageBitset.empty(cell_total),
			"complete": false,
			"status": String(source["status"]),
			"erase_deadline_tick": null,
			"chunk_ids": (source["chunk_ids"] as Array).duplicate(),
		}
	for node_id in SurveySpace.sorted_int_keys(space.nodes):
		var node: Dictionary = space.nodes[node_id]
		var kind := String(node["kind"])
		var station: Variant = null
		if kind == SurveyGraphV1.KIND_STATION:
			station = SurveyGraphV1.make_station("S-%04d" % int(node_id), "HALVARD", null)
		graph.nodes[int(node_id)] = {
			"id": int(node_id),
			"pos": node["pos"],
			"region_id": int(node["region_id"]),
			"kind": kind,
			"scanned": bool(node["scanned"]),
			"station": station,
		}
	for edge_id in SurveySpace.sorted_int_keys(space.edges):
		graph.edges[int(edge_id)] = (space.edges[edge_id] as Dictionary).duplicate(true)
	for chunk_id in SurveySpace.sorted_int_keys(space.chunks):
		graph.chunks[int(chunk_id)] = (space.chunks[chunk_id] as Dictionary).duplicate(true)
	graph.next_ids = (space.next_ids as Dictionary).duplicate(true)
	if scanner != null:
		var scanner_snapshot := scanner.to_snapshot()
		graph.scanner = {
			"seed": int(scanner_snapshot["seed"]),
			"charge_tenths": int(scanner_snapshot["charge_tenths"]),
			"charge_accumulator": int(scanner_snapshot["charge_accumulator"]),
			"burst_count": int(scanner_snapshot["burst_count"]),
			"sample_count": int(scanner_snapshot["sample_count"]),
			"rng_state": int(scanner_snapshot["rng_state"]),
		}
	if player != null:
		var player_snapshot := player.to_snapshot()
		graph.player = {
			"pos_mm": player_snapshot["pos"],
			"accumulator": int(player_snapshot["accumulator"]),
			"stride_progress_mm": int(player_snapshot["stride_progress_mm"]),
			"step_count": int(player_snapshot["step_count"]),
			"yaw_centidegrees": int(player_snapshot["yaw_centidegrees"]),
			"pitch_centidegrees": 0,
			"lean_mm": int(player_snapshot["lean_mm"]),
			"crouched": String(player_snapshot["stance"]) == PlayerMotionState.STANCE_CROUCH,
			"surface": String(player_snapshot["surface"]),
			"charge_tenths": int(graph.scanner["charge_tenths"]),
			"tripod_deployed": true,
			"tripod_carried_by_entity": false,
			"tripod_node_id": -1,
			"inventory": [],
			"artifacts_read": [],
		}
		# Footsteps are the AudibleEvents of section 11: draining them into the
		# graph queue is what makes the 30 s Triangulate guard survive a save.
		for event in player_snapshot["events"]:
			var record: Dictionary = event
			graph.push_audible_event(record["pos"], int(record["loudness_tenths"]), int(record["radius_mm"]), graph.tick)
	if patroller != null:
		var entity_snapshot := patroller.to_snapshot()
		var entity := SurveyGraphV1.default_entity()
		entity["present"] = int(entity_snapshot["at_node_id"]) != -1 or int(entity_snapshot["edge_id"]) != -1
		entity["node_id"] = int(entity_snapshot["at_node_id"])
		entity["edge_id"] = int(entity_snapshot["edge_id"])
		entity["edge_from"] = int(entity_snapshot["edge_from"])
		entity["edge_to"] = int(entity_snapshot["edge_to"])
		entity["edge_t_mm"] = int(entity_snapshot["edge_t_mm"])
		entity["accumulator"] = int(entity_snapshot["accumulator"])
		entity["route"] = (entity_snapshot["route"] as Array).duplicate()
		entity["route_index"] = int(entity_snapshot["route_index"])
		entity["halted_at_boundary"] = bool(entity_snapshot["halted_at_boundary"])
		entity["boundary_halts"] = int(entity_snapshot["boundary_halts"])
		entity["arrivals"] = int(entity_snapshot["arrivals"])
		graph.entity = entity
	graph.rebuild_caches()
	return graph

static func space_from_graph(graph: SurveyGraphV1) -> SurveySpace:
	var nodes := {}
	var adjacency := {}
	for node_id in graph.sorted_node_ids():
		var node: Dictionary = graph.nodes[node_id]
		nodes[int(node_id)] = {
			"id": int(node_id),
			"pos": node["pos"],
			"region_id": int(node["region_id"]),
			"kind": String(node["kind"]),
			"scanned": bool(node["scanned"]),
		}
		adjacency[int(node_id)] = graph.incident_edge_ids(int(node_id))
	var edges := {}
	for edge_id in graph.sorted_edge_ids():
		edges[int(edge_id)] = (graph.edges[edge_id] as Dictionary).duplicate(true)
	var regions := {}
	var cell_chunks := {}
	var dedup := {}
	for region_id in graph.sorted_region_ids():
		var region: Dictionary = graph.regions[region_id]
		regions[int(region_id)] = {
			"id": int(region_id),
			"chamber_code": String(region["chamber_code"]),
			"status": String(region["status"]),
			"stored": graph.region_point_total(int(region_id)),
			"chunk_ids": (region["chunk_ids"] as Array).duplicate(),
		}
		cell_chunks[int(region_id)] = {}
		dedup[int(region_id)] = {}
	var chunks := {}
	var stored_total := 0
	for chunk_id in graph.sorted_chunk_ids():
		var chunk: Dictionary = graph.chunks[chunk_id]
		var region_id := int(chunk["region_id"])
		chunks[int(chunk_id)] = chunk.duplicate(true)
		var cells: Dictionary = cell_chunks.get(region_id, {})
		cells[int(chunk["cell"])] = int(chunk_id)
		cell_chunks[region_id] = cells
		var keys: Dictionary = dedup.get(region_id, {})
		var points: PackedInt32Array = chunk["points"]
		var quads := points.size() / 4
		for index in quads:
			var base := index * 4
			keys[SurveySpace.dedup_key(points[base], points[base + 1], points[base + 2])] = true
		dedup[region_id] = keys
		stored_total += int(chunk["count"])
	return SurveySpace.from_snapshot({
		"global_cap": int(graph.caps["global"]),
		"region_cap": int(graph.caps["region"]),
		"next_ids": (graph.next_ids as Dictionary).duplicate(true),
		"nodes": nodes,
		"edges": edges,
		"regions": regions,
		"chunks": chunks,
		"adjacency": adjacency,
		"cell_chunks": cell_chunks,
		"dedup": dedup,
		"stored_total": stored_total,
	})

static func scanner_from_graph(graph: SurveyGraphV1) -> ScannerCore:
	return ScannerCore.from_snapshot({
		"seed": int(graph.scanner["seed"]),
		"charge_tenths": int(graph.scanner["charge_tenths"]),
		"charge_accumulator": int(graph.scanner["charge_accumulator"]),
		"burst_count": int(graph.scanner["burst_count"]),
		"sample_count": int(graph.scanner["sample_count"]),
		"rng_state": int(graph.scanner["rng_state"]),
	})

static func player_from_graph(graph: SurveyGraphV1) -> PlayerMotionState:
	return PlayerMotionState.from_snapshot({
		"pos": graph.player["pos_mm"],
		"stance": PlayerMotionState.STANCE_CROUCH if bool(graph.player["crouched"]) else PlayerMotionState.STANCE_WALK,
		"lean_mm": int(graph.player["lean_mm"]),
		"yaw_centidegrees": int(graph.player["yaw_centidegrees"]),
		"surface": String(graph.player["surface"]),
		"accumulator": int(graph.player["accumulator"]),
		"stride_progress_mm": int(graph.player["stride_progress_mm"]),
		"step_count": int(graph.player["step_count"]),
		"events": [],
	})

static func patroller_from_graph(graph: SurveyGraphV1) -> EntityPatroller:
	return EntityPatroller.from_snapshot({
		"route": (graph.entity["route"] as Array).duplicate(),
		"route_index": int(graph.entity["route_index"]),
		"at_node_id": int(graph.entity["node_id"]),
		"edge_id": int(graph.entity["edge_id"]),
		"edge_from": int(graph.entity["edge_from"]),
		"edge_to": int(graph.entity["edge_to"]),
		"edge_t_mm": int(graph.entity["edge_t_mm"]),
		"accumulator": int(graph.entity["accumulator"]),
		"halted_at_boundary": bool(graph.entity["halted_at_boundary"]),
		"boundary_halts": int(graph.entity["boundary_halts"]),
		"arrivals": int(graph.entity["arrivals"]),
	})

static func m1_from_graph(graph: SurveyGraphV1) -> Dictionary:
	return {
		"space": space_from_graph(graph),
		"scanner": scanner_from_graph(graph),
		"player": player_from_graph(graph),
		"patroller": patroller_from_graph(graph),
	}

static func state_hash(bundle: Dictionary) -> String:
	return M1StateHash.of(bundle["space"], bundle["scanner"], bundle["player"], bundle["patroller"])
