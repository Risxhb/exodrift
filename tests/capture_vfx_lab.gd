extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.008, 0.014)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.22, 0.3)
	environment.ambient_light_energy = 0.35
	environment_node.environment = environment
	stage.add_child(environment_node)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 42.0, 520.0)
	camera.fov = 48.0
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	for _frame in 4:
		await process_frame
	var vfx := root.get_node_or_null("CombatVFX")
	if vfx == null:
		quit(2)
		return
	vfx.spawn_faction_burst("nuclear", Vector3.ZERO, &"friendly", &"cvn_sidebay", 2.8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	for sample in [{"frames": 4, "file": "vfx-nuclear-early.png"}, {"frames": 10, "file": "vfx-nuclear-mid.png"}, {"frames": 18, "file": "vfx-nuclear-late.png"}]:
		for _frame in int(sample.frames):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image != null:
			image.save_png(ProjectSettings.globalize_path("res://build/%s" % sample.file))
	quit(0)
