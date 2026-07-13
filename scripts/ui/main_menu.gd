class_name ExodriftMainMenu
extends Node

signal new_run_requested
signal continue_requested
signal quit_requested

const SETTINGS_PATH := "user://exodrift_settings.cfg"
const UIStyle := preload("res://scripts/ui/ui_style.gd")

var world_root: Node3D
var camera: Camera3D
var interface: Control
var main_panel: Control
var settings_panel: Control
var credits_panel: Control
var controls_panel: Control
var confirmation_panel: Control
var continue_button: Button
var status_label: Label
var volume_slider: HSlider
var music_slider: HSlider
var sfx_slider: HSlider
var fullscreen_toggle: CheckButton
var flash_toggle: CheckButton
var quality_selector: OptionButton
var menu_buttons: Array[Button] = []
var ships: Array[Dictionary] = []
var tracers: Array[Dictionary] = []
var explosions: Array[Dictionary] = []
var elapsed: float = 0.0
var reduced_flashes: bool = false
var departing: bool = false
var can_continue_available: bool = false
var binding_buttons: Dictionary = {}
var listening_action: String = ""

func _graphics_quality() -> Node:
	return get_node_or_null("/root/GraphicsQualityManager")

func configure(can_continue: bool) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	can_continue_available = can_continue
	_load_settings()
	_build_world()
	_build_interface(can_continue)
	_apply_settings()

func _process(delta: float) -> void:
	elapsed += delta
	_update_battle(delta)

func fade_out() -> void:
	if departing:
		return
	departing = true
	for button in menu_buttons:
		button.disabled = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(interface, "modulate:a", 0.0, 0.35)
	tween.tween_property(world_root, "scale", Vector3.ONE * 1.035, 0.45)
	await tween.finished

func set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message

func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "AnimatedFleetBattle"
	add_child(world_root)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.006, 0.018, 0.045)
	sky_material.sky_horizon_color = Color(0.055, 0.17, 0.28)
	sky_material.sky_curve = 0.1
	sky_material.ground_bottom_color = Color(0.006, 0.018, 0.045)
	sky_material.ground_horizon_color = Color(0.055, 0.17, 0.28)
	sky_material.ground_curve = 0.16
	sky_material.sun_angle_max = 1.0
	sky_material.sun_curve = 0.06
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.background_energy_multiplier = 1.28
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.19, 0.3, 0.52)
	environment.ambient_light_energy = 1.05
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world_root.add_child(environment_node)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-32.0, -38.0, 0.0)
	key_light.light_color = Color(0.58, 0.74, 1.0)
	key_light.light_energy = 2.65
	world_root.add_child(key_light)
	var hostile_light := DirectionalLight3D.new()
	hostile_light.rotation_degrees = Vector3(22.0, 138.0, 0.0)
	hostile_light.light_color = Color(1.0, 0.18, 0.06)
	hostile_light.light_energy = 1.25
	world_root.add_child(hostile_light)
	var camera_fill := DirectionalLight3D.new()
	camera_fill.name = "FleetReadabilityFill"
	camera_fill.rotation_degrees = Vector3(18.0, 28.0, 0.0)
	camera_fill.light_color = Color(0.42, 0.66, 1.0)
	camera_fill.light_energy = 1.85
	world_root.add_child(camera_fill)
	_build_stars()
	_add_menu_nebula_card(Vector3(-5400.0, 1500.0, -11800.0), Vector2(7200.0, 3600.0), Color(0.08, 0.42, 0.7, 0.5))
	_add_menu_nebula_card(Vector3(5900.0, -1200.0, -13200.0), Vector2(6200.0, 3100.0), Color(0.74, 0.2, 0.055, 0.38))
	camera = Camera3D.new()
	camera.fov = 51.0
	camera.far = 30000.0
	camera.position = Vector3(35.0, 145.0, 980.0)
	camera.current = true
	world_root.add_child(camera)
	camera.look_at(Vector3(0.0, -25.0, -710.0))
	# The menu battle is composed as two readable formations instead of a loose
	# collection of ships. Sidebay owns the near-left foreground while the enemy
	# command group holds the high-right distance, leaving the center as a firing lane.
	_add_ship(&"cvn_sidebay", "Sidebay Carrier", "carrier", Vector3(-395.0, -82.0, -470.0), Color(0.26, 0.5, 0.66), Vector3(42.0, 20.0, 120.0), &"friendly", 3.2, 0.0)
	_add_ship(&"iss_resolute", "Resolute", "frigate", Vector3(-665.0, 105.0, -810.0), Color(0.28, 0.52, 0.67), Vector3(24.0, 12.0, 65.0), &"friendly", 2.5, 1.8)
	_add_ship(&"iss_harrier", "Harrier", "corvette", Vector3(-175.0, 145.0, -1010.0), Color(0.26, 0.54, 0.68), Vector3(16.0, 8.0, 42.0), &"friendly", 2.7, 2.5)
	_add_ship(&"iss_bulwark", "Bulwark", "frigate", Vector3(-720.0, -180.0, -1140.0), Color(0.3, 0.48, 0.62), Vector3(28.0, 15.0, 70.0), &"friendly", 2.6, 4.0)
	_add_ship(&"acheron_command_frigate", "Acheron Command", "command", Vector3(455.0, 48.0, -735.0), Color(0.55, 0.2, 0.08), Vector3(34.0, 18.0, 86.0), &"hostile", 2.9, 3.1)
	_add_ship(&"vesper_lance_cruiser", "Vesper Spear", "cruiser", Vector3(725.0, -120.0, -960.0), Color(0.42, 0.16, 0.58), Vector3(30.0, 15.0, 80.0), &"hostile", 2.35, 4.7)
	_add_ship(&"crucible_war_regent", "Crucible Guard", "cruiser", Vector3(220.0, -205.0, -1190.0), Color(0.29, 0.17, 0.4), Vector3(32.0, 17.0, 86.0), &"hostile", 2.35, 5.4)
	for index in 12:
		var friendly := index < 6
		var phase := float(index) * 0.57
		var origin := Vector3(-410.0 if friendly else 465.0, -25.0, -650.0 if friendly else -830.0)
		var fighter_id := (&"watcher_drone" if index % 3 == 0 else &"raptor_interceptor") if friendly else (&"crucible_talon_fighter" if index % 3 == 0 else &"acheron_interceptor")
		var fighter_role := "drone" if fighter_id == &"watcher_drone" else "fighter"
		_add_fighter(fighter_id, fighter_role, origin, Color(0.28, 0.62, 0.78) if friendly else Color(0.62, 0.2, 0.08), phase, friendly)
	_build_tracers()
	_build_explosions()

