class_name SurveyGraphV1
extends RefCounted

# M2 core, DESIGN.md sections 3 and 6. The versioned authoritative survey graph:
# strict typed records, integers only, deterministic sorted iteration, coverage,
# tombstones, the audible event queue, and the player/scanner/entity snapshots the
# save file must round-trip. Geometry authority (integer distance, the biased
# Morton cell key) stays with the M1 SurveySpace statics; this class calls them
# instead of re-deriving them, so there is exactly one spatial truth.

const VERSION := 1
const KIND_STATION := "STATION"
const KIND_JUNCTION := "JUNCTION"
const KIND_WAYPOINT := "WAYPOINT"
const KINDS := [KIND_STATION, KIND_JUNCTION, KIND_WAYPOINT]
const STATUS_LIVE := "LIVE"
const STATUS_PENDING_ERASE := "PENDING_ERASE"
const STATUSES := [STATUS_LIVE, STATUS_PENDING_ERASE]
const INSTALLERS := ["HALVARD", "PLAYER"]
const SURFACE_PERMILLE := {
	"ROCK": 1000,
	"RAIL": 1000,
	"GRATE": 1100,
	"RUBBLE": 1400,
	"WATER": 1600,
	"SALT": 1200,
}
const ENTITY_STATES := ["Survey", "Triangulate", "Intercept", "Withdraw", "Recalibrate"]
const PENDING_ACTIONS := ["SCAN_BURST", "ERASE_HOLD", "PLOT_UNFOLD", "NONE"]
const DEFAULT_GLOBAL_CAP := 900000
const DEFAULT_REGION_CAP := 60000

var version := VERSION
var seed_value := 0
var tick := 0
var playtime_ms := 0
var act := 1
var caps := {"global": DEFAULT_GLOBAL_CAP, "region": DEFAULT_REGION_CAP}
var next_ids := {"node": 1, "edge": 1, "region": 1, "chunk": 1}
var nodes := {}
var edges := {}
var regions := {}
var chunks := {}
var tombstones: Array = []
var audible_events: Array = []
var next_event_seq := 1
var rng := {"gen_stream": 0, "sim_stream": [0, 0]}
var player := default_player()
var scanner := default_scanner()
var entity := default_entity()
var pending := default_pending()
var last_error := ""

var _adjacency := {}
var _cell_chunks := {}
var _region_points := {}
var _point_total := 0

func _init(p_seed: int = 0, p_global_cap: int = DEFAULT_GLOBAL_CAP, p_region_cap: int = DEFAULT_REGION_CAP) -> void:
	seed_value = p_seed
	caps = {"global": maxi(0, p_global_cap), "region": maxi(0, p_region_cap)}

static func default_player() -> Dictionary:
	return {
		"pos_mm": Vector3i.ZERO,
		"accumulator": 0,
		"stride_progress_mm": 0,
		"step_count": 0,
		"yaw_centidegrees": 0,
		"pitch_centidegrees": 0,
		"lean_mm": 0,
		"crouched": false,
		"surface": "ROCK",
		"charge_tenths": 0,
		"tripod_deployed": false,
		"tripod_carried_by_entity": false,
		"tripod_node_id": -1,
		"inventory": [],
		"artifacts_read": [],
	}

static func default_scanner() -> Dictionary:
	return {
		"seed": 0,
		"charge_tenths": 0,
		"charge_accumulator": 0,
		"burst_count": 0,
		"sample_count": 0,
		"rng_state": 0,
	}

static func default_entity() -> Dictionary:
	return {
		"present": false,
		"state": "Survey",
		"waiting": false,
		"node_id": -1,
		"edge_id": -1,
		"edge_from": -1,
		"edge_to": -1,
		"edge_t_mm": 0,
		"accumulator": 0,
		"timers_ticks": {"state": 0, "wait": 0, "retry": 0},
		"bearings_taken": 0,
		"route": [],
		"route_index": 0,
		"visit_counts": [],
		"route_memory": [],
		"suspicion_tenths": 0,
		"halted_at_boundary": false,
		"boundary_halts": 0,
		"arrivals": 0,
		"erase_deadline_tick": -1,
	}

static func default_pending() -> Dictionary:
	return {"action": "NONE", "elapsed_ticks": 0, "params": {}}

static func make_station(station_no: String, installed_by: String, log_id: Variant = null) -> Dictionary:
	return {
		"station_no": station_no,
		"installed_by": installed_by if INSTALLERS.has(installed_by) else "PLAYER",
		"log_id": null if log_id == null else String(log_id),
	}

static func sorted_keys(source: Dictionary) -> Array:
	var keys := source.keys()
	keys.sort()
	return keys

