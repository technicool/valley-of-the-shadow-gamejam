extends SceneTree

var _mode := "static"
var _shot_path := ""
var _frames := 0
var _stage := 0
var _stage_frames := 0
var _target := ""
var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]
	if args.size() > 1:
		_shot_path = args[1]
	print("main_scene setting: ", ProjectSettings.get_setting("application/run/main_scene"))
	change_scene_to_file("res://scenes/start_menu.tscn")


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1


func _finish() -> bool:
	print("RESULT failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)
	return true


func _check_menu(menu: Node) -> void:
	_check("menu scene loaded", menu.scene_file_path == "res://scenes/start_menu.tscn")
	var bg := menu.get_node("Background") as TextureRect
	_check("background texture assigned", bg != null and bg.texture != null)
	if bg != null and bg.texture != null:
		print("background texture size: ", bg.texture.get_size())
	var start := menu.get_node("Menu/Buttons/StartButton") as Button
	var editor := menu.get_node("Menu/Buttons/EditorButton") as Button
	_check("start button text is Start", start.text == "Start")
	_check("editor button text is Editor", editor.text == "Editor")
	_check("start button focused", start.has_focus())
	_check("theme normal style is StyleBoxFlat", start.get_theme_stylebox("normal") is StyleBoxFlat)
	print("start rect: ", start.get_global_rect(), "  editor rect: ", editor.get_global_rect())
	print("viewport size: ", root.get_visible_rect().size)


func _process(_delta: float) -> bool:
	_frames += 1
	if _stage == 0:
		if _frames < 10 or current_scene == null:
			return false
		_check_menu(current_scene)
		if _mode == "static":
			if _shot_path != "":
				root.get_texture().get_image().save_png(_shot_path)
				print("saved ", _shot_path)
			return _finish()
		var button_path := "Menu/Buttons/StartButton" if _mode == "start" else "Menu/Buttons/EditorButton"
		_target = "res://scenes/main.tscn" if _mode == "start" else "res://scenes/editor.tscn"
		(current_scene.get_node(button_path) as Button).pressed.emit()
		_stage = 1
		return false

	if _stage == 1:
		_stage_frames += 1
		if current_scene != null and current_scene.scene_file_path == _target:
			_check("navigated to " + _target, true)
			_stage = 2
			_stage_frames = 0
		elif _stage_frames > 300:
			_check("navigated to " + _target, false)
			return _finish()
		return false

	# Let the destination scene run for a while so runtime errors surface.
	_stage_frames += 1
	if _stage_frames >= 120:
		_check("destination still running", current_scene != null)
		return _finish()
	return false