func _build_stars() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.8
	mesh.height = 3.6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.66, 0.82, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.55, 0.72, 1.0) * 1.8
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 280
	var random := RandomNumberGenerator.new()
	random.seed = 905014
	for index in multimesh.instance_count:
		var direction := Vector3(random.randf_range(-1.0, 1.0), random.randf_range(-0.65, 0.65), random.randf_range(-1.0, 0.4)).normalized()
		var transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * random.randf_range(0.4, 1.35)), direction * random.randf_range(2400.0, 7200.0))
		multimesh.set_instance_transform(index, transform)
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = multimesh
	world_root.add_child(stars)

func _add_menu_nebula_card(position_value: Vector3, size_value: Vector2, tint: Color) -> void:
	var card := MeshInstance3D.new()
	card.name = "MenuNebulaVeil"
	var mesh := QuadMesh.new()
	mesh.size = size_value
	card.mesh = mesh
	card.position = position_value
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = tint
	var nebula_texture := load("res://assets/textures/nebula_card.svg") as Texture2D
	material.albedo_texture = nebula_texture
	material.emission_enabled = true
	material.emission = Color(tint.r, tint.g, tint.b) * 0.78
	material.emission_texture = nebula_texture
	card.material_override = material
	card.add_to_group("menu_nebula_veil")
	world_root.add_child(card)

func _add_ship(ship_id: StringName, ship_name: String, role: String, base_position: Vector3, color: Color, dimensions: Vector3, faction: StringName, cinematic_scale: float, phase: float) -> void:
	var ship: CombatShip = PlayerCarrier.new() if ship_id == &"cvn_sidebay" else CombatShip.new()
	ship.name = ship_name
	world_root.add_child(ship)
	ship.configure(_menu_ship_definition(ship_id, ship_name, role, dimensions), StringName("menu_%s" % ship_id), faction, color)
	ship.set_physics_process(false)
	ship.set_process(false)
	if ship is PlayerCarrier:
		ship.velocity = -ship.global_transform.basis.z * 105.0
		(ship as PlayerCarrier)._update_engine_trails()
	ship.position = base_position
	ship.scale = Vector3.ONE * cinematic_scale
	ship.add_to_group("menu_runtime_ship")
	ships.append({"node": ship, "base": base_position, "phase": phase, "fighter": false, "friendly": faction == &"friendly", "model_id": ship_id})

