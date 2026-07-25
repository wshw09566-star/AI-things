extends GdUnitTestSuite
## M2 plot-sheet content tests (HOLLOW SURVEY, DESIGN slice B).

const MODEL := preload("res://src/ui/m2/plot_sheet_model.gd")
const FIXTURE := preload("res://src/ui/m2/plot_sheet_fixture.gd")
const SCENE_PATH := "res://scenes/m2/plot_sheet_preview.tscn"


func _loaded_model() -> RefCounted:
	var m: RefCounted = MODEL.new()
	var errs: Array = m.load_snapshot(FIXTURE.snapshot())
	assert_bool(errs.is_empty()).is_true()
	return m


func _reversed_insertion(d: Dictionary) -> Dictionary:
	var keys: Array = d.keys()
	keys.reverse()
	var out := {}
	for k: Variant in keys:
		out[k] = d[k]
	return out


func test_validate_accepts_fixture() -> void:
	var errs: Array = MODEL.validate(FIXTURE.snapshot())
	assert_array(errs).is_empty()


func test_validate_rejects_missing_or_extra_top_keys() -> void:
	for key: String in ["nodes", "edges", "regions", "stations", "completion", "tombstones"]:
		var bad: Dictionary = FIXTURE.snapshot()
		bad.erase(key)
		assert_bool((MODEL.validate(bad) as Array).is_empty()).is_false()
	var extra: Dictionary = FIXTURE.snapshot()
	extra["extra"] = 1
	assert_bool((MODEL.validate(extra) as Array).is_empty()).is_false()
	assert_bool((MODEL.validate(null) as Array).is_empty()).is_false()


func test_validate_rejects_bad_edges() -> void:
	var bad: Dictionary = FIXTURE.snapshot().duplicate(true)
	bad["edges"][1]["a"] = bad["edges"][1]["b"]
	assert_bool((MODEL.validate(bad) as Array).is_empty()).is_false()
	var unknown: Dictionary = FIXTURE.snapshot().duplicate(true)
	unknown["edges"][1]["b"] = 999
	assert_bool((MODEL.validate(unknown) as Array).is_empty()).is_false()
	var unscanned: Dictionary = FIXTURE.snapshot().duplicate(true)
	unscanned["edges"][6]["scanned"] = true
	assert_bool((MODEL.validate(unscanned) as Array).is_empty()).is_false()


func test_validate_rejects_bad_tombstones_and_completion() -> void:
	var live: Dictionary = FIXTURE.snapshot().duplicate(true)
	live["tombstones"][0]["region_id"] = 1
	assert_bool((MODEL.validate(live) as Array).is_empty()).is_false()
	var unsorted: Dictionary = FIXTURE.snapshot().duplicate(true)
	var tmp: Variant = unsorted["tombstones"][0]
	unsorted["tombstones"][0] = unsorted["tombstones"][1]
	unsorted["tombstones"][1] = tmp
	assert_bool((MODEL.validate(unsorted) as Array).is_empty()).is_false()
	var over: Dictionary = FIXTURE.snapshot().duplicate(true)
	over["completion"]["numerator"] = over["completion"]["denominator"] + 1
	assert_bool((MODEL.validate(over) as Array).is_empty()).is_false()


func test_load_fail_closed_produces_no_commands() -> void:
	var bad: Dictionary = FIXTURE.snapshot().duplicate(true)
	bad.erase("completion")
	var m: RefCounted = MODEL.new()
	var errs: Array = m.load_snapshot(bad)
	assert_bool(errs.is_empty()).is_false()
	assert_int(m.command_count()).is_equal(0)


func test_commands_deterministic_across_insertion_order() -> void:
	var a: RefCounted = _loaded_model()
	var b: RefCounted = _loaded_model()
	var shuffled: Dictionary = FIXTURE.snapshot()
	shuffled["nodes"] = _reversed_insertion(shuffled["nodes"])
	shuffled["edges"] = _reversed_insertion(shuffled["edges"])
	shuffled["regions"] = _reversed_insertion(shuffled["regions"])
	shuffled["stations"] = _reversed_insertion(shuffled["stations"])
	var c: RefCounted = MODEL.new()
	assert_bool((c.load_snapshot(shuffled) as Array).is_empty()).is_true()
	var text_a := JSON.stringify(a.commands())
	assert_str(text_a).is_equal(JSON.stringify(b.commands()))
	assert_str(text_a).is_equal(JSON.stringify(c.commands()))


