class_name SurveySpace
extends RefCounted

# M1 core, DESIGN.md sections 3.1 to 3.2. Integer region/station graph plus the
# persistent point store. Millimetres are authoritative for geometry; stored
# points are whole centimetres. Every order-sensitive walk uses sorted ids.

const KIND_STATION := "STATION"
const KIND_JUNCTION := "JUNCTION"
const KIND_WAYPOINT := "WAYPOINT"
const STATUS_LIVE := "LIVE"
const STATUS_PENDING_ERASE := "PENDING_ERASE"
const SURFACE_PERMILLE := {
	"ROCK": 1000,
	"RAIL": 1000,
	"GRATE": 1100,
	"RUBBLE": 1400,
	"WATER": 1600,
	"SALT": 1200,
}
const CHUNK_EDGE_MM := 4000
const DEDUP_CELL_CM := 10
const AXIS_BITS := 21
const AXIS_BIAS := 1048576
const DEFAULT_GLOBAL_CAP := 900000
const DEFAULT_REGION_CAP := 60000

var global_cap := DEFAULT_GLOBAL_CAP
var region_cap := DEFAULT_REGION_CAP
var next_ids := {"node": 1, "edge": 1, "region": 1, "chunk": 1}
var nodes := {}
var edges := {}
var regions := {}
var chunks := {}
var last_error := ""

var _adjacency := {}
var _cell_chunks := {}
var _dedup := {}
var _stored_total := 0

func _init(p_global_cap: int = DEFAULT_GLOBAL_CAP, p_region_cap: int = DEFAULT_REGION_CAP) -> void:
	global_cap = maxi(0, p_global_cap)
	region_cap = maxi(0, p_region_cap)

func _take_id(kind: String) -> int:
	var value := int(next_ids[kind])
	next_ids[kind] = value + 1
	return value

func add_region(chamber_code: String, status: String = STATUS_LIVE) -> int:
	if status != STATUS_LIVE and status != STATUS_PENDING_ERASE:
		last_error = "unknown region status %s" % status
		return -1
	var id := _take_id("region")
	regions[id] = {"id": id, "chamber_code": chamber_code, "status": status, "stored": 0, "chunk_ids": []}
	_cell_chunks[id] = {}
	_dedup[id] = {}
	return id

func set_region_status(region_id: int, status: String) -> bool:
	if not regions.has(region_id):
		last_error = "unknown region %d" % region_id
		return false
	if status != STATUS_LIVE and status != STATUS_PENDING_ERASE:
		last_error = "unknown region status %s" % status
		return false
	regions[region_id]["status"] = status
	return true

func is_region_live(region_id: int) -> bool:
	if not regions.has(region_id):
		return false
	return String(regions[region_id]["status"]) == STATUS_LIVE

func add_node(region_id: int, pos: Vector3i, kind: String = KIND_WAYPOINT, scanned: bool = false) -> int:
	if not regions.has(region_id):
		last_error = "unknown region %d" % region_id
		return -1
	if kind != KIND_STATION and kind != KIND_JUNCTION and kind != KIND_WAYPOINT:
		last_error = "unknown node kind %s" % kind
		return -1
	var id := _take_id("node")
	nodes[id] = {"id": id, "pos": pos, "region_id": region_id, "kind": kind, "scanned": scanned}
	_adjacency[id] = []
	return id

func add_edge(a: int, b: int, surface: String = "ROCK") -> int:
	if not nodes.has(a) or not nodes.has(b) or a == b:
		last_error = "invalid edge endpoints"
		return -1
	if not SURFACE_PERMILLE.has(surface):
		last_error = "unknown surface %s" % surface
		return -1
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var found := edge_between(lo, hi)
	if found != -1:
		return found
	var length_mm := distance_mm(node_position(lo), node_position(hi))
	var permille := int(SURFACE_PERMILLE[surface])
	var id := _take_id("edge")
	edges[id] = {
		"id": id,
		"a": lo,
		"b": hi,
		"length_mm": length_mm,
		"surface": surface,
		"cost": (length_mm * permille) / 1000,
		"scanned": false,
	}
	_link(lo, id)
	_link(hi, id)
	return id

func _link(node_id: int, edge_id: int) -> void:
	var list: Array = _adjacency[node_id]
	list.append(edge_id)
	list.sort()

func node_position(node_id: int) -> Vector3i:
	if not nodes.has(node_id):
		return Vector3i.ZERO
	return nodes[node_id]["pos"]

func node_kind(node_id: int) -> String:
	if not nodes.has(node_id):
		return ""
	return String(nodes[node_id]["kind"])

func edge_between(a: int, b: int) -> int:
	if not _adjacency.has(a):
		return -1
	for edge_id in _adjacency[a]:
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

func edge_length_mm(edge_id: int) -> int:
	if not edges.has(edge_id):
		return -1
	return int(edges[edge_id]["length_mm"])

func neighbours(node_id: int) -> Array:
	var out: Array = []
	if not _adjacency.has(node_id):
		return out
	for edge_id in _adjacency[node_id]:
		out.append(other_end(int(edge_id), node_id))
	out.sort()
	return out

