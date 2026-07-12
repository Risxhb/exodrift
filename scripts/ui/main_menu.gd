class_name ExodriftMainMenu
extends Node

signal new_run_requested
signal continue_requested
signal quit_requested

const SETTINGS_PATH := "user://exodrift_settings.cfg"

var world_root: Node3D
var camera: Camera3D
var interface: Control
var main_panel: Control
var settings_panel: Control
var credits_panel: Control
var continue_button: Button
var status_label: Label
var volume_slider: HSlider
var fullscreen_toggle: CheckButton
var flash_toggle: CheckButton
var menu_buttons: Array[Button] = []
var ships: Array[Dictionary] = []
var tracers: Array[Dictionary] = []
var explosions: Array[Dictionary] = []
var elapsed: float = 0.0
var reduced_flashes: bool = false
var departing: bool = false

func configure(can_continue: bool) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.004, 0.009, 0.028)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.2, 0.36)
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world_root.add_child(environment_node)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-32.0, -38.0, 0.0)
	key_light.light_color = Color(0.58, 0.74, 1.0)
	key_light.light_energy = 1.7
	world_root.add_child(key_light)
	var hostile_light := DirectionalLight3D.new()
	hostile_light.rotation_degrees = Vector3(22.0, 138.0, 0.0)
	hostile_light.light_color = Color(1.0, 0.18, 0.06)
	hostile_light.light_energy = 0.65
	world_root.add_child(hostile_light)
	_build_stars()
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.position = Vector3(0.0, 180.0, 1050.0)
	camera.current = true
	world_root.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -650.0))
	_add_ship("Sidebay Carrier", Vector3(-590.0, -50.0, -520.0), Color(0.12, 0.48, 0.72), Vector3(190.0, 48.0, 520.0), true, 0.0)
	_add_ship("Resolute", Vector3(-830.0, 155.0, -980.0), Color(0.15, 0.58, 0.8), Vector3(78.0, 30.0, 220.0), false, 1.8)
	_add_ship("Acheron Command", Vector3(610.0, 75.0, -790.0), Color(0.7, 0.08, 0.04), Vector3(126.0, 42.0, 320.0), false, 3.1)
	_add_ship("Acheron Screen", Vector3(845.0, -175.0, -430.0), Color(0.82, 0.12, 0.035), Vector3(68.0, 27.0, 185.0), false, 4.7)
	for index in 8:
		var friendly := index < 4
		var phase := float(index) * 0.78
		var origin := Vector3(-560.0 if friendly else 590.0, -20.0, -610.0 if friendly else -820.0)
		_add_fighter(origin, Color(0.2, 0.76, 1.0) if friendly else Color(1.0, 0.2, 0.04), phase, friendly)
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

func _add_ship(ship_name: String, base_position: Vector3, color: Color, dimensions: Vector3, carrier: bool, phase: float) -> void:
	var ship := Node3D.new()
	ship.name = ship_name
	world_root.add_child(ship)
	ship.position = base_position
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = dimensions
	hull.mesh = hull_mesh
	hull.material_override = _material(color, 0.12)
	ship.add_child(hull)
	var nose := MeshInstance3D.new()
	var nose_mesh := PrismMesh.new()
	nose_mesh.size = Vector3(dimensions.x * 0.74, dimensions.y * 0.72, dimensions.z * 0.32)
	nose.mesh = nose_mesh
	nose.position.z = -dimensions.z * 0.62
	nose.rotation.y = PI
	nose.material_override = _material(color.lightened(0.18), 0.05)
	ship.add_child(nose)
	if carrier:
		for side in [-1.0, 1.0]:
			var bay := MeshInstance3D.new()
			var bay_mesh := BoxMesh.new()
			bay_mesh.size = Vector3(34.0, 20.0, 210.0)
			bay.mesh = bay_mesh
			bay.position = Vector3(side * (dimensions.x * 0.62), 0.0, 18.0)
			bay.material_override = _material(Color(0.06, 0.22, 0.32), 0.1)
			ship.add_child(bay)
			var gallery := MeshInstance3D.new()
			var gallery_mesh := BoxMesh.new()
			gallery_mesh.size = Vector3(3.0, 12.0, 156.0)
			gallery.mesh = gallery_mesh
			gallery.position = Vector3(side * (dimensions.x * 0.75), 0.0, 12.0)
			gallery.material_override = _material(Color(0.05, 0.8, 1.0), 3.2)
			ship.add_child(gallery)
	var engine := MeshInstance3D.new()
	var engine_mesh := BoxMesh.new()
	engine_mesh.size = Vector3(dimensions.x * 0.56, dimensions.y * 0.38, 5.0)
	engine.mesh = engine_mesh
	engine.position.z = dimensions.z * 0.52
	engine.material_override = _material(Color(0.08, 0.62, 1.0) if color.b > color.r else Color(1.0, 0.16, 0.025), 4.0)
	ship.add_child(engine)
	ships.append({"node": ship, "base": base_position, "phase": phase, "fighter": false, "friendly": color.b > color.r})

