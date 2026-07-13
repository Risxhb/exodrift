extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in 12:
		await process_frame
	for hostile in get_nodes_in_group("team_hostile"):
		if hostile is CombatShip:
			hostile.ai_enabled = false
	scene.sensors.emit_active_ping()
	for wing in [scene.interceptor, scene.scout]:
		wing.definition.launch_interval_seconds = 0.03
		for craft in wing.crafts:
			craft.definition.maximum_speed_mps = 1700.0
			craft.definition.acceleration_mps2 = 2600.0
	scene.interceptor.request_launch()
	scene.scout.request_launch()
	for _frame in 70:
		await physics_frame
	var formation_index := 0
	for wing in [scene.interceptor, scene.scout]:
		for craft in wing.crafts:
			if not is_instance_valid(craft) or not craft.deployed:
				continue
			var side := -1.0 if formation_index % 2 == 0 else 1.0
			var rank := formation_index / 2
			craft.global_position = scene.carrier.global_position + Vector3(side * (95.0 + rank * 48.0), 38.0 + rank * 18.0, -230.0 - rank * 95.0)
			craft.set_physics_process(false)
			formation_index += 1
	var screen_center := scene.get_viewport().get_visible_rect().size * 0.5
	scene.carrier.begin_flak_placement(screen_center)
	for _frame in 14:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var placement_image := await _capture_best_frame(5)
	if placement_image != null:
		placement_image.save_png(ProjectSettings.globalize_path("res://build/flak-placement-preview.png"))
	scene.carrier.confirm_flak_placement()
	scene.carrier.flak_cooldown = 0.0
	scene.carrier.missile_cooldown = 0.0
	scene.carrier.fire_missile(scene.hostile_command)
	scene.carrier.fire_nuclear(scene.hostile_command)
	var vfx := root.get_node_or_null("CombatVFX")
	if vfx != null:
		for index in 7:
			var side := -1.0 if index % 2 == 0 else 1.0
			vfx.spawn_damage_effect(scene.carrier.global_position + Vector3(side * (110.0 + index * 24.0), 35.0 + index * 16.0, -620.0 - index * 170.0), false, 0.75 + index * 0.05)
		vfx.spawn_ship_explosion(scene.carrier.global_position + Vector3(470.0, 110.0, -2350.0), 1.15)
	for _frame in 46:
		await physics_frame
	scene.sensors.emit_active_ping()
	var command_contact: SensorContact = scene.sensors.get_contact(&"hostile_command")
	scene.hud.update_target(command_contact, scene.hostile_command.display_name, scene.hostile_command)
	var flight_image := await _capture_best_frame(8)
	if flight_image == null:
		push_error("Rendering backend did not provide a viewport texture")
		quit(2)
		return
	flight_image.save_png(ProjectSettings.globalize_path("res://build/flight-preview-1280.png"))
	root.size = Vector2i(1920, 1080)
	for _frame in 8:
		await process_frame
	var flight_1080 := await _capture_best_frame(8)
	flight_1080.save_png(ProjectSettings.globalize_path("res://build/flight-preview-1080.png"))
	flight_1080.save_png(ProjectSettings.globalize_path("res://build/flight-preview.png"))
	root.size = Vector2i(2560, 1440)
	for _frame in 8:
		await process_frame
	var flight_1440 := await _capture_best_frame(8)
	flight_1440.save_png(ProjectSettings.globalize_path("res://build/flight-preview-1440.png"))
	root.size = Vector2i(1920, 1080)
	for _frame in 4:
		await process_frame
	scene.carrier.request_bays_closed()
	for _frame in 160:
		await physics_frame
	var sealed_image := await _capture_best_frame(6)
	sealed_image.save_png(ProjectSettings.globalize_path("res://build/carrier-bays-sealed-preview-1080.png"))
	scene.tactical.set_enabled(true)
	for _frame in 12:
		await process_frame
	var tactical_image := await _capture_best_frame(6)
	tactical_image.save_png(ProjectSettings.globalize_path("res://build/tactical-preview-1080.png"))
	root.size = Vector2i(2560, 1440)
	for _frame in 8:
		await process_frame
	var tactical_1440 := await _capture_best_frame(6)
	tactical_1440.save_png(ProjectSettings.globalize_path("res://build/tactical-preview-1440.png"))
	scene.tactical.select_commandable(scene.carrier)
	scene.hud.open_target_context_menu(Vector2(1780.0, 330.0), &"hostile_command")
	for _frame in 3:
		await process_frame
	var context_1440 := await _capture_best_frame(4)
	context_1440.save_png(ProjectSettings.globalize_path("res://build/tactical-context-preview-1440.png"))
	quit(0)

func _capture_best_frame(sample_count: int) -> Image:
	var best_image: Image
	var best_size := -1
	for _sample in sample_count:
		await process_frame
		await RenderingServer.frame_post_draw
		var candidate := root.get_texture().get_image()
		if candidate == null:
			continue
		var encoded_size := candidate.save_png_to_buffer().size()
		if encoded_size > best_size:
			best_size = encoded_size
			best_image = candidate.duplicate() as Image
	return best_image