func _add_fighter(ship_id: StringName, role: String, origin: Vector3, color: Color, phase: float, friendly: bool) -> void:
	var fighter := FighterCraft.new()
	fighter.name = "Menu %s" % String(ship_id).capitalize()
	world_root.add_child(fighter)
	var dimensions := Vector3(8.0, 3.0, 14.0) if role == "fighter" else Vector3(7.0, 3.2, 12.0)
	fighter.configure(_menu_ship_definition(ship_id, fighter.name, role, dimensions), StringName("menu_%s_%d" % [ship_id, ships.size()]), &"friendly" if friendly else &"hostile", color)
	fighter.set_physics_process(false)
	fighter.scale = Vector3.ONE * 1.45
	fighter.add_to_group("menu_runtime_fighter")
	ships.append({"node": fighter, "base": origin, "phase": phase, "fighter": true, "friendly": friendly, "model_id": ship_id})

func _menu_ship_definition(ship_id: StringName, display_name: String, role: String, dimensions: Vector3) -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = ship_id
	definition.display_name = display_name
	definition.role = role
	definition.dimensions_m = dimensions
	definition.damage_layers = DamageLayerDefinition.new()
	return definition

func _build_tracers() -> void:
	for index in 28:
		var tracer := Node3D.new()
		var is_missile := index % 5 == 0
		tracer.name = "MenuMissileTrail" if is_missile else "MenuFlakTracer"
		var friendly := index % 2 == 0
		var shot_color := Color(0.1, 0.78, 1.0) if friendly else Color(1.0, 0.18, 0.025)
		var head := MeshInstance3D.new()
		head.name = "Warhead" if is_missile else "FlakRound"
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 5.5 if is_missile else 2.5
		head_mesh.height = head_mesh.radius * 2.0
		head_mesh.radial_segments = 8
		head_mesh.rings = 4
		head.mesh = head_mesh
		head.material_override = _material(shot_color.lightened(0.24), 6.0)
		tracer.add_child(head)
		var streak := MeshInstance3D.new()
		streak.name = "PropellantTrail" if is_missile else "TracerStreak"
		var streak_mesh: PrimitiveMesh
		if is_missile:
			var plume_mesh := PrismMesh.new()
			plume_mesh.size = Vector3(9.0, 9.0, 105.0)
			streak_mesh = plume_mesh
		else:
			var tracer_mesh := BoxMesh.new()
			tracer_mesh.size = Vector3(2.2, 2.2, 56.0)
			streak_mesh = tracer_mesh
		streak.mesh = streak_mesh
		streak.position.z = 48.0 if is_missile else 27.0
		var trail_material := _material(shot_color, 4.4 if is_missile else 3.4)
		trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail_material.albedo_color.a = 0.48 if is_missile else 0.68
		streak.material_override = trail_material
		tracer.add_child(streak)
		if is_missile:
			var plume_light := OmniLight3D.new()
			plume_light.name = "MissilePlumeLight"
			plume_light.light_color = shot_color
			plume_light.light_energy = 1.4
			plume_light.omni_range = 42.0
			plume_light.position.z = 16.0
			tracer.add_child(plume_light)
			tracer.add_to_group("menu_missile_trail")
		else:
			tracer.add_to_group("menu_flak_tracer")
		world_root.add_child(tracer)
		tracers.append({"node": tracer, "phase": float(index) / 28.0, "friendly": friendly, "lane": index % 5, "missile": is_missile})