func sorted_node_ids() -> Array:
	return sorted_keys(nodes)

func sorted_edge_ids() -> Array:
	return sorted_keys(edges)

func sorted_region_ids() -> Array:
	return sorted_keys(regions)

func sorted_chunk_ids() -> Array:
	return sorted_keys(chunks)

func _take_id(kind: String) -> int:
	var value := int(next_ids[kind])
	next_ids[kind] = value + 1
	return value

# --- mutation ---------------------------------------------------------------

func add_region(chamber_code: String, region_name: String, cell_total: int, status: String = STATUS_LIVE) -> int:
	if cell_total < 0:
		last_error = "cell_total must not be negative"
		return -1
	if not STATUSES.has(status):
		last_error = "unknown region status %s" % status
		return -1
	var id := _take_id("region")
	regions[id] = {
		"id": id,
		"chamber_code": chamber_code,
		"name": region_name,
		"cell_total": cell_total,
		"cells": SurveyCoverageBitset.empty(cell_total),
		"complete": false,
		"status": status,
		"erase_deadline_tick": null,
		"chunk_ids": [],
	}
	_cell_chunks[id] = {}
	_region_points[id] = 0
	return id

func _entity_touches_region(region_id: int) -> bool:
	if not bool(entity.get("present", false)):
		return false
	var node_id := int(entity.get("node_id", -1))
	if nodes.has(node_id) and int((nodes[node_id] as Dictionary)["region_id"]) == region_id:
		return true
	var edge_id := int(entity.get("edge_id", -1))
	if edges.has(edge_id):
		var edge: Dictionary = edges[edge_id]
		for endpoint in [int(edge["a"]), int(edge["b"])]:
			if nodes.has(endpoint) and int((nodes[endpoint] as Dictionary)["region_id"]) == region_id:
				return true
	for route_node in entity.get("route", []):
		var route_id := int(route_node)
		if nodes.has(route_id) and int((nodes[route_id] as Dictionary)["region_id"]) == region_id:
			return true
	return false

func _despawn_entity_if_region_invalid(region_id: int) -> void:
	if _entity_touches_region(region_id):
		entity = default_entity()

func set_region_status(region_id: int, status: String, deadline_tick: int = -1) -> bool:
	if not regions.has(region_id):
		last_error = "unknown region %d" % region_id
		return false
	if not STATUSES.has(status):
		last_error = "unknown region status %s" % status
		return false
	var region: Dictionary = regions[region_id]
	if status == STATUS_PENDING_ERASE:
		if deadline_tick < 0:
			last_error = "PENDING_ERASE needs an erase_deadline_tick"
			return false
		region["erase_deadline_tick"] = deadline_tick
	else:
		region["erase_deadline_tick"] = null
	region["status"] = status
	if status != STATUS_LIVE:
		_despawn_entity_if_region_invalid(region_id)
	return true

func is_region_live(region_id: int) -> bool:
	if not regions.has(region_id):
		return false
	return String(regions[region_id]["status"]) == STATUS_LIVE

func mark_cell_scanned(region_id: int, cell_index: int) -> bool:
	if not regions.has(region_id):
		last_error = "unknown region %d" % region_id
		return false
	var region: Dictionary = regions[region_id]
	var cell_total := int(region["cell_total"])
	if cell_index < 0 or cell_index >= cell_total:
		last_error = "cell %d outside region %d" % [cell_index, region_id]
		return false
	region["cells"] = SurveyCoverageBitset.set_bit(String(region["cells"]), cell_total, cell_index)
	region["complete"] = SurveyCompletion.region_complete(region)
	return true

func add_node(region_id: int, pos: Vector3i, kind: String = KIND_WAYPOINT, scanned: bool = false, station: Variant = null) -> int:
	if not regions.has(region_id):
		last_error = "unknown region %d" % region_id
		return -1
	if not KINDS.has(kind):
		last_error = "unknown node kind %s" % kind
		return -1
	if kind != KIND_STATION and station != null:
		last_error = "only STATION nodes carry station metadata"
		return -1
	var id := _take_id("node")
	var meta: Variant = station
	if kind == KIND_STATION and meta == null:
		meta = make_station("S-%04d" % id, "PLAYER", null)
	nodes[id] = {"id": id, "pos": pos, "region_id": region_id, "kind": kind, "scanned": scanned, "station": meta}
	_adjacency[id] = []
	return id