func test_commands_sorted_by_ids_and_completion_last() -> void:
	var m: RefCounted = _loaded_model()
	var cmds: Array = m.commands()
	var edge_ids: Array = []
	var node_ids: Array = []
	for cmd: Dictionary in cmds:
		if cmd["op"] == "line":
			edge_ids.append(cmd["edge_id"])
		elif cmd["op"] == "marker":
			node_ids.append(cmd["node_id"])
	assert_array(edge_ids).is_equal([1, 2, 3, 4, 5, 6, 7, 8])
	assert_array(node_ids).is_equal([1, 2, 3, 4, 5, 6, 7, 8, 9])
	assert_str((cmds[cmds.size() - 1] as Dictionary)["op"]).is_equal("completion")


func test_layers_prior_fresh_projection() -> void:
	var m: RefCounted = _loaded_model()
	var layers := {}
	for cmd: Dictionary in m.commands():
		if cmd["op"] == "line":
			layers[cmd["edge_id"]] = cmd["layer"]
	assert_str(layers[1]).is_equal("prior")
	assert_str(layers[3]).is_equal("fresh")
	assert_str(layers[6]).is_equal("projection")
	assert_str(layers[7]).is_equal("projection")


func test_station_labels_present() -> void:
	var m: RefCounted = _loaded_model()
	var labels: Array = []
	for cmd: Dictionary in m.commands():
		if cmd["op"] == "label":
			labels.append(cmd["text"])
	assert_array(labels).is_equal(["S-0114", "S-0117", "S-0123", "S-0131"])


func test_tombstone_and_pending_strikes() -> void:
	var m: RefCounted = _loaded_model()
	var tombs: Array = []
	var pending: Array = []
	for cmd: Dictionary in m.commands():
		if cmd["op"] == "strike":
			if cmd["source"] == "tombstone":
				tombs.append(cmd)
			else:
				pending.append(cmd)
	assert_int(tombs.size()).is_equal(2)
	assert_int((tombs[0] as Dictionary)["region_id"]).is_equal(5)
	assert_int((tombs[1] as Dictionary)["region_id"]).is_equal(7)
	var strokes: Array = (tombs[1] as Dictionary)["strokes"]
	assert_int(strokes.size()).is_equal(2)
	assert_array(strokes[0]).is_equal([[6000, 15000], [12000, 19000]])
	assert_array(strokes[1]).is_equal([[6000, 19000], [12000, 15000]])
	assert_int(pending.size()).is_equal(1)
	assert_int((pending[0] as Dictionary)["region_id"]).is_equal(3)


func test_completion_display_rules() -> void:
	assert_str(MODEL.completion_text(0, 0)).is_equal("SURVEY 0.0%")
	assert_str(MODEL.completion_text(1, 3)).is_equal("SURVEY 33.3%")
	assert_str(MODEL.completion_text(4213, 11200)).is_equal("SURVEY 37.6%")
	assert_str(MODEL.completion_text(11199, 11200)).is_equal("SURVEY 99.9%")
	assert_str(MODEL.completion_text(11200, 11200)).is_equal("SURVEY 100.0%")
	var zero: Dictionary = FIXTURE.snapshot()
	zero["completion"] = {"numerator": 0, "denominator": 0}
	var m: RefCounted = MODEL.new()
	assert_bool((m.load_snapshot(zero) as Array).is_empty()).is_true()
	var last: Dictionary = (m.commands() as Array).back()
	assert_str(last["text"]).is_equal("SURVEY 0.0%")
	assert_bool(last["complete"]).is_false()
	var full: Dictionary = FIXTURE.snapshot()
	full["completion"] = {"numerator": 11200, "denominator": 11200}
	var m2: RefCounted = MODEL.new()
	assert_bool((m2.load_snapshot(full) as Array).is_empty()).is_true()
	var last2: Dictionary = (m2.commands() as Array).back()
	assert_str(last2["text"]).is_equal("SURVEY 100.0%")
	assert_bool(last2["complete"]).is_true()
	var near: Dictionary = (_loaded_model().commands() as Array).back()
	assert_bool(near["complete"]).is_false()


func test_unfold_takes_exactly_90_ticks() -> void:
	var m: RefCounted = MODEL.new()
	assert_str(m.fold_state()).is_equal("CLOSED")
	m.request(true)
	var n := 0
	while not m.is_open():
		m.tick()
		n += 1
		assert_bool(n <= MODEL.FOLD_TICKS).is_true()
	assert_int(n).is_equal(90)
	assert_str(m.fold_state()).is_equal("OPEN")
	m.request(false)
	var back := 0
	while not m.is_closed():
		m.tick()
		back += 1
		assert_bool(back <= MODEL.FOLD_TICKS).is_true()
	assert_int(back).is_equal(90)


