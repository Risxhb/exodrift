extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in 12:
		await process_frame
	if scene.hud != null:
		scene.hud.visible = false
	for entity in get_nodes_in_group("combat_entities"):
		if entity is CombatShip:
			entity.ai_enabled = false
			entity.velocity = Vector3.ZERO
			entity.set_physics_process(false)
	for projectile in get_nodes_in_group("projectiles"):
		projectile.queue_free()
	_scene_ship(scene.carrier, Vector3(-145.0, -55.0, 75.0), Vector3(0.0, 0.42, 0.0))
	_scene_ship(scene.escort, Vector3(-300.0, 100.0, 145.0), Vector3(0.02, 0.34, -0.05))
	_scene_ship(scene.hostile_command, Vector3(145.0, 80.0, 130.0), Vector3(0.0, -0.4, 0.02))
	_scene_ship(scene.hostile_corvette, Vector3(310.0, -95.0, 55.0), Vector3(-0.03, -0.32, 0.06))
	if scene.hostile_fighters != null:
		var fighter_index := 0
		for craft in scene.hostile_fighters.crafts:
			if not is_instance_valid(craft) or fighter_index >= 4:
				continue
			craft.deployed = true
			craft.visible = true
			craft.set_physics_process(false)
			craft.global_position = Vector3(70.0 + fighter_index * 48.0, -155.0 + (fighter_index % 2) * 38.0, 10.0 + fighter_index * 24.0)
			craft.rotation = Vector3(0.0, -0.12, 0.05)
			fighter_index += 1
	var camera := Camera3D.new()
	camera.name = "ShowcaseCamera"
	camera.fov = 46.0
	camera.far = 30000.0
	camera.position = Vector3(0.0, 105.0, -420.0)
	scene.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 90.0))
	camera.current = true
	for _frame in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Showcase capture did not produce an image")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	image.save_png(ProjectSettings.globalize_path("res://build/ship-showcase-m16.png"))
	print("CAPTURE: build/ship-showcase-m16.png %dx%d" % [image.get_width(), image.get_height()])
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _scene_ship(ship: CombatShip, position_value: Vector3, rotation_value: Vector3) -> void:
	if not is_instance_valid(ship):
		return
	ship.global_position = position_value
	ship.rotation = rotation_value
