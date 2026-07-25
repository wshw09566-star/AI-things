class_name SurveyMigrations
extends RefCounted

# DESIGN.md section 3.4: the loader switches on version and every migration is a
# pure vN to vN+1 function over the parsed envelope. Unknown future versions fail
# closed with a diegetic refusal rather than a best-effort load.

const LATEST_VERSION := 1

static func envelope_version(envelope: Dictionary, errors: Array) -> int:
	if not envelope.has("header") or typeof(envelope["header"]) != TYPE_DICTIONARY:
		errors.append("MIGRATE: header section is missing")
		return -1
	var header: Dictionary = envelope["header"]
	return SurveyIntCodec.decode(header.get("version", null), "header.version", errors)

static func migrate(envelope: Dictionary, errors: Array) -> Dictionary:
	var version := envelope_version(envelope, errors)
	if not errors.is_empty():
		return {}
	if version > LATEST_VERSION:
		errors.append("UNKNOWN_FUTURE_VERSION: %d is newer than %d" % [version, LATEST_VERSION])
		return {}
	if version < 0:
		errors.append("UNKNOWN_VERSION: %d" % version)
		return {}
	var current := envelope.duplicate(true)
	while version < LATEST_VERSION:
		match version:
			0:
				current = v0_to_v1(current)
			_:
				errors.append("NO_MIGRATION: v%d has no registered upgrade" % version)
				return {}
		version += 1
	return current

# v0 was the pre-review envelope of DESIGN.md 15.1 defects 2 and 6: no region
# erase status, no audible event queue, no pending action, no tick clock. The
# upgrade is pure: it copies the envelope and fills those fields with the
# documented defaults.
static func v0_to_v1(envelope: Dictionary) -> Dictionary:
	var out := envelope.duplicate(true)
	var header: Dictionary = out.get("header", {})
	header["version"] = "1"
	if not header.has("tick"):
		header["tick"] = "0"
	if not header.has("act"):
		header["act"] = "1"
	if not header.has("playtime_ms"):
		header["playtime_ms"] = "0"
	if not header.has("checksum"):
		header["checksum"] = "0"
	out["header"] = header
	var graph: Dictionary = out.get("graph", {})
	graph["version"] = "1"
	if not graph.has("caps"):
		graph["caps"] = {"global": "900000", "region": "60000"}
	if not graph.has("tombstones"):
		graph["tombstones"] = []
	var regions: Array = graph.get("regions", [])
	for item in regions:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var region: Dictionary = item
		if not region.has("status"):
			region["status"] = SurveyGraphV1.STATUS_LIVE
		if not region.has("erase_deadline_tick"):
			region["erase_deadline_tick"] = null
		if not region.has("complete"):
			region["complete"] = false
		if not region.has("name"):
			region["name"] = String(region.get("chamber_code", ""))
	graph["regions"] = regions
	out["graph"] = graph
	if not out.has("audio"):
		out["audio"] = {"events": [], "next_seq": "1"}
	if not out.has("pending"):
		out["pending"] = {"action": "NONE", "elapsed_ticks": "0", "params": {}}
	if not out.has("rng"):
		out["rng"] = {"gen_stream": "0", "sim_stream": ["0", "0"]}
	return out
