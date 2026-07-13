extends SceneTree

const OUTPUT_SIZE := Vector2i(900, 520)

func _initialize() -> void:
	call_deferred("_capture_archive")

func _capture_archive() -> void:
	print("CAPTURE: preparing fleet archive renderer")
	root.size = OUTPUT_SIZE
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	if scene.hud != null:
		scene.hud.visible = false
		scene.hud.process_mode = Node.PROCESS_MODE_DISABLED
	for _frame in 12:
		await process_frame
	for entity in get_nodes_in_group("combat_entities"):
		if entity is CombatShip:
			entity.ai_enabled = false
			entity.velocity = Vector3.ZERO
			entity.set_physics_process(false)
			entity.visible = false
	for projectile in get_nodes_in_group("projectiles"):
		projectile.queue_free()
	var camera := Camera3D.new()
	camera.name = "FleetArchiveCamera"
	camera.fov = 34.0
	camera.near = 0.03
	camera.far = 30000.0
	camera.cull_mask = 2
	scene.add_child(camera)
	camera.current = true
	_add_archive_light(scene, Color(0.78, 0.91, 1.0), 2.8, Vector3(-52.0, -38.0, 0.0))
	_add_archive_light(scene, Color(0.24, 0.7, 1.0), 1.6, Vector3(28.0, 138.0, 6.0))
	_add_archive_light(scene, Color(1.0, 0.48, 0.24), 0.7, Vector3(-12.0, 72.0, -8.0))
	var archive: Array[Dictionary] = [
		{"file": "sidebay-model.png", "ship": scene.carrier},
		{"file": "resolute-model.png", "ship": scene.escort},
		{"file": "raptor-model.png", "ship": scene.interceptor.crafts[0]},
		{"file": "watcher-model.png", "ship": scene.scout.crafts[0]},
		{"file": "acheron-picket-model.png", "ship": scene.hostile_command},
	]
	for sector_index in [1, 2]:
		scene.campaign_sector_index = sector_index
		var sector: Dictionary = scene._sector_encounter_profile()
		var hostile := CombatShip.new()
		scene.add_child(hostile)
		hostile.configure(scene._frigate_definition(String(sector.command_name), true), StringName("archive_hostile_%d" % sector_index), &"hostile", sector.command_color)
		hostile.ai_enabled = false
		hostile.set_physics_process(false)
		hostile.visible = false
		archive.append({
			"file": "vesper-lance-model.png" if sector_index == 1 else "crucible-regent-model.png",
			"ship": hostile,
		})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://web/assets"))
	for entry in archive:
		await _capture_model(entry, archive, camera)
	print("CAPTURE: %d fleet archive model renders written to web/assets" % archive.size())
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _capture_model(entry: Dictionary, archive: Array[Dictionary], camera: Camera3D) -> void:
	print("CAPTURE: staging %s" % entry.file)
	for candidate in archive:
		var candidate_ship: CombatShip = candidate.ship
		candidate_ship.visible = false
	var ship: CombatShip = entry.ship
	ship.global_position = Vector3.ZERO
	ship.rotation_degrees = Vector3(0.0, -8.0, 0.0)
	ship.visible = true
	_set_render_layer(ship, 2)
	_add_archive_material_fill(ship)
	var dimensions: Vector3 = ship.definition.dimensions_m
	var span := maxf(dimensions.x, dimensions.z)
	camera.global_position = Vector3(span * 0.58, span * 0.45, -span * 1.12)
	camera.look_at(Vector3(0.0, 0.0, dimensions.z * 0.04), Vector3.UP)
	for _frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Fleet archive capture failed for %s" % entry.file)
		quit(2)
		return
	var output_path := ProjectSettings.globalize_path("res://web/assets/%s" % entry.file)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Unable to save %s (error %d)" % [output_path, error])
		quit(3)
		return
	print("CAPTURE: web/assets/%s %dx%d" % [entry.file, image.get_width(), image.get_height()])

func _set_render_layer(node: Node, layer_value: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer_value
	for child in node.get_children():
		_set_render_layer(child, layer_value)

func _add_archive_light(parent: Node3D, color: Color, energy: float, rotation_value: Vector3) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.light_cull_mask = 2
	light.rotation_degrees = rotation_value
	parent.add_child(light)

func _add_archive_material_fill(node: Node) -> void:
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		var material := (node.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		if material.albedo_texture != null:
			material.emission_enabled = true
			material.emission = material.albedo_color
			material.emission_texture = material.albedo_texture
			material.emission_energy_multiplier = 0.28
		node.material_override = material
	for child in node.get_children():
		_add_archive_material_fill(child)