func add_edge(a: int, b: int, surface: String = "ROCK", scanned: bool = false, length_mm: int = -1) -> int:
	if not nodes.has(a) or not nodes.has(b) or a == b:
		last_error = "invalid edge endpoints"
		return -1
	if not SURFACE_PERMILLE.has(surface):
		last_error = "unknown surface %s" % surface
		return -1
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var existing := edge_between(lo, hi)
	if existing != -1:
		return existing
	var length := length_mm
	if length < 0:
		length = SurveySpace.distance_mm(node_position(lo), node_position(hi))
	var permille := int(SURFACE_PERMILLE[surface])
	var id := _take_id("edge")
	edges[id] = {
		"id": id,
		"a": lo,
		"b": hi,
		"length_mm": length,
		"surface": surface,
		"cost": (length * permille) / 1000,
		"scanned": scanned,
	}
	_link(lo, id)
	_link(hi, id)
	return id

func _link(node_id: int, edge_id: int) -> void:
	var list: Array = _adjacency.get(node_id, [])
	if not list.has(edge_id):
		list.append(edge_id)
		list.sort()
	_adjacency[node_id] = list

func node_position(node_id: int) -> Vector3i:
	if not nodes.has(node_id):
		return Vector3i.ZERO
	return nodes[node_id]["pos"]

func edge_between(a: int, b: int) -> int:
	for edge_id in incident_edge_ids(a):
		if other_end(int(edge_id), a) == b:
			return int(edge_id)
	return -1

func other_end(edge_id: int, node_id: int) -> int:
	if not edges.has(edge_id):
		return -1
	var edge: Dictionary = edges[edge_id]
	if int(edge["a"]) == node_id:
		return int(edge["b"])
	if int(edge["b"]) == node_id:
		return int(edge["a"])
	return -1

func incident_edge_ids(node_id: int) -> Array:
	if not _adjacency.has(node_id):
		return []
	return (_adjacency[node_id] as Array).duplicate()

func mark_node_scanned(node_id: int) -> bool:
	if not nodes.has(node_id):
		last_error = "unknown node %d" % node_id
		return false
	nodes[node_id]["scanned"] = true
	return true

func mark_edge_scanned(edge_id: int) -> bool:
	if not edges.has(edge_id):
		last_error = "unknown edge %d" % edge_id
		return false
	var edge: Dictionary = edges[edge_id]
	if not is_node_scanned(int(edge["a"])) or not is_node_scanned(int(edge["b"])):
		last_error = "edge %d has unscanned endpoints" % edge_id
		return false
	edge["scanned"] = true
	return true

func scan_path(node_ids: Array) -> int:
	var scanned_edges := 0
	for node_id in node_ids:
		mark_node_scanned(int(node_id))
	for index in maxi(0, node_ids.size() - 1):
		var edge_id := edge_between(int(node_ids[index]), int(node_ids[index + 1]))
		if edge_id != -1 and mark_edge_scanned(edge_id):
			scanned_edges += 1
	return scanned_edges

func is_node_scanned(node_id: int) -> bool:
	if not nodes.has(node_id):
		return false
	return bool(nodes[node_id]["scanned"])

func is_edge_scanned(edge_id: int) -> bool:
	if not edges.has(edge_id):
		return false
	return bool(edges[edge_id]["scanned"])

func is_node_traversable(node_id: int) -> bool:
	if not is_node_scanned(node_id):
		return false
	return is_region_live(int(nodes[node_id]["region_id"]))

func is_edge_traversable(edge_id: int) -> bool:
	if not is_edge_scanned(edge_id):
		return false
	var edge: Dictionary = edges[edge_id]
	return is_node_traversable(int(edge["a"])) and is_node_traversable(int(edge["b"]))

func station_node_ids() -> Array:
	var out: Array = []
	for node_id in sorted_node_ids():
		if String(nodes[node_id]["kind"]) == KIND_STATION:
			out.append(int(node_id))
	return out

# Stores whole-centimetre x,y,z,intensity quadruples. Points that land in the
# same 4 m cell of the same region always merge into the one chunk for that
# cell, so a duplicate cell can never shadow stored points. Nothing is dropped
# silently: received == stored + region_capped + global_capped.
func store_points(region_id: int, points_cm: PackedInt32Array) -> Dictionary:
	var result := {"ok": false, "received": 0, "stored": 0, "region_capped": 0, "global_capped": 0, "chunk_ids": []}
	if not regions.has(region_id):
		last_error = "unknown region %d" % region_id
		return result
	if points_cm.size() % 4 != 0:
		last_error = "point batch is not a whole number of quadruples"
		return result
	var received := points_cm.size() / 4
	result["ok"] = true
	result["received"] = received
	var touched := {}
	for index in received:
		var base := index * 4
		var x := points_cm[base]
		var y := points_cm[base + 1]
		var z := points_cm[base + 2]
		var intensity := clampi(points_cm[base + 3], 0, 255)
		if region_point_total(region_id) >= int(caps["region"]):
			result["region_capped"] = int(result["region_capped"]) + 1
			continue
		if _point_total >= int(caps["global"]):
			result["global_capped"] = int(result["global_capped"]) + 1
			continue
		var chunk_id := chunk_for_cell(region_id, SurveySpace.cell_key(x * 10, y * 10, z * 10))
		var chunk: Dictionary = chunks[chunk_id]
		var points: PackedInt32Array = chunk["points"]
		points.append(x)
		points.append(y)
		points.append(z)
		points.append(intensity)
		chunk["points"] = points
		chunk["count"] = int(chunk["count"]) + 1
		_region_points[region_id] = region_point_total(region_id) + 1
		_point_total += 1
		touched[chunk_id] = true
		result["stored"] = int(result["stored"]) + 1
	result["chunk_ids"] = sorted_keys(touched)
	return result

