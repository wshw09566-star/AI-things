extends Node3D
## CH-02 "Sorting Hall" — M1 design slice preview (HOLLOW SURVEY).
## 1979 potash-mine sorting hall, converted 1974 to a seed archive, abandoned 1977.
## Everything is generated from primitives at runtime; zero external assets.
## Composition contract:
##   - Prior survey (Halvard) = CYAN residue points covering the WEST exit + corridor.
##   - Fresh survey = AMBER points over traversable structure (floor, conveyor,
##     pillars, racks, far wall).
##   - The EAST exit falls into true unscanned black (no points, no light).
##   - The entity is only a denser desaturated-white anomaly inside scanned space.

const SCENE_SEED := 19790212
const MAX_PREVIEW_INSTANCES := 5000

const CYAN := Color(0.435, 0.827, 0.78)
const AMBER := Color(0.91, 0.639, 0.239)
const STATION_RED := Color(0.851, 0.314, 0.165)
const ANOMALY_WHITE := Color(0.93, 0.95, 0.96)

# Hall envelope: x in [-6, 6], z in [-20, 2], floor y = 0, back wall z = -20.
const WEST_EXIT_CENTER := Vector3(-3.0, 1.5, -20.0)
const EAST_EXIT_CENTER := Vector3(3.0, 1.5, -20.0)

const DEFAULT_CAMERA_POSITION := Vector3(0.4, 1.65, 1.3)
const DEFAULT_CAMERA_TARGET := Vector3(-0.2, 1.1, -19.0)

## M1 visual-QA 12-frame shot list. Keys are filename tokens (output basename
## m1-f01 -> "f01"); values are [camera position, look-at target]. Fully deterministic:
## no random camera placement. Unknown or absent tokens keep the accepted
## default camera above.
const SHOT_POSES := {
	"f01": [Vector3(0.0, 2.6, 1.9), Vector3(0.0, 1.0, -19.0)], # wide establishing from the cage-side entrance
	"f02": [Vector3(-2.6, 2.1, -2.4), Vector3(1.2, 0.6, -12.5)], # amber fresh-survey structure diagonal
	"f03": [Vector3(0.0, 1.7, -11.5), Vector3(0.0, 1.6, -20.0)], # both exits: cyan west vs black east
	"f04": [Vector3(-1.4, 1.3, -15.2), Vector3(-3.0, 1.1, -18.5)], # white entity anomaly at scanned boundary
	"f05": [Vector3(0.4, 1.25, -3.6), Vector3(1.5, 1.05, -5.5)], # station marker tripod close
	"f06": [Vector3(2.6, 1.35, -3.2), Vector3(-0.45, 1.05, -14.0)], # conveyor silhouette down the spine
	"f07": [Vector3(1.6, 1.7, -5.6), Vector3(4.3, 0.5, -9.6)], # archive crates near the east wall
	"f08": [Vector3(-4.3, 1.8, 0.8), Vector3(-5.55, 2.4, -14.0)], # pillar rhythm depth along the west wall
	"f09": [Vector3(-4.6, 1.4, -16.8), Vector3(-2.8, 1.5, -20.1)], # scanned west-exit close with cyan residue
	"f10": [Vector3(2.3, 1.6, -14.8), Vector3(3.2, 1.4, -20.0)], # unscanned east-exit black threshold
	"f11": [Vector3(0.0, 5.3, -5.2), Vector3(0.0, 0.0, -11.5)], # overhead survey-density composition
	"f12": [Vector3(0.9, 0.3, -0.6), Vector3(3.2, 2.4, -19.8)], # low-angle darkness/depth stress shot
}

var _capture_path := ""
var _frames_waited := 0
# Generated point sets kept by cloud name so tests can verify content without
# reading back from the RenderingServer (headless uses a dummy renderer).
var _cloud_points := {}

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SCENE_SEED
	_capture_path = _read_capture_path()
	_build_camera(shot_id_from_output(_capture_path))
	_build_environment()
	_build_lamp()
	_build_silhouettes()
	_build_exits()
	_build_scanned_zone(rng)
	_build_station_marker()