func _add_fighter(origin: Vector3, color: Color, phase: float, friendly: bool) -> void:
	var fighter := Node3D.new()
	world_root.add_child(fighter)
	var body := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(13.0, 5.0, 28.0)
	body.mesh = mesh
	body.rotation.y = PI
	body.material_override = _material(color, 0.3)
	fighter.add_child(body)
	ships.append({"node": fighter, "base": origin, "phase": phase, "fighter": true, "friendly": friendly})

func _build_tracers() -> void:
	for index in 22:
		var tracer := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 3.4 if index % 5 else 6.0
		mesh.height = mesh.radius * 2.0
		tracer.mesh = mesh
		var friendly := index % 2 == 0
		tracer.material_override = _material(Color(0.08, 0.78, 1.0) if friendly else Color(1.0, 0.16, 0.025), 5.0)
		world_root.add_child(tracer)
		tracers.append({"node": tracer, "phase": float(index) / 22.0, "friendly": friendly, "lane": index % 5})

func _build_explosions() -> void:
	for index in 4:
		var burst := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 26.0
		mesh.height = 52.0
		burst.mesh = mesh
		burst.material_override = _material(Color(1.0, 0.26, 0.035), 4.5)
		world_root.add_child(burst)
		explosions.append({"node": burst, "phase": float(index) * 2.15 + 0.7, "position": Vector3(-280.0 + index * 205.0, -90.0 + index * 55.0, -650.0 - index * 110.0)})