func chunk_for_cell(region_id: int, cell: int) -> int:
	var map: Dictionary = _cell_chunks.get(region_id, {})
	if map.has(cell):
		_cell_chunks[region_id] = map
		return int(map[cell])
	var id := _take_id("chunk")
	chunks[id] = {"id": id, "region_id": region_id, "cell": cell, "count": 0, "points": PackedInt32Array()}
	map[cell] = id
	_cell_chunks[region_id] = map
	var list: Array = regions[region_id]["chunk_ids"]
	list.append(id)
	list.sort()
	return id

func region_point_total(region_id: int) -> int:
	return int(_region_points.get(region_id, 0))

func point_total() -> int:
	return _point_total

func push_audible_event(pos_mm: Vector3i, loudness_tenths: int, radius_mm: int, born_tick: int) -> int:
	var seq := next_event_seq
	next_event_seq += 1
	audible_events.append({
		"seq": seq,
		"pos_mm": pos_mm,
		"loudness_tenths": loudness_tenths,
		"radius_mm": radius_mm,
		"born_tick": born_tick,
	})
	sort_audible_events()
	return seq

func sort_audible_events() -> void:
	audible_events.sort_custom(Callable(self, "_event_before"))

func _event_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["born_tick"]) != int(b["born_tick"]):
		return int(a["born_tick"]) < int(b["born_tick"])
	return int(a["seq"]) < int(b["seq"])

func sort_tombstones() -> void:
	tombstones.sort_custom(Callable(self, "_tombstone_before"))

func _tombstone_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["erased_tick"]) != int(b["erased_tick"]):
		return int(a["erased_tick"]) < int(b["erased_tick"])
	return int(a["region_id"]) < int(b["region_id"])

# DESIGN.md section 5 step 4 bookkeeping only: the M4 algorithm decides when a
# region may be erased; this records the result so status, tombstones, and
# completion round-trip through a save.
func erase_region(region_id: int, erased_tick: int) -> bool:
	if not regions.has(region_id):
		last_error = "unknown region %d" % region_id
		return false
	_despawn_entity_if_region_invalid(region_id)
	var region: Dictionary = regions[region_id]
	var node_ids: Array = []
	for node_id in sorted_node_ids():
		if int(nodes[node_id]["region_id"]) == region_id:
			node_ids.append(int(node_id))
	var edge_ids: Array = []
	for edge_id in sorted_edge_ids():
		var edge: Dictionary = edges[edge_id]
		if node_ids.has(int(edge["a"])) or node_ids.has(int(edge["b"])):
			edge_ids.append(int(edge_id))
	var chunk_ids: Array = (region["chunk_ids"] as Array).duplicate()
	tombstones.append({
		"region_id": region_id,
		"chamber_code": String(region["chamber_code"]),
		"erased_tick": erased_tick,
		"erased_day": 1 + playtime_ms / 86400000,
		"node_ids": node_ids,
		"edge_ids": edge_ids,
		"chunk_ids": chunk_ids,
		"cell_total": int(region["cell_total"]),
	})
	for edge_id in edge_ids:
		edges.erase(int(edge_id))
	for node_id in node_ids:
		nodes.erase(int(node_id))
	for chunk_id in chunk_ids:
		chunks.erase(int(chunk_id))
	regions.erase(region_id)
	sort_tombstones()
	rebuild_caches()
	return true