func _process(_delta: float) -> void:
	if _capture_path.is_empty():
		return
	_frames_waited += 1
	if _frames_waited < 8:
		return
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_capture_path)
	if error != OK:
		push_error("Capture failed: %s" % error_string(error))
		get_tree().quit(2)
	else:
		print("CAPTURE SAVED ", _capture_path, " ", image.get_width(), "x", image.get_height())
		get_tree().quit(0)

func total_point_instances() -> int:
	var total := 0
	for key in _cloud_points:
		total += (_cloud_points[key] as PackedVector3Array).size()
	return total

func point_checksum() -> int:
	var checksum := 0
	var keys := _cloud_points.keys()
	keys.sort()
	for key in keys:
		checksum ^= hash(_cloud_points[key]) + (_cloud_points[key] as PackedVector3Array).size()
	return checksum

func cloud_centroid(cloud_name: String) -> Vector3:
	var points: PackedVector3Array = _cloud_points[cloud_name]
	var mean := Vector3.ZERO
	for point in points:
		mean += point
	return mean / float(points.size())

func _build_camera(shot_id: String) -> void:
	var camera := Camera3D.new()
	camera.name = "SurveyCamera"
	camera.fov = 68.0
	var pose := camera_pose_for_shot(shot_id)
	camera.position = pose[0]
	add_child(camera)
	camera.look_at(pose[1])

static func shot_id_from_output(path: String) -> String:
	var base := path.get_file().get_basename().to_lower()
	for part in base.replace("_", "-").replace(".", "-").split("-"):
		if SHOT_POSES.has(part):
			return part
	return ""

static func camera_pose_for_shot(shot_id: String) -> Array:
	if SHOT_POSES.has(shot_id):
		return SHOT_POSES[shot_id]
	return [DEFAULT_CAMERA_POSITION, DEFAULT_CAMERA_TARGET]

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "HallEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.003, 0.004, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.25, 0.28, 1.0)
	environment.ambient_light_energy = 0.3
	world.environment = environment
	add_child(world)

func _build_lamp() -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "HeadLamp"
	lamp.position = Vector3(0.0, 1.75, 1.0)
	lamp.omni_range = 7.5
	lamp.light_energy = 0.85
	lamp.light_color = Color(1.0, 0.92, 0.78)
	lamp.shadow_enabled = false
	add_child(lamp)

func _build_silhouettes() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.23, 0.22, 0.2)
	concrete.roughness = 1.0
	var parent := Node3D.new()
	parent.name = "Silhouettes"
	add_child(parent)
	var specs := [
		[Vector3(12.4, 0.2, 24.0), Vector3(0.0, -0.1, -9.0)],
		[Vector3(12.4, 0.3, 24.0), Vector3(0.0, 6.15, -9.0)],
		[Vector3(0.4, 6.0, 24.0), Vector3(-6.2, 3.0, -9.0)],
		[Vector3(0.4, 6.0, 24.0), Vector3(6.2, 3.0, -9.0)],
		[Vector3(2.0, 6.0, 0.4), Vector3(-5.0, 3.0, -20.2)],
		[Vector3(4.0, 6.0, 0.4), Vector3(0.0, 3.0, -20.2)],
		[Vector3(2.0, 6.0, 0.4), Vector3(5.0, 3.0, -20.2)],
		[Vector3(2.0, 3.0, 0.4), Vector3(-3.0, 4.5, -20.2)],
		[Vector3(2.0, 3.0, 0.4), Vector3(3.0, 4.5, -20.2)],
	]
	for pillar_z in [-2.0, -6.0, -10.0, -14.0, -18.0]:
		specs.append([Vector3(0.6, 6.0, 0.6), Vector3(-5.55, 3.0, pillar_z)])
		specs.append([Vector3(0.6, 6.0, 0.6), Vector3(5.55, 3.0, pillar_z)])
	for spec in specs:
		var mesh := BoxMesh.new()
		mesh.size = spec[0]
		mesh.material = concrete
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = spec[1]
		parent.add_child(instance)

