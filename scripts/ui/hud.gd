class_name SidebayHUD
extends CanvasLayer

const RadarDisplay := preload("res://scripts/ui/radar_display.gd")

var carrier: PlayerCarrier
var interceptor: SidebaySquadron
var scout: SidebaySquadron
var sensors: SidebaySensorSystem
var tactical: TacticalController
var status_label: Label
var wing_label: Label
var weapon_label: Label
var target_label: Label
var target_panel: ColorRect
var target_indicator: Label
var target_shield_bar: ProgressBar
var target_armor_bar: ProgressBar
var target_hull_bar: ProgressBar
var locked_target: CombatShip
var objective_label: Label
var notification_label: Label
var mode_label: Label
var controls_label: Label
var crosshair_label: Label
var map_info_label: Label
var result_panel: ColorRect
var result_label: Label
var pause_panel: ColorRect
var shield_bar: ProgressBar
var armor_bar: ProgressBar
var hull_bar: ProgressBar
var notification_time: float = 0.0
var radar

func configure(
	player_carrier: PlayerCarrier,
	interceptor_wing: SidebaySquadron,
	scout_wing: SidebaySquadron,
	sensor_system: SidebaySensorSystem,
	tactical_controller: TacticalController
) -> void:
	layer = 10
	carrier = player_carrier
	interceptor = interceptor_wing
	scout = scout_wing
	sensors = sensor_system
	tactical = tactical_controller
	_build_ui()

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	objective_label = _label(root, Vector2(24, 18), Vector2(700, 34), 20)
	objective_label.text = "OBJECTIVE  Identify and destroy the hostile command frigate"
	status_label = _label(root, Vector2(24, 58), Vector2(430, 92), 16)
	wing_label = _label(root, Vector2(24, 166), Vector2(520, 130), 15)
	weapon_label = _label(root, Vector2(24, 292), Vector2(560, 62), 14)
	target_panel = _panel(root, Vector2(905, 18), Vector2(350, 176), Color(0.012, 0.035, 0.055, 0.92))
	var portrait_back := _panel(target_panel, Vector2(12, 12), Vector2(92, 92), Color(0.025, 0.09, 0.13, 0.95))
	var portrait := Polygon2D.new()
	portrait.polygon = PackedVector2Array([Vector2(46, 7), Vector2(62, 30), Vector2(83, 44), Vector2(67, 55), Vector2(61, 82), Vector2(31, 82), Vector2(25, 55), Vector2(9, 44), Vector2(30, 30)])
	portrait.color = Color(0.35, 0.78, 0.95, 0.92)
	portrait_back.add_child(portrait)
	target_label = _label(target_panel, Vector2(116, 12), Vector2(220, 92), 14)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	target_shield_bar = _bar(target_panel, Vector2(12, 116), Vector2(326, 10), Color(0.1, 0.65, 1.0))
	target_armor_bar = _bar(target_panel, Vector2(12, 134), Vector2(326, 10), Color(0.95, 0.65, 0.12))
	target_hull_bar = _bar(target_panel, Vector2(12, 152), Vector2(326, 10), Color(0.9, 0.15, 0.12))
	target_indicator = _label(root, Vector2(624, 300), Vector2(38, 38), 30)
	target_indicator.text = "▲"
	target_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_indicator.add_theme_color_override("font_color", Color(0.25, 0.92, 1.0))
	target_indicator.pivot_offset = Vector2(19, 19)
	target_indicator.visible = false
	mode_label = _label(root, Vector2(470, 20), Vector2(340, 48), 26)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label = _label(root, Vector2(340, 610), Vector2(600, 36), 18)
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label = _label(root, Vector2(18, 660), Vector2(1240, 46), 14)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.text = "WASD thrust  Space/C vertical  Shift boost  Ctrl brake  LMB flak  RMB missile  P ping  Z/X wings  Tab tactical map  Esc pause"
	crosshair_label = _label(root, Vector2(624, 340), Vector2(32, 32), 24)
	crosshair_label.text = ""
	crosshair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair_label.visible = false
	map_info_label = _label(root, Vector2(24, 70), Vector2(440, 170), 17)
	map_info_label.visible = false
	shield_bar = _bar(root, Vector2(24, 136), Vector2(132, 12), Color(0.1, 0.65, 1.0))
	armor_bar = _bar(root, Vector2(164, 136), Vector2(132, 12), Color(0.95, 0.65, 0.12))
	hull_bar = _bar(root, Vector2(304, 136), Vector2(132, 12), Color(0.9, 0.15, 0.12))
	var radar_panel := _panel(root, Vector2(1025, 432), Vector2(230, 220), Color(0.008, 0.035, 0.052, 0.9))
	var radar_title := _label(radar_panel, Vector2(12, 8), Vector2(206, 24), 13)
	radar_title.text = "TACTICAL RADAR // ACTIVE"
	radar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radar = RadarDisplay.new()
	radar.position = Vector2(20, 26)
	radar.size = Vector2(190, 190)
	radar_panel.add_child(radar)
	radar.configure(carrier, sensors)
	result_panel = _panel(root, Vector2(340, 230), Vector2(600, 250), Color(0.01, 0.025, 0.05, 0.94))
	result_label = _label(result_panel, Vector2(25, 55), Vector2(550, 150), 30)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.visible = false
	pause_panel = _panel(root, Vector2(390, 210), Vector2(500, 300), Color(0.01, 0.025, 0.05, 0.96))
	var pause_title := _label(pause_panel, Vector2(20, 22), Vector2(460, 45), 28)
	pause_title.text = "PAUSED / SETTINGS"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pause_copy := _label(pause_panel, Vector2(40, 90), Vector2(420, 160), 18)
	pause_copy.text = "Esc — resume\n\nMouse sensitivity: %.4f\nMiddle-drag: orbit combat camera\nMouse wheel: camera zoom\nVertical battlespace: ±1,400 m\n\nEnter — restart encounter" % carrier.mouse_sensitivity
	pause_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_panel.visible = false