func _build_explosions() -> void:
	for index in 4:
		var burst := Node3D.new()
		burst.name = "MenuLayeredImpact"
		burst.add_to_group("menu_layered_explosion")
		world_root.add_child(burst)
		var core := _explosion_sphere(burst, "WhiteHotCore", 14.0, Color(1.0, 0.88, 0.5), 8.0)
		var fire_shell := _explosion_sphere(burst, "Fireball", 27.0, Color(1.0, 0.18, 0.025, 0.68), 5.0)
		var smoke := _explosion_sphere(burst, "PlasmaSmoke", 36.0, Color(0.18, 0.035, 0.018, 0.34), 0.7)
		var shockwave := MeshInstance3D.new()
		shockwave.name = "ShockwaveRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 24.0
		ring_mesh.outer_radius = 29.0
		ring_mesh.rings = 20
		ring_mesh.ring_segments = 8
		shockwave.mesh = ring_mesh
		shockwave.rotation_degrees.x = 72.0 + index * 11.0
		var ring_material := _material(Color(1.0, 0.48, 0.12, 0.7), 5.2)
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shockwave.material_override = ring_material
		burst.add_child(shockwave)
		var sparks := MultiMeshInstance3D.new()
		sparks.name = "DirectionalDebris"
		var spark_mesh := BoxMesh.new()
		spark_mesh.size = Vector3(1.4, 1.4, 18.0)
		spark_mesh.material = _material(Color(1.0, 0.52, 0.12), 5.5)
		var spark_multimesh := MultiMesh.new()
		spark_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		spark_multimesh.mesh = spark_mesh
		spark_multimesh.instance_count = 12
		for spark_index in spark_multimesh.instance_count:
			var angle := TAU * float(spark_index) / float(spark_multimesh.instance_count) + index * 0.37
			var direction := Vector3(cos(angle), sin(angle * 1.7) * 0.65, sin(angle)).normalized()
			var spark_basis := Basis.looking_at(-direction, Vector3.UP)
			spark_multimesh.set_instance_transform(spark_index, Transform3D(spark_basis, direction * 42.0))
		sparks.multimesh = spark_multimesh
		burst.add_child(sparks)
		var blast_light := OmniLight3D.new()
		blast_light.name = "BlastLight"
		blast_light.light_color = Color(1.0, 0.32, 0.055)
		blast_light.light_energy = 5.0
		blast_light.omni_range = 190.0
		burst.add_child(blast_light)
		explosions.append({"node": burst, "core": core, "fire": fire_shell, "smoke": smoke, "shockwave": shockwave, "sparks": sparks, "light": blast_light, "phase": float(index) * 2.15 - 0.15, "position": Vector3(-280.0 + index * 205.0, -90.0 + index * 55.0, -650.0 - index * 110.0)})

func _explosion_sphere(parent: Node3D, node_name: String, radius: float, color: Color, emission_energy: float) -> MeshInstance3D:
	var sphere := MeshInstance3D.new()
	sphere.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	sphere.mesh = mesh
	var material := _material(color, emission_energy)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material_override = material
	parent.add_child(sphere)
	return sphere

