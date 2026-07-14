class_name SidebayHUD
extends CanvasLayer

const RadarDisplay := preload("res://scripts/ui/radar_display.gd")
const UIStyle := preload("res://scripts/ui/ui_style.gd")
const TargetLockReticle := preload("res://scripts/ui/target_lock_reticle.gd")
const TargetDirectionArrow := preload("res://scripts/ui/target_direction_arrow.gd")

signal target_lock_requested(entity_id: StringName)
signal target_command_requested(command: StringName, entity_id: StringName)
signal target_navigation_requested(command: StringName, entity_id: StringName, distance_m: float)
signal carrier_operations_requested
signal fighter_squadron_toggle_requested(squadron_index: int)
signal fighter_group_action_requested(action: StringName)

const HUD_SCALE := 0.75
const CONTEXT_LOCK := 1
const CONTEXT_APPROACH := 2
const CONTEXT_ORBIT_500 := 10
const CONTEXT_ORBIT_5000 := 11
const CONTEXT_ORBIT_10000 := 12
const CONTEXT_ORBIT_25000 := 13
const CONTEXT_KEEP_500 := 20
const CONTEXT_KEEP_5000 := 21
const CONTEXT_KEEP_10000 := 22
const CONTEXT_KEEP_25000 := 23
const CONTEXT_CLEAR := 30

var carrier: PlayerCarrier
var interceptor: SidebaySquadron
var fighter_squadrons: Array[SidebaySquadron] = []
var scout: SidebaySquadron
var sensors: SidebaySensorSystem
var tactical: TacticalController
var status_label: Label
var wing_label: Label
var weapon_label: Label
var target_label: Label
var target_panel: Panel
var target_indicator: Control
var target_shield_bar: ProgressBar
var target_armor_bar: ProgressBar
var target_hull_bar: ProgressBar
var locked_target: CombatShip
var target_reticle: ExodriftTargetLockReticle
var target_caption: Label
var overview_panel: Panel
var overview_rows: Array[Button] = []
var overview_contact_ids: Array[StringName] = []
var overview_selected_id: StringName = &""
var overview_refresh_seconds: float = 0.0
var collapsible_panels: Dictionary = {}
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
var hud_root: Control
var target_context_menu: PopupMenu
var context_target_id: StringName = &""
var scaled_hud_panels: Array[Control] = []
var carrier_operations_state: Object
var carrier_operations_panel: Panel
var carrier_operations_label: Label
var carrier_operations_button: Button
var cic_overlay: ExodriftCICOverlay
var fighter_deployment_menu: PopupMenu
var fighter_menu_button: Button

func configure(
	player_carrier: PlayerCarrier,
	interceptor_wing: SidebaySquadron,
	scout_wing: SidebaySquadron,
	sensor_system: SidebaySensorSystem,
	tactical_controller: TacticalController,
	fighter_wings: Array[SidebaySquadron] = []
) -> void:
	layer = 10
	carrier = player_carrier
	interceptor = interceptor_wing
	fighter_squadrons = fighter_wings.duplicate()
	if fighter_squadrons.is_empty() and is_instance_valid(interceptor_wing):
		fighter_squadrons.append(interceptor_wing)
	scout = scout_wing
	sensors = sensor_system
	tactical = tactical_controller
	_build_ui()
	cic_overlay = ExodriftCICOverlay.new()
	cic_overlay.name = "CICOverlay"
	hud_root.add_child(cic_overlay)
	cic_overlay.configure(carrier, tactical, tactical.commandables)
	get_viewport().size_changed.connect(_layout_scaled_hud)