func _process(delta: float) -> void:
	if not is_instance_valid(carrier):
		return
	var layers := carrier.layer_percentages()
	shield_bar.value = layers.x * 100.0
	armor_bar.value = layers.y * 100.0
	hull_bar.value = layers.z * 100.0
	status_label.text = "%s  SPD %4.0f m/s\nSHIELD %3.0f%%   ARMOR %3.0f%%   HULL %3.0f%%\nBAYS %s   CONTACTS %d" % [carrier.display_name.to_upper(), carrier.velocity.length(), layers.x * 100.0, layers.y * 100.0, layers.z * 100.0, carrier.bay_status(), sensors.contacts.size()]
	wing_label.text = "[Z] %s  %s  craft %d  ammo %d  end %.0fs\n[X] %s  %s  craft %d  ammo %d  end %.0fs" % [
		interceptor.display_name, interceptor.operation.label(), interceptor.living_craft_count(), interceptor.total_ammunition(), interceptor.average_endurance(),
		scout.display_name, scout.operation.label(), scout.living_craft_count(), scout.total_ammunition(), scout.average_endurance()
	]
	var flak_status := "READY" if carrier.flak_cooldown <= 0.0 else "CYCLING %.1fs" % carrier.flak_cooldown
	var missile_status := "READY" if carrier.missile_cooldown <= 0.0 else "RELOAD %.1fs" % carrier.missile_cooldown
	weapon_label.text = "FLAK CURTAIN  %s  //  %d rounds\nMISSILE SALVO  %s  //  %d weapons  %.1f km" % [flak_status, carrier.flak_burst_count, missile_status, carrier.missile_salvo_count, carrier.missile_weapon.range_m / 1000.0]
	mode_label.text = "TACTICAL MAP — LIVE" if tactical.enabled else ""
	_update_target_presentation()
	if tactical.enabled:
		status_label.visible = false
		wing_label.visible = false
		weapon_label.visible = false
		shield_bar.visible = false
		armor_bar.visible = false
		hull_bar.visible = false
		crosshair_label.visible = false
		objective_label.visible = false
		map_info_label.visible = true
		map_info_label.text = _map_information()
		controls_label.text = "1–4 groups  LMB select  RMB move/attack  I intercept  E escort  Shift queue  Q stance  F form  R recall  H hold  X withdraw  V jump prep  MMB orbit  Wheel zoom"
	else:
		status_label.visible = true
		wing_label.visible = true
		weapon_label.visible = true
		shield_bar.visible = true
		armor_bar.visible = true
		hull_bar.visible = true
		crosshair_label.visible = false
		objective_label.visible = true
		map_info_label.visible = false
		controls_label.text = ("Cursor steer  " if OS.has_feature("web") else "Mouse steer  ") + "WASD thrust  Space/C vertical  Wheel zoom  Shift boost  Ctrl brake  LMB flak barrage  RMB missile salvo  P ping  Z/X wings  V jump prep  Tab map  Esc pause"
	if notification_time > 0.0:
		notification_time -= delta
		if notification_time <= 0.0:
			notification_label.text = ""

func notify(message: String) -> void:
	notification_label.text = message
	notification_time = 3.5

func set_objective(message: String) -> void:
	objective_label.text = "OBJECTIVE  %s" % message