func _build_exits() -> void:
	var exits := Node3D.new()
	exits.name = "Exits"
	add_child(exits)
	var west := Node3D.new()
	west.name = "ExitWestScanned"
	west.position = WEST_EXIT_CENTER
	exits.add_child(west)
	var east := Node3D.new()
	east.name = "ExitEastUnscanned"
	east.position = EAST_EXIT_CENTER
	exits.add_child(east)

func _build_scanned_zone(rng: RandomNumberGenerator) -> void:
	var zone := Node3D.new()
	zone.name = "ScannedZone"
	add_child(zone)
	var amber := _fresh_survey_points(rng)
	_cloud_points["FreshSurveyAmber"] = amber[0]
	zone.add_child(_make_cloud("FreshSurveyAmber", amber[0], amber[1], 0.055))
	var cyan := _prior_survey_points(rng)
	_cloud_points["PriorSurveyCyan"] = cyan[0]
	zone.add_child(_make_cloud("PriorSurveyCyan", cyan[0], cyan[1], 0.13))
	var anomaly := _entity_anomaly_points(rng)
	_cloud_points["EntityAnomaly"] = anomaly[0]
	zone.add_child(_make_cloud("EntityAnomaly", anomaly[0], anomaly[1], 0.07))
	if total_point_instances() > MAX_PREVIEW_INSTANCES:
		push_warning("Preview instance budget exceeded: %d" % total_point_instances())