func _build_ui() -> void:
	var root := Control.new()
	hud_root = root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	objective_panel = _panel(root, Vector2(18, 14), Vector2(650, 36), Color(0.006, 0.024, 0.038, 0.74), UIStyle.AMBER)
	_accent_line(objective_panel, Vector2(0, 0), Vector2(4, 36), UIStyle.AMBER)
	objective_label = _label(objective_panel, Vector2(16, 2), Vector2(620, 28), 15)
	objective_label.text = "OBJECTIVE  Identify and destroy the hostile command frigate"
	telemetry_panel = _panel(root, Vector2(18, 58), Vector2(370, 98), Color(0.006, 0.024, 0.038, 0.72))
	_collapsible_heading(telemetry_panel, "CARRIER TELEMETRY", UIStyle.CYAN)
	status_label = _label(telemetry_panel, Vector2(14, 23), Vector2(342, 50), 12)
	shield_bar = _bar(telemetry_panel, Vector2(14, 80), Vector2(104, 7), Color(0.1, 0.65, 1.0))
	armor_bar = _bar(telemetry_panel, Vector2(126, 80), Vector2(104, 7), Color(0.95, 0.65, 0.12))
	hull_bar = _bar(telemetry_panel, Vector2(238, 80), Vector2(104, 7), Color(0.9, 0.15, 0.12))
	_register_collapsible(telemetry_panel)
	wing_panel = _panel(root, Vector2(18, 164), Vector2(438, 94), Color(0.006, 0.024, 0.038, 0.68))
	_collapsible_heading(wing_panel, "AIR GROUP", UIStyle.CYAN)
	wing_label = _label(wing_panel, Vector2(14, 23), Vector2(410, 66), 10)
	fighter_menu_button = _overview_button(wing_panel, Vector2(288, 2), Vector2(138, 19), 9)
	fighter_menu_button.text = "[Z] SQUADRON OPS"
	fighter_menu_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	fighter_menu_button.pressed.connect(open_fighter_deployment_menu)
	_register_collapsible(wing_panel)
	_build_fighter_deployment_menu(root)
	weapon_panel = _panel(root, Vector2(18, 240), Vector2(470, 88), Color(0.006, 0.024, 0.038, 0.68))
	_collapsible_heading(weapon_panel, "FIRE CONTROL", UIStyle.AMBER)
	weapon_label = _label(weapon_panel, Vector2(14, 23), Vector2(442, 60), 11)
	_register_collapsible(weapon_panel)
	carrier_operations_panel = _panel(root, Vector2(18, 336), Vector2(438, 74), Color(0.006, 0.024, 0.038, 0.7), UIStyle.AMBER)
	_collapsible_heading(carrier_operations_panel, "CARRIER OPERATIONS", UIStyle.AMBER)
	carrier_operations_label = _label(carrier_operations_panel, Vector2(14, 25), Vector2(304, 40), 11)
	carrier_operations_label.text = "%s BALANCED  //  8 / 8 POWER\nCREW 240  //  STORES NOMINAL" % _operations_key_tag()
	carrier_operations_button = _overview_button(carrier_operations_panel, Vector2(326, 29), Vector2(96, 30), 10)
	carrier_operations_button.text = "OPEN %s" % _operations_key_tag()
	carrier_operations_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	carrier_operations_button.pressed.connect(func() -> void: carrier_operations_requested.emit())
	_register_collapsible(carrier_operations_panel)
	target_panel = _panel(root, Vector2(934, 14), Vector2(328, 158), Color(0.006, 0.024, 0.038, 0.76), UIStyle.CYAN)
	_collapsible_heading(target_panel, "TARGET SOLUTION", UIStyle.CYAN)
	target_label = _label(target_panel, Vector2(14, 29), Vector2(300, 68), 11)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label(target_panel, Vector2(14, 112), Vector2(18, 14), 9, Color(0.3, 0.75, 1.0)).text = "S"
	_label(target_panel, Vector2(14, 130), Vector2(18, 14), 9, Color(1.0, 0.7, 0.25)).text = "A"
	_label(target_panel, Vector2(14, 148), Vector2(18, 14), 9, Color(1.0, 0.3, 0.24)).text = "H"
	target_shield_bar = _bar(target_panel, Vector2(32, 106), Vector2(282, 7), Color(0.1, 0.65, 1.0))
	target_armor_bar = _bar(target_panel, Vector2(32, 124), Vector2(282, 7), Color(0.95, 0.65, 0.12))
	target_hull_bar = _bar(target_panel, Vector2(32, 142), Vector2(282, 7), Color(0.9, 0.15, 0.12))
	_register_collapsible(target_panel)
	overview_panel = _panel(root, Vector2(934, 180), Vector2(328, 218), Color(0.005, 0.022, 0.034, 0.82), UIStyle.CYAN_SOFT)
	_collapsible_heading(overview_panel, "TACTICAL OVERVIEW", UIStyle.CYAN_SOFT)
	for index in 5:
		var row := _overview_button(overview_panel, Vector2(12, 28 + index * 31), Vector2(304, 28), 10)
		row.pressed.connect(_select_overview_row.bind(index))
		row.gui_input.connect(_on_overview_row_input.bind(index))
		overview_rows.append(row)
		overview_contact_ids.append(&"")
	var overview_hint := _label(overview_panel, Vector2(12, 190), Vector2(304, 20), 8, UIStyle.TEXT_MUTED)
	overview_hint.text = "RMB TRACK  //  LOCK OR HELM GEOMETRY"
	overview_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_register_collapsible(overview_panel)
	_build_target_context_menu(root)
	target_indicator = TargetDirectionArrow.new()
	target_indicator.name = "TargetDirectionArrow"
	target_indicator.position = Vector2(624, 300)
	target_indicator.size = Vector2(38, 38)
	target_indicator.pivot_offset = Vector2(19, 19)
	target_indicator.visible = false
	root.add_child(target_indicator)
	target_reticle = TargetLockReticle.new()
	target_reticle.position = Vector2(560, 280)
	target_reticle.size = Vector2(160, 160)
	target_reticle.visible = false
	root.add_child(target_reticle)
	target_caption = _label(root, Vector2(548, 424), Vector2(184, 36), 10, UIStyle.TEXT_PRIMARY)
	target_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_caption.visible = false
	mode_panel = _panel(root, Vector2(692, 14), Vector2(224, 36), Color(0.006, 0.024, 0.038, 0.72), UIStyle.CYAN)
	mode_label = _label(mode_panel, Vector2(8, 2), Vector2(208, 28), 14)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_panel.visible = false
	notification_panel = _panel(root, Vector2(350, 616), Vector2(580, 38), Color(0.006, 0.03, 0.045, 0.76), UIStyle.AMBER)
	notification_label = _label(notification_panel, Vector2(12, 5), Vector2(556, 30), 15)
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_panel.visible = false
	controls_panel = _panel(root, Vector2(84, 680), Vector2(1112, 28), Color(0.004, 0.018, 0.028, 0.62), UIStyle.CYAN_SOFT)
	controls_label = _label(controls_panel, Vector2(10, 3), Vector2(1092, 22), 10, UIStyle.TEXT_MUTED)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.text = "1 FLAK WALL  2 MISSILES  3 NUCLEAR  %s CARRIER OPS  B HANGAR WINGS  MMB ORBIT  WHEEL ZOOM" % _operations_key_label()
	crosshair_label = _label(root, Vector2(624, 340), Vector2(32, 32), 24)
	crosshair_label.text = "⌖"
	crosshair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair_label.visible = false
	map_info_panel = _panel(root, Vector2(18, 74), Vector2(390, 286), Color(0.006, 0.024, 0.038, 0.94), UIStyle.CYAN)
	_section_heading(map_info_panel, "COMMAND LINK", UIStyle.CYAN)
	map_info_label = _label(map_info_panel, Vector2(16, 34), Vector2(358, 238), 12)
	map_info_panel.visible = false
	radar_panel = _panel(root, Vector2(1032, 442), Vector2(230, 216), Color(0.004, 0.025, 0.038, 0.56), UIStyle.CYAN_SOFT)
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
	pause_copy.text = "Esc - resume\n\n1: fire a flak wall toward the identified target lock\n2: guided missile salvo  /  3: one nuclear torpedo\nFlak destroys missiles and strikecraft; friendlies must clear the firing sector\n%s: live carrier operations console\nB: deploy or retract all wings  /  Z: fighter squadron menu\nX: Watcher EW/scout wing\nW/S: throttle  /  Double-click: full-cruise heading\nMiddle-drag: camera orbit  /  Wheel: signed zoom\n\nEnter - restart encounter" % _operations_key_label()
	pause_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_panel.visible = false
	pause_veil.visible = false
	scaled_hud_panels = [objective_panel, telemetry_panel, wing_panel, weapon_panel, carrier_operations_panel, target_panel, overview_panel, map_info_panel, radar_panel, mode_panel, notification_panel, controls_panel]
	_layout_scaled_hud()

