extends GdUnitTestSuite

const SCENE_PATH := "res://scenes/m1/sorting_hall.tscn"
const SCRIPT_PATH := "res://src/content/m1/sorting_hall.gd"

func _spawn_hall() -> Node3D:
	var packed: PackedScene = load(SCENE_PATH)
	assert_object(packed).is_not_null()
	var hall: Node3D = packed.instantiate()
	add_child(hall)
	return auto_free(hall)

func test_scene_loads_and_builds() -> void:
	var hall := _spawn_hall()
	assert_object(hall).is_not_null()
	assert_bool(hall.has_node("ScannedZone")).is_true()
	assert_bool(hall.has_node("ScannedZone/PriorSurveyCyan")).is_true()
	assert_bool(hall.has_node("ScannedZone/FreshSurveyAmber")).is_true()

func test_both_exits_exist_and_are_named() -> void:
	var hall := _spawn_hall()
	assert_bool(hall.has_node("Exits/ExitWestScanned")).is_true()
	assert_bool(hall.has_node("Exits/ExitEastUnscanned")).is_true()
	var west: Node3D = hall.get_node("Exits/ExitWestScanned")
	var east: Node3D = hall.get_node("Exits/ExitEastUnscanned")
	assert_float(west.position.distance_to(east.position)).is_greater(3.0)

func test_instance_count_within_budget() -> void:
	var hall := _spawn_hall()
	var total: int = hall.total_point_instances()
	assert_int(total).is_greater(500)
	assert_int(total).is_less_equal(hall.MAX_PREVIEW_INSTANCES)
	assert_int(total).is_less_equal(120000)

func test_deterministic_seed_exposed_and_stable() -> void:
	var script: GDScript = load(SCRIPT_PATH)
	var constants: Dictionary = script.get_script_constant_map()
	assert_bool(constants.has("SCENE_SEED")).is_true()
	assert_int(constants["SCENE_SEED"]).is_greater(0)
	var first := _spawn_hall()
	var second := _spawn_hall()
	assert_int(first.point_checksum()).is_equal(second.point_checksum())

func test_no_external_assets_referenced() -> void:
	var scene_text := FileAccess.get_file_as_string(SCENE_PATH)
	assert_int(scene_text.count("ext_resource")).is_equal(1)
	assert_bool(scene_text.contains("type=\"Script\"")).is_true()
	var script_text := FileAccess.get_file_as_string(SCRIPT_PATH)
	for banned in [".png", ".jpg", ".jpeg", ".obj", ".gltf", ".glb", ".wav", ".ogg", ".svg", ".exr", ".hdr"]:
		assert_bool(script_text.contains(banned)).is_false()

func test_entity_anomaly_parented_in_scanned_zone() -> void:
	var hall := _spawn_hall()
	assert_bool(hall.has_node("ScannedZone/EntityAnomaly")).is_true()
	var anomaly: MultiMeshInstance3D = hall.get_node("ScannedZone/EntityAnomaly")
	assert_object(anomaly.get_parent()).is_same(hall.get_node("ScannedZone"))
	var west: Node3D = hall.get_node("Exits/ExitWestScanned")
	var center: Vector3 = hall.cloud_centroid("EntityAnomaly") + anomaly.position
	var planar := Vector2(center.x, center.z).distance_to(Vector2(west.position.x, west.position.z))
	assert_float(planar).is_less(4.0)