func scanned_neighbours(node_id: int) -> Array:
	var out: Array = []
	if not _adjacency.has(node_id):
		return out
	for edge_id in _adjacency[node_id]:
		if is_edge_traversable(int(edge_id)):
			out.append(other_end(int(edge_id), node_id))
	out.sort()
	return out

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

func scan_corridor(node_ids: Array) -> Dictionary:
	var result := {"nodes": 0, "edges": 0}
	for node_id in node_ids:
		if mark_node_scanned(int(node_id)):
			result["nodes"] = int(result["nodes"]) + 1
	for index in maxi(0, node_ids.size() - 1):
		var edge_id := edge_between(int(node_ids[index]), int(node_ids[index + 1]))
		if edge_id != -1 and mark_edge_scanned(edge_id):
			result["edges"] = int(result["edges"]) + 1
	return result

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

func scanned_node_ids() -> Array:
	var out: Array = []
	for node_id in sorted_int_keys(nodes):
		if is_node_scanned(int(node_id)):
			out.append(int(node_id))
	return out

func scanned_edge_ids() -> Array:
	var out: Array = []
	for edge_id in sorted_int_keys(edges):
		if is_edge_scanned(int(edge_id)):
			out.append(int(edge_id))
	return out

# Stores a batch of x,y,z,intensity centimetre quadruples in region_id.
# Nothing is dropped silently: received == stored + duplicates + region_capped
# + global_capped for every call, which is the M1 cap policy contract.
func store_points(region_id: int, points_cm: PackedInt32Array) -> Dictionary:
	var result := {
		"ok": false,
		"received": 0,
		"stored": 0,
		"duplicates": 0,
		"region_capped": 0,
		"global_capped": 0,
		"at_cap": false,
	}
	if not regions.has(region_id):
		last_error = "unknown region %d" % region_id
		return result
	if points_cm.size() % 4 != 0:
		last_error = "point batch is not a whole number of quadruples"
		return result
	var received := points_cm.size() / 4
	result["ok"] = true
	result["received"] = received
	var region: Dictionary = regions[region_id]
	var dedup: Dictionary = _dedup[region_id]
	for index in received:
		var base := index * 4
		var x := points_cm[base]
		var y := points_cm[base + 1]
		var z := points_cm[base + 2]
		var intensity := clampi(points_cm[base + 3], 0, 255)
		var key := dedup_key(x, y, z)
		if dedup.has(key):
			result["duplicates"] = int(result["duplicates"]) + 1
			continue
		if int(region["stored"]) >= region_cap:
			result["region_capped"] = int(result["region_capped"]) + 1
			continue
		if _stored_total >= global_cap:
			result["global_capped"] = int(result["global_capped"]) + 1
			continue
		var chunk: Dictionary = chunks[_chunk_for(region_id, x, y, z)]
		var points: PackedInt32Array = chunk["points"]
		points.append(x)
		points.append(y)
		points.append(z)
		points.append(intensity)
		chunk["points"] = points
		chunk["count"] = int(chunk["count"]) + 1
		dedup[key] = true
		region["stored"] = int(region["stored"]) + 1
		_stored_total += 1
		result["stored"] = int(result["stored"]) + 1
	result["at_cap"] = int(result["region_capped"]) > 0 or int(result["global_capped"]) > 0
	return result

func _chunk_for(region_id: int, x_cm: int, y_cm: int, z_cm: int) -> int:
	var cell := cell_key(x_cm * 10, y_cm * 10, z_cm * 10)
	var map: Dictionary = _cell_chunks[region_id]
	if map.has(cell):
		return int(map[cell])
	var id := _take_id("chunk")
	chunks[id] = {"id": id, "region_id": region_id, "cell": cell, "count": 0, "points": PackedInt32Array()}
	map[cell] = id
	var list: Array = regions[region_id]["chunk_ids"]
	list.append(id)
	list.sort()
	return id

func point_total() -> int:
	return _stored_total

func region_point_total(region_id: int) -> int:
	if not regions.has(region_id):
		return -1
	return int(regions[region_id]["stored"])

func chunk_ids_for(region_id: int) -> Array:
	if not regions.has(region_id):
		return []
	return (regions[region_id]["chunk_ids"] as Array).duplicate()

func chunk_point_sum() -> int:
	var total := 0
	for chunk_id in sorted_int_keys(chunks):
		total += int(chunks[chunk_id]["count"])
	return total