func _build_target_context_menu(root: Control) -> void:
	target_context_menu = PopupMenu.new()
	target_context_menu.name = "TargetNavigationMenu"
	target_context_menu.add_item("LOCK TARGET", CONTEXT_LOCK)
	target_context_menu.add_item("APPROACH — 500 M", CONTEXT_APPROACH)
	target_context_menu.add_separator("ORBIT")
	target_context_menu.add_item("ORBIT — 500 M", CONTEXT_ORBIT_500)
	target_context_menu.add_item("ORBIT — 5 KM", CONTEXT_ORBIT_5000)
	target_context_menu.add_item("ORBIT — 10 KM", CONTEXT_ORBIT_10000)
	target_context_menu.add_item("ORBIT — 25 KM", CONTEXT_ORBIT_25000)
	target_context_menu.add_separator("KEEP AT DISTANCE")
	target_context_menu.add_item("KEEP — 500 M", CONTEXT_KEEP_500)
	target_context_menu.add_item("KEEP — 5 KM", CONTEXT_KEEP_5000)
	target_context_menu.add_item("KEEP — 10 KM", CONTEXT_KEEP_10000)
	target_context_menu.add_item("KEEP — 25 KM", CONTEXT_KEEP_25000)
	target_context_menu.add_separator()
	target_context_menu.add_item("CLEAR RELATIVE NAVIGATION", CONTEXT_CLEAR)
	target_context_menu.add_theme_font_size_override("font_size", 13)
	target_context_menu.id_pressed.connect(_on_target_context_id_pressed)
	root.add_child(target_context_menu)

func _build_fighter_deployment_menu(root: Control) -> void:
	fighter_deployment_menu = PopupMenu.new()
	fighter_deployment_menu.name = "FighterSquadronDeploymentMenu"
	fighter_deployment_menu.add_theme_font_size_override("font_size", 13)
	fighter_deployment_menu.add_theme_color_override("font_color", UIStyle.TEXT_PRIMARY)
	fighter_deployment_menu.add_theme_color_override("font_hover_color", Color.WHITE)
	fighter_deployment_menu.add_theme_color_override("font_disabled_color", UIStyle.TEXT_MUTED)
	fighter_deployment_menu.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.006, 0.024, 0.038, 0.98), UIStyle.CYAN, 2, 4))
	fighter_deployment_menu.add_theme_stylebox_override("hover", UIStyle.panel_style(Color(0.02, 0.12, 0.17, 0.98), UIStyle.CYAN, 1, 2))
	fighter_deployment_menu.id_pressed.connect(_on_fighter_deployment_id_pressed)
	root.add_child(fighter_deployment_menu)

func open_fighter_deployment_menu() -> void:
	if fighter_deployment_menu == null:
		return
	_refresh_fighter_deployment_menu()
	var menu_position := wing_panel.global_position + Vector2(wing_panel.size.x * HUD_SCALE + 10.0, 0.0)
	fighter_deployment_menu.position = Vector2i(menu_position)
	fighter_deployment_menu.popup()

