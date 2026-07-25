extends Node3D

const CYAN := Color(0.18, 0.92, 0.82, 1.0)
const AMBER := Color(1.0, 0.42, 0.12, 1.0)
const POINT_COUNT := 720

var _capture_path := ""
var _frames_waited := 0

func _ready() -> void:
	_build_camera()
	_build_environment()
	_build_survey_cloud()
	_build_station()
	_capture_path = _read_capture_path()

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

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.2, 6.8)
	camera.fov = 67.0
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.0, -4.0))
	add_child(camera)

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.004, 0.006, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.15, 0.22, 0.23, 1.0)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)

func _build_survey_cloud() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, 0.035)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.instance_count = POINT_COUNT
	multimesh.mesh = mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 19790417
	for index in POINT_COUNT:
		var z := -rng.randf_range(0.5, 14.0)
		var side := index % 4
		var point := Vector3.ZERO
		if side == 0:
			point = Vector3(-2.1 + rng.randf_range(-0.08, 0.08), rng.randf_range(-1.35, 1.5), z)
		elif side == 1:
			point = Vector3(2.1 + rng.randf_range(-0.08, 0.08), rng.randf_range(-1.35, 1.5), z)
		elif side == 2:
			point = Vector3(rng.randf_range(-2.1, 2.1), 1.5 + rng.randf_range(-0.06, 0.06), z)
		else:
			point = Vector3(rng.randf_range(-2.1, 2.1), -1.35 + rng.randf_range(-0.04, 0.04), z)
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, point))
		var depth_fade := clampf(1.0 - ((-point.z) / 18.0), 0.25, 1.0)
		var noise := rng.randf_range(0.72, 1.0)
		multimesh.set_instance_color(index, Color(CYAN.r * depth_fade * noise, CYAN.g * depth_fade * noise, CYAN.b * depth_fade * noise, 1.0))
	var cloud := MultiMeshInstance3D.new()
	cloud.multimesh = multimesh
	add_child(cloud)

func _build_station() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.13
	mesh.height = 0.26
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = AMBER
	material.emission_enabled = true
	material.emission = AMBER
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	for point in [Vector3(0.0, 0.0, -3.2), Vector3(-0.75, 0.45, -7.0), Vector3(0.9, -0.25, -10.5)]:
		var station := MeshInstance3D.new()
		station.mesh = mesh
		station.position = point
		add_child(station)

func _read_capture_path() -> String:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--output" and index + 1 < args.size():
			return ProjectSettings.globalize_path(args[index + 1])
	return ""