func test_scanner_lock_first_opening_tick_until_fully_closed() -> void:
	var m: RefCounted = MODEL.new()
	assert_bool(m.scanner_locked()).is_false()
	m.request(true)
	assert_bool(m.scanner_locked()).is_false()
	m.tick()
	assert_bool(m.scanner_locked()).is_true()
	assert_str(m.fold_state()).is_equal("OPENING")
	for i: int in 89:
		m.tick()
	assert_bool(m.is_open()).is_true()
	m.request(false)
	for i: int in 89:
		m.tick()
	assert_bool(m.scanner_locked()).is_true()
	assert_str(m.fold_state()).is_equal("CLOSING")
	m.tick()
	assert_bool(m.is_closed()).is_true()
	assert_bool(m.scanner_locked()).is_false()


func test_repeated_input_is_deterministic() -> void:
	var m: RefCounted = MODEL.new()
	m.request(true)
	m.request(true)
	for i: int in 200:
		m.tick()
	assert_bool(m.is_open()).is_true()
	assert_float(m.fold_fraction()).is_equal(1.0)
	m.request(false)
	m.request(false)
	for i: int in 200:
		m.tick()
	assert_bool(m.is_closed()).is_true()
	assert_float(m.fold_fraction()).is_equal(0.0)


func test_fold_serialize_resume_at_1_45_89() -> void:
	for t: int in [1, 45, 89]:
		var a: RefCounted = MODEL.new()
		a.request(true)
		for i: int in t:
			a.tick()
		var blob: Dictionary = a.serialize_fold()
		assert_int(blob["fold_ticks"]).is_equal(t)
		var b: RefCounted = MODEL.new()
		assert_bool(b.resume_fold(blob)).is_true()
		assert_bool(b.scanner_locked()).is_true()
		var extra := 0
		while not b.is_open():
			b.tick()
			extra += 1
			assert_bool(extra <= MODEL.FOLD_TICKS).is_true()
		assert_int(t + extra).is_equal(90)


func test_resume_rejects_invalid_state() -> void:
	var m: RefCounted = MODEL.new()
	assert_bool(m.resume_fold(null)).is_false()
	assert_bool(m.resume_fold({"fold_ticks": 1})).is_false()
	assert_bool(m.resume_fold({"fold_ticks": 91, "want_open": true})).is_false()
	assert_bool(m.resume_fold({"fold_ticks": -1, "want_open": false})).is_false()
	assert_bool(m.resume_fold({"fold_ticks": 5, "want_open": 1})).is_false()
	assert_bool(m.scanner_locked()).is_false()


func test_preview_scene_builds_without_external_assets() -> void:
	var scene_text := FileAccess.get_file_as_string(SCENE_PATH)
	assert_int(scene_text.count("ext_resource")).is_equal(2)
	for banned: String in [".png", ".jpg", ".obj", ".gltf", ".glb", ".wav", ".ogg", ".svg"]:
		assert_bool(scene_text.contains(banned)).is_false()
	var packed: PackedScene = load(SCENE_PATH)
	assert_object(packed).is_not_null()
	var preview: Control = packed.instantiate()
	add_child(preview)
	auto_free(preview)
	await get_tree().process_frame
	assert_int(preview.command_count()).is_greater(10)


func test_zz_end_to_end_banner() -> void:
	var m: RefCounted = MODEL.new()
	var ok: bool = (m.load_snapshot(FIXTURE.snapshot()) as Array).is_empty()
	m.request(true)
	var opened := 0
	while not m.is_open() and opened <= 200:
		m.tick()
		opened += 1
	ok = ok and opened == MODEL.FOLD_TICKS and m.scanner_locked()
	var blob: Dictionary = m.serialize_fold()
	var m2: RefCounted = MODEL.new()
	ok = ok and m2.resume_fold(blob) and m2.is_open()
	ok = ok and (m2.load_snapshot(FIXTURE.snapshot()) as Array).is_empty()
	ok = ok and JSON.stringify(m.commands()) == JSON.stringify(m2.commands())
	m2.request(false)
	var closed := 0
	while not m2.is_closed() and closed <= 200:
		m2.tick()
		closed += 1
	ok = ok and closed == MODEL.FOLD_TICKS and not m2.scanner_locked()
	assert_bool(ok).is_true()
	if ok:
		print("M2 PLOT MODEL PASS")
