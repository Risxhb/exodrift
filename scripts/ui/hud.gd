class_name SidebayHUD
extends CanvasLayer

const RadarDisplay := preload("res://scripts/ui/radar_display.gd")
const UIStyle := preload("res://scripts/ui/ui_style.gd")

var carrier: PlayerCarrier
var interceptor: SidebaySquadron
var scout: SidebaySquadron
var sensors: SidebaySensorSystem
var tactical: TacticalController
var status_label: Label
var wing_label: Label
var weapon_label: Label
var target_label: Label
var target_panel: Panel
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
var result_panel: Panel
var result_label: Label
var pause_panel: Panel
var shield_bar: ProgressBar
var armor_bar: ProgressBar
var hull_bar: ProgressBar
var notification_time: float = 0.0
var radar
var radar_title: Label
var objective_panel: Panel
var telemetry_panel: Panel
var wing_panel: Panel
var weapon_panel: Panel
var radar_panel: Panel
var map_info_panel: Panel
var mode_panel: Panel
var notification_panel: Panel
var controls_panel: Panel
var pause_veil: ColorRect
var result_veil: ColorRect

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
	objective_panel = _panel(root, Vector2(18, 14), Vector2(720, 40), Color(0.006, 0.024, 0.038, 0.88), UIStyle.AMBER)
	_accent_line(objective_panel, Vector2(0, 0), Vector2(5, 40), UIStyle.AMBER)
	objective_label = _label(objective_panel, Vector2(16, 4), Vector2(690, 30), 17)
	objective_label.text = "OBJECTIVE  Identify and destroy the hostile command frigate"
	telemetry_panel = _panel(root, Vector2(18, 62), Vector2(430, 108), Color(0.006, 0.024, 0.038, 0.9))
	_section_heading(telemetry_panel, "CARRIER TELEMETRY", UIStyle.CYAN)
	status_label = _label(telemetry_panel, Vector2(14, 24), Vector2(402, 58), 13)
	shield_bar = _bar(telemetry_panel, Vector2(14, 88), Vector2(126, 9), Color(0.1, 0.65, 1.0))
	armor_bar = _bar(telemetry_panel, Vector2(152, 88), Vector2(126, 9), Color(0.95, 0.65, 0.12))
	hull_bar = _bar(telemetry_panel, Vector2(290, 88), Vector2(126, 9), Color(0.9, 0.15, 0.12))
	wing_panel = _panel(root, Vector2(18, 178), Vector2(510, 76), Color(0.006, 0.024, 0.038, 0.86))
	_section_heading(wing_panel, "AIR GROUP", UIStyle.CYAN)
	wing_label = _label(wing_panel, Vector2(14, 24), Vector2(482, 46), 12)
	weapon_panel = _panel(root, Vector2(18, 262), Vector2(460, 76), Color(0.006, 0.024, 0.038, 0.86))
	_section_heading(weapon_panel, "FIRE CONTROL", UIStyle.AMBER)
	weapon_label = _label(weapon_panel, Vector2(14, 24), Vector2(432, 46), 12)
	target_panel = _panel(root, Vector2(912, 14), Vector2(350, 172), Color(0.006, 0.024, 0.038, 0.94), UIStyle.CYAN)
	_section_heading(target_panel, "TARGET SOLUTION", UIStyle.CYAN)
	var portrait_back := _panel(target_panel, Vector2(14, 30), Vector2(84, 76), Color(0.012, 0.065, 0.09, 0.96), UIStyle.CYAN_SOFT)
	var portrait := Polygon2D.new()
	portrait.polygon = PackedVector2Array([Vector2(42, 6), Vector2(57, 25), Vector2(76, 38), Vector2(62, 48), Vector2(56, 70), Vector2(28, 70), Vector2(22, 48), Vector2(8, 38), Vector2(27, 25)])
	portrait.color = Color(0.22, 0.72, 0.92, 0.9)
	portrait_back.add_child(portrait)
	target_label = _label(target_panel, Vector2(112, 30), Vector2(224, 76), 12)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(target_panel, Vector2(14, 112), Vector2(18, 14), 9, Color(0.3, 0.75, 1.0)).text = "S"
	_label(target_panel, Vector2(14, 130), Vector2(18, 14), 9, Color(1.0, 0.7, 0.25)).text = "A"
	_label(target_panel, Vector2(14, 148), Vector2(18, 14), 9, Color(1.0, 0.3, 0.24)).text = "H"
	target_shield_bar = _bar(target_panel, Vector2(32, 114), Vector2(304, 8), Color(0.1, 0.65, 1.0))
	target_armor_bar = _bar(target_panel, Vector2(32, 132), Vector2(304, 8), Color(0.95, 0.65, 0.12))
	target_hull_bar = _bar(target_panel, Vector2(32, 150), Vector2(304, 8), Color(0.9, 0.15, 0.12))
	target_indicator = _label(root, Vector2(624, 300), Vector2(38, 38), 30)
	target_indicator.text = "▲"
	target_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_indicator.add_theme_color_override("font_color", Color(0.25, 0.92, 1.0))
	target_indicator.pivot_offset = Vector2(19, 19)
	target_indicator.visible = false
	mode_panel = _panel(root, Vector2(470, 14), Vector2(340, 48), Color(0.006, 0.024, 0.038, 0.9), UIStyle.CYAN)
	mode_label = _label(mode_panel, Vector2(8, 4), Vector2(324, 38), 22)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_panel.visible = false
	notification_panel = _panel(root, Vector2(350, 614), Vector2(580, 42), Color(0.006, 0.03, 0.045, 0.94), UIStyle.AMBER)
	notification_label = _label(notification_panel, Vector2(12, 5), Vector2(556, 30), 15)
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_panel.visible = false
	controls_panel = _panel(root, Vector2(12, 674), Vector2(1256, 34), Color(0.004, 0.018, 0.028, 0.92), UIStyle.CYAN_SOFT)
	controls_label = _label(controls_panel, Vector2(10, 3), Vector2(1236, 25), 11, UIStyle.TEXT_MUTED)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.text = "Mouse free-look / flak aim  WASD thrust  Space/C vertical  LMB flak  RMB missile  P ping  Z/X wings  Tab map  Esc pause"
	crosshair_label = _label(root, Vector2(624, 340), Vector2(32, 32), 24)
	crosshair_label.text = ""
	crosshair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair_label.visible = false
	map_info_panel = _panel(root, Vector2(18, 74), Vector2(342, 210), Color(0.006, 0.024, 0.038, 0.94), UIStyle.CYAN)
	_section_heading(map_info_panel, "COMMAND LINK", UIStyle.CYAN)
	map_info_label = _label(map_info_panel, Vector2(16, 34), Vector2(312, 164), 14)
	map_info_panel.visible = false
	radar_panel = _panel(root, Vector2(1032, 438), Vector2(230, 220), Color(0.004, 0.025, 0.038, 0.94), UIStyle.CYAN_SOFT)
	radar_title = _label(radar_panel, Vector2(12, 8), Vector2(206, 24), 11, UIStyle.TEXT_MUTED)
	radar_title.text = "TACTICAL RADAR // ACTIVE"
	radar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radar = RadarDisplay.new()
	radar.position = Vector2(20, 26)
	radar.size = Vector2(190, 190)
	radar_panel.add_child(radar)
	radar.configure(carrier, sensors)
	result_veil = _veil(root)
	result_panel = _panel(root, Vector2(340, 230), Vector2(600, 250), Color(0.006, 0.024, 0.038, 0.98), UIStyle.CYAN)
	_accent_line(result_panel, Vector2(0, 0), Vector2(600, 4), UIStyle.CYAN)
	result_label = _label(result_panel, Vector2(25, 55), Vector2(550, 150), 30)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.visible = false
	result_veil.visible = false
	pause_veil = _veil(root)
	pause_panel = _panel(root, Vector2(390, 210), Vector2(500, 300), Color(0.006, 0.024, 0.038, 0.98), UIStyle.AMBER)
	_accent_line(pause_panel, Vector2(0, 0), Vector2(500, 4), UIStyle.AMBER)
	var pause_title := _label(pause_panel, Vector2(20, 22), Vector2(460, 45), 28)
	pause_title.text = "PAUSED / SETTINGS"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pause_copy := _label(pause_panel, Vector2(40, 90), Vector2(420, 160), 18)
	pause_copy.text = "Esc — resume\n\nMouse: independent camera + flak director\nCarrier hull remains on its helm heading\nMouse wheel: camera zoom\nVertical battlespace: ±1,400 m\n\nEnter — restart encounter"
	pause_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_panel.visible = false
	pause_veil.visible = false