func _make_cloud(cloud_name: String, points: PackedVector3Array, colors: PackedColorArray, point_size: float) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * point_size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = points.size()
	for index in points.size():
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, points[index]))
		multimesh.set_instance_color(index, colors[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = cloud_name
	instance.multimesh = multimesh
	return instance

func _amber_shade(rng: RandomNumberGenerator, z: float) -> Color:
	var fade := clampf(1.0 - absf(z) / 30.0, 0.35, 1.0)
	var glow := rng.randf_range(0.55, 1.0) * fade
	return Color(AMBER.r * glow, AMBER.g * glow, AMBER.b * glow, 1.0)

func _cyan_shade(rng: RandomNumberGenerator) -> Color:
	var glow := rng.randf_range(0.62, 1.0)
	return Color(CYAN.r * glow, CYAN.g * glow, CYAN.b * glow, 1.0)

func _fresh_survey_points(rng: RandomNumberGenerator) -> Array:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	# Floor coverage: this session's traversable scan.
	var z := -19.2
	while z < 0.4:
		var x := -5.4
		while x < 5.5:
			if rng.randf() > 0.24:
				points.append(Vector3(x + rng.randf_range(-0.16, 0.16), 0.02 + rng.randf_range(0.0, 0.05), z + rng.randf_range(-0.2, 0.2)))
				colors.append(_amber_shade(rng, z))
			x += 0.62
		z += 0.72
	# Conveyor skeleton down the hall spine: rails, legs, ties.
	var cz := -18.0
	while cz <= -2.0:
		for rail_x in [-0.45, 0.45]:
			points.append(Vector3(rail_x + rng.randf_range(-0.02, 0.02), 1.06 + rng.randf_range(-0.02, 0.02), cz))
			colors.append(_amber_shade(rng, cz))
		cz += 0.16
	var leg_z := -18.0
	while leg_z <= -2.0:
		for leg_x in [-0.5, 0.5]:
			var leg_y := 0.05
			while leg_y < 1.05:
				points.append(Vector3(leg_x, leg_y, leg_z + rng.randf_range(-0.02, 0.02)))
				colors.append(_amber_shade(rng, leg_z))
				leg_y += 0.16
		var tie_x := -0.45
		while tie_x <= 0.45:
			points.append(Vector3(tie_x, 1.07, leg_z))
			colors.append(_amber_shade(rng, leg_z))
			tie_x += 0.15
		leg_z += 2.0
	# Concrete/salt pillar rhythm along both walls; salt bloom near floor line.
	for pillar_z in [-2.0, -6.0, -10.0, -14.0, -18.0]:
		for pillar_x in [-5.55, 5.55]:
			var py := 0.1
			while py < 5.5:
				points.append(Vector3(pillar_x + rng.randf_range(-0.28, 0.28), py, pillar_z + rng.randf_range(-0.28, 0.28)))
				var shade := _amber_shade(rng, pillar_z)
				if py < 1.2:
					shade = shade.lerp(Color(1.0, 1.0, 0.92), 0.35)
				colors.append(shade)
				py += 0.17
	# Far wall scan, skipping both exit openings (east opening stays black).
	var wx := -5.9
	while wx < 6.0:
		var wy := 0.15
		while wy < 5.8:
			var in_west := wx > -4.1 and wx < -1.9 and wy < 3.1
			var in_east := wx > 1.9 and wx < 4.1 and wy < 3.1
			if not in_west and not in_east and rng.randf() > 0.3:
				points.append(Vector3(wx + rng.randf_range(-0.12, 0.12), wy + rng.randf_range(-0.12, 0.12), -19.85))
				colors.append(_amber_shade(rng, -19.85))
			wy += 0.42
		wx += 0.36
	# Sparse archive crates (hollow shells) near the east wall.
	for crate in [[Vector3(4.2, 0.5, -7.0), Vector3(1.2, 1.0, 1.2)], [Vector3(4.5, 0.42, -9.2), Vector3(1.0, 0.84, 1.4)], [Vector3(3.7, 0.36, -11.4), Vector3(0.9, 0.72, 1.0)]]:
		for i in 70:
			var local := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
			var axis := rng.randi_range(0, 2)
			var face := 0.5 if rng.randf() < 0.5 else -0.5
			if axis == 0:
				local.x = face
			elif axis == 1:
				local.y = face
			else:
				local.z = face
			points.append(crate[0] + local * crate[1])
			colors.append(_amber_shade(rng, crate[0].z))
	# Archive rack shelves against the west wall.
	for shelf_y in [0.35, 1.15, 1.95]:
		var rx := -5.45
		while rx < -4.2:
			for rz in [-12.2, -13.6]:
				points.append(Vector3(rx, shelf_y + rng.randf_range(-0.02, 0.02), rz + rng.randf_range(-0.5, 0.5)))
				colors.append(_amber_shade(rng, rz))
			rx += 0.14
	# Ceiling rib lines every 4 m.
	for rib_z in [-4.0, -8.0, -12.0, -16.0]:
		var rx2 := -5.5
		while rx2 < 5.6:
			points.append(Vector3(rx2, 5.7 + rng.randf_range(-0.05, 0.05), rib_z + rng.randf_range(-0.06, 0.06)))
			colors.append(_amber_shade(rng, rib_z))
			rx2 += 0.5
	return [points, colors]

func _prior_survey_points(rng: RandomNumberGenerator) -> Array:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	# Halvard's corridor beyond the west exit.
	var cz := -20.1
	while cz > -24.4:
		var t := 0.0
		while t < 3.0:
			for wall_x in [-4.05, -1.95]:
				if rng.randf() > 0.35:
					points.append(Vector3(wall_x + rng.randf_range(-0.05, 0.05), t + rng.randf_range(0.0, 0.3), cz))
					colors.append(_cyan_shade(rng))
			t += 0.34
		var fx := -4.0
		while fx < -1.9:
			if rng.randf() > 0.4:
				points.append(Vector3(fx, 0.03 + rng.randf_range(0.0, 0.04), cz))
				colors.append(_cyan_shade(rng))
			if rng.randf() > 0.5:
				points.append(Vector3(fx, 3.0 + rng.randf_range(-0.05, 0.02), cz))
				colors.append(_cyan_shade(rng))
			fx += 0.3
		cz -= 0.36
	# Dense residue on the west door frame.
	for i in 160:
		var p := rng.randf()
		var pos := Vector3.ZERO
		if p < 0.3:
			pos = Vector3(-4.0, rng.randf_range(0.0, 3.0), -19.9)
		elif p < 0.6:
			pos = Vector3(-2.0, rng.randf_range(0.0, 3.0), -19.9)
		else:
			pos = Vector3(rng.randf_range(-4.0, -2.0), 3.0, -19.9)
		pos += Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.1, 0.1))
		points.append(pos)
		colors.append(_cyan_shade(rng))
	# Residue spill onto the wall left of the exit and along the west wall.
	for i in 220:
		var wy := rng.randf_range(0.0, 4.2)
		if rng.randf() < 0.5:
			points.append(Vector3(rng.randf_range(-5.9, -4.2), wy, -19.85))
		else:
			points.append(Vector3(-5.9, wy, rng.randf_range(-19.9, -14.0)))
		colors.append(_cyan_shade(rng))
	# Halvard's plotted line from the west exit into the hall.
	for i in 70:
		var lt := i / 69.0
		var pos2 := Vector3(-3.0, 0.05, -19.6).lerp(Vector3(-0.6, 0.05, -9.0), lt)
		pos2.x += sin(lt * 3.0) * 0.3
		points.append(pos2)
		var glow := rng.randf_range(0.75, 1.0)
		colors.append(Color(CYAN.r * glow, CYAN.g * glow, CYAN.b * glow, 1.0))
	# Tripod station ticks along the plotted line.
	for tick_t in [0.15, 0.55, 0.9]:
		var base := Vector3(-3.0, 0.05, -19.6).lerp(Vector3(-0.6, 0.05, -9.0), tick_t)
		for i in 10:
			points.append(base + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.0, 0.5), rng.randf_range(-0.08, 0.08)))
			colors.append(_cyan_shade(rng))
	return [points, colors]