# Load step 5 of DESIGN.md section 6: rebuild every derived cache from the
# authoritative records. Adjacency, per-cell chunk lookup, point totals, and the
# cached region completion flag are all derived, never serialized truth.
func rebuild_caches() -> void:
	_adjacency = {}
	_cell_chunks = {}
	_region_points = {}
	_point_total = 0
	for node_id in sorted_node_ids():
		_adjacency[int(node_id)] = []
	for region_id in sorted_region_ids():
		_cell_chunks[int(region_id)] = {}
		_region_points[int(region_id)] = 0
	for edge_id in sorted_edge_ids():
		var edge: Dictionary = edges[edge_id]
		_link(int(edge["a"]), int(edge_id))
		_link(int(edge["b"]), int(edge_id))
	for chunk_id in sorted_chunk_ids():
		var chunk: Dictionary = chunks[chunk_id]
		var region_id := int(chunk["region_id"])
		var map: Dictionary = _cell_chunks.get(region_id, {})
		map[int(chunk["cell"])] = int(chunk_id)
		_cell_chunks[region_id] = map
		_region_points[region_id] = int(_region_points.get(region_id, 0)) + int(chunk["count"])
		_point_total += int(chunk["count"])
	for region_id in sorted_region_ids():
		var region: Dictionary = regions[region_id]
		region["complete"] = SurveyCompletion.region_complete(region)

func scanned_component(start_node_id: int) -> Array:
	var seen := {}
	if not nodes.has(start_node_id):
		return []
	var queue: Array = [start_node_id]
	seen[start_node_id] = true
	while not queue.is_empty():
		var current := int(queue.pop_front())
		for edge_id in incident_edge_ids(current):
			if not is_edge_scanned(int(edge_id)):
				continue
			var next_node := other_end(int(edge_id), current)
			if next_node == -1 or seen.has(next_node):
				continue
			seen[next_node] = true
			queue.append(next_node)
	return sorted_keys(seen)

func completion() -> Dictionary:
	return SurveyCompletion.of(self)

# --- serialization ----------------------------------------------------------

func to_json_dict() -> Dictionary:
	var node_list: Array = []
	for node_id in sorted_node_ids():
		var node: Dictionary = nodes[node_id]
		node_list.append({
			"id": int(node["id"]),
			"pos": node["pos"],
			"region_id": int(node["region_id"]),
			"kind": String(node["kind"]),
			"scanned": bool(node["scanned"]),
			"station": null if node["station"] == null else (node["station"] as Dictionary).duplicate(true),
		})
	var edge_list: Array = []
	for edge_id in sorted_edge_ids():
		edge_list.append((edges[edge_id] as Dictionary).duplicate(true))
	var region_list: Array = []
	for region_id in sorted_region_ids():
		region_list.append((regions[region_id] as Dictionary).duplicate(true))
	var chunk_list: Array = []
	for chunk_id in sorted_chunk_ids():
		chunk_list.append((chunks[chunk_id] as Dictionary).duplicate(true))
	return {
		"version": version,
		"seed": seed_value,
		"caps": caps.duplicate(),
		"next_ids": next_ids.duplicate(),
		"nodes": node_list,
		"edges": edge_list,
		"regions": region_list,
		"chunks": chunk_list,
		"tombstones": tombstones.duplicate(true),
	}

func audio_json() -> Dictionary:
	return {"events": audible_events.duplicate(true), "next_seq": next_event_seq}

func canonical_text() -> String:
	var image := {
		"graph": to_json_dict(),
		"audio": audio_json(),
		"entity": entity.duplicate(true),
		"player": player.duplicate(true),
		"scanner": scanner.duplicate(true),
		"pending": pending.duplicate(true),
		"rng": rng.duplicate(true),
		"tick": tick,
		"playtime_ms": playtime_ms,
		"act": act,
	}
	return SurveyCanonicalJson.stringify(SurveyCanonicalJson.encode(image))

func state_hash() -> String:
	return SurveyCanonicalJson.checksum(canonical_text())

# --- strict parsing ---------------------------------------------------------

static func _require_dict(source: Dictionary, key: String, errors: Array) -> Dictionary:
	if not source.has(key) or typeof(source[key]) != TYPE_DICTIONARY:
		errors.append("%s: missing object section" % key)
		return {}
	return source[key]

static func _require_array(source: Dictionary, key: String, errors: Array) -> Array:
	if not source.has(key) or typeof(source[key]) != TYPE_ARRAY:
		errors.append("%s: missing array section" % key)
		return []
	return source[key]

static func _require_string(source: Dictionary, key: String, field: String, allowed: Array, errors: Array) -> String:
	if not source.has(key) or typeof(source[key]) != TYPE_STRING:
		errors.append("%s: missing string" % field)
		return ""
	var text := String(source[key])
	if not allowed.is_empty() and not allowed.has(text):
		errors.append("%s: unexpected value %s" % [field, text])
	return text

static func _require_bool(source: Dictionary, key: String, field: String, errors: Array) -> bool:
	if not source.has(key) or typeof(source[key]) != TYPE_BOOL:
		errors.append("%s: missing boolean" % field)
		return false
	return bool(source[key])