func _update_battle(_delta: float) -> void:
	if camera == null:
		return
	# Slow command-camera drift keeps silhouettes stable long enough to read while
	# still making the engagement feel live.
	camera.position = Vector3(35.0 + sin(elapsed * 0.055) * 68.0, 145.0 + sin(elapsed * 0.09) * 22.0, 980.0 + cos(elapsed * 0.05) * 42.0)
	camera.look_at(Vector3(sin(elapsed * 0.04) * 35.0, -25.0, -710.0))
	for ship_data in ships:
		var ship: Node3D = ship_data.node
		var base: Vector3 = ship_data.base
		var phase := float(ship_data.phase)
		if bool(ship_data.fighter):
			var friendly := bool(ship_data.friendly)
			var angle := elapsed * (0.31 if friendly else -0.35) + phase
			ship.position = base + Vector3(cos(angle) * 315.0, sin(angle * 1.7) * 118.0, sin(angle) * 390.0)
			ship.rotation = Vector3(sin(angle) * 0.22, -angle + (PI * 0.5 if friendly else -PI * 0.5), cos(angle) * 0.25)
		else:
			ship.position = base + Vector3(sin(elapsed * 0.12 + phase) * 50.0, cos(elapsed * 0.16 + phase) * 28.0, sin(elapsed * 0.09 + phase) * 36.0)
			var broadside_yaw := -0.58 if bool(ship_data.friendly) else 0.58
			ship.rotation.y = broadside_yaw + sin(elapsed * 0.07 + phase) * 0.09
	for tracer_data in tracers:
		var tracer := tracer_data.node as Node3D
		var friendly := bool(tracer_data.friendly)
		var is_missile := bool(tracer_data.missile)
		var cycle_speed := 0.18 if is_missile else (0.26 if tracer_data.lane == 0 else 0.42)
		var cycle := fposmod(elapsed * cycle_speed + float(tracer_data.phase), 1.0)
		var origin := Vector3(-590.0, -35.0 + float(tracer_data.lane) * 45.0, -520.0) if friendly else Vector3(610.0, 80.0 - float(tracer_data.lane) * 38.0, -790.0)
		var target := Vector3(610.0, 60.0, -790.0) if friendly else Vector3(-590.0, -45.0, -520.0)
		var arc_height := (150.0 if is_missile else 72.0) + float(tracer_data.lane) * 13.0
		var current_position := origin.lerp(target, cycle) + Vector3(0.0, sin(cycle * PI) * arc_height, sin(cycle * TAU + tracer_data.lane) * (34.0 if is_missile else 8.0))
		var next_cycle := minf(cycle + 0.012, 1.0)
		var next_position := origin.lerp(target, next_cycle) + Vector3(0.0, sin(next_cycle * PI) * arc_height, sin(next_cycle * TAU + tracer_data.lane) * (34.0 if is_missile else 8.0))
		tracer.position = current_position
		if not current_position.is_equal_approx(next_position):
			tracer.look_at(next_position, Vector3.UP)
		tracer.visible = cycle > 0.04 and cycle < 0.94
	for explosion_data in explosions:
		var burst := explosion_data.node as Node3D
		var pulse := fposmod(elapsed - float(explosion_data.phase), 8.6)
		burst.position = explosion_data.position
		burst.visible = pulse < 1.15
		if burst.visible:
			var flash_limit := 0.76 if reduced_flashes else 1.0
			var core_fade := clampf(1.0 - pulse / 0.34, 0.0, 1.0)
			var fire_fade := clampf(1.0 - pulse / 0.78, 0.0, 1.0)
			var smoke_fade := clampf(1.0 - pulse / 1.15, 0.0, 1.0)
			(explosion_data.core as MeshInstance3D).scale = Vector3.ONE * (0.35 + pulse * 2.8)
			(explosion_data.fire as MeshInstance3D).scale = Vector3.ONE * (0.22 + pulse * 1.9)
			(explosion_data.smoke as MeshInstance3D).scale = Vector3.ONE * (0.18 + pulse * 1.45)
			(explosion_data.shockwave as MeshInstance3D).scale = Vector3.ONE * (0.4 + pulse * 4.6)
			(explosion_data.sparks as MultiMeshInstance3D).scale = Vector3.ONE * (0.55 + pulse * 2.7)
			_set_mesh_alpha(explosion_data.core, core_fade * flash_limit)
			_set_mesh_alpha(explosion_data.fire, fire_fade * 0.76 * flash_limit)
			_set_mesh_alpha(explosion_data.smoke, smoke_fade * 0.4)
			_set_mesh_alpha(explosion_data.shockwave, fire_fade * 0.68 * flash_limit)
			(explosion_data.light as OmniLight3D).light_energy = core_fade * (2.2 if reduced_flashes else 6.2)

func _set_mesh_alpha(mesh_instance: MeshInstance3D, alpha: float) -> void:
	var material := mesh_instance.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color.a = clampf(alpha, 0.0, 1.0)

func _build_interface(can_continue: bool) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	interface = Control.new()
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(interface)
	var vignette := ColorRect.new()
	vignette.color = Color(0.002, 0.006, 0.014, 0.34)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interface.add_child(vignette)
	var top_line := ColorRect.new()
	top_line.color = Color(0.08, 0.68, 0.92, 0.75)
	top_line.position = Vector2(0, 0)
	top_line.size = Vector2(1280, 3)
	interface.add_child(top_line)
	var telemetry := _label(interface, Vector2(26, 22), Vector2(350, 56), 13)
	telemetry.text = "LIVE COMBAT FEED // HELIOS REACH\nCOMMAND LINK: STANDBY"
	var build := _label(interface, Vector2(990, 22), Vector2(260, 52), 13)
	build.text = "FLEET + ORDNANCE BUILD // M17\nSINGLE-PLAYER // PC + WEB"
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main_panel = _command_bar()
	var title := _label(main_panel, Vector2(22, 14), Vector2(218, 42), 30)
	title.text = "EXODRIFT"
	var subtitle := _label(main_panel, Vector2(23, 51), Vector2(218, 22), 11)
	subtitle.text = "CARRIER COMMAND // M17"
	var divider := ColorRect.new()
	divider.color = Color(0.08, 0.7, 0.96, 0.72)
	divider.position = Vector2(246, 14)
	divider.size = Vector2(1, 72)
	main_panel.add_child(divider)
	var new_button := _button(main_panel, "NEW OPERATION", Vector2(264, 18), Vector2(196, 46))
	new_button.pressed.connect(_request_new_run)
	continue_button = _button(main_panel, "CONTINUE", Vector2(468, 18), Vector2(172, 46))
	continue_button.disabled = not can_continue
	continue_button.tooltip_text = "No manual run save is available." if not can_continue else "Load the current manual campaign save."
	continue_button.pressed.connect(_request_continue)
	var settings_button := _button(main_panel, "SETTINGS", Vector2(648, 18), Vector2(142, 46))
	settings_button.pressed.connect(_show_settings)
	var credits_button := _button(main_panel, "CREDITS", Vector2(798, 18), Vector2(126, 46))
	credits_button.pressed.connect(_show_credits)
	var quit_button := _button(main_panel, "QUIT", Vector2(932, 18), Vector2(128, 46))
	quit_button.visible = not OS.has_feature("web")
	if OS.has_feature("web"):
		credits_button.size.x = 262.0
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	status_label = _label(main_panel, Vector2(264, 68), Vector2(796, 20), 10)
	status_label.text = "COMMAND LINK READY // SELECT AN OPERATION"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_build_settings_panel()
	_build_credits_panel()
	_build_controls_panel()
	_build_confirmation_panel()
	new_button.grab_focus()

