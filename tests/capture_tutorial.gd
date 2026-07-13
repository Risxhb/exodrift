extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(2560, 1440)
	var menu := ExodriftMainMenu.new()
	root.add_child(menu)
	menu.configure(false)
	for _frame in 20:
		await process_frame
	menu._show_tutorial()
	for _frame in 36:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	image.save_png(ProjectSettings.globalize_path("res://build/tutorial-preview-1440.png"))
	quit(0)
