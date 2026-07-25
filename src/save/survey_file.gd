class_name SurveyFile
extends RefCounted

# DESIGN.md section 6, the survey file. One human-readable JSON envelope per slot
# with a fixed sorted key order, an FNV-1a 64 checksum over the canonical byte
# stream with the checksum field zeroed, a transactional tmp-write plus atomic
# rename keeping one .bak generation, and the fixed load order
# parse -> checksum -> migrate -> validate -> rebuild derived caches.

const SCHEMA_VERSION := 1
const ZERO_CHECKSUM := "0"
const DIEGETIC_ERROR := "SURVEY FILE UNREADABLE - THE SLOT IS REFUSED"

static func envelope_from_graph(graph: SurveyGraphV1) -> Dictionary:
	return {
		"header": {
			"version": SCHEMA_VERSION,
			"seed": graph.seed_value,
			"tick": graph.tick,
			"playtime_ms": graph.playtime_ms,
			"act": graph.act,
			"checksum": ZERO_CHECKSUM,
		},
		"rng": {
			"gen_stream": int(graph.rng["gen_stream"]),
			"sim_stream": [int((graph.rng["sim_stream"] as Array)[0]), int((graph.rng["sim_stream"] as Array)[1])],
		},
		"graph": graph.to_json_dict(),
		"audio": graph.audio_json(),
		"player": graph.player.duplicate(true),
		"scanner": graph.scanner.duplicate(true),
		"entity": graph.entity.duplicate(true),
		"pending": graph.pending.duplicate(true),
	}

static func canonical_text(envelope: Dictionary) -> String:
	return SurveyCanonicalJson.stringify(SurveyCanonicalJson.encode(envelope)) + "\n"

static func checksum_of(envelope: Dictionary) -> String:
	var zeroed := envelope.duplicate(true)
	var header: Dictionary = zeroed.get("header", {})
	header["checksum"] = ZERO_CHECKSUM
	zeroed["header"] = header
	return SurveyCanonicalJson.checksum(canonical_text(zeroed))

static func stamp_checksum(envelope: Dictionary) -> Dictionary:
	var out := envelope.duplicate(true)
	var header: Dictionary = out.get("header", {})
	header["checksum"] = checksum_of(out)
	out["header"] = header
	return out

static func verify_checksum(envelope: Dictionary, errors: Array) -> bool:
	if not envelope.has("header") or typeof(envelope["header"]) != TYPE_DICTIONARY:
		errors.append("CHECKSUM: header section is missing")
		return false
	var header: Dictionary = envelope["header"]
	var stored: Variant = header.get("checksum", null)
	if typeof(stored) != TYPE_STRING:
		errors.append("CHECKSUM: header.checksum must be a string")
		return false
	var expected := checksum_of(envelope)
	if String(stored) != expected:
		errors.append("CHECKSUM_MISMATCH: stored %s, computed %s" % [String(stored), expected])
		return false
	return true

static func save_graph(graph: SurveyGraphV1, path: String) -> Dictionary:
	var report := SurveyValidator.validate(graph)
	if not bool(report["ok"]):
		return {"ok": false, "path": path, "checksum": "", "bak": "", "error": "INVALID_GRAPH: %s" % String((report["errors"] as Array)[0])}
	return write_envelope(envelope_from_graph(graph), path)

# Transactional write: sibling temp file, flush, close, verify the bytes and the
# checksum that were actually written, rotate one .bak generation, then a single
# atomic rename over the slot. A partially written .tmp is never renamed.
static func write_envelope(envelope: Dictionary, path: String) -> Dictionary:
	var result := {"ok": false, "path": path, "checksum": "", "bak": "", "error": ""}
	if path.ends_with(".tmp") or path.ends_with(".bak"):
		result["error"] = "REFUSED_SLOT_SUFFIX"
		return result
	var stamped := stamp_checksum(envelope)
	var text := canonical_text(stamped)
	var tmp_path := path + ".tmp"
	var writer := FileAccess.open(tmp_path, FileAccess.WRITE)
	if writer == null:
		result["error"] = "TMP_OPEN_FAILED: %d" % FileAccess.get_open_error()
		return result
	writer.store_string(text)
	writer.flush()
	writer.close()
	var written := FileAccess.get_file_as_string(tmp_path)
	var verify_errors: Array = []
	var reparsed: Variant = SurveyCanonicalJson.parse(written, verify_errors)
	if written != text:
		verify_errors.append("TMP_BYTES_DIFFER")
	elif typeof(reparsed) != TYPE_DICTIONARY:
		verify_errors.append("TMP_NOT_AN_OBJECT")
	elif not verify_checksum(reparsed, verify_errors):
		verify_errors.append("TMP_CHECKSUM_FAILED")
	if not verify_errors.is_empty():
		DirAccess.remove_absolute(tmp_path)
		result["error"] = String(verify_errors[0])
		return result
	var bak_path := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		var rotated := DirAccess.rename_absolute(path, bak_path)
		if rotated != OK:
			DirAccess.remove_absolute(tmp_path)
			result["error"] = "BAK_ROTATE_FAILED: %d" % rotated
			return result
		result["bak"] = bak_path
	var renamed := DirAccess.rename_absolute(tmp_path, path)
	if renamed != OK:
		result["error"] = "RENAME_FAILED: %d" % renamed
		return result
	result["ok"] = true
	result["checksum"] = String((stamped["header"] as Dictionary)["checksum"])
	return result

static func load_graph(path: String) -> Dictionary:
	var errors: Array = []
	var result := {"ok": false, "path": path, "graph": null, "errors": errors, "message": "", "bak_available": FileAccess.file_exists(path + ".bak")}
	if path.ends_with(".tmp"):
		return _refuse(result, errors, "PARTIAL_WRITE_REFUSED")
	if not FileAccess.file_exists(path):
		return _refuse(result, errors, "MISSING_SLOT")
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = SurveyCanonicalJson.parse(text, errors)
	if not errors.is_empty():
		return _refuse(result, errors, "")
	if typeof(parsed) != TYPE_DICTIONARY:
		return _refuse(result, errors, "NOT_AN_OBJECT")
	var envelope: Dictionary = parsed
	if not verify_checksum(envelope, errors):
		return _refuse(result, errors, "")
	var migrated := SurveyMigrations.migrate(envelope, errors)
	if not errors.is_empty():
		return _refuse(result, errors, "")
	var graph := SurveyGraphV1.from_envelope(migrated, errors)
	if not errors.is_empty():
		return _refuse(result, errors, "")
	var report := SurveyValidator.validate(graph)
	if not bool(report["ok"]):
		for message in report["errors"]:
			errors.append(String(message))
		return _refuse(result, errors, "")
	graph.rebuild_caches()
	result["ok"] = true
	result["graph"] = graph
	return result

# The slot loader offers the one kept .bak generation when the slot itself is
# refused, which is the diegetic "consult the bound copy" path of section 6.
static func load_slot(path: String) -> Dictionary:
	var primary := load_graph(path)
	primary["used_bak"] = false
	if bool(primary["ok"]):
		return primary
	var bak_path := path + ".bak"
	if not FileAccess.file_exists(bak_path):
		return primary
	var fallback := load_graph(bak_path)
	fallback["used_bak"] = true
	fallback["slot_errors"] = primary["errors"]
	return fallback

static func _refuse(result: Dictionary, errors: Array, code: String) -> Dictionary:
	if not code.is_empty():
		errors.append(code)
	result["errors"] = errors
	result["message"] = DIEGETIC_ERROR
	result["ok"] = false
	return result
