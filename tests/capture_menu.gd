extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(2560, 1440)
	var app := (load("res://scenes/app.tscn") as PackedScene).instantiate()
	root.add_child(app)
	for _frame in 20:
		await process_frame
	# Capture the representative counter-salvo phase instead of whichever early
	# warp frame happens to align with the renderer's startup speed.
	if is_instance_valid(app.main_menu):
		app.main_menu.elapsed = 5.1
		app.main_menu._update_battle(0.0)
	for _frame in 8:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	image.save_png(ProjectSettings.globalize_path("res://build/menu-preview.png"))
	image.save_png(ProjectSettings.globalize_path("res://build/menu-preview-1440.png"))
	quit(0)