func _refresh_fighter_deployment_menu() -> void:
	fighter_deployment_menu.clear()
	fighter_deployment_menu.add_item("FIGHTER CONTROL // 6 SQUADRONS", 90)
	fighter_deployment_menu.set_item_disabled(0, true)
	fighter_deployment_menu.add_separator()
	for squadron_index in fighter_squadrons.size():
		var wing := fighter_squadrons[squadron_index]
		if not is_instance_valid(wing):
			continue
		var action := "STATUS"
		if wing.operation.state == BayOperation.State.READY:
			action = "LAUNCH"
		elif wing.operation.state in [BayOperation.State.QUEUED, BayOperation.State.LAUNCHING, BayOperation.State.DEPLOYED]:
			action = "RECALL"
		elif wing.operation.is_service_state():
			action = "QUEUE REDEPLOY"
		var item_text := "%d  %-16s  %3d%% %-8s  %d/%d  // %s" % [
			squadron_index + 1, wing.display_name.to_upper(), wing.wing_health_percent(), wing.wing_health_label(),
			wing.living_craft_count(), wing.maximum_craft_count(), action
		]
		fighter_deployment_menu.add_item(item_text, squadron_index)
	fighter_deployment_menu.add_separator()
	fighter_deployment_menu.add_item("LAUNCH ALL READY FIGHTER SQUADRONS", 100)
	fighter_deployment_menu.add_item("RECALL ALL FIGHTER SQUADRONS", 101)
	fighter_deployment_menu.add_separator()
	fighter_deployment_menu.add_item("WATCHER EW / SCOUT WING REMAINS ON [X]", 102)
	fighter_deployment_menu.set_item_disabled(fighter_deployment_menu.item_count - 1, true)

func _on_fighter_deployment_id_pressed(id: int) -> void:
	if id >= 0 and id < fighter_squadrons.size():
		fighter_squadron_toggle_requested.emit(id)
	elif id == 100:
		fighter_group_action_requested.emit(&"deploy_all")
	elif id == 101:
		fighter_group_action_requested.emit(&"recall_all")

func _layout_scaled_hud() -> void:
	if hud_root == null:
		return
	for panel in scaled_hud_panels:
		if is_instance_valid(panel):
			panel.scale = Vector2.ONE * HUD_SCALE
	var viewport_size := get_viewport().get_visible_rect().size
	objective_panel.position = Vector2(18.0, 14.0)
	telemetry_panel.position = Vector2(18.0, 49.0)
	wing_panel.position = Vector2(18.0, 131.0)
	weapon_panel.position = Vector2(18.0, 215.0)
	carrier_operations_panel.position = Vector2(18.0, 287.0)
	map_info_panel.position = Vector2(18.0, 49.0)
	target_panel.position = Vector2(viewport_size.x - 18.0 - target_panel.size.x * HUD_SCALE, 14.0)
	overview_panel.position = Vector2(viewport_size.x - 18.0 - overview_panel.size.x * HUD_SCALE, 141.0)
	radar_panel.position = Vector2(viewport_size.x - 18.0 - radar_panel.size.x * HUD_SCALE, viewport_size.y - 44.0 - radar_panel.size.y * HUD_SCALE)
	mode_panel.position = Vector2((viewport_size.x - mode_panel.size.x * HUD_SCALE) * 0.5, 14.0)
	controls_panel.position = Vector2((viewport_size.x - controls_panel.size.x * HUD_SCALE) * 0.5, viewport_size.y - 12.0 - controls_panel.size.y * HUD_SCALE)
	notification_panel.position = Vector2((viewport_size.x - notification_panel.size.x * HUD_SCALE) * 0.5, controls_panel.position.y - 12.0 - notification_panel.size.y * HUD_SCALE)

func _process(delta: float) -> void:
	if not is_instance_valid(carrier):
		return
	var layers := carrier.layer_percentages()
	shield_bar.value = layers.x * 100.0
	armor_bar.value = layers.y * 100.0
	hull_bar.value = layers.z * 100.0
	status_label.text = "%s  //  SPD %4.0f m/s\nBAYS %s  //  CONTACTS %d\nSHD %3.0f%%    ARM %3.0f%%    HULL %3.0f%%" % [carrier.display_name.to_upper(), carrier.velocity.length(), carrier.bay_status(), sensors.contacts.size(), layers.x * 100.0, layers.y * 100.0, layers.z * 100.0]
	var fighter_health := _fighter_group_health_percent()
	var fighter_craft := _fighter_group_living_craft()
	var fighter_deployed := _fighter_group_deployed_count()
	wing_label.text = "[Z] FIGHTER SQUADRONS  %d/6 OUT  //  HEALTH %3d%%  //  %d CRAFT\n    DEPLOYED %d  //  READY %d  //  SELECT SQUADRON TO LAUNCH\n[X] %s  //  %s  //  HEALTH %3d%% %s  //  EW + SCOUT" % [
		_fighter_squadrons_out(), fighter_health, fighter_craft, fighter_deployed, _fighter_squadrons_ready(),
		scout.display_name, _wing_state(scout), scout.wing_health_percent(), scout.wing_health_label()
	]
	var flak_status := "READY" if carrier.flak_cooldown <= 0.0 else "CYCLING %.1fs" % carrier.flak_cooldown
	var missile_status := "READY" if carrier.missile_cooldown <= 0.0 else "RELOAD %.1fs" % carrier.missile_cooldown
	var nuclear_status := "ARMED" if carrier.nuclear_available else "EXPENDED"
	var pd_status := "PD READY" if carrier.point_defense_cooldown <= 0.0 else "PD %.1fs" % carrier.point_defense_cooldown
	if is_finite(carrier.point_defense_last_tti):
		pd_status += " / TTI %.1fs" % carrier.point_defense_last_tti
	weapon_label.text = "[1] FLAK WALL  //  LOCK DIRECTED  •  %s  •  %.1f km  •  HAZARD R %.0fm\n[2] MISSILES  //  %s  •  %d WEAPONS  •  %.1f km  •  %s\n[3] NUCLEAR  //  %s  •  ARM %.1f km  •  BLAST %.0fm" % [flak_status, carrier.flak_weapon.range_m / 1000.0, carrier.flak_airburst_radius_m, missile_status, carrier.missile_salvo_count, carrier.missile_weapon.range_m / 1000.0, pd_status, nuclear_status, carrier.nuclear_arming_distance_m / 1000.0, carrier.nuclear_blast_radius_m]
	_update_carrier_operations_summary()
	var graphics := get_node_or_null("/root/GraphicsQualityManager")
	radar_title.text = "TACTICAL RADAR // %s" % (graphics.profile_label() if graphics != null else "ACTIVE")
	mode_label.text = "TACTICAL MAP - LIVE" if tactical.enabled else "COMMAND VIEW  //  THROTTLE %03d%%  //  ZOOM %+d%%" % [carrier.throttle_percent(), carrier.chase_zoom_percent()]
	overview_refresh_seconds -= delta
	if overview_refresh_seconds <= 0.0:
		overview_refresh_seconds = 0.25
		_refresh_overview()
	_update_target_presentation()
	if tactical.enabled:
		telemetry_panel.visible = false
		wing_panel.visible = false
		weapon_panel.visible = false
		carrier_operations_panel.visible = true
		crosshair_label.visible = false
		objective_panel.visible = false
		map_info_panel.visible = true
		mode_panel.visible = true
		map_info_label.text = _map_information()
		controls_label.text = "1 FLAK WALL  %s OPS  F1-F4 GROUPS  LMB SELECT  RMB WHEEL  SHIFT QUEUE  SHIFT+MMB PAN  HOME CARRIER  WHEEL ZOOM" % _operations_key_label()
	else:
		telemetry_panel.visible = true
		wing_panel.visible = true
		weapon_panel.visible = true
		carrier_operations_panel.visible = true
		crosshair_label.visible = false
		objective_panel.visible = true
		map_info_panel.visible = false
		mode_panel.visible = true
		controls_label.text = "LOCK + 1 FLAK WALL   2 MISSILES   3 NUCLEAR   %s OPS   B ALL WINGS   Z SQUADRON MENU   X WATCHER EW/SCOUT   TAB MAP" % _operations_key_label()
	if notification_time > 0.0:
		notification_time -= delta
		if notification_time <= 0.0:
			notification_label.text = ""
			notification_panel.visible = false