func _entity_anomaly_points(rng: RandomNumberGenerator) -> Array:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	# Denser desaturated-white reading inside the prior-scanned zone, just
	# inside the hall in front of the west exit. Not a monster mesh.
	var core := Vector3(-3.0, 0.0, -18.5)
	for i in 430:
		var px := clampf(rng.randfn(0.0, 0.15), -0.4, 0.4)
		var pz := clampf(rng.randfn(0.0, 0.15), -0.4, 0.4)
		var py := clampf(rng.randfn(1.05, 0.6), 0.1, 2.1)
		points.append(core + Vector3(px, py, pz))
		var glow := rng.randf_range(0.7, 1.0)
		var color := Color(ANOMALY_WHITE.r * glow, ANOMALY_WHITE.g * glow, ANOMALY_WHITE.b * glow, 1.0)
		if rng.randf() < 0.18:
			color = color.lerp(CYAN, 0.4)
		colors.append(color)
	return [points, colors]

func _build_station_marker() -> void:
	var marker := Node3D.new()
	marker.name = "StationMarker"
	marker.position = Vector3(1.5, 0.0, -5.5)
	add_child(marker)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.09
	head_mesh.height = 0.18
	var head_material := StandardMaterial3D.new()
	head_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head_material.albedo_color = STATION_RED
	head_mesh.material = head_material
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.18, 0.0)
	marker.add_child(head)
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.035, 1.3, 0.035)
	var leg_material := StandardMaterial3D.new()
	leg_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leg_material.albedo_color = STATION_RED.darkened(0.45)
	leg_mesh.material = leg_material
	for angle in [0.0, TAU / 3.0, 2.0 * TAU / 3.0]:
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		leg.position = Vector3(cos(angle) * 0.28, 0.62, sin(angle) * 0.28)
		leg.rotation = Vector3(sin(angle) * 0.35, 0.0, -cos(angle) * 0.35)
		marker.add_child(leg)

func _read_capture_path() -> String:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--output" and index + 1 < args.size():
			return ProjectSettings.globalize_path(args[index + 1])
	return ""