func canonical_text() -> String:
	var parts := PackedStringArray()
	parts.append("space caps=%d/%d stored=%d" % [global_cap, region_cap, _stored_total])
	parts.append("next n=%d e=%d r=%d c=%d" % [int(next_ids["node"]), int(next_ids["edge"]), int(next_ids["region"]), int(next_ids["chunk"])])
	for node_id in sorted_int_keys(nodes):
		var node: Dictionary = nodes[node_id]
		var pos: Vector3i = node["pos"]
		parts.append("n%d r%d %d,%d,%d %s scanned=%d" % [int(node_id), int(node["region_id"]), pos.x, pos.y, pos.z, String(node["kind"]), 1 if bool(node["scanned"]) else 0])
	for edge_id in sorted_int_keys(edges):
		var edge: Dictionary = edges[edge_id]
		parts.append("e%d %d-%d len=%d %s cost=%d scanned=%d" % [int(edge_id), int(edge["a"]), int(edge["b"]), int(edge["length_mm"]), String(edge["surface"]), int(edge["cost"]), 1 if bool(edge["scanned"]) else 0])
	for region_id in sorted_int_keys(regions):
		var region: Dictionary = regions[region_id]
		parts.append("r%d %s %s stored=%d chunks=%s" % [int(region_id), String(region["chamber_code"]), String(region["status"]), int(region["stored"]), str(region["chunk_ids"])])
	for chunk_id in sorted_int_keys(chunks):
		var chunk: Dictionary = chunks[chunk_id]
		var points: PackedInt32Array = chunk["points"]
		var joined := PackedStringArray()
		for value in points:
			joined.append(str(value))
		parts.append("c%d r%d cell=%d count=%d [%s]" % [int(chunk_id), int(chunk["region_id"]), int(chunk["cell"]), int(chunk["count"]), ",".join(joined)])
	return "\n".join(parts)

# M1 save seam. The M2 milestone owns the on-disk survey file; this dictionary is
# the canonical in-memory image the golden replay harness round-trips.
func to_snapshot() -> Dictionary:
	return {
		"global_cap": global_cap,
		"region_cap": region_cap,
		"next_ids": next_ids.duplicate(true),
		"nodes": nodes.duplicate(true),
		"edges": edges.duplicate(true),
		"regions": regions.duplicate(true),
		"chunks": chunks.duplicate(true),
		"adjacency": _adjacency.duplicate(true),
		"cell_chunks": _cell_chunks.duplicate(true),
		"dedup": _dedup.duplicate(true),
		"stored_total": _stored_total,
	}

static func from_snapshot(data: Dictionary) -> SurveySpace:
	var space := SurveySpace.new(int(data["global_cap"]), int(data["region_cap"]))
	space.next_ids = (data["next_ids"] as Dictionary).duplicate(true)
	space.nodes = (data["nodes"] as Dictionary).duplicate(true)
	space.edges = (data["edges"] as Dictionary).duplicate(true)
	space.regions = (data["regions"] as Dictionary).duplicate(true)
	space.chunks = (data["chunks"] as Dictionary).duplicate(true)
	space._adjacency = (data["adjacency"] as Dictionary).duplicate(true)
	space._cell_chunks = (data["cell_chunks"] as Dictionary).duplicate(true)
	space._dedup = (data["dedup"] as Dictionary).duplicate(true)
	space._stored_total = int(data["stored_total"])
	return space

static func sorted_int_keys(source: Dictionary) -> Array:
	var keys := source.keys()
	keys.sort()
	return keys

static func distance_mm(a: Vector3i, b: Vector3i) -> int:
	var dx := a.x - b.x
	var dy := a.y - b.y
	var dz := a.z - b.z
	return isqrt(dx * dx + dy * dy + dz * dz)

# Integer floor square root, so no float arithmetic reaches an edge length.
static func isqrt(value: int) -> int:
	if value <= 0:
		return 0
	var x := value
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + value / x) / 2
	return x

static func floor_div(value: int, divisor: int) -> int:
	var quotient := value / divisor
	if value % divisor != 0 and (value < 0) != (divisor < 0):
		quotient -= 1
	return quotient

# DESIGN 3.1 spatial hash: biased 21-bit-per-axis Morton interleave of the 4 m
# grid cell, so the key is always non-negative and sorts deterministically.
static func cell_key(x_mm: int, y_mm: int, z_mm: int) -> int:
	var cx := floor_div(x_mm, CHUNK_EDGE_MM) + AXIS_BIAS
	var cy := floor_div(y_mm, CHUNK_EDGE_MM) + AXIS_BIAS
	var cz := floor_div(z_mm, CHUNK_EDGE_MM) + AXIS_BIAS
	return morton3(cx, cy, cz)

static func morton3(x: int, y: int, z: int) -> int:
	var out := 0
	for bit in AXIS_BITS:
		out |= ((x >> bit) & 1) << (3 * bit)
		out |= ((y >> bit) & 1) << (3 * bit + 1)
		out |= ((z >> bit) & 1) << (3 * bit + 2)
	return out

# Duplicate suppression cell: one stored point per 10 cm cube per region.
static func dedup_key(x_cm: int, y_cm: int, z_cm: int) -> int:
	var dx := floor_div(x_cm, DEDUP_CELL_CM) + AXIS_BIAS
	var dy := floor_div(y_cm, DEDUP_CELL_CM) + AXIS_BIAS
	var dz := floor_div(z_cm, DEDUP_CELL_CM) + AXIS_BIAS
	return dx | (dy << AXIS_BITS) | (dz << (2 * AXIS_BITS))