func _map_information() -> String:
	var selected_name := "None"
	var link_name := "Local"
	var stance_name := "—"
	var formation := "—"
	if tactical.selected != null:
		selected_name = tactical.selected.display_name if "display_name" in tactical.selected else tactical.selected.name
		if "command_link" in tactical.selected:
			link_name = tactical.selected.command_link.label()
		if "stance" in tactical.selected:
			stance_name = String(tactical.selected.stance).capitalize()
		if "formation_name" in tactical.selected:
			formation = String(tactical.selected.formation_name).capitalize()
	return "SELECTED  %s\nLINK  %s\nSTANCE  %s\nFORMATION  %s\n\nCONTACTS  %d" % [selected_name, link_name, stance_name, formation, sensors.contacts.size()]

func update_target(contact: SensorContact, target_name: String = "", target_ship: CombatShip = null) -> void:
	if contact == null:
		locked_target = null
		target_label.text = "NO MISSILE LOCK"
		target_shield_bar.value = 0.0
		target_armor_bar.value = 0.0
		target_hull_bar.value = 0.0
		target_indicator.visible = false
		return
	locked_target = target_ship
	var state: String = SensorContact.IdentificationState.keys()[contact.identification_state]
	var distance := carrier.global_position.distance_to(target_ship.global_position) if is_instance_valid(target_ship) else carrier.global_position.distance_to(contact.estimated_position)
	target_label.text = "LOCKED // %s\n%s  CONF %d%%\nRANGE %.0f m\nUNCERTAINTY %.0f m" % [target_name if not target_name.is_empty() else String(contact.classification).capitalize(), state, contact.confidence * 100.0, distance, contact.uncertainty_radius_m]

func _update_target_presentation() -> void:
	if not is_instance_valid(locked_target):
		target_indicator.visible = false
		return
	var layers := locked_target.layer_percentages()
	target_shield_bar.value = layers.x * 100.0
	target_armor_bar.value = layers.y * 100.0
	target_hull_bar.value = layers.z * 100.0
	if tactical.enabled or not is_instance_valid(carrier.chase_camera):
		target_indicator.visible = false
		return
	var camera := carrier.chase_camera
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var camera_space := camera.global_transform.affine_inverse() * locked_target.global_position
	var behind := camera_space.z > 0.0
	var projected := camera.unproject_position(locked_target.global_position)
	var direction := projected - center
	if behind:
		direction = Vector2(-camera_space.x, camera_space.y)
	if direction.length_squared() < 0.01:
		direction = Vector2.UP
	direction = direction.normalized()
	var safe_rect := Rect2(Vector2(54, 78), viewport_size - Vector2(108, 148))
	var on_screen := not behind and safe_rect.has_point(projected)
	if on_screen:
		target_indicator.text = "◇"
		target_indicator.rotation = 0.0
		target_indicator.position = projected - target_indicator.size * 0.5
	else:
		target_indicator.text = "▲"
		target_indicator.rotation = direction.angle() + PI * 0.5
		var edge := center + direction * minf(viewport_size.x * 0.42, viewport_size.y * 0.38)
		edge.x = clampf(edge.x, 54.0, viewport_size.x - 54.0)
		edge.y = clampf(edge.y, 78.0, viewport_size.y - 70.0)
		target_indicator.position = edge - target_indicator.size * 0.5
	target_indicator.visible = true

func set_result(victory: bool, action_text: String = "Press Enter to restart", outcome: String = "victory") -> void:
	result_panel.visible = true
	var summary := "CARRIER LOST\nTask force command destroyed"
	if victory:
		match outcome:
			"withdrawal":
				summary = "WITHDRAWAL COMPLETE\nTask force extracted under pressure"
			"interception":
				summary = "INTERCEPTION COMPLETE\nHostile screen neutralized"
			"defense":
				summary = "DEFENSE COMPLETE\nLongwatch relay remains operational"
			"escort":
				summary = "ESCORT COMPLETE\nAtlas convoy reached the jump corridor"
			"capture":
				summary = "CAPTURE COMPLETE\nControl zone secured"
			"defense_failed":
				summary = "OBJECTIVE FAILED\nLongwatch relay lost; task force can withdraw"
			"escort_failed":
				summary = "OBJECTIVE FAILED\nAtlas convoy lost; task force can withdraw"
			_:
				summary = "MISSION COMPLETE\nHostile command ship destroyed"
	result_label.text = summary + "\n\n" + action_text
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_paused(value: bool) -> void:
	pause_panel.visible = value

func _label(parent: Node, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.72, 0.9, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label

func _bar(parent: Node, position_value: Vector2, size_value: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = position_value
	bar.size = size_value
	bar.show_percentage = false
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = color
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.03, 0.06, 0.09, 0.9)
	bar.add_theme_stylebox_override("fill", foreground)
	bar.add_theme_stylebox_override("background", background)
	parent.add_child(bar)
	return bar

func _panel(parent: Node, position_value: Vector2, size_value: Vector2, color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.position = position_value
	panel.size = size_value
	panel.color = color
	parent.add_child(panel)
	return panel
