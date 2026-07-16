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
	environment.background_color = Color(0.001, 0.004, 0.012)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.24, 0.38)
	environment.ambient_light_energy = 0.55
	environment.glow_enabled = true
	environment_node.environment = environment
	stage.add_child(environment_node)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28.0, -34.0, 0.0)
	key.light_color = Color(0.55, 0.78, 1.0)
	key.light_energy = 2.8
	stage.add_child(key)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 34.0, 325.0)
	camera.fov = 49.0
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, -4.0, 0.0), Vector3.UP)

	for _frame in 4:
		await process_frame
	var vfx := root.get_node_or_null("CombatVFX")
	if vfx == null:
		quit(2)
		return
	vfx.spawn_burst("shield", Vector3(-106.0, 38.0, 0.0), 5.2)
	vfx.spawn_faction_burst("nuclear", Vector3(-8.0, 36.0, 0.0), &"friendly", &"cvn_sidebay", 2.45)
	vfx.spawn_warp_effect(Vector3(94.0, 38.0, 0.0), false, 1.8)
	vfx.spawn_warp_effect(Vector3(101.0, -54.0, 0.0), true, 1.05)
	vfx.spawn_damage_effect(Vector3(-96.0, -54.0, 0.0), false, 2.2)
	for index in 4:
		vfx.spawn_burst("armor_shard", Vector3(-112.0 + index * 10.0, -60.0 + (index % 2) * 10.0, 0.0), 4.0)
	vfx.spawn_shockwave(Vector3(-10.0, -54.0, 0.0), 2.5)

	var guided: Node3D = vfx.create_projectile_visual("missile", true, &"friendly", &"cvn_sidebay")
	guided.position = Vector3(18.0, -50.0, 0.0)
	guided.scale = Vector3.ONE * 3.8
	guided.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	stage.add_child(guided)
	var torpedo: Node3D = vfx.create_projectile_visual("nuclear", true, &"friendly", &"cvn_sidebay")
	torpedo.position = Vector3(50.0, -50.0, 0.0)
	torpedo.scale = Vector3.ONE * 3.0
	torpedo.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	stage.add_child(torpedo)

	_add_screen_labels()

	# Stage every effect at a representative production frame. This makes the
	# reference deterministic even when the window starts at a different refresh
	# rate on CI or a developer workstation.
	for slot in vfx.impact_slots:
		if not bool(slot.active):
			continue
		var display_scale := 7.0
		match String(slot.role):
			"shield": display_scale = 15.0
			"nuclear": display_scale = 13.0
			"nuclear_ring": display_scale = 17.0
			"blast_core": display_scale = 6.5
			"shockwave": display_scale = 12.0
			"armor_shard", "debris": display_scale = 3.2
			"warp_in_ring", "warp_out_ring": display_scale = 15.0
			"warp_in_core", "warp_out_core": display_scale = 10.5
			"warp_in_wake", "warp_out_wake": display_scale = 12.0
		slot.start_scale = display_scale
		slot.end_scale = display_scale
		slot.age = float(slot.duration) * 0.12
	vfx._process(0.0)
	vfx.set_process(false)

	for _frame in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		quit(3)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png(ProjectSettings.globalize_path("res://build/authored-vfx-runtime.png"))
	quit(0 if error == OK else 4)

func _add_screen_labels() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	for entry in [
		["SHIELD IMPACT", Vector2(284.0, 114.0)], ["NUCLEAR BLOOM", Vector2(552.0, 114.0)],
		["WARP IN", Vector2(838.0, 114.0)], ["ARMOR BREAK", Vector2(274.0, 650.0)],
		["SHOCKWAVE", Vector2(548.0, 650.0)], ["MISSILE / TORPEDO", Vector2(690.0, 650.0)],
		["WARP OFF", Vector2(1000.0, 650.0)],
	]:
		var label := Label.new()
		label.text = entry[0]
		label.position = entry[1]
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", Color(0.52, 0.8, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.03, 0.08, 0.95))
		label.add_theme_constant_override("outline_size", 5)
		layer.add_child(label)
