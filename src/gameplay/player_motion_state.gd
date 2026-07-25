class_name PlayerMotionState
extends RefCounted

# M1 core, DESIGN.md section 2. Pure walk/crouch/lean state with deterministic
# footstep events. Node input wiring and audio synthesis are integration work;
# this object never touches the scene tree.

const STANCE_WALK := "WALK"
const STANCE_CROUCH := "CROUCH"
const SPEED_WALK_MM := 2600
const SPEED_CROUCH_MM := 1200
const LEAN_LIMIT_MM := 350
const TICKS_PER_SECOND := 60
const STRIDE_MM := 750
const FULL_TURN_CENTIDEGREES := 36000

# Walking values are DESIGN section 2 verbatim. The one specified crouch pair
# (rock, 4 m, 0.4) fixes the crouch ratio, which is applied to the other floors
# rather than inventing per-surface crouch constants.
const SURFACE_STEPS := {
	"ROCK": {"radius_mm": 9000, "loudness_tenths": 10},
	"GRATE": {"radius_mm": 14000, "loudness_tenths": 15},
	"WATER": {"radius_mm": 16000, "loudness_tenths": 18},
	"SALT": {"radius_mm": 11000, "loudness_tenths": 12},
}
const SURFACE_ALIAS := {"RAIL": "ROCK", "RUBBLE": "ROCK"}
const CROUCH_RADIUS_NUM := 4000
const CROUCH_RADIUS_DEN := 9000
const CROUCH_LOUDNESS_NUM := 4
const CROUCH_LOUDNESS_DEN := 10

var pos := Vector3i.ZERO
var stance := STANCE_WALK
var lean_mm := 0
var yaw_centidegrees := 0
var surface := "ROCK"
var accumulator := 0
var stride_progress_mm := 0
var step_count := 0
var events: Array = []
var last_error := ""

func _init(p_pos: Vector3i = Vector3i.ZERO, p_surface: String = "ROCK") -> void:
	pos = p_pos
	set_surface(p_surface)

func set_stance(value: String) -> bool:
	if value != STANCE_WALK and value != STANCE_CROUCH:
		last_error = "unknown stance %s" % value
		return false
	if value != stance:
		stance = value
		accumulator = 0
	return true

func toggle_crouch() -> String:
	set_stance(STANCE_CROUCH if stance == STANCE_WALK else STANCE_WALK)
	return stance

func set_surface(value: String) -> bool:
	var resolved := resolve_surface(value)
	if resolved.is_empty():
		last_error = "unknown floor surface %s" % value
		return false
	surface = resolved
	return true

static func resolve_surface(value: String) -> String:
	if SURFACE_STEPS.has(value):
		return value
	if SURFACE_ALIAS.has(value):
		return String(SURFACE_ALIAS[value])
	return ""

func set_lean(value_mm: int) -> int:
	lean_mm = clampi(value_mm, -LEAN_LIMIT_MM, LEAN_LIMIT_MM)
	return lean_mm

func set_yaw(value_centidegrees: int) -> int:
	yaw_centidegrees = value_centidegrees % FULL_TURN_CENTIDEGREES
	if yaw_centidegrees < 0:
		yaw_centidegrees += FULL_TURN_CENTIDEGREES
	return yaw_centidegrees

func speed_mm_per_second() -> int:
	return SPEED_CROUCH_MM if stance == STANCE_CROUCH else SPEED_WALK_MM

func lean_offset() -> Vector3i:
	var quadrant := yaw_centidegrees / 9000
	if quadrant == 0:
		return Vector3i(lean_mm, 0, 0)
	if quadrant == 1:
		return Vector3i(0, 0, lean_mm)
	if quadrant == 2:
		return Vector3i(-lean_mm, 0, 0)
	return Vector3i(0, 0, -lean_mm)

func effective_pos() -> Vector3i:
	return pos + lean_offset()

# One 60 Hz tick of motion along a cardinal unit direction. Returns the
# millimetres travelled this tick. Direction Vector3i.ZERO holds position.
func tick(direction: Vector3i) -> int:
	if direction == Vector3i.ZERO:
		return 0
	if not is_cardinal(direction):
		last_error = "direction must be a cardinal unit vector"
		return 0
	accumulator += speed_mm_per_second()
	var step_mm := accumulator / TICKS_PER_SECOND
	accumulator -= step_mm * TICKS_PER_SECOND
	pos += direction * step_mm
	stride_progress_mm += step_mm
	while stride_progress_mm >= STRIDE_MM:
		stride_progress_mm -= STRIDE_MM
		step_count += 1
		events.append(footstep_event())
	return step_mm

func footstep_event() -> Dictionary:
	var entry: Dictionary = SURFACE_STEPS[surface]
	var radius_mm := int(entry["radius_mm"])
	var loudness_tenths := int(entry["loudness_tenths"])
	if stance == STANCE_CROUCH:
		radius_mm = radius_mm * CROUCH_RADIUS_NUM / CROUCH_RADIUS_DEN
		loudness_tenths = loudness_tenths * CROUCH_LOUDNESS_NUM / CROUCH_LOUDNESS_DEN
	return {
		"index": step_count,
		"pos": effective_pos(),
		"surface": surface,
		"stance": stance,
		"radius_mm": radius_mm,
		"loudness_tenths": loudness_tenths,
	}

func drain_events() -> Array:
	var out := events.duplicate(true)
	events.clear()
	return out

static func is_cardinal(direction: Vector3i) -> bool:
	var nonzero := 0
	for axis in [direction.x, direction.y, direction.z]:
		if axis == 0:
			continue
		if axis != 1 and axis != -1:
			return false
		nonzero += 1
	return nonzero == 1

func canonical_text() -> String:
	var parts := PackedStringArray()
	parts.append("player %d,%d,%d %s lean=%d yaw=%d %s acc=%d stride=%d steps=%d" % [pos.x, pos.y, pos.z, stance, lean_mm, yaw_centidegrees, surface, accumulator, stride_progress_mm, step_count])
	for event in events:
		var event_pos: Vector3i = event["pos"]
		parts.append("step%d %d,%d,%d %s %s r=%d l=%d" % [int(event["index"]), event_pos.x, event_pos.y, event_pos.z, String(event["surface"]), String(event["stance"]), int(event["radius_mm"]), int(event["loudness_tenths"])])
	return "\n".join(parts)

func to_snapshot() -> Dictionary:
	return {
		"pos": pos,
		"stance": stance,
		"lean_mm": lean_mm,
		"yaw_centidegrees": yaw_centidegrees,
		"surface": surface,
		"accumulator": accumulator,
		"stride_progress_mm": stride_progress_mm,
		"step_count": step_count,
		"events": events.duplicate(true),
	}

static func from_snapshot(data: Dictionary) -> PlayerMotionState:
	var player := PlayerMotionState.new(data["pos"], String(data["surface"]))
	player.stance = String(data["stance"])
	player.lean_mm = int(data["lean_mm"])
	player.yaw_centidegrees = int(data["yaw_centidegrees"])
	player.accumulator = int(data["accumulator"])
	player.stride_progress_mm = int(data["stride_progress_mm"])
	player.step_count = int(data["step_count"])
	player.events = (data["events"] as Array).duplicate(true)
	return player
