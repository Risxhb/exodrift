extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1920, 1080)
	var app := (load("res://scenes/app.tscn") as PackedScene).instantiate()
	root.add_child(app)
	for _frame in 16:
		await process_frame
	if not is_instance_valid(app.main_menu):
		quit(2)
		return
	app.main_menu.elapsed = 1.18
	app.main_menu._update_battle(0.0)
	for _frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		quit(3)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png(ProjectSettings.globalize_path("res://build/menu-warp-authored.png"))
	quit(0 if error == OK else 4)
