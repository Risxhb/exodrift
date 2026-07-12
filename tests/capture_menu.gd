extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var app := (load("res://scenes/app.tscn") as PackedScene).instantiate()
	root.add_child(app)
	for _frame in 90:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	image.save_png(ProjectSettings.globalize_path("res://build/menu-preview.png"))
	quit(0)