static func _decode_vector(value: Variant, field: String, errors: Array) -> Vector3i:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		errors.append("%s: expected three decimal strings" % field)
		return Vector3i.ZERO
	var parts: Array = value
	return Vector3i(
		SurveyIntCodec.decode(parts[0], "%s.x" % field, errors),
		SurveyIntCodec.decode(parts[1], "%s.y" % field, errors),
		SurveyIntCodec.decode(parts[2], "%s.z" % field, errors))

static func _decode_id_array(value: Variant, field: String, errors: Array) -> Array:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: expected an array" % field)
		return []
	var out: Array = []
	for item in value:
		out.append(SurveyIntCodec.decode(item, field, errors))
	return out

static func _decode_loose(value: Variant) -> Variant:
	match typeof(value):
		TYPE_STRING:
			var text := String(value)
			if SurveyIntCodec.is_canonical(text):
				return text.to_int()
			return text
		TYPE_ARRAY:
			var out: Array = []
			for item in value:
				out.append(_decode_loose(item))
			return out
		TYPE_DICTIONARY:
			var out_dict := {}
			var source: Dictionary = value
			for key in source.keys():
				out_dict[String(key)] = _decode_loose(source[key])
			return out_dict
	return value

static func _decode_field(template: Variant, value: Variant, field: String, errors: Array) -> Variant:
	match typeof(template):
		TYPE_INT:
			return SurveyIntCodec.decode(value, field, errors)
		TYPE_BOOL:
			if typeof(value) != TYPE_BOOL:
				errors.append("%s: expected a boolean" % field)
				return false
			return bool(value)
		TYPE_STRING:
			if typeof(value) != TYPE_STRING:
				errors.append("%s: expected a string" % field)
				return ""
			return String(value)
		TYPE_VECTOR3I:
			return _decode_vector(value, field, errors)
		TYPE_ARRAY:
			if typeof(value) != TYPE_ARRAY:
				errors.append("%s: expected an array" % field)
				return []
			return _decode_loose(value)
		TYPE_DICTIONARY:
			if typeof(value) != TYPE_DICTIONARY:
				errors.append("%s: expected an object" % field)
				return (template as Dictionary).duplicate(true)
			if (template as Dictionary).is_empty():
				return _decode_loose(value)
			return _decode_section(template, value, field, errors)
	return value

static func _decode_section(template: Dictionary, value: Variant, field: String, errors: Array) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected an object" % field)
		return template.duplicate(true)
	var source: Dictionary = value
	var out := {}
	for key in template.keys():
		var name := String(key)
		if not source.has(name):
			errors.append("%s.%s: missing required field" % [field, name])
			out[name] = template[key]
			continue
		out[name] = _decode_field(template[key], source[name], "%s.%s" % [field, name], errors)
	return out

