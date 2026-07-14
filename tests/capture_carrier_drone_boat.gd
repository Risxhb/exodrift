extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	ExodriftSpaceSky.apply_to_environment(environment, &"acheron")
	environment.background_energy_multiplier = 0.3
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.34, 0.48)
	environment.ambient_light_energy = 1.4
	world_environment.environment = environment
	stage.add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.light_energy = 2.2
	key_light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	stage.add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.light_color = Color(0.2, 0.58, 1.0)
	fill_light.light_energy = 7.0
	fill_light.omni_range = 480.0
	fill_light.position = Vector3(-150.0, 90.0, 110.0)
	stage.add_child(fill_light)
	var carrier := PlayerCarrier.new()
	stage.add_child(carrier)
	carrier.configure(_carrier_definition(), &"preview_carrier", &"friendly", Color(0.18, 0.38, 0.58))
	carrier.set_physics_process(false)
	carrier.rotation_degrees = Vector3(-4.0, -28.0, 0.0)
	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(190.0, 82.0, 265.0)
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 4.0, 0.0), Vector3.UP)
	camera.current = true
	for _frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png(ProjectSettings.globalize_path("res://build/carrier-drone-boat-preview.png"))
	quit(0 if error == OK else 3)

func _carrier_definition() -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"cvn_sidebay"
	definition.display_name = "CVN Sidebay"
	definition.role = "carrier"
	definition.dimensions_m = Vector3(76.0, 32.0, 220.0)
	definition.maximum_speed_mps = 260.0
	definition.acceleration_mps2 = 14.0
	definition.rotation_speed_radians = 0.3
	definition.damage_layers = DamageLayerDefinition.new()
	return definition
