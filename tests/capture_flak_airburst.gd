extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	ExodriftSpaceSky.apply_to_environment(environment, &"acheron")
	environment.background_energy_multiplier = 0.42
	environment_node.environment = environment
	stage.add_child(environment_node)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 70.0, 780.0)
	camera.fov = 44.0
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	for _frame in 6:
		await process_frame
	var vfx := root.get_node_or_null("CombatVFX")
	if vfx == null:
		quit(2)
		return
	vfx.spawn_flak_airburst(Vector3(-170.0, 55.0, 0.0), &"friendly", &"cvn_sidebay", 1.15)
	vfx.spawn_flak_airburst(Vector3(30.0, -30.0, -45.0), &"friendly", &"cvn_sidebay", 1.3)
	vfx.spawn_flak_airburst(Vector3(210.0, 82.0, -110.0), &"hostile", &"acheron_screen_corvette", 1.0)
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	image.save_png(ProjectSettings.globalize_path("res://build/flak-airburst-preview.png"))
	quit(0)
