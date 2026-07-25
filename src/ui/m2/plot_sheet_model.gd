class_name PlotSheetModel
extends RefCounted
## M2 diegetic plot-sheet presentation model (HOLLOW SURVEY, DESIGN slice B).
## Consumes ONE immutable plain-Dictionary graph snapshot, validates it
## fail-closed, and emits a deterministic ordered hand-plot command list.
## Completion is NEVER recomputed here: only the supplied numerator and
## denominator are formatted. After load_snapshot() no graph state survives
## inside this object -- only the command list and the fold state machine,
## so no second store of spatial truth can exist.
##
## Snapshot contract (all ids int >= 0, all coordinates integer millimetres):
## {
##   "nodes": { id: {"pos_mm":[x,y], "region_id":int,
##                   "kind":"STATION"|"JUNCTION"|"WAYPOINT", "scanned":bool} },
##   "edges": { id: {"a":int, "b":int, "scanned":bool, "prior":bool} },  # a < b
##   "regions": { id: {"status":"LIVE"|"PENDING_ERASE"} },
##   "stations": { node_id: {"station_no":String} },  # exactly the STATION nodes
##   "completion": {"numerator":int, "denominator":int},  # authoritative
##   "tombstones": [ {"region_id":int, "erased_tick":int,
##                    "bounds_mm":[minx,miny,maxx,maxy]} ]  # sorted (erased_tick, region_id)
## }

const FOLD_TICKS := 90
const KINDS: Array[String] = ["STATION", "JUNCTION", "WAYPOINT"]
const STATUSES: Array[String] = ["LIVE", "PENDING_ERASE"]
const TOP_KEYS: Array[String] = ["completion", "edges", "nodes", "regions", "stations", "tombstones"]
const STRIKE_PAD_MM := 400

var _commands: Array[Dictionary] = []
var _fold_ticks := 0
var _want_open := false


static func _is_id(v: Variant) -> bool:
	return typeof(v) == TYPE_INT and v >= 0