func _process(delta: float) -> void:
	if not is_instance_valid(carrier):
		return
	var layers := carrier.layer_percentages()
	shield_bar.value = layers.x * 100.0
	armor_bar.value = layers.y * 100.0
	hull_bar.value = layers.z * 100.0
	status_label.text = "%s  //  SPD %4.0f m/s\nBAYS %s  //  CONTACTS %d\nSHD %3.0f%%    ARM %3.0f%%    HULL %3.0f%%" % [carrier.display_name.to_upper(), carrier.velocity.length(), carrier.bay_status(), sensors.contacts.size(), layers.x * 100.0, layers.y * 100.0, layers.z * 100.0]
	wing_label.text = "[Z] %s  //  %s  •  %d CRAFT  •  %d AMMO  •  %.0fs\n[X] %s  //  %s  •  %d CRAFT  •  %d AMMO  •  %.0fs" % [
		interceptor.display_name, interceptor.operation.label(), interceptor.living_craft_count(), interceptor.total_ammunition(), interceptor.average_endurance(),
		scout.display_name, scout.operation.label(), scout.living_craft_count(), scout.total_ammunition(), scout.average_endurance()
	]
	var flak_status := "READY" if carrier.flak_cooldown <= 0.0 else "CYCLING %.1fs" % carrier.flak_cooldown
	var missile_status := "READY" if carrier.missile_cooldown <= 0.0 else "RELOAD %.1fs" % carrier.missile_cooldown
	weapon_label.text = "FLAK CURTAIN  //  %s  •  %d ROUNDS\nMISSILE SALVO  //  %s  •  %d WEAPONS  •  %.1f km" % [flak_status, carrier.flak_burst_count, missile_status, carrier.missile_salvo_count, carrier.missile_weapon.range_m / 1000.0]
	var graphics := get_node_or_null("/root/GraphicsQualityManager")
	radar_title.text = "TACTICAL RADAR // %s" % (graphics.profile_label() if graphics != null else "ACTIVE")
	mode_label.text = "TACTICAL MAP — LIVE" if tactical.enabled else ""
	_update_target_presentation()
	if tactical.enabled:
		telemetry_panel.visible = false
		wing_panel.visible = false
		weapon_panel.visible = false
		crosshair_label.visible = false
		objective_panel.visible = false
		map_info_panel.visible = true
		mode_panel.visible = true
		map_info_label.text = _map_information()
		controls_label.text = "1–4 GROUPS   LMB SELECT   RMB ORDER   I INTERCEPT   E ESCORT   SHIFT QUEUE   Q STANCE   F FORM   R RECALL   H HOLD   X WITHDRAW   V JUMP   MMB ORBIT   WHEEL ZOOM"
	else:
		telemetry_panel.visible = true
		wing_panel.visible = true
		weapon_panel.visible = true
		crosshair_label.visible = false
		objective_panel.visible = true
		map_info_panel.visible = false
		mode_panel.visible = false
		controls_label.text = ("CURSOR AIM / CAMERA   " if OS.has_feature("web") else "MOUSE FREE-LOOK / FLAK AIM   ") + "WASD THRUST   SPACE/C VERTICAL   WHEEL ZOOM   SHIFT BOOST   CTRL BRAKE   LMB FLAK   RMB MISSILES   P PING   Z/X WINGS   V JUMP   TAB MAP   ESC PAUSE"
	if notification_time > 0.0:
		notification_time -= delta
		if notification_time <= 0.0:
			notification_label.text = ""
			notification_panel.visible = false