func _update_battle(_delta: float) -> void:
	if camera == null:
		return
	camera.position = Vector3(sin(elapsed * 0.08) * 115.0, 175.0 + sin(elapsed * 0.13) * 35.0, 1050.0 + cos(elapsed * 0.07) * 90.0)
	camera.look_at(Vector3(0.0, -20.0, -650.0))
	for ship_data in ships:
		var ship: Node3D = ship_data.node
		var base: Vector3 = ship_data.base
		var phase := float(ship_data.phase)
		if bool(ship_data.fighter):
			var friendly := bool(ship_data.friendly)
			var angle := elapsed * (0.38 if friendly else -0.43) + phase
			ship.position = base + Vector3(cos(angle) * 420.0, sin(angle * 1.7) * 145.0, sin(angle) * 520.0)
			ship.rotation = Vector3(sin(angle) * 0.22, -angle + (PI * 0.5 if friendly else -PI * 0.5), cos(angle) * 0.25)
		else:
			ship.position = base + Vector3(sin(elapsed * 0.12 + phase) * 50.0, cos(elapsed * 0.16 + phase) * 28.0, sin(elapsed * 0.09 + phase) * 36.0)
			var broadside_yaw := -0.72 if bool(ship_data.friendly) else 0.72
			ship.rotation.y = broadside_yaw + sin(elapsed * 0.08 + phase) * 0.14
	for tracer_data in tracers:
		var tracer: Node3D = tracer_data.node
		var friendly := bool(tracer_data.friendly)
		var cycle := fposmod(elapsed * (0.22 if tracer_data.lane == 0 else 0.34) + float(tracer_data.phase), 1.0)
		var origin := Vector3(-590.0, -35.0 + float(tracer_data.lane) * 45.0, -520.0) if friendly else Vector3(610.0, 80.0 - float(tracer_data.lane) * 38.0, -790.0)
		var target := Vector3(610.0, 60.0, -790.0) if friendly else Vector3(-590.0, -45.0, -520.0)
		tracer.position = origin.lerp(target, cycle) + Vector3(0.0, sin(cycle * PI) * (90.0 + tracer_data.lane * 12.0), 0.0)
		tracer.visible = cycle > 0.04 and cycle < 0.94
	for explosion_data in explosions:
		var burst: MeshInstance3D = explosion_data.node
		var pulse := fposmod(elapsed - float(explosion_data.phase), 8.6)
		burst.position = explosion_data.position
		burst.visible = pulse < 0.75
		if burst.visible:
			var intensity := sin(pulse / 0.75 * PI)
			burst.scale = Vector3.ONE * (0.25 + intensity * (1.15 if reduced_flashes else 1.8))

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
	build.text = "DEVELOPMENT BUILD // M10\nSINGLE-PLAYER // PC + WEB"
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main_panel = _menu_panel()
	var title := _label(main_panel, Vector2(24, 22), Vector2(392, 58), 42)
	title.text = "EXODRIFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label(main_panel, Vector2(24, 76), Vector2(392, 30), 16)
	subtitle.text = "C A R R I E R   C O M M A N D"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var divider := ColorRect.new()
	divider.color = Color(0.08, 0.7, 0.96, 0.8)
	divider.position = Vector2(86, 116)
	divider.size = Vector2(268, 2)
	main_panel.add_child(divider)
	var doctrine := _label(main_panel, Vector2(24, 128), Vector2(392, 44), 13)
	doctrine.text = "PILOT THE FLAGSHIP. COMMAND THE FLEET."
	doctrine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var new_button := _button(main_panel, "BEGIN NEW OPERATION", Vector2(54, 188), Vector2(332, 48))
	new_button.pressed.connect(_request_new_run)
	continue_button = _button(main_panel, "CONTINUE SAVED RUN", Vector2(54, 246), Vector2(332, 48))
	continue_button.disabled = not can_continue
	continue_button.tooltip_text = "No manual run save is available." if not can_continue else "Load the current manual campaign save."
	continue_button.pressed.connect(_request_continue)
	var settings_button := _button(main_panel, "SETTINGS", Vector2(54, 304), Vector2(332, 48))
	settings_button.pressed.connect(_show_settings)
	var credits_button := _button(main_panel, "CREDITS", Vector2(54, 362), Vector2(332, 48))
	credits_button.pressed.connect(_show_credits)
	var quit_button := _button(main_panel, "QUIT TO DESKTOP", Vector2(54, 420), Vector2(332, 48))
	quit_button.visible = not OS.has_feature("web")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	status_label = _label(main_panel, Vector2(28, 482), Vector2(384, 40), 12)
	status_label.text = "SELECT A COMMAND OPTION"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_settings_panel()
	_build_credits_panel()
	new_button.grab_focus()