func bind_carrier_operations(state: Object) -> void:
	carrier_operations_state = state
	if carrier_operations_state != null and carrier_operations_state.has_signal(&"changed"):
		var callback := Callable(self, "_on_carrier_operations_changed")
		if not carrier_operations_state.is_connected(&"changed", callback):
			carrier_operations_state.connect(&"changed", callback)
	_update_carrier_operations_summary()

func _on_carrier_operations_changed(_reason: StringName = &"") -> void:
	_update_carrier_operations_summary()

func _update_carrier_operations_summary() -> void:
	if carrier_operations_label == null:
		return
	carrier_operations_button.text = "OPEN %s" % _operations_key_tag()
	if carrier_operations_state == null:
		carrier_operations_label.text = "%s BALANCED  //  8 / 8 POWER\nCREW 240  //  STORES NOMINAL" % _operations_key_tag()
		return
	var preset := String(_operations_value([&"current_power_preset", &"power_preset", &"current_preset"], "balanced")).replace("_", " ").to_upper()
	var available := int(_operations_value([&"available_power_points", &"available_power", &"available_reactor_points", &"power_budget"], 8))
	var crew := int(_operations_value([&"crew", &"surviving_crew", &"crew_current"], 240))
	var hazards = _operations_value([&"hazards", &"active_hazards"], {})
	var hazard_count := 0
	if hazards is Dictionary:
		for value in hazards.values():
			if value is Array:
				hazard_count += value.size()
			elif value is Dictionary:
				for active in value.values():
					hazard_count += 1 if bool(active) else 0
			elif value != null and bool(value):
				hazard_count += 1
	var trapped := _active_operations_incident()
	if not trapped.is_empty():
		carrier_operations_label.text = "%s %s  //  %d / 8 POWER\nRESCUE %s // %s // %.1fs" % [
			_operations_key_tag(), preset, available,
			String(trapped.get("display_name", "OFFICER")).to_upper(),
			String(trapped.get("subsystem", "SYSTEM")).replace("_", " ").to_upper(),
			maxf(0.0, float(trapped.get("time_remaining", 0.0))),
		]
		carrier_operations_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.22))
	else:
		var warning := "STORES / INTERNALS NOMINAL" if hazard_count == 0 else "%d INTERNAL WARNING%s" % [hazard_count, "" if hazard_count == 1 else "S"]
		carrier_operations_label.text = "%s %s  //  %d / 8 POWER\nCREW %d  //  %s" % [_operations_key_tag(), preset, available, crew, warning]
		carrier_operations_label.add_theme_color_override("font_color", UIStyle.TEXT_PRIMARY if hazard_count == 0 else UIStyle.AMBER)

func _active_operations_incident() -> Dictionary:
	var incidents = _operations_value([&"officer_incidents"], [])
	if incidents is Array:
		for incident in incidents:
			if incident is Dictionary and String((incident as Dictionary).get("outcome", "")) == "trapped":
				return incident
	return {}


func _operations_key_label() -> String:
	return ExodriftInputSettings.key_label("carrier_operations")


func _operations_key_tag() -> String:
	return "[%s]" % _operations_key_label()

