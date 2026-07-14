extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(2560, 1440)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in 20:
		await process_frame
	var operations := scene.carrier.carrier_operations as CarrierOperationsState
	operations.set_power_preset(&"recovery")
	operations.subsystem_condition.command_cic = 0.15
	operations.subsystem_condition.propulsion = 0.58
	operations.create_hazard(&"command_cic", &"fire", 0.9)
	operations.create_hazard(&"propulsion", &"breach", 0.65)
	operations.stores.flak_rounds = 1460
	operations.stores.guided_missiles = 11
	operations.stores.aviation_ordnance = 74
	operations.stores.craft_refuel = 7
	scene.carrier_operations_console.open_console()
	for _frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png(ProjectSettings.globalize_path("res://build/carrier-operations-1440.png"))
	quit(0 if error == OK else 3)
