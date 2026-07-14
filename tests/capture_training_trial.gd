extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(2560, 1440)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.training_trial = true
	root.add_child(game)
	for _frame in 30:
		if is_instance_valid(game.training_controller):
			break
		await process_frame
	if not is_instance_valid(game.training_controller):
		quit(2)
		return
	game.training_controller.set_process(false)
	game.hostile_command.global_position = Vector3(0.0, 35.0, 450.0)
	game.sensors.emit_active_ping()
	game.training_controller._set_step(ExodriftTrainingTrialController.Step.ENGAGE)
	for _frame in 24:
		await process_frame
	# A few completed draw/readback cycles avoid intermittent partial GPU frames on
	# Windows compatibility rendering when font atlases have just been populated.
	for _draw in 3:
		await RenderingServer.frame_post_draw
		await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	image.save_png(ProjectSettings.globalize_path("res://build/training-trial-preview-1440.png"))
	game.queue_free()
	await process_frame
	quit(0)