static func _is_pos(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		return false
	return typeof(v[0]) == TYPE_INT and typeof(v[1]) == TYPE_INT


static func _keys_exact(d: Dictionary, keys: Array) -> bool:
	if d.size() != keys.size():
		return false
	for k: Variant in keys:
		if not d.has(k):
			return false
	return true


static func validate(snapshot: Variant) -> Array[String]:
	var errs: Array[String] = []
	if typeof(snapshot) != TYPE_DICTIONARY:
		errs.append("snapshot: not a Dictionary")
		return errs
	var s: Dictionary = snapshot
	if not _keys_exact(s, TOP_KEYS):
		errs.append("snapshot: top-level keys must be exactly %s" % [TOP_KEYS])
		return errs
	for k: String in ["nodes", "edges", "regions", "stations", "completion"]:
		if typeof(s[k]) != TYPE_DICTIONARY:
			errs.append("%s: must be a Dictionary" % k)
	if typeof(s["tombstones"]) != TYPE_ARRAY:
		errs.append("tombstones: must be an Array")
	if not errs.is_empty():
		return errs
	var nodes: Dictionary = s["nodes"]
	var edges: Dictionary = s["edges"]
	var regions: Dictionary = s["regions"]
	var stations: Dictionary = s["stations"]
	for rid: Variant in regions:
		if not _is_id(rid):
			errs.append("regions: bad id %s" % [rid])
			continue
		var r: Variant = regions[rid]
		if typeof(r) != TYPE_DICTIONARY or not _keys_exact(r, ["status"]) or not (r["status"] in STATUSES):
			errs.append("region %d: bad body" % rid)
	for nid: Variant in nodes:
		if not _is_id(nid):
			errs.append("nodes: bad id %s" % [nid])
			continue
		var n: Variant = nodes[nid]
		if typeof(n) != TYPE_DICTIONARY or not _keys_exact(n, ["kind", "pos_mm", "region_id", "scanned"]):
			errs.append("node %d: bad keys" % nid)
			continue
		if not _is_pos(n["pos_mm"]):
			errs.append("node %d: bad pos_mm" % nid)
		if not (n["kind"] in KINDS):
			errs.append("node %d: bad kind" % nid)
		if typeof(n["scanned"]) != TYPE_BOOL:
			errs.append("node %d: scanned must be bool" % nid)
		if not (_is_id(n["region_id"]) and regions.has(n["region_id"])):
			errs.append("node %d: region_id is not a live region" % nid)
	for sid: Variant in stations:
		if not (_is_id(sid) and nodes.has(sid) and typeof(nodes[sid]) == TYPE_DICTIONARY and nodes[sid].get("kind") == "STATION"):
			errs.append("stations: %s is not a STATION node id" % [sid])
			continue
		var st: Variant = stations[sid]
		if typeof(st) != TYPE_DICTIONARY or not _keys_exact(st, ["station_no"]) or typeof(st["station_no"]) != TYPE_STRING or (st["station_no"] as String).is_empty():
			errs.append("station %d: bad station_no" % sid)
	for nid: Variant in nodes:
		if typeof(nodes[nid]) == TYPE_DICTIONARY and nodes[nid].get("kind") == "STATION" and not stations.has(nid):
			errs.append("node %s: STATION missing from stations" % [nid])
	for eid: Variant in edges:
		if not _is_id(eid):
			errs.append("edges: bad id %s" % [eid])
			continue
		var e: Variant = edges[eid]
		if typeof(e) != TYPE_DICTIONARY or not _keys_exact(e, ["a", "b", "prior", "scanned"]):
			errs.append("edge %d: bad keys" % eid)
			continue
		if typeof(e["scanned"]) != TYPE_BOOL or typeof(e["prior"]) != TYPE_BOOL:
			errs.append("edge %d: scanned/prior must be bool" % eid)
			continue
		if not (_is_id(e["a"]) and _is_id(e["b"]) and e["a"] < e["b"]):
			errs.append("edge %d: endpoints must satisfy a < b" % eid)
			continue
		if not (nodes.has(e["a"]) and nodes.has(e["b"])):
			errs.append("edge %d: unknown endpoint" % eid)
			continue
		if e["scanned"] and not (nodes[e["a"]]["scanned"] and nodes[e["b"]]["scanned"]):
			errs.append("edge %d: scanned edge with unscanned endpoint" % eid)
	var c: Dictionary = s["completion"]
	if not _keys_exact(c, ["denominator", "numerator"]) or not _is_id(c.get("numerator")) or not _is_id(c.get("denominator")):
		errs.append("completion: needs int numerator/denominator >= 0")
	elif c["numerator"] > c["denominator"]:
		errs.append("completion: numerator > denominator")
	var prev_tick := -1
	var prev_rid := -1
	var seen_rids := {}
	for i: int in (s["tombstones"] as Array).size():
		var t: Variant = s["tombstones"][i]
		if typeof(t) != TYPE_DICTIONARY or not _keys_exact(t, ["bounds_mm", "erased_tick", "region_id"]):
			errs.append("tombstone %d: bad keys" % i)
			continue
		if not (_is_id(t["region_id"]) and _is_id(t["erased_tick"])):
			errs.append("tombstone %d: bad ids" % i)
			continue
		if regions.has(t["region_id"]) or seen_rids.has(t["region_id"]):
			errs.append("tombstone %d: region id collides with live region or duplicate tombstone" % i)
		seen_rids[t["region_id"]] = true
		var b: Variant = t["bounds_mm"]
		if typeof(b) != TYPE_ARRAY or (b as Array).size() != 4 \
				or typeof(b[0]) != TYPE_INT or typeof(b[1]) != TYPE_INT \
				or typeof(b[2]) != TYPE_INT or typeof(b[3]) != TYPE_INT \
				or b[0] >= b[2] or b[1] >= b[3]:
			errs.append("tombstone %d: bad bounds_mm" % i)
			continue
		if t["erased_tick"] < prev_tick or (t["erased_tick"] == prev_tick and t["region_id"] <= prev_rid):
			errs.append("tombstone %d: not sorted by (erased_tick, region_id)" % i)
		prev_tick = t["erased_tick"]
		prev_rid = t["region_id"]
	return errs


static func completion_text(numerator: int, denominator: int) -> String:
	if denominator == 0:
		return "SURVEY 0.0%"
	@warning_ignore("integer_division")
	var tenths: int = (numerator * 1000) / denominator
	@warning_ignore("integer_division")
	return "SURVEY %d.%d%%" % [tenths / 10, tenths % 10]


func load_snapshot(snapshot: Variant) -> Array[String]:
	var errs := validate(snapshot)
	_commands.clear()
	if not errs.is_empty():
		return errs
	var s: Dictionary = snapshot
	var nodes: Dictionary = s["nodes"]
	var edges: Dictionary = s["edges"]
	var regions: Dictionary = s["regions"]
	var stations: Dictionary = s["stations"]
	var edge_ids: Array = edges.keys()
	edge_ids.sort()
	for eid: Variant in edge_ids:
		var e: Dictionary = edges[eid]
		var layer := "projection"
		if e["prior"]:
			layer = "prior"
		elif e["scanned"]:
			layer = "fresh"
		_commands.append({
			"op": "line",
			"edge_id": eid,
			"layer": layer,
			"from_mm": (nodes[e["a"]]["pos_mm"] as Array).duplicate(),
			"to_mm": (nodes[e["b"]]["pos_mm"] as Array).duplicate(),
		})
	var node_ids: Array = nodes.keys()
	node_ids.sort()
	for nid: Variant in node_ids:
		var n: Dictionary = nodes[nid]
		_commands.append({
			"op": "marker",
			"node_id": nid,
			"kind": n["kind"],
			"scanned": n["scanned"],
			"at_mm": (n["pos_mm"] as Array).duplicate(),
		})
	var station_ids: Array = stations.keys()
	station_ids.sort()
	for sid: Variant in station_ids:
		_commands.append({
			"op": "label",
			"node_id": sid,
			"text": stations[sid]["station_no"],
			"at_mm": (nodes[sid]["pos_mm"] as Array).duplicate(),
		})
	var region_ids: Array = regions.keys()
	region_ids.sort()
	for rid: Variant in region_ids:
		if regions[rid]["status"] != "PENDING_ERASE":
			continue
		var have := false
		var lo := Vector2i.ZERO
		var hi := Vector2i.ZERO
		for nid: Variant in node_ids:
			if nodes[nid]["region_id"] != rid:
				continue
			var p: Array = nodes[nid]["pos_mm"]
			var v := Vector2i(p[0], p[1])
			if not have:
				lo = v
				hi = v
				have = true
			else:
				lo = Vector2i(mini(lo.x, v.x), mini(lo.y, v.y))
				hi = Vector2i(maxi(hi.x, v.x), maxi(hi.y, v.y))
		if have:
			_commands.append(_strike_command("pending", rid, lo.x - STRIKE_PAD_MM, lo.y - STRIKE_PAD_MM, hi.x + STRIKE_PAD_MM, hi.y + STRIKE_PAD_MM))
	for t: Dictionary in s["tombstones"]:
		var b: Array = t["bounds_mm"]
		_commands.append(_strike_command("tombstone", t["region_id"], b[0], b[1], b[2], b[3]))
	var num: int = s["completion"]["numerator"]
	var den: int = s["completion"]["denominator"]
	_commands.append({
		"op": "completion",
		"text": completion_text(num, den),
		"numerator": num,
		"denominator": den,
		"complete": den > 0 and num == den,
	})
	return errs


static func _strike_command(source: String, rid: int, minx: int, miny: int, maxx: int, maxy: int) -> Dictionary:
	return {
		"op": "strike",
		"source": source,
		"region_id": rid,
		"strokes": [
			[[minx, miny], [maxx, maxy]],
			[[minx, maxy], [maxx, miny]],
		],
	}


func commands() -> Array[Dictionary]:
	return _commands.duplicate(true)


func command_count() -> int:
	return _commands.size()


func request(open: bool) -> void:
	_want_open = open


func tick() -> void:
	_fold_ticks = clampi(_fold_ticks + (1 if _want_open else -1), 0, FOLD_TICKS)


func fold_state() -> String:
	if _fold_ticks == 0:
		return "CLOSED"
	if _fold_ticks == FOLD_TICKS:
		return "OPEN"
	return "OPENING" if _want_open else "CLOSING"


func is_open() -> bool:
	return _fold_ticks == FOLD_TICKS


func is_closed() -> bool:
	return _fold_ticks == 0


func scanner_locked() -> bool:
	return _fold_ticks > 0


func fold_fraction() -> float:
	return float(_fold_ticks) / float(FOLD_TICKS)


func serialize_fold() -> Dictionary:
	return {"fold_ticks": _fold_ticks, "want_open": _want_open}


func resume_fold(state: Variant) -> bool:
	if typeof(state) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = state
	if not _keys_exact(d, ["fold_ticks", "want_open"]):
		return false
	if typeof(d["fold_ticks"]) != TYPE_INT or d["fold_ticks"] < 0 or d["fold_ticks"] > FOLD_TICKS:
		return false
	if typeof(d["want_open"]) != TYPE_BOOL:
		return false
	_fold_ticks = d["fold_ticks"]
	_want_open = d["want_open"]
	return true