func _operations_value(names: Array[StringName], fallback):
	for entry in carrier_operations_state.get_property_list():
		var property_name := StringName(entry.name)
		if names.has(property_name):
			var value = carrier_operations_state.get(property_name)
			if value != null:
				return value
	for method_name in names:
		if carrier_operations_state.has_method(method_name):
			return carrier_operations_state.call(method_name)
	return fallback

func notify(message: String) -> void:
	notification_label.text = message
	notification_time = 3.5
	notification_panel.visible = true

func _refresh_overview() -> void:
	if overview_rows.is_empty() or sensors == null:
		return
	var contacts: Array[SensorContact] = []
	for contact in sensors.contacts.values():
		if contact is SensorContact and contact.confidence > 0.04:
			contacts.append(contact)
	contacts.sort_custom(func(a: SensorContact, b: SensorContact) -> bool:
		return carrier.global_position.distance_squared_to(a.estimated_position) < carrier.global_position.distance_squared_to(b.estimated_position)
	)
	for index in overview_rows.size():
		var row := overview_rows[index]
		if index >= contacts.size():
			overview_contact_ids[index] = &""
			row.text = "—  NO TRACK"
			row.disabled = true
			continue
		var contact := contacts[index]
		overview_contact_ids[index] = contact.tracked_entity_id
		row.disabled = false
		var target := sensors.resolve_combat_target(contact.tracked_entity_id)
		var target_name := target.display_name if is_instance_valid(target) else String(contact.classification).capitalize()
		var range_m := carrier.global_position.distance_to(contact.estimated_position)
		var relative := contact.estimated_velocity - carrier.velocity
		var line_of_sight := carrier.global_position.direction_to(contact.estimated_position)
		var closing_speed := -relative.dot(line_of_sight)
		var state := "ID" if contact.is_targetable() else ("CL" if contact.identification_state == SensorContact.IdentificationState.CLASSIFIED else "??")
		var selected_marker := ">" if overview_selected_id == contact.tracked_entity_id else " "
		row.text = "%s %-13s %5.1fK  %+4.0fM/S  %s" % [selected_marker, target_name.left(13).to_upper(), range_m / 1000.0, closing_speed, state]
		row.add_theme_color_override("font_color", UIStyle.AMBER if overview_selected_id == contact.tracked_entity_id else UIStyle.TEXT_PRIMARY)

func _select_overview_row(index: int) -> void:
	if index < 0 or index >= overview_contact_ids.size():
		return
	var entity_id := overview_contact_ids[index]
	if entity_id.is_empty():
		return
	overview_selected_id = entity_id
	_refresh_overview()

func _on_overview_row_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	if index < 0 or index >= overview_contact_ids.size():
		return
	var entity_id := overview_contact_ids[index]
	if entity_id.is_empty():
		return
	overview_selected_id = entity_id
	open_target_context_menu(get_viewport().get_mouse_position(), entity_id)
	get_viewport().set_input_as_handled()

func open_target_context_menu(screen_position: Vector2, entity_id: StringName) -> void:
	var contact := sensors.get_contact(entity_id) if sensors != null else null
	if contact == null or not contact.is_targetable():
		notify("NAVIGATION MENU — identified combat track required")
		return
	context_target_id = entity_id
	overview_selected_id = entity_id
	target_context_menu.position = Vector2i(screen_position)
	target_context_menu.popup()

func _on_target_context_id_pressed(id: int) -> void:
	if id == CONTEXT_LOCK:
		target_lock_requested.emit(context_target_id)
		return
	if id == CONTEXT_CLEAR:
		target_navigation_requested.emit(&"clear", context_target_id, 0.0)
		return
	var command := &"orbit" if id in [CONTEXT_ORBIT_500, CONTEXT_ORBIT_5000, CONTEXT_ORBIT_10000, CONTEXT_ORBIT_25000] else (&"keep_distance" if id in [CONTEXT_KEEP_500, CONTEXT_KEEP_5000, CONTEXT_KEEP_10000, CONTEXT_KEEP_25000] else &"approach")
	var distance := 500.0
	if id in [CONTEXT_ORBIT_5000, CONTEXT_KEEP_5000]:
		distance = 5000.0
	elif id in [CONTEXT_ORBIT_10000, CONTEXT_KEEP_10000]:
		distance = 10000.0
	elif id in [CONTEXT_ORBIT_25000, CONTEXT_KEEP_25000]:
		distance = 25000.0
	target_navigation_requested.emit(command, context_target_id, distance)

func _issue_overview_command(command: StringName) -> void:
	if overview_selected_id.is_empty():
		notify("TACTICAL OVERVIEW — select a sensor track first")
		return
	if command == &"lock":
		target_lock_requested.emit(overview_selected_id)
	else:
		target_command_requested.emit(command, overview_selected_id)

func _wing_state(wing: SidebaySquadron) -> String:
	return "%s → REDEPLOY" % wing.operation.label() if wing.redeploy_requested else wing.operation.label()

func _fighter_group_health_percent() -> int:
	var weighted_health := 0.0
	var maximum_craft := 0
	for wing in fighter_squadrons:
		if not is_instance_valid(wing):
			continue
		var wing_capacity := wing.maximum_craft_count()
		weighted_health += wing.wing_health_fraction() * wing_capacity
		maximum_craft += wing_capacity
	return roundi(weighted_health / maxf(1.0, float(maximum_craft)) * 100.0)

