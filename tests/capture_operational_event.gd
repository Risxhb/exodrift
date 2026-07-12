extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var app := (load("res://scenes/app.tscn") as PackedScene).instantiate()
	root.add_child(app)
	for _frame in 6:
		await process_frame
	app._start_new_run()
	for _frame in 6:
		await process_frame
	app._on_node_selected(&"s1_entry_b")
	for _frame in 12:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	image.save_png(ProjectSettings.globalize_path("res://build/event-preview.png"))
	quit(0)
