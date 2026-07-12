extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in 12:
		await process_frame
	for hostile in get_nodes_in_group("team_hostile"):
		if hostile is CombatShip:
			hostile.ai_enabled = false
	scene.sensors.emit_active_ping()
	scene.interceptor.request_launch()
	scene.scout.request_launch()
	for _burst in 3:
		scene.carrier.flak_cooldown = 0.0
		scene.carrier.fire_flak()
		for _frame in 3:
			await process_frame
	scene.carrier.missile_cooldown = 0.0
	scene.carrier.fire_missile(scene.hostile_command)
	for _frame in 12:
		await process_frame
	scene.set_process(false)
	var command_contact: SensorContact = scene.sensors.get_contact(&"hostile_command")
	scene.hud.update_target(command_contact, scene.hostile_command.display_name, scene.hostile_command)
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var flight_image := root.get_texture().get_image()
	if flight_image == null:
		push_error("Rendering backend did not provide a viewport texture")
		quit(2)
		return
	flight_image.save_png(ProjectSettings.globalize_path("res://build/flight-preview.png"))
	scene.carrier.request_bays_closed()
	for _frame in 160:
		await physics_frame
	var sealed_image := root.get_texture().get_image()
	sealed_image.save_png(ProjectSettings.globalize_path("res://build/carrier-bays-sealed-preview.png"))
	scene.tactical.set_enabled(true)
	for _frame in 12:
		await process_frame
	var tactical_image := root.get_texture().get_image()
	tactical_image.save_png(ProjectSettings.globalize_path("res://build/tactical-preview.png"))
	quit(0)
