class_name EntityPatroller
extends RefCounted

# M1 core, DESIGN.md section 4 movement law only. A dumb cyclic route stands in
# for the M3 behaviour tree, but the confinement law is the real one: the entity
# occupies scanned live graph space, moves at most 1700 mm/s along measured
# straight segments, and halts at a scanned boundary instead of entering unscanned
# space. It can never teleport because every departure needs an incident edge.

const SPEED_MM_PER_SECOND := 1700
const TICKS_PER_SECOND := 60
const MAX_STEP_MM := 29

var route: Array = []
var route_index := 0
var at_node_id := -1
var edge_id := -1
var edge_from := -1
var edge_to := -1
var edge_t_mm := 0
var accumulator := 0
var halted_at_boundary := false
var boundary_halts := 0
var arrivals := 0
var last_error := ""

# Places the patroller on a scanned live node and pins a cyclic route. Every
# consecutive pair in the route (including the wrap) must share an edge.
func place(space: SurveySpace, start_node_id: int, p_route: Array) -> bool:
	if space == null or p_route.size() < 2:
		last_error = "route needs at least two nodes"
		return false
	if not space.is_node_traversable(start_node_id):
		last_error = "start node %d is not scanned live space" % start_node_id
		return false
	var start_index := -1
	for index in p_route.size():
		var node_id := int(p_route[index])
		if not space.nodes.has(node_id):
			last_error = "route node %d does not exist" % node_id
			return false
		if node_id == start_node_id and start_index == -1:
			start_index = index
	if start_index == -1:
		last_error = "start node %d is not on the route" % start_node_id
		return false
	for index in p_route.size():
		var a := int(p_route[index])
		var b := int(p_route[(index + 1) % p_route.size()])
		if a == b or space.edge_between(a, b) == -1:
			last_error = "route leg %d-%d is not an edge" % [a, b]
			return false
	route = p_route.duplicate()
	route_index = start_index
	at_node_id = start_node_id
	edge_id = -1
	edge_from = -1
	edge_to = -1
	edge_t_mm = 0
	accumulator = 0
	halted_at_boundary = false
	return true

func next_route_node() -> int:
	if route.size() < 2:
		return -1
	return int(route[(route_index + 1) % route.size()])

func position_mm(space: SurveySpace) -> Vector3i:
	if at_node_id != -1:
		return space.node_position(at_node_id)
	if edge_id == -1:
		return Vector3i.ZERO
	var from_pos := space.node_position(edge_from)
	var to_pos := space.node_position(edge_to)
	var length := space.edge_length_mm(edge_id)
	if length <= 0:
		return from_pos
	var delta := to_pos - from_pos
	return from_pos + Vector3i(delta.x * edge_t_mm / length, delta.y * edge_t_mm / length, delta.z * edge_t_mm / length)

func is_confined(space: SurveySpace) -> bool:
	if at_node_id != -1:
		return space.is_node_traversable(at_node_id)
	if edge_id == -1:
		return false
	return space.is_edge_traversable(edge_id)

# One 60 Hz tick. Returns the millimetres moved, whether the tick ended in a
# boundary halt, and the node arrived at (-1 when still travelling).
func tick(space: SurveySpace) -> Dictionary:
	var result := {"moved_mm": 0, "halted": false, "arrived_node": -1, "reason": ""}
	if space == null or (at_node_id == -1 and edge_id == -1):
		result["halted"] = true
		result["reason"] = "UNPLACED"
		return result
	accumulator += SPEED_MM_PER_SECOND
	var step_mm := accumulator / TICKS_PER_SECOND
	accumulator -= step_mm * TICKS_PER_SECOND
	if edge_id == -1:
		var target := next_route_node()
		var candidate := -1
		if target != -1:
			candidate = space.edge_between(at_node_id, target)
		if candidate == -1 or not space.is_edge_traversable(candidate) or not space.is_node_traversable(target):
			halted_at_boundary = true
			boundary_halts += 1
			accumulator = 0
			result["halted"] = true
			result["reason"] = "SCANNED_BOUNDARY"
			return result
		halted_at_boundary = false
		edge_id = candidate
		edge_from = at_node_id
		edge_to = target
		edge_t_mm = 0
		at_node_id = -1
	var length := space.edge_length_mm(edge_id)
	var advance := mini(step_mm, maxi(0, length - edge_t_mm))
	edge_t_mm += advance
	result["moved_mm"] = advance
	result["reason"] = "TRAVELLING"
	if edge_t_mm >= length:
		at_node_id = edge_to
		route_index = (route_index + 1) % route.size()
		edge_id = -1
		edge_from = -1
		edge_to = -1
		edge_t_mm = 0
		accumulator = 0
		arrivals += 1
		result["arrived_node"] = at_node_id
		result["reason"] = "ARRIVED"
	return result

func canonical_text() -> String:
	return "entity node=%d edge=%d from=%d to=%d t=%d acc=%d idx=%d route=%s halted=%d halts=%d arrivals=%d" % [at_node_id, edge_id, edge_from, edge_to, edge_t_mm, accumulator, route_index, str(route), 1 if halted_at_boundary else 0, boundary_halts, arrivals]

func to_snapshot() -> Dictionary:
	return {
		"route": route.duplicate(),
		"route_index": route_index,
		"at_node_id": at_node_id,
		"edge_id": edge_id,
		"edge_from": edge_from,
		"edge_to": edge_to,
		"edge_t_mm": edge_t_mm,
		"accumulator": accumulator,
		"halted_at_boundary": halted_at_boundary,
		"boundary_halts": boundary_halts,
		"arrivals": arrivals,
	}

static func from_snapshot(data: Dictionary) -> EntityPatroller:
	var patroller := EntityPatroller.new()
	patroller.route = (data["route"] as Array).duplicate()
	patroller.route_index = int(data["route_index"])
	patroller.at_node_id = int(data["at_node_id"])
	patroller.edge_id = int(data["edge_id"])
	patroller.edge_from = int(data["edge_from"])
	patroller.edge_to = int(data["edge_to"])
	patroller.edge_t_mm = int(data["edge_t_mm"])
	patroller.accumulator = int(data["accumulator"])
	patroller.halted_at_boundary = bool(data["halted_at_boundary"])
	patroller.boundary_halts = int(data["boundary_halts"])
	patroller.arrivals = int(data["arrivals"])
	return patroller
