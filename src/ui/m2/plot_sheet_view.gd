extends Control
## Hand-plotted plot-sheet renderer (HOLLOW SURVEY M2, DESIGN slice B).
## Pure CanvasItem 2D drawing driven ONLY by a PlotSheetModel command list:
## ivory paper, graphite pencil work, cyan prior-survey lines, amber fresh
## lines, red-orange station marks, tombstone strike-throughs, and the
## SURVEY completion figure. Cheap under llvmpipe: bounded line/circle/text
## primitives, no shaders, no textures, no external assets.

const PAPER := Color(0.92, 0.89, 0.8)
const PAPER_EDGE := Color(0.75, 0.71, 0.6)
const GRAPHITE := Color(0.28, 0.27, 0.25)
const CYAN := Color(0.435, 0.827, 0.78)
const AMBER := Color(0.91, 0.639, 0.239)
const STATION_RED := Color(0.851, 0.314, 0.165)
const MARGIN_PX := 34.0

var _commands: Array[Dictionary] = []
var _fold_fraction := 1.0
var _min_mm := Vector2.ZERO
var _max_mm := Vector2.ONE
var _scale := 1.0
var _offset := Vector2.ZERO


func present(commands: Array[Dictionary], fold_fraction: float) -> void:
	_commands = commands
	_fold_fraction = clampf(fold_fraction, 0.0, 1.0)
	_recompute_bounds()
	queue_redraw()


func _recompute_bounds() -> void:
	var pts: Array = []
	for cmd: Dictionary in _commands:
		match cmd["op"]:
			"line":
				pts.append(cmd["from_mm"])
				pts.append(cmd["to_mm"])
			"marker", "label":
				pts.append(cmd["at_mm"])
			"strike":
				for stroke: Array in cmd["strokes"]:
					pts.append(stroke[0])
					pts.append(stroke[1])
	if pts.is_empty():
		_min_mm = Vector2.ZERO
		_max_mm = Vector2.ONE
		return
	_min_mm = Vector2(INF, INF)
	_max_mm = Vector2(-INF, -INF)
	for p: Array in pts:
		var v := Vector2(float(p[0]), float(p[1]))
		_min_mm = _min_mm.min(v)
		_max_mm = _max_mm.max(v)
	if _max_mm.x - _min_mm.x < 1.0:
		_max_mm.x = _min_mm.x + 1.0
	if _max_mm.y - _min_mm.y < 1.0:
		_max_mm.y = _min_mm.y + 1.0


func _px(p_mm: Array) -> Vector2:
	var x := (float(p_mm[0]) - _min_mm.x) * _scale + _offset.x
	var y := (_max_mm.y - float(p_mm[1])) * _scale + _offset.y
	return Vector2(x, y)


func _draw() -> void:
	if _fold_fraction <= 0.0:
		return
	var full := get_rect().size
	var paper := Rect2(Vector2(0.0, full.y * 0.5 * (1.0 - _fold_fraction)), Vector2(full.x, full.y * _fold_fraction))
	draw_rect(paper, PAPER)
	draw_rect(paper, PAPER_EDGE, false, 2.0)
	var area := full - Vector2(MARGIN_PX * 2.0, MARGIN_PX * 2.0)
	var span := _max_mm - _min_mm
	_scale = minf(area.x / span.x, area.y / span.y)
	_offset = Vector2(MARGIN_PX, MARGIN_PX) + (area - span * _scale) * 0.5
	if _fold_fraction < 1.0:
		draw_line(Vector2(0.0, full.y * 0.5), Vector2(full.x, full.y * 0.5), PAPER_EDGE, 1.0)
	draw_set_transform(Vector2(0.0, paper.position.y), 0.0, Vector2(1.0, _fold_fraction))
	var font := ThemeDB.fallback_font
	for cmd: Dictionary in _commands:
		match cmd["op"]:
			"line":
				var a := _px(cmd["from_mm"])
				var b := _px(cmd["to_mm"])
				match cmd["layer"]:
					"prior":
						draw_line(a, b, CYAN, 2.0)
					"fresh":
						draw_line(a, b, AMBER, 2.0)
					_:
						draw_dashed_line(a, b, GRAPHITE, 1.0, 6.0)
			"marker":
				var p := _px(cmd["at_mm"])
				match cmd["kind"]:
					"STATION":
						draw_circle(p, 5.0, STATION_RED)
						draw_circle(p, 2.0, PAPER)
					"JUNCTION":
						draw_rect(Rect2(p - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), GRAPHITE)
					_:
						draw_circle(p, 2.0, GRAPHITE if cmd["scanned"] else PAPER_EDGE)
			"label":
				draw_string(font, _px(cmd["at_mm"]) + Vector2(8.0, -8.0), cmd["text"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, GRAPHITE)
			"strike":
				for stroke: Array in cmd["strokes"]:
					draw_line(_px(stroke[0]), _px(stroke[1]), GRAPHITE, 2.5)
			"completion":
				draw_string(font, Vector2(MARGIN_PX, 26.0), cmd["text"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, GRAPHITE)
