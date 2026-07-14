extends SceneTree

const OUTPUT_SIZE := Vector2i(900, 520)

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	print("CAPTURE: preparing missile frigate renderer")
	root.size = OUTPUT_SIZE
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in 12:
		await process_frame
	print("CAPTURE: staging ISS Resolute")
	if scene.hud != null:
		scene.hud.visible = false
		scene.hud.process_mode = Node.PROCESS_MODE_DISABLED
	for entity in get_nodes_in_group("combat_entities"):
		if entity is CombatShip:
			entity.ai_enabled = false
			entity.velocity = Vector3.ZERO
			entity.set_physics_process(false)
			entity.visible = false
	for projectile in get_nodes_in_group("projectiles"):
		projectile.queue_free()
	var frigate: CombatShip = scene.escort
	frigate.global_position = Vector3.ZERO
	frigate.rotation_degrees = Vector3.ZERO
	frigate.visible = true
	_set_render_layer(frigate, 2)
	_add_material_fill(frigate)
	var camera := Camera3D.new()
	camera.name = "MissileFrigateCamera"
	camera.fov = 34.0
	camera.near = 0.03
	camera.far = 30000.0
	camera.cull_mask = 2
	scene.add_child(camera)
	camera.current = true
	_add_light(scene, Color(0.78, 0.91, 1.0), 2.8, Vector3(-52.0, -38.0, 0.0))
	_add_light(scene, Color(0.24, 0.7, 1.0), 1.6, Vector3(28.0, 138.0, 6.0))
	_add_light(scene, Color(1.0, 0.48, 0.24), 0.7, Vector3(-12.0, 72.0, -8.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://web/assets"))
	var span := maxf(frigate.definition.dimensions_m.x, frigate.definition.dimensions_m.z)
	camera.global_position = Vector3(span * 0.58, span * 0.48, -span * 1.12)
	camera.look_at(Vector3(0.0, 0.0, frigate.definition.dimensions_m.z * 0.04), Vector3.UP)
	print("CAPTURE: rendering dorsal view")
	await _save_frame(["res://build/missile-frigate-preview.png", "res://web/assets/resolute-model.png"])
	camera.global_position = Vector3(span * 0.62, -span * 0.46, -span * 1.08)
	camera.look_at(Vector3(0.0, -frigate.definition.dimensions_m.y * 0.08, frigate.definition.dimensions_m.z * 0.03), Vector3.UP)
	print("CAPTURE: rendering ventral view")
	await _save_frame(["res://build/missile-frigate-ventral-preview.png"])
	print("CAPTURE: missile frigate dorsal and ventral previews written")
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _save_frame(paths: Array[String]) -> void:
	for _frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Missile frigate capture did not produce an image")
		quit(2)
		return
	for path in paths:
		var error := image.save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			push_error("Unable to save %s (error %d)" % [path, error])
			quit(3)
			return

func _set_render_layer(node: Node, layer_value: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer_value
	for child in node.get_children():
		_set_render_layer(child, layer_value)

func _add_light(parent: Node3D, color: Color, energy: float, rotation_value: Vector3) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.light_cull_mask = 2
	light.rotation_degrees = rotation_value
	parent.add_child(light)

func _add_material_fill(node: Node) -> void:
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		var material := (node.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		if material.albedo_texture != null:
			material.emission_enabled = true
			material.emission = material.albedo_color
			material.emission_texture = material.albedo_texture
			material.emission_energy_multiplier = 0.28
		node.material_override = material
	for child in node.get_children():
		_add_material_fill(child)
