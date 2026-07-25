extends Control
## Standalone M2 plot-sheet preview and capture harness (HOLLOW SURVEY).
## Not wired into project.godot; run directly as a scene. With user args
## "-- --output PATH" it saves one frame to PATH and quits, otherwise it just
## displays the fully unfolded fixture sheet.

const PlotSheetModelScript := preload("res://src/ui/m2/plot_sheet_model.gd")
const FixtureScript := preload("res://src/ui/m2/plot_sheet_fixture.gd")

var _model: RefCounted


func _ready() -> void:
	_model = PlotSheetModelScript.new()
	var errs: Array = _model.load_snapshot(FixtureScript.snapshot())
	if not errs.is_empty():
		push_error("plot sheet fixture invalid: %s" % [errs])
		get_tree().quit(1)
		return
	_model.request(true)
	for i: int in PlotSheetModelScript.FOLD_TICKS:
		_model.tick()
	$View.present(_model.commands(), _model.fold_fraction())
	var out := _output_arg()
	if not out.is_empty():
		_capture(out)


func command_count() -> int:
	if _model == null:
		return 0
	return _model.command_count()


func _output_arg() -> String:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size() - 1:
		if args[i] == "--output":
			return args[i + 1]
	return ""


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var abs_path := path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("plot sheet capture failed: %d" % err)
		get_tree().quit(1)
		return
	print("M2 PLOT SHEET CAPTURE OK %s" % path)
	get_tree().quit()