func _fighter_group_living_craft() -> int:
	var total := 0
	for wing in fighter_squadrons:
		if is_instance_valid(wing):
			total += wing.living_craft_count()
	return total

func _fighter_group_deployed_count() -> int:
	var total := 0
	for wing in fighter_squadrons:
		if is_instance_valid(wing):
			total += wing.deployed_craft_count()
	return total

func _fighter_squadrons_out() -> int:
	var total := 0
	for wing in fighter_squadrons:
		if is_instance_valid(wing) and wing.operation.state in [BayOperation.State.QUEUED, BayOperation.State.LAUNCHING, BayOperation.State.DEPLOYED, BayOperation.State.RETURNING, BayOperation.State.APPROACH, BayOperation.State.DOCKING]:
			total += 1
	return total

func _fighter_squadrons_ready() -> int:
	var total := 0
	for wing in fighter_squadrons:
		if is_instance_valid(wing) and wing.operation.state == BayOperation.State.READY:
			total += 1
	return total

func _group_order_label(group: Node) -> String:
	if not is_instance_valid(group) or not group.has_method("command_snapshot"):
		return "NO ORDER"
	var snapshot: Dictionary = group.command_snapshot()
	var current: Dictionary = snapshot.get("current_order", {})
	return "%s/%s" % [String(current.get("type", "Hold")).to_upper(), String(snapshot.get("stance", "balanced")).to_upper()]

func set_objective(message: String) -> void:
	objective_label.text = "OBJECTIVE  %s" % message

func _map_information() -> String:
	if tactical.selected == null:
		return "SELECTED  NONE\n\nF1 CARRIER  F2 ESCORT\nF3 INTERCEPTORS  F4 SCOUTS\n\nCONTACTS  %d" % sensors.contacts.size()
	var selected_name: String = tactical.selected.display_name if "display_name" in tactical.selected else tactical.selected.name
	var snapshot: Dictionary = tactical.selected.command_snapshot() if tactical.selected.has_method("command_snapshot") else {}
	var current: Dictionary = snapshot.get("current_order", {})
	var queue: Array = snapshot.get("queue", [])
	var transmitting: Array = snapshot.get("transmitting", [])
	var queue_lines: Array[String] = []
	for index in mini(5, queue.size()):
		queue_lines.append("%d  %s  %s" % [index + 1, String(queue[index].get("type", "Order")).to_upper(), String(queue[index].get("status", "Queued")).to_upper()])
	if queue_lines.is_empty():
		queue_lines.append("—  QUEUE EMPTY")
	var transmission := ""
	if not transmitting.is_empty():
		transmission = "\nTX  %s  %.1fs" % [String(transmitting[0].get("type", "Order")).to_upper(), float(transmitting[0].get("seconds_remaining", 0.0))]
	return "SELECTED  %s\nLINK  %s%s\nORDER  %s  //  %s\nDOCTRINE  %s\nFORMATION  %s / %s\nLEADER  %s\n\nORDER QUEUE\n%s\n\nCONTACTS  %d" % [
		selected_name, String(snapshot.get("link", "Local")).to_upper(), transmission,
		String(current.get("type", "Hold")).to_upper(), String(current.get("status", "Active")).to_upper(),
		String(snapshot.get("stance", "balanced")).to_upper(), String(snapshot.get("formation", "wedge")).to_upper(), String(snapshot.get("spacing", "standard")).to_upper(),
		String(snapshot.get("leader_id", "—")).to_upper(), "\n".join(queue_lines), sensors.contacts.size()
	]

func update_target(contact: SensorContact, target_name: String = "", target_ship: CombatShip = null) -> void:
	if contact == null:
		locked_target = null
		target_label.text = "NO VALID TRACK\n\nMISSILE LOCK\nUNAVAILABLE"
		target_shield_bar.value = 0.0
		target_armor_bar.value = 0.0
		target_hull_bar.value = 0.0
		target_indicator.visible = false
		target_reticle.visible = false
		target_caption.visible = false
		return
	locked_target = target_ship
	overview_selected_id = contact.tracked_entity_id
	var state: String = SensorContact.IdentificationState.keys()[contact.identification_state]
	var distance := carrier.global_position.distance_to(target_ship.global_position) if is_instance_valid(target_ship) else carrier.global_position.distance_to(contact.estimated_position)
	var relative_speed := (contact.estimated_velocity - carrier.velocity).length()
	target_label.text = "LOCKED  //  %s\n%s  •  CONF %d%%\nRANGE %.0f m  •  REL %.0f m/s\nERROR ±%.0f m" % [target_name if not target_name.is_empty() else String(contact.classification).capitalize(), state, contact.confidence * 100.0, distance, relative_speed, contact.uncertainty_radius_m]