func _command_bar() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-550, -116)
	panel.size = Vector2(1100, 98)
	var style := UIStyle.panel_style(Color(0.004, 0.017, 0.031, 0.92), UIStyle.CYAN, 1, 4)
	style.shadow_size = 14
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)
	interface.add_child(panel)
	return panel

func _menu_panel() -> Panel:
	var panel := Panel.new()
	panel.position = Vector2(420, 84)
	panel.size = Vector2(440, 552)
	var style := StyleBoxFlat.new()
	style = UIStyle.panel_style(Color(0.006, 0.022, 0.038, 0.94), UIStyle.CYAN, 2, 6)
	style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", style)
	interface.add_child(panel)
	return panel

func _build_settings_panel() -> void:
	settings_panel = _menu_panel()
	settings_panel.visible = false
	var title := _label(settings_panel, Vector2(28, 28), Vector2(384, 44), 28)
	title.text = "SYSTEM SETTINGS"
	var volume_label := _label(settings_panel, Vector2(38, 74), Vector2(364, 24), 14)
	volume_label.text = "MASTER VOLUME"
	volume_slider = HSlider.new()
	volume_slider.position = Vector2(38, 96)
	volume_slider.size = Vector2(364, 28)
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	settings_panel.add_child(volume_slider)
	var music_label := _label(settings_panel, Vector2(38, 124), Vector2(364, 24), 14)
	music_label.text = "MUSIC VOLUME"
	music_slider = HSlider.new()
	music_slider.position = Vector2(38, 146)
	music_slider.size = Vector2(364, 28)
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.05
	settings_panel.add_child(music_slider)
	var sfx_label := _label(settings_panel, Vector2(38, 174), Vector2(364, 24), 14)
	sfx_label.text = "SFX + RADIO VOLUME"
	sfx_slider = HSlider.new()
	sfx_slider.position = Vector2(38, 196)
	sfx_slider.size = Vector2(364, 28)
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	settings_panel.add_child(sfx_slider)
	var quality_label := _label(settings_panel, Vector2(38, 236), Vector2(170, 28), 14)
	quality_label.text = "GRAPHICS PROFILE"
	quality_selector = OptionButton.new()
	quality_selector.position = Vector2(218, 230)
	quality_selector.size = Vector2(184, 36)
	UIStyle.apply_option_button(quality_selector, 15)
	var graphics := _graphics_quality()
	var profile_order: Array = graphics.PROFILE_ORDER if graphics != null else [&"low", &"medium", &"high"]
	for profile_name in profile_order:
		quality_selector.add_item(String(profile_name).to_upper())
	settings_panel.add_child(quality_selector)
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "FULLSCREEN"
	fullscreen_toggle.position = Vector2(38, 274)
	fullscreen_toggle.size = Vector2(364, 38)
	UIStyle.apply_check_button(fullscreen_toggle, 16)
	settings_panel.add_child(fullscreen_toggle)
	flash_toggle = CheckButton.new()
	flash_toggle.text = "REDUCED COMBAT FLASHES"
	flash_toggle.position = Vector2(38, 314)
	flash_toggle.size = Vector2(364, 38)
	UIStyle.apply_check_button(flash_toggle, 16)
	settings_panel.add_child(flash_toggle)
	var controls := _button(settings_panel, "REMAP CONTROLS", Vector2(54, 368), Vector2(332, 42))
	controls.pressed.connect(_show_controls)
	var back := _button(settings_panel, "RETURN", Vector2(54, 430), Vector2(332, 48))
	back.pressed.connect(_show_main)
	volume_slider.value_changed.connect(_on_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	quality_selector.item_selected.connect(_on_quality_selected)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	flash_toggle.toggled.connect(_on_flash_toggled)

func _build_credits_panel() -> void:
	credits_panel = _menu_panel()
	credits_panel.visible = false
	var title := _label(credits_panel, Vector2(28, 28), Vector2(384, 44), 28)
	title.text = "CREDITS // ALPHA"
	var copy := _label(credits_panel, Vector2(38, 100), Vector2(364, 300), 16)
	copy.text = "EXODRIFT: CARRIER COMMAND\n\nDesign & Direction\nRisxhb Games\n\nEngineering & Production\nBuilt collaboratively with Codex\n\nEngine\nGodot 4\n\nAdaptive score & combat audio\nProcedurally synthesized in-engine\n\nProject Sidebay remains the internal codename."
	copy.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var back := _button(credits_panel, "RETURN", Vector2(54, 452), Vector2(332, 48))
	back.pressed.connect(_show_main)

func _build_controls_panel() -> void:
	controls_panel = _menu_panel()
	controls_panel.visible = false
	var title := _label(controls_panel, Vector2(28, 24), Vector2(384, 40), 27)
	title.text = "COMMAND BINDINGS"
	var hint := _label(controls_panel, Vector2(30, 64), Vector2(380, 36), 12)
	hint.text = "SELECT A CONTROL, THEN PRESS A KEY"
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(28, 102)
	scroll.size = Vector2(384, 338)
	controls_panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(360, 0)
	rows.add_theme_constant_override("separation", 5)
	scroll.add_child(rows)
	for action in ExodriftInputSettings.ACTION_LABELS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(360, 38)
		rows.add_child(row)
		var label := Label.new()
		label.text = String(ExodriftInputSettings.ACTION_LABELS[action]).to_upper()
		label.custom_minimum_size = Vector2(190, 38)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UIStyle.apply_label(label, 13)
		row.add_child(label)
		var binding := Button.new()
		binding.text = ExodriftInputSettings.key_label(action)
		binding.custom_minimum_size = Vector2(150, 38)
		UIStyle.apply_button(binding, 13)
		binding.pressed.connect(_begin_binding.bind(String(action)))
		row.add_child(binding)
		binding_buttons[String(action)] = binding
	var back := _button(controls_panel, "RETURN TO SETTINGS", Vector2(54, 468), Vector2(332, 48))
	back.pressed.connect(_show_settings)

func _build_confirmation_panel() -> void:
	confirmation_panel = _menu_panel()
	confirmation_panel.visible = false
	var title := _label(confirmation_panel, Vector2(34, 76), Vector2(372, 50), 26)
	title.text = "BEGIN NEW OPERATION?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var warning := _label(confirmation_panel, Vector2(48, 150), Vector2(344, 150), 15)
	warning.text = "A checkpoint already exists.\n\nStarting over replaces the current operation after preserving one automatic backup."
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var confirm := _button(confirmation_panel, "CONFIRM NEW OPERATION", Vector2(54, 336), Vector2(332, 48))
	confirm.pressed.connect(_confirm_new_run)
	var cancel := _button(confirmation_panel, "CANCEL", Vector2(54, 402), Vector2(332, 48))
	cancel.pressed.connect(_show_main)

func _show_settings() -> void:
	main_panel.visible = false
	credits_panel.visible = false
	controls_panel.visible = false
	confirmation_panel.visible = false
	settings_panel.visible = true
	volume_slider.grab_focus()

func _request_new_run() -> void:
	if departing:
		return
	if can_continue_available:
		main_panel.visible = false
		confirmation_panel.visible = true
		return
	new_run_requested.emit()

func _confirm_new_run() -> void:
	if not departing:
		new_run_requested.emit()

func _request_continue() -> void:
	if not departing:
		continue_requested.emit()

func _show_credits() -> void:
	main_panel.visible = false
	settings_panel.visible = false
	controls_panel.visible = false
	confirmation_panel.visible = false
	credits_panel.visible = true

func _show_controls() -> void:
	main_panel.visible = false
	settings_panel.visible = false
	credits_panel.visible = false
	confirmation_panel.visible = false
	controls_panel.visible = true
	for action in binding_buttons:
		binding_buttons[action].text = ExodriftInputSettings.key_label(action)
	if not binding_buttons.is_empty():
		binding_buttons.values()[0].grab_focus()

func _show_main() -> void:
	main_panel.visible = true
	settings_panel.visible = false
	credits_panel.visible = false
	controls_panel.visible = false
	confirmation_panel.visible = false
	listening_action = ""
	menu_buttons[0].grab_focus()

func _begin_binding(action: String) -> void:
	listening_action = action
	for mapped_action in binding_buttons:
		binding_buttons[mapped_action].text = ExodriftInputSettings.key_label(mapped_action)
	binding_buttons[action].text = "PRESS KEY..."

func _unhandled_input(event: InputEvent) -> void:
	if listening_action.is_empty() or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var keycode := int(key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode)
	if keycode == KEY_ESCAPE:
		binding_buttons[listening_action].text = ExodriftInputSettings.key_label(listening_action)
		listening_action = ""
		get_viewport().set_input_as_handled()
		return
	ExodriftInputSettings.rebind(listening_action, keycode)
	binding_buttons[listening_action].text = ExodriftInputSettings.key_label(listening_action)
	listening_action = ""
	_save_settings()
	get_viewport().set_input_as_handled()

func _load_settings() -> void:
	var graphics := _graphics_quality()
	if graphics != null:
		graphics.load_settings()
		reduced_flashes = bool(graphics.reduced_flashes)

func _apply_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var volume := clampf(float(config.get_value("audio", "master_volume", 0.8)), 0.0, 1.0)
	var music_volume := clampf(float(config.get_value("audio", "music_volume", 0.72)), 0.0, 1.0)
	var sfx_volume := clampf(float(config.get_value("audio", "sfx_volume", 0.85)), 0.0, 1.0)
	var fullscreen := bool(config.get_value("display", "fullscreen", false))
	volume_slider.set_value_no_signal(volume)
	music_slider.set_value_no_signal(music_volume)
	sfx_slider.set_value_no_signal(sfx_volume)
	ExodriftInputSettings.load_bindings(config)
	var graphics := _graphics_quality()
	quality_selector.select(graphics.profile_index() if graphics != null else (1 if OS.has_feature("web") else 2))
	fullscreen_toggle.set_pressed_no_signal(fullscreen)
	flash_toggle.set_pressed_no_signal(reduced_flashes)
	_set_bus_volume("Master", volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "master_volume", volume_slider.value)
	config.set_value("audio", "music_volume", music_slider.value)
	config.set_value("audio", "sfx_volume", sfx_slider.value)
	config.set_value("display", "fullscreen", fullscreen_toggle.button_pressed)
	var graphics := _graphics_quality()
	config.set_value("display", "graphics_quality", String(graphics.current_quality) if graphics != null else ("medium" if OS.has_feature("web") else "high"))
	config.set_value("accessibility", "reduced_flashes", flash_toggle.button_pressed)
	ExodriftInputSettings.save_bindings(config)
	config.save(SETTINGS_PATH)

func _on_volume_changed(value: float) -> void:
	_set_bus_volume("Master", value)
	_save_settings()

func _on_music_volume_changed(value: float) -> void:
	_set_bus_volume("Music", value)
	_save_settings()

func _on_sfx_volume_changed(value: float) -> void:
	_set_bus_volume("SFX", value)
	_save_settings()

func _set_bus_volume(bus_name: String, value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value, 0.001)))

func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()

func _on_quality_selected(index: int) -> void:
	var graphics := _graphics_quality()
	if graphics == null or index < 0 or index >= graphics.PROFILE_ORDER.size():
		return
	graphics.set_quality(graphics.PROFILE_ORDER[index])
	_save_settings()

func _on_flash_toggled(enabled: bool) -> void:
	reduced_flashes = enabled
	var graphics := _graphics_quality()
	if graphics != null:
		graphics.set_reduced_flashes(enabled)
	_save_settings()

func _material(color: Color, emission_energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.62
	material.roughness = 0.38
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color * emission_energy
	return material

func _label(parent: Control, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size)
	parent.add_child(label)
	return label

func _button(parent: Control, text_value: String, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	UIStyle.apply_button(button, 15)
	parent.add_child(button)
	menu_buttons.append(button)
	return button