func notify(message: String) -> void:
	notification_label.text = message
	notification_time = 3.5
	notification_panel.visible = true

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
		target_label.text = "NO VALID TRACK\n\nMISSILE LOCK\nUNAVAILABLE"
		target_shield_bar.value = 0.0
		target_armor_bar.value = 0.0
		target_hull_bar.value = 0.0
		target_indicator.visible = false
		return
	locked_target = target_ship
	var state: String = SensorContact.IdentificationState.keys()[contact.identification_state]
	var distance := carrier.global_position.distance_to(target_ship.global_position) if is_instance_valid(target_ship) else carrier.global_position.distance_to(contact.estimated_position)
	target_label.text = "LOCKED  //  %s\n%s  •  CONF %d%%\nRANGE %.0f m\nERROR ±%.0f m" % [target_name if not target_name.is_empty() else String(contact.classification).capitalize(), state, contact.confidence * 100.0, distance, contact.uncertainty_radius_m]

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
	result_veil.visible = true
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
	pause_veil.visible = value
	pause_panel.visible = value

func _label(parent: Node, position_value: Vector2, size_value: Vector2, font_size: int, color: Color = UIStyle.TEXT_PRIMARY) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size, color)
	parent.add_child(label)
	return label

func _bar(parent: Node, position_value: Vector2, size_value: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = position_value
	bar.size = size_value
	bar.custom_minimum_size = Vector2(0.0, 1.0)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_font_size_override("font_size", 1)
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = color
	foreground.set_corner_radius_all(2)
	foreground.content_margin_top = 0.0
	foreground.content_margin_bottom = 0.0
	foreground.content_margin_left = 0.0
	foreground.content_margin_right = 0.0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.015, 0.045, 0.06, 0.95)
	background.border_color = Color(color.r, color.g, color.b, 0.28)
	background.set_border_width_all(1)
	background.set_corner_radius_all(2)
	background.content_margin_top = 0.0
	background.content_margin_bottom = 0.0
	background.content_margin_left = 0.0
	background.content_margin_right = 0.0
	bar.add_theme_stylebox_override("fill", foreground)
	bar.add_theme_stylebox_override("background", background)
	parent.add_child(bar)
	# ProgressBar reserves label height even when percentages are hidden; scale only
	# the visual track so compact HUD bars retain their authored thickness.
	var rendered_height := maxf(bar.size.y, bar.get_combined_minimum_size().y)
	bar.scale.y = size_value.y / rendered_height if rendered_height > size_value.y else 1.0
	return bar

func _panel(parent: Node, position_value: Vector2, size_value: Vector2, color: Color, accent: Color = UIStyle.CYAN_SOFT) -> Panel:
	var panel := Panel.new()
	panel.position = position_value
	panel.size = size_value
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(color, accent, 1, 5))
	parent.add_child(panel)
	return panel

func _section_heading(parent: Control, text_value: String, accent: Color) -> void:
	var heading := _label(parent, Vector2(14, 5), Vector2(parent.size.x - 28.0, 16), 10, Color(accent.r, accent.g, accent.b, 0.9))
	heading.text = text_value
	_accent_line(parent, Vector2(14, 20), Vector2(parent.size.x - 28.0, 1), Color(accent.r, accent.g, accent.b, 0.48))

func _accent_line(parent: Node, position_value: Vector2, size_value: Vector2, color: Color) -> void:
	var accent := ColorRect.new()
	accent.position = position_value
	accent.size = size_value
	accent.color = color
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(accent)

func _veil(parent: Node) -> ColorRect:
	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.006, 0.012, 0.68)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(veil)
	return veil