func _update_target_presentation() -> void:
	if not is_instance_valid(locked_target):
		target_indicator.visible = false
		target_reticle.visible = false
		target_caption.visible = false
		return
	var layers := locked_target.layer_percentages()
	target_shield_bar.value = layers.x * 100.0
	target_armor_bar.value = layers.y * 100.0
	target_hull_bar.value = layers.z * 100.0
	var camera := tactical.camera if tactical.enabled else carrier.chase_camera
	if not is_instance_valid(camera):
		target_indicator.visible = false
		target_reticle.visible = false
		target_caption.visible = false
		return
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
		target_indicator.visible = false
		var radius_point := locked_target.global_position + camera.global_transform.basis.x.normalized() * maxf(locked_target.collision_radius_m, 12.0)
		var screen_radius := camera.unproject_position(radius_point).distance_to(projected)
		var span := clampf(screen_radius * 2.5, 52.0, 132.0)
		var range_m := carrier.global_position.distance_to(locked_target.global_position)
		var in_envelope := carrier.missile_weapon != null and range_m <= carrier.missile_weapon.range_m
		var lock_color := UIStyle.CYAN if in_envelope else Color(1.0, 0.22, 0.16)
		var projectile_speed := carrier.missile_weapon.projectile_speed_mps if carrier.missile_weapon != null else 900.0
		var flight_time := range_m / maxf(projectile_speed, 1.0)
		var lead_world := locked_target.global_position + locked_target.velocity * flight_time
		var lead_screen := camera.unproject_position(lead_world)
		target_reticle.position = projected - target_reticle.size * 0.5
		target_reticle.set_solution(span, lock_color, lead_screen - projected, true)
		target_reticle.visible = true
		var relative_speed := (locked_target.velocity - carrier.velocity).length()
		target_caption.text = "%s  //  %.1f KM  //  ΔV %.0f M/S  //  TTI %.1fs" % [locked_target.display_name.to_upper(), range_m / 1000.0, relative_speed, flight_time]
		target_caption.position = projected + Vector2(-92.0, span * 0.5 + 10.0)
		target_caption.visible = true
	else:
		target_reticle.visible = false
		target_caption.visible = false
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
			"training":
				summary = "COMBAT TRIAL COMPLETE\nTarget dummy disabled — systems qualified"
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
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", UIStyle.hud_panel_style(color, accent))
	panel.set_meta("military_hud_frame", true)
	parent.add_child(panel)
	_add_frame_marks(panel, accent)
	return panel

func _add_frame_marks(panel: Panel, accent: Color) -> void:
	var top_mark := Polygon2D.new()
	top_mark.polygon = PackedVector2Array([Vector2(0, 0), Vector2(38, 0), Vector2(31, 3), Vector2(0, 3)])
	top_mark.color = Color(accent.r, accent.g, accent.b, 0.9)
	top_mark.set_meta("collapsible_chrome", true)
	panel.add_child(top_mark)
	var lower_mark := Polygon2D.new()
	lower_mark.position = Vector2(panel.size.x - 38.0, panel.size.y - 3.0)
	lower_mark.polygon = PackedVector2Array([Vector2(7, 0), Vector2(38, 0), Vector2(38, 3), Vector2(0, 3)])
	lower_mark.color = Color(accent.r, accent.g, accent.b, 0.52)
	lower_mark.set_meta("collapsible_chrome", true)
	panel.add_child(lower_mark)

func _collapsible_heading(panel: Panel, title: String, accent: Color) -> Button:
	var heading := Button.new()
	heading.name = "%sCollapse" % title.replace(" ", "")
	heading.position = Vector2(8.0, 3.0)
	heading.size = Vector2(panel.size.x - 16.0, 19.0)
	heading.text = "[-]  %s" % title
	heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.toggle_mode = true
	heading.button_pressed = true
	heading.flat = true
	heading.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	heading.add_theme_font_size_override("font_size", 10)
	heading.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.94))
	heading.add_theme_color_override("font_hover_color", Color.WHITE)
	heading.add_theme_color_override("font_pressed_color", Color(accent.r, accent.g, accent.b, 1.0))
	heading.set_meta("collapsible_chrome", true)
	panel.add_child(heading)
	heading.toggled.connect(_set_panel_expanded.bind(panel, heading, title))
	var line := ColorRect.new()
	line.position = Vector2(14.0, 21.0)
	line.size = Vector2(panel.size.x - 28.0, 1.0)
	line.color = Color(accent.r, accent.g, accent.b, 0.48)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_meta("collapsible_chrome", true)
	panel.add_child(line)
	return heading

func _register_collapsible(panel: Panel) -> void:
	var body: Array[CanvasItem] = []
	for child in panel.get_children():
		if child is CanvasItem and not bool(child.get_meta("collapsible_chrome", false)):
			body.append(child)
	collapsible_panels[panel.get_instance_id()] = {
		"expanded_height": panel.size.y,
		"body": body,
		"expanded": true,
	}

func _set_panel_expanded(expanded: bool, panel: Panel, heading: Button, title: String) -> void:
	if not collapsible_panels.has(panel.get_instance_id()):
		return
	var state: Dictionary = collapsible_panels[panel.get_instance_id()]
	state.expanded = expanded
	collapsible_panels[panel.get_instance_id()] = state
	heading.text = "%s  %s" % ["[-]" if expanded else "[+]", title]
	for child in state.body:
		if is_instance_valid(child):
			child.visible = expanded
	panel.size.y = float(state.expanded_height) if expanded else 25.0

func _overview_button(parent: Control, position_value: Vector2, size_value: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.position = position_value
	button.size = size_value
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", UIStyle.TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", UIStyle.CYAN)
	button.add_theme_color_override("font_pressed_color", UIStyle.AMBER)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.01, 0.05, 0.075, 0.74)
	normal.border_color = Color(0.12, 0.4, 0.55, 0.42)
	normal.set_border_width_all(1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.025, 0.13, 0.18, 0.92)
	hover.border_color = Color(UIStyle.CYAN.r, UIStyle.CYAN.g, UIStyle.CYAN.b, 0.72)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)
	parent.add_child(button)
	return button

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