func _menu_panel() -> Panel:
	var panel := Panel.new()
	panel.position = Vector2(420, 84)
	panel.size = Vector2(440, 552)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.022, 0.04, 0.91)
	style.border_color = Color(0.1, 0.62, 0.86, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", style)
	interface.add_child(panel)
	return panel

func _build_settings_panel() -> void:
	settings_panel = _menu_panel()
	settings_panel.visible = false
	var title := _label(settings_panel, Vector2(28, 28), Vector2(384, 44), 28)
	title.text = "SYSTEM SETTINGS"
	var volume_label := _label(settings_panel, Vector2(38, 112), Vector2(364, 28), 16)
	volume_label.text = "MASTER VOLUME"
	volume_slider = HSlider.new()
	volume_slider.position = Vector2(38, 150)
	volume_slider.size = Vector2(364, 34)
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	settings_panel.add_child(volume_slider)
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "FULLSCREEN"
	fullscreen_toggle.position = Vector2(38, 220)
	fullscreen_toggle.size = Vector2(364, 44)
	fullscreen_toggle.add_theme_font_size_override("font_size", 16)
	settings_panel.add_child(fullscreen_toggle)
	flash_toggle = CheckButton.new()
	flash_toggle.text = "REDUCED COMBAT FLASHES"
	flash_toggle.position = Vector2(38, 278)
	flash_toggle.size = Vector2(364, 44)
	flash_toggle.add_theme_font_size_override("font_size", 16)
	settings_panel.add_child(flash_toggle)
	var note := _label(settings_panel, Vector2(38, 348), Vector2(364, 58), 13)
	note.text = "Settings are saved locally and apply immediately. Fullscreen may require browser permission."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var back := _button(settings_panel, "RETURN", Vector2(54, 452), Vector2(332, 48))
	back.pressed.connect(_show_main)
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	flash_toggle.toggled.connect(_on_flash_toggled)

func _build_credits_panel() -> void:
	credits_panel = _menu_panel()
	credits_panel.visible = false
	var title := _label(credits_panel, Vector2(28, 28), Vector2(384, 44), 28)
	title.text = "CREDITS // ALPHA"
	var copy := _label(credits_panel, Vector2(38, 100), Vector2(364, 300), 16)
	copy.text = "EXODRIFT: CARRIER COMMAND\n\nDesign & Direction\nRisxhb Games\n\nEngineering & Production\nBuilt collaboratively with Codex\n\nEngine\nGodot 4\n\nMusic & final art\nIn development\n\nProject Sidebay remains the internal codename."
	copy.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var back := _button(credits_panel, "RETURN", Vector2(54, 452), Vector2(332, 48))
	back.pressed.connect(_show_main)

func _show_settings() -> void:
	main_panel.visible = false
	credits_panel.visible = false
	settings_panel.visible = true
	volume_slider.grab_focus()

func _request_new_run() -> void:
	if not departing:
		new_run_requested.emit()

func _request_continue() -> void:
	if not departing:
		continue_requested.emit()

func _show_credits() -> void:
	main_panel.visible = false
	settings_panel.visible = false
	credits_panel.visible = true

func _show_main() -> void:
	main_panel.visible = true
	settings_panel.visible = false
	credits_panel.visible = false
	menu_buttons[0].grab_focus()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	reduced_flashes = bool(config.get_value("accessibility", "reduced_flashes", false))

func _apply_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var volume := clampf(float(config.get_value("audio", "master_volume", 0.8)), 0.0, 1.0)
	var fullscreen := bool(config.get_value("display", "fullscreen", false))
	volume_slider.set_value_no_signal(volume)
	fullscreen_toggle.set_pressed_no_signal(fullscreen)
	flash_toggle.set_pressed_no_signal(reduced_flashes)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(volume, 0.001)))
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", volume_slider.value)
	config.set_value("display", "fullscreen", fullscreen_toggle.button_pressed)
	config.set_value("accessibility", "reduced_flashes", flash_toggle.button_pressed)
	config.save(SETTINGS_PATH)

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(value, 0.001)))
	_save_settings()

func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()

func _on_flash_toggled(enabled: bool) -> void:
	reduced_flashes = enabled
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
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.76, 0.92, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label

func _button(parent: Control, text_value: String, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	button.add_theme_font_size_override("font_size", 15)
	parent.add_child(button)
	menu_buttons.append(button)
	return button