static func from_envelope(envelope: Dictionary, errors: Array) -> SurveyGraphV1:
	var graph := SurveyGraphV1.new()
	var header := _require_dict(envelope, "header", errors)
	var graph_data := _require_dict(envelope, "graph", errors)
	var rng_data := _require_dict(envelope, "rng", errors)
	var audio_data := _require_dict(envelope, "audio", errors)
	if not errors.is_empty():
		return graph
	graph.version = SurveyIntCodec.decode(header.get("version", null), "header.version", errors)
	graph.seed_value = SurveyIntCodec.decode(header.get("seed", null), "header.seed", errors)
	graph.tick = SurveyIntCodec.decode_nonnegative(header.get("tick", null), "header.tick", errors)
	graph.playtime_ms = SurveyIntCodec.decode_nonnegative(header.get("playtime_ms", null), "header.playtime_ms", errors)
	graph.act = SurveyIntCodec.decode_nonnegative(header.get("act", null), "header.act", errors)
	if graph.version != VERSION:
		errors.append("header.version: expected %d after migration, got %d" % [VERSION, graph.version])
	var sim_stream := _decode_id_array(rng_data.get("sim_stream", null), "rng.sim_stream", errors)
	if sim_stream.size() != 2:
		errors.append("rng.sim_stream: expected two u64 words")
		sim_stream = [0, 0]
	graph.rng = {
		"gen_stream": SurveyIntCodec.decode(rng_data.get("gen_stream", null), "rng.gen_stream", errors),
		"sim_stream": sim_stream,
	}
	var graph_version := SurveyIntCodec.decode(graph_data.get("version", null), "graph.version", errors)
	if graph_version != VERSION:
		errors.append("graph.version: expected %d, got %d" % [VERSION, graph_version])
	var caps_data := _require_dict(graph_data, "caps", errors)
	graph.caps = {
		"global": SurveyIntCodec.decode_nonnegative(caps_data.get("global", null), "graph.caps.global", errors),
		"region": SurveyIntCodec.decode_nonnegative(caps_data.get("region", null), "graph.caps.region", errors),
	}
	var next_data := _require_dict(graph_data, "next_ids", errors)
	var next_out := {}
	for kind in ["node", "edge", "region", "chunk"]:
		next_out[kind] = SurveyIntCodec.decode_nonnegative(next_data.get(kind, null), "graph.next_ids.%s" % kind, errors)
	graph.next_ids = next_out
	for item in _require_array(graph_data, "regions", errors):
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("graph.regions: expected objects")
			continue
		var record: Dictionary = item
		var region_id := SurveyIntCodec.decode_nonnegative(record.get("id", null), "region.id", errors)
		var cell_total := SurveyIntCodec.decode_nonnegative(record.get("cell_total", null), "region.%d.cell_total" % region_id, errors)
		var cells := _require_string(record, "cells", "region.%d.cells" % region_id, [], errors)
		SurveyCoverageBitset.decode(cells, cell_total, "region.%d.cells" % region_id, errors)
		var status := _require_string(record, "status", "region.%d.status" % region_id, STATUSES, errors)
		var deadline: Variant = record.get("erase_deadline_tick", 0)
		var deadline_out: Variant = null
		if deadline != null:
			deadline_out = SurveyIntCodec.decode_nonnegative(deadline, "region.%d.erase_deadline_tick" % region_id, errors)
		if graph.regions.has(region_id):
			errors.append("region %d appears twice" % region_id)
		graph.regions[region_id] = {
			"id": region_id,
			"chamber_code": _require_string(record, "chamber_code", "region.%d.chamber_code" % region_id, [], errors),
			"name": _require_string(record, "name", "region.%d.name" % region_id, [], errors),
			"cell_total": cell_total,
			"cells": cells,
			"complete": _require_bool(record, "complete", "region.%d.complete" % region_id, errors),
			"status": status,
			"erase_deadline_tick": deadline_out,
			"chunk_ids": _decode_id_array(record.get("chunk_ids", null), "region.%d.chunk_ids" % region_id, errors),
		}
	for item in _require_array(graph_data, "nodes", errors):
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("graph.nodes: expected objects")
			continue
		var record: Dictionary = item
		var node_id := SurveyIntCodec.decode_nonnegative(record.get("id", null), "node.id", errors)
		var kind := _require_string(record, "kind", "node.%d.kind" % node_id, KINDS, errors)
		var station: Variant = record.get("station", 0)
		var station_out: Variant = null
		if station == null:
			if kind == KIND_STATION:
				errors.append("node.%d.station: STATION nodes require metadata" % node_id)
		elif typeof(station) != TYPE_DICTIONARY:
			errors.append("node.%d.station: expected an object or null" % node_id)
		else:
			if kind != KIND_STATION:
				errors.append("node.%d.station: only STATION nodes carry metadata" % node_id)
			var meta: Dictionary = station
			station_out = {
				"station_no": _require_string(meta, "station_no", "node.%d.station.station_no" % node_id, [], errors),
				"installed_by": _require_string(meta, "installed_by", "node.%d.station.installed_by" % node_id, INSTALLERS, errors),
				"log_id": null if meta.get("log_id", null) == null else String(meta["log_id"]),
			}
		if graph.nodes.has(node_id):
			errors.append("node %d appears twice" % node_id)
		graph.nodes[node_id] = {
			"id": node_id,
			"pos": _decode_vector(record.get("pos", null), "node.%d.pos" % node_id, errors),
			"region_id": SurveyIntCodec.decode_nonnegative(record.get("region_id", null), "node.%d.region_id" % node_id, errors),
			"kind": kind,
			"scanned": _require_bool(record, "scanned", "node.%d.scanned" % node_id, errors),
			"station": station_out,
		}
	for item in _require_array(graph_data, "edges", errors):
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("graph.edges: expected objects")
			continue
		var record: Dictionary = item
		var edge_id := SurveyIntCodec.decode_nonnegative(record.get("id", null), "edge.id", errors)
		if graph.edges.has(edge_id):
			errors.append("edge %d appears twice" % edge_id)
		graph.edges[edge_id] = {
			"id": edge_id,
			"a": SurveyIntCodec.decode_nonnegative(record.get("a", null), "edge.%d.a" % edge_id, errors),
			"b": SurveyIntCodec.decode_nonnegative(record.get("b", null), "edge.%d.b" % edge_id, errors),
			"length_mm": SurveyIntCodec.decode_nonnegative(record.get("length_mm", null), "edge.%d.length_mm" % edge_id, errors),
			"surface": _require_string(record, "surface", "edge.%d.surface" % edge_id, SURFACE_PERMILLE.keys(), errors),
			"cost": SurveyIntCodec.decode_nonnegative(record.get("cost", null), "edge.%d.cost" % edge_id, errors),
			"scanned": _require_bool(record, "scanned", "edge.%d.scanned" % edge_id, errors),
		}
	for item in _require_array(graph_data, "chunks", errors):
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("graph.chunks: expected objects")
			continue
		var record: Dictionary = item
		var chunk_id := SurveyIntCodec.decode_nonnegative(record.get("id", null), "chunk.id", errors)
		var points := PackedInt32Array()
		var raw: Variant = record.get("points", null)
		if typeof(raw) != TYPE_ARRAY:
			errors.append("chunk.%d.points: expected an array" % chunk_id)
		else:
			for value in raw:
				if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
					errors.append("chunk.%d.points: expected integer centimetres" % chunk_id)
					break
				var number := float(value)
				if number != floor(number):
					errors.append("chunk.%d.points: expected integer centimetres" % chunk_id)
					break
				points.append(int(number))
		if graph.chunks.has(chunk_id):
			errors.append("chunk %d appears twice" % chunk_id)
		graph.chunks[chunk_id] = {
			"id": chunk_id,
			"region_id": SurveyIntCodec.decode_nonnegative(record.get("region_id", null), "chunk.%d.region_id" % chunk_id, errors),
			"cell": SurveyIntCodec.decode_nonnegative(record.get("cell", null), "chunk.%d.cell" % chunk_id, errors),
			"count": SurveyIntCodec.decode_nonnegative(record.get("count", null), "chunk.%d.count" % chunk_id, errors),
			"points": points,
		}
	var tombstone_list: Array = []
	for item in _require_array(graph_data, "tombstones", errors):
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("graph.tombstones: expected objects")
			continue
		var record: Dictionary = item
		var region_id := SurveyIntCodec.decode_nonnegative(record.get("region_id", null), "tombstone.region_id", errors)
		tombstone_list.append({
			"region_id": region_id,
			"chamber_code": _require_string(record, "chamber_code", "tombstone.%d.chamber_code" % region_id, [], errors),
			"erased_tick": SurveyIntCodec.decode_nonnegative(record.get("erased_tick", null), "tombstone.%d.erased_tick" % region_id, errors),
			"erased_day": SurveyIntCodec.decode_nonnegative(record.get("erased_day", null), "tombstone.%d.erased_day" % region_id, errors),
			"node_ids": _decode_id_array(record.get("node_ids", null), "tombstone.%d.node_ids" % region_id, errors),
			"edge_ids": _decode_id_array(record.get("edge_ids", null), "tombstone.%d.edge_ids" % region_id, errors),
			"chunk_ids": _decode_id_array(record.get("chunk_ids", null), "tombstone.%d.chunk_ids" % region_id, errors),
			"cell_total": SurveyIntCodec.decode_nonnegative(record.get("cell_total", null), "tombstone.%d.cell_total" % region_id, errors),
		})
	graph.tombstones = tombstone_list
	var event_list: Array = []
	for item in _require_array(audio_data, "events", errors):
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("audio.events: expected objects")
			continue
		var record: Dictionary = item
		event_list.append({
			"seq": SurveyIntCodec.decode_nonnegative(record.get("seq", null), "audio.event.seq", errors),
			"pos_mm": _decode_vector(record.get("pos_mm", null), "audio.event.pos_mm", errors),
			"loudness_tenths": SurveyIntCodec.decode_nonnegative(record.get("loudness_tenths", null), "audio.event.loudness_tenths", errors),
			"radius_mm": SurveyIntCodec.decode_nonnegative(record.get("radius_mm", null), "audio.event.radius_mm", errors),
			"born_tick": SurveyIntCodec.decode_nonnegative(record.get("born_tick", null), "audio.event.born_tick", errors),
		})
	graph.audible_events = event_list
	graph.next_event_seq = SurveyIntCodec.decode_nonnegative(audio_data.get("next_seq", null), "audio.next_seq", errors)
	graph.player = _decode_section(default_player(), envelope.get("player", null), "player", errors)
	graph.scanner = _decode_section(default_scanner(), envelope.get("scanner", null), "scanner", errors)
	graph.entity = _decode_section(default_entity(), envelope.get("entity", null), "entity", errors)
	graph.pending = _decode_section(default_pending(), envelope.get("pending", null), "pending", errors)
	graph.rebuild_caches()
	return graph
