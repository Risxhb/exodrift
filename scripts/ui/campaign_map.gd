class_name SidebayCampaignMap
extends Control

const UIStyle := preload("res://scripts/ui/ui_style.gd")

const MAP_RECT := Rect2(16.0, 128.0, 844.0, 528.0)
const DOSSIER_POSITION := Vector2(876.0, 128.0)
const DOSSIER_SIZE := Vector2(388.0, 528.0)
const DEPLOYMENT_POSITION := Vector2(34.0, 388.0)
const SECTOR_SPACING := 277.0
const COLUMN_SPACING := 87.0
const NODE_ORIGIN := Vector2(88.0, 246.0)
const ROW_SPACING := 142.0

signal node_selected(node_id: StringName)
signal new_run_requested
signal save_requested
signal load_requested
signal forecast_requested
signal fleet_requested
signal logistics_requested
signal personnel_requested
signal playtest_requested
signal title_requested

var run_state: SidebayRunState
var generator: SidebayCampaignGenerator
var node_buttons: Dictionary = {}
var selected_node_id: StringName = &""
var resource_label: Label
var status_label: Label
var run_label: Label
var dossier_panel: Panel
var dossier_kicker: Label
var mission_name_label: Label
var mission_type_label: Label
var mission_description_label: Label
var objective_value_label: Label
var threat_value_label: Label
var route_value_label: Label
var reward_value_label: Label
var confidence_value_label: Label
var route_status_label: Label
var course_button: Button
var system_panel: Panel
var restart_confirmation_panel: Panel
var forecast_button: Button
var presentation_tween: Tween
var elapsed: float = 0.0
var course_locked: bool = false

func configure(state: SidebayRunState, campaign_generator: SidebayCampaignGenerator) -> void:
	run_state = state
	generator = campaign_generator
	_build_shell()
	refresh()

func _process(delta: float) -> void:
	elapsed += delta
	if visible:
		queue_redraw()

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var background := ColorRect.new()
	background.name = "StrategicBackdrop"
	background.color = Color(0.002, 0.007, 0.015, 1.0)
	background.show_behind_parent = true
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var header := Panel.new()
	header.name = "CommandHeader"
	header.position = Vector2(16.0, 14.0)
	header.size = Vector2(1248.0, 98.0)
	header.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.004, 0.019, 0.032, 0.96), UIStyle.CYAN_SOFT, 1, 4))
	add_child(header)

	var title := _label(Vector2(16.0, 8.0), Vector2(390.0, 32.0), 23, header)
	title.name = "OperationTitle"
	title.text = "OPERATION DEEP STRIKE"
	var subtitle := _label(Vector2(17.0, 38.0), Vector2(390.0, 20.0), 11, header, UIStyle.TEXT_MUTED)
	subtitle.text = "FLEET NAVIGATION // HELIOS REACH"

	resource_label = _label(Vector2(17.0, 65.0), Vector2(610.0, 20.0), 14, header)
	run_label = _label(Vector2(405.0, 66.0), Vector2(370.0, 18.0), 10, header, UIStyle.TEXT_MUTED)
	run_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var fleet_button := _button("FLEET", Vector2(622.0, 17.0), Vector2(88.0, 38.0), header, 12)
	fleet_button.pressed.connect(func() -> void: fleet_requested.emit())
	var logistics_button := _button("LOGISTICS", Vector2(718.0, 17.0), Vector2(102.0, 38.0), header, 12)
	logistics_button.pressed.connect(func() -> void: logistics_requested.emit())
	var personnel_button := _button("PERSONNEL", Vector2(828.0, 17.0), Vector2(108.0, 38.0), header, 12)
	personnel_button.pressed.connect(func() -> void: personnel_requested.emit())
	forecast_button = _button("DEEP FORECAST  [1 INTEL]", Vector2(944.0, 17.0), Vector2(194.0, 38.0), header, 12)
	forecast_button.name = "ForecastButton"
	forecast_button.pressed.connect(func() -> void: forecast_requested.emit())
	var system_button := _button("SYSTEM", Vector2(1146.0, 17.0), Vector2(86.0, 38.0), header, 12)
	system_button.pressed.connect(_toggle_system_panel)

	for sector in 3:
		var sector_label := _label(Vector2(27.0 + sector * SECTOR_SPACING, 145.0), Vector2(250.0, 27.0), 14)
		sector_label.text = ["SECTOR I  //  OUTER LINE", "SECTOR II  //  CONTESTED", "SECTOR III  //  COMMAND ZONE"][sector]
		sector_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var command_kicker := _label(Vector2(32.0, 612.0), Vector2(134.0, 22.0), 10, self, UIStyle.CYAN)
	command_kicker.text = "COMMAND LOG  //"
	status_label = _label(Vector2(158.0, 609.0), Vector2(682.0, 30.0), 13)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_build_dossier()
	_build_system_panel()

func _build_dossier() -> void:
	dossier_panel = Panel.new()
	dossier_panel.name = "MissionDossier"
	dossier_panel.position = DOSSIER_POSITION
	dossier_panel.size = DOSSIER_SIZE
	var dossier_style := UIStyle.panel_style(Color(0.005, 0.022, 0.038, 0.98), Color(0.08, 0.55, 0.72), 1, 4)
	dossier_style.border_width_left = 3
	dossier_style.shadow_size = 14
	dossier_panel.add_theme_stylebox_override("panel", dossier_style)
	add_child(dossier_panel)

	dossier_kicker = _label(Vector2(24.0, 20.0), Vector2(336.0, 20.0), 10, dossier_panel, UIStyle.CYAN)
	dossier_kicker.text = "MISSION DOSSIER  //  AWAITING SELECTION"
	mission_name_label = _label(Vector2(22.0, 45.0), Vector2(342.0, 42.0), 27, dossier_panel)
	mission_name_label.text = "SELECT A ROUTE"
	mission_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mission_type_label = _label(Vector2(24.0, 87.0), Vector2(336.0, 25.0), 13, dossier_panel, UIStyle.AMBER)
	mission_type_label.text = "NO TRACK SELECTED"

	var divider := ColorRect.new()
	divider.color = Color(0.08, 0.52, 0.68, 0.48)
	divider.position = Vector2(24.0, 119.0)
	divider.size = Vector2(340.0, 1.0)
	dossier_panel.add_child(divider)

	mission_description_label = _label(Vector2(24.0, 132.0), Vector2(340.0, 82.0), 13, dossier_panel, UIStyle.TEXT_MUTED)
	mission_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	mission_description_label.text = "Select a confirmed route marker to review mission intelligence and commit the fleet."

	_add_dossier_row("OBJECTIVE", 226.0)
	objective_value_label = _dossier_value(226.0)
	_add_dossier_row("THREAT", 267.0)
	threat_value_label = _dossier_value(267.0)
	_add_dossier_row("ROUTE COST", 308.0)
	route_value_label = _dossier_value(308.0)
	_add_dossier_row("EXPECTED YIELD", 349.0)
	reward_value_label = _dossier_value(349.0)
	_add_dossier_row("INTELLIGENCE", 390.0)
	confidence_value_label = _dossier_value(390.0)

	route_status_label = _label(Vector2(24.0, 430.0), Vector2(340.0, 42.0), 12, dossier_panel, UIStyle.TEXT_MUTED)
	route_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	route_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	route_status_label.text = "No navigation solution selected."

	course_button = _button("SELECT A ROUTE", Vector2(24.0, 474.0), Vector2(340.0, 38.0), dossier_panel, 15)
	course_button.name = "PlotCourseButton"
	course_button.disabled = true
	course_button.pressed.connect(_confirm_course)

func _add_dossier_row(caption: String, y_position: float) -> void:
	var label := _label(Vector2(24.0, y_position), Vector2(116.0, 26.0), 10, dossier_panel, UIStyle.TEXT_MUTED)
	label.text = caption
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var line := ColorRect.new()
	line.color = Color(0.05, 0.24, 0.32, 0.58)
	line.position = Vector2(24.0, y_position + 30.0)
	line.size = Vector2(340.0, 1.0)
	dossier_panel.add_child(line)

func _dossier_value(y_position: float) -> Label:
	var label := _label(Vector2(140.0, y_position), Vector2(224.0, 26.0), 13, dossier_panel)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "--"
	return label

func _build_system_panel() -> void:
	system_panel = Panel.new()
	system_panel.name = "SystemMenu"
	system_panel.position = Vector2(1028.0, 111.0)
	system_panel.size = Vector2(220.0, 252.0)
	system_panel.z_index = 50
	system_panel.visible = false
	var style := UIStyle.panel_style(Color(0.004, 0.018, 0.032, 0.99), UIStyle.CYAN, 1, 4)
	style.shadow_size = 18
	system_panel.add_theme_stylebox_override("panel", style)
	add_child(system_panel)
	var title := _label(Vector2(16.0, 12.0), Vector2(188.0, 24.0), 11, system_panel, UIStyle.CYAN)
	title.text = "OPERATION SYSTEM"
	var debrief_button := _button("DEBRIEF", Vector2(16.0, 43.0), Vector2(188.0, 34.0), system_panel, 12)
	debrief_button.pressed.connect(func() -> void: _close_system_panel(); playtest_requested.emit())
	var save_button := _button("SAVE CHECKPOINT", Vector2(16.0, 83.0), Vector2(188.0, 34.0), system_panel, 12)
	save_button.pressed.connect(func() -> void: _close_system_panel(); save_requested.emit())
	var load_button := _button("LOAD CHECKPOINT", Vector2(16.0, 123.0), Vector2(188.0, 34.0), system_panel, 12)
	load_button.pressed.connect(func() -> void: _close_system_panel(); load_requested.emit())
	var new_button := _button("NEW OPERATION", Vector2(16.0, 163.0), Vector2(188.0, 34.0), system_panel, 12, UIStyle.AMBER)
	new_button.pressed.connect(_show_restart_confirmation)
	var title_button := _button("RETURN TO TITLE", Vector2(16.0, 203.0), Vector2(188.0, 34.0), system_panel, 12)
	title_button.pressed.connect(func() -> void: _close_system_panel(); title_requested.emit())

	restart_confirmation_panel = Panel.new()
	restart_confirmation_panel.name = "RestartConfirmation"
	restart_confirmation_panel.position = Vector2(1028.0, 111.0)
	restart_confirmation_panel.size = Vector2(220.0, 210.0)
	restart_confirmation_panel.z_index = 51
	restart_confirmation_panel.visible = false
	var confirm_style := UIStyle.panel_style(Color(0.018, 0.012, 0.014, 0.995), UIStyle.AMBER, 1, 4)
	confirm_style.shadow_size = 18
	restart_confirmation_panel.add_theme_stylebox_override("panel", confirm_style)
	add_child(restart_confirmation_panel)
	var confirm_title := _label(Vector2(16.0, 14.0), Vector2(188.0, 24.0), 12, restart_confirmation_panel, UIStyle.AMBER)
	confirm_title.text = "RESTART OPERATION?"
	var warning := _label(Vector2(16.0, 43.0), Vector2(188.0, 76.0), 11, restart_confirmation_panel, UIStyle.TEXT_MUTED)
	warning.text = "Current progress will be replaced after preserving the latest checkpoint backup."
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var confirm_button := _button("CONFIRM RESTART", Vector2(16.0, 126.0), Vector2(188.0, 32.0), restart_confirmation_panel, 11, UIStyle.AMBER)
	confirm_button.pressed.connect(func() -> void: _close_system_panel(); new_run_requested.emit())
	var cancel_button := _button("CANCEL", Vector2(16.0, 164.0), Vector2(188.0, 32.0), restart_confirmation_panel, 11)
	cancel_button.pressed.connect(_cancel_restart_confirmation)

func refresh() -> void:
	if run_state == null or generator == null:
		return
	course_locked = false
	for button in node_buttons.values():
		button.queue_free()
	node_buttons.clear()

	var reachable := generator.reachable_node_ids(run_state)
	if not reachable.has(selected_node_id):
		selected_node_id = _default_selection(reachable)

	for node_value in generator.nodes.values():
		var node: SidebayCampaignNode = node_value
		var completed := run_state.completed_node_ids.has(node.node_id)
		var connected := reachable.has(node.node_id)
		var accessible := connected and run_state.can_afford_route(node.fuel_cost) and not run_state.run_completed and not run_state.run_failed
		var revealed := connected or completed or run_state.revealed_node_ids.has(node.node_id)
		var button_size := _node_button_size(completed, connected, revealed)
		var button_position := _node_position(node) - button_size * 0.5
		if connected and node.column == 0:
			button_position.x -= 8.0
		var button := _button(_node_button_text(node, revealed, completed, connected), button_position, button_size, self, 10 if connected else 11)
		button.name = String(node.node_id)
		button.z_index = 6 if connected else (4 if completed else 2)
		button.disabled = not revealed
		button.tooltip_text = _node_tooltip(node, revealed, accessible, connected)
		button.set_meta("node_id", node.node_id)
		button.set_meta("completed", completed)
		button.set_meta("connected", connected)
		button.set_meta("accessible", accessible)
		button.set_meta("revealed", revealed)
		button.pressed.connect(_select_node.bind(node.node_id))
		button.focus_entered.connect(_select_node.bind(node.node_id))
		_apply_node_style(button, node, completed, accessible, revealed, connected, node.node_id == selected_node_id)
		node_buttons[node.node_id] = button

	resource_label.text = "SUP %03d    FUEL %02d    INTEL %02d    REQ %02d    SALV %03d" % [run_state.supplies, run_state.fuel, run_state.intel, run_state.requisition, run_state.salvage_stock]
	run_label.text = "RUN %s  //  %s" % [run_state.run_id, String(run_state.active_logistics_posture_data().get("name", "Balanced Stores")).to_upper()]
	forecast_button.disabled = run_state.intel < 1 or run_state.run_completed or run_state.run_failed

	if run_state.run_completed:
		status_label.text = "Operation complete. Strategic command has been destroyed."
	elif run_state.run_failed:
		status_label.text = "Operation failed. Carrier command link lost."
	elif reachable.is_empty():
		status_label.text = "No navigation routes remain available."
	_update_dossier()
	queue_redraw()

func present(message: String, emphasize_routes: bool = false) -> void:
	visible = true
	set_status(message)
	if presentation_tween != null and presentation_tween.is_valid():
		presentation_tween.kill()
	if DisplayServer.get_name() == "headless":
		modulate.a = 1.0
		dossier_panel.position = DOSSIER_POSITION
		dossier_panel.modulate.a = 1.0
		return
	if emphasize_routes:
		modulate.a = 1.0
		dossier_panel.position = DOSSIER_POSITION + Vector2(24.0, 0.0)
		dossier_panel.modulate.a = 0.0
		presentation_tween = create_tween().set_parallel(true)
		presentation_tween.tween_property(dossier_panel, "position", DOSSIER_POSITION, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		presentation_tween.tween_property(dossier_panel, "modulate:a", 1.0, 0.24)
	else:
		modulate.a = 0.0
		dossier_panel.position = DOSSIER_POSITION + Vector2(20.0, 0.0)
		presentation_tween = create_tween().set_parallel(true)
		presentation_tween.tween_property(self, "modulate:a", 1.0, 0.35)
		presentation_tween.tween_property(dossier_panel, "position", DOSSIER_POSITION, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message

func replace_state(state: SidebayRunState, campaign_generator: SidebayCampaignGenerator) -> void:
	run_state = state
	generator = campaign_generator
	refresh()

func _default_selection(reachable: Array[StringName]) -> StringName:
	for node_id in reachable:
		var node := generator.get_node(node_id)
		if node != null and run_state.can_afford_route(node.fuel_cost):
			return node_id
	return reachable[0] if not reachable.is_empty() else &""

func _select_node(node_id: StringName) -> void:
	if course_locked or generator == null:
		return
	var node := generator.get_node(node_id)
	if node == null:
		return
	var reachable := generator.reachable_node_ids(run_state)
	var revealed := reachable.has(node_id) or run_state.completed_node_ids.has(node_id) or run_state.revealed_node_ids.has(node_id)
	if not revealed:
		return
	selected_node_id = node_id
	for candidate in node_buttons.values():
		var candidate_id: StringName = candidate.get_meta("node_id", &"")
		var candidate_node := generator.get_node(candidate_id)
		if candidate_node != null:
			_apply_node_style(candidate, candidate_node, bool(candidate.get_meta("completed", false)), bool(candidate.get_meta("accessible", false)), bool(candidate.get_meta("revealed", false)), bool(candidate.get_meta("connected", false)), candidate_id == selected_node_id)
	_update_dossier()
	queue_redraw()

func _confirm_course() -> void:
	if course_locked or selected_node_id == &"" or generator == null or run_state == null:
		return
	var node := generator.get_node(selected_node_id)
	var reachable := generator.reachable_node_ids(run_state)
	if node == null or not reachable.has(selected_node_id) or not run_state.can_afford_route(node.fuel_cost):
		_update_dossier()
		return
	course_locked = true
	course_button.disabled = true
	course_button.text = "COURSE LOCKED"
	status_label.text = "Navigation solution locked for %s. Fleet is committing." % node.display_name
	if DisplayServer.get_name() == "headless":
		node_selected.emit(selected_node_id)
		return
	var tween := create_tween()
	tween.tween_property(dossier_panel, "modulate", Color(0.72, 0.95, 1.0, 1.0), 0.12)
	tween.tween_interval(0.12)
	tween.tween_callback(func() -> void: node_selected.emit(selected_node_id))

func _update_dossier() -> void:
	if generator == null or run_state == null or selected_node_id == &"":
		_set_empty_dossier()
		return
	var node := generator.get_node(selected_node_id)
	if node == null:
		_set_empty_dossier()
		return
	var reachable := generator.reachable_node_ids(run_state)
	var connected := reachable.has(node.node_id)
	var completed := run_state.completed_node_ids.has(node.node_id)
	var accessible := connected and run_state.can_afford_route(node.fuel_cost) and not run_state.run_completed and not run_state.run_failed
	var forecast := run_state.revealed_node_ids.has(node.node_id) and not connected and not completed

	dossier_kicker.text = "DEPLOYMENT ROUTE  //  CONFIRMED" if run_state.current_node_id == &"" and connected else ("MISSION DOSSIER  //  FORECAST" if forecast else "MISSION DOSSIER  //  CONFIRMED")
	mission_name_label.text = node.display_name.to_upper()
	mission_type_label.text = "%s  //  %s" % [_node_icon(node), node.type_label().to_upper()]
	mission_type_label.add_theme_color_override("font_color", _node_accent(node))
	mission_description_label.text = _mission_description(node)
	objective_value_label.text = node.objective_label().to_upper() if node.is_battle() else _support_objective(node)
	threat_value_label.text = _threat_pips(node.threat)
	var fuel_cost := run_state.route_fuel_cost(node.fuel_cost)
	var supply_cost := run_state.route_supply_cost()
	route_value_label.text = "%d FUEL%s" % [fuel_cost, "  +  %d SUP" % supply_cost if supply_cost > 0 else ""]
	reward_value_label.text = _reward_text(node)
	confidence_value_label.text = "ROUTE-CONFIRMED" if connected else ("AFTER-ACTION RECORD" if completed else "DEEP FORECAST")

	if completed:
		route_status_label.text = "Operation resolved. This route is part of the fleet record."
		course_button.text = "OPERATION COMPLETE"
		course_button.disabled = true
	elif not connected:
		route_status_label.text = "Forecast available. This track is not connected to the current fleet position."
		course_button.text = "ROUTE UNAVAILABLE"
		course_button.disabled = true
	elif not accessible:
		route_status_label.text = "Navigation solution confirmed, but current route resources are insufficient."
		course_button.text = "INSUFFICIENT RESOURCES"
		course_button.disabled = true
	else:
		route_status_label.text = "Navigation solution ready. Committing will spend the quoted route resources."
		course_button.text = "PLOT COURSE"
		course_button.disabled = course_locked
		_apply_course_button_style(_node_accent(node))

func _set_empty_dossier() -> void:
	dossier_kicker.text = "MISSION DOSSIER  //  AWAITING SELECTION"
	mission_name_label.text = "SELECT A ROUTE"
	mission_type_label.text = "NO TRACK SELECTED"
	mission_description_label.text = "Select a confirmed route marker to review mission intelligence and commit the fleet."
	objective_value_label.text = "--"
	threat_value_label.text = "--"
	route_value_label.text = "--"
	reward_value_label.text = "--"
	confidence_value_label.text = "--"
	route_status_label.text = "No navigation solution selected."
	course_button.text = "SELECT A ROUTE"
	course_button.disabled = true

func _draw() -> void:
	# Layered navigation surface: sector lanes, plotting grid, and a restrained scan wash.
	draw_rect(MAP_RECT, Color(0.003, 0.015, 0.027, 0.98), true)
	draw_rect(MAP_RECT, Color(0.06, 0.38, 0.5, 0.78), false, 1.0)
	for sector in 3:
		var sector_rect := Rect2(24.0 + sector * SECTOR_SPACING, 177.0, 267.0, 420.0)
		var sector_tint: Color = [Color(0.02, 0.11, 0.16, 0.35), Color(0.09, 0.065, 0.13, 0.3), Color(0.13, 0.045, 0.05, 0.3)][sector]
		draw_rect(sector_rect, sector_tint, true)
		draw_line(Vector2(sector_rect.position.x, 177.0), Vector2(sector_rect.position.x, 597.0), Color(0.07, 0.24, 0.31, 0.44), 1.0)
	for row in 7:
		var y := 190.0 + row * 63.0
		draw_line(Vector2(25.0, y), Vector2(850.0, y), Color(0.035, 0.12, 0.16, 0.22), 1.0)

	if generator == null or run_state == null:
		return
	var reachable := generator.reachable_node_ids(run_state)
	if run_state.current_node_id == &"":
		for starting_id in generator.starting_node_ids:
			var starting_node := generator.get_node(starting_id)
			if starting_node != null:
				_draw_route(DEPLOYMENT_POSITION, _node_position(starting_node), starting_id, reachable, false)
		var deployment_pulse := 7.0 + sin(elapsed * 3.2) * 2.0
		draw_circle(DEPLOYMENT_POSITION, deployment_pulse, Color(0.2, 0.84, 1.0, 0.18), false, 2.0, true)
		draw_circle(DEPLOYMENT_POSITION, 4.0, UIStyle.CYAN, true)
		draw_colored_polygon(PackedVector2Array([DEPLOYMENT_POSITION + Vector2(-3.0, -7.0), DEPLOYMENT_POSITION + Vector2(8.0, 0.0), DEPLOYMENT_POSITION + Vector2(-3.0, 7.0)]), Color(0.66, 0.95, 1.0, 0.94))
	else:
		var current_node := generator.get_node(run_state.current_node_id)
		if current_node != null:
			var current_position := _node_position(current_node)
			var current_pulse := 27.0 + sin(elapsed * 3.2) * 3.0
			draw_circle(current_position, current_pulse, Color(0.2, 0.84, 1.0, 0.2), false, 2.0, true)
			draw_colored_polygon(PackedVector2Array([current_position + Vector2(-6.0, -10.0), current_position + Vector2(11.0, 0.0), current_position + Vector2(-6.0, 10.0)]), Color(0.62, 0.94, 1.0, 0.9))

	for node_value in generator.nodes.values():
		var node: SidebayCampaignNode = node_value
		for destination_id in node.connections:
			var destination := generator.get_node(destination_id)
			if destination != null:
				_draw_route(_node_position(node), _node_position(destination), destination_id, reachable, run_state.completed_node_ids.has(destination_id))

func _draw_route(from: Vector2, to: Vector2, destination_id: StringName, reachable: Array[StringName], completed: bool) -> void:
	if completed:
		draw_line(from, to, Color(0.08, 0.64, 0.82, 0.9), 3.0, true)
		return
	if reachable.has(destination_id):
		var selected := destination_id == selected_node_id
		var pulse := 0.72 + sin(elapsed * 4.0) * 0.16
		var color := Color(1.0, 0.58, 0.15, pulse) if selected else Color(0.12, 0.72, 0.94, pulse)
		draw_line(from, to, color, 3.0 if selected else 2.0, true)
		return
	var revealed := run_state.revealed_node_ids.has(destination_id) or run_state.completed_node_ids.has(destination_id)
	if revealed:
		draw_line(from, to, Color(0.08, 0.25, 0.33, 0.58), 1.5, true)
	else:
		draw_dashed_line(from, to, Color(0.05, 0.17, 0.23, 0.46), 1.0, 7.0, false, true)

func _node_position(node: SidebayCampaignNode) -> Vector2:
	return NODE_ORIGIN + Vector2(node.sector * SECTOR_SPACING + node.column * COLUMN_SPACING, node.row * ROW_SPACING)

func _node_button_size(completed: bool, connected: bool, revealed: bool) -> Vector2:
	if connected:
		return Vector2(112.0, 68.0)
	if completed:
		return Vector2(48.0, 48.0)
	if revealed:
		return Vector2(72.0, 42.0)
	return Vector2(30.0, 30.0)

func _node_button_text(node: SidebayCampaignNode, revealed: bool, completed: bool, connected: bool) -> String:
	if completed:
		return "OK"
	if not revealed:
		return "?"
	if not connected:
		return "%s\nT%d" % [_node_code(node), node.threat]
	var fuel_cost := run_state.route_fuel_cost(node.fuel_cost) if run_state != null else node.fuel_cost
	var supply_cost := run_state.route_supply_cost() if run_state != null else 0
	var mission_line := _compact_objective(node)
	return "%s\n%s  //  T%d\nF%d%s" % [node.display_name.to_upper(), mission_line, node.threat, fuel_cost, "  S%d" % supply_cost if supply_cost > 0 else ""]

func _node_tooltip(node: SidebayCampaignNode, revealed: bool, accessible: bool, connected: bool) -> String:
	if not revealed:
		return "Spend intel to reveal this forecast."
	var route_status := "Ready to plot" if accessible else ("Insufficient route resources" if connected else "Not on current route")
	return "%s // %s\nThreat %d // %s" % [node.display_name, node.objective_label() if node.is_battle() else node.type_label(), node.threat, route_status]

func _apply_node_style(button: Button, node: SidebayCampaignNode, completed: bool, accessible: bool, revealed: bool, connected: bool, selected: bool) -> void:
	var accent := _node_accent(node)
	var normal := StyleBoxFlat.new()
	if not revealed:
		normal.bg_color = Color(0.018, 0.04, 0.055, 0.92)
		normal.border_color = Color(0.12, 0.22, 0.27, 0.72)
		normal.set_corner_radius_all(15)
	elif completed:
		normal.bg_color = Color(0.035, 0.22, 0.28, 0.96)
		normal.border_color = Color(0.12, 0.68, 0.82, 0.8)
		normal.set_corner_radius_all(24)
	elif connected:
		normal.bg_color = Color(accent.r * 0.19, accent.g * 0.19, accent.b * 0.19, 0.98)
		normal.border_color = Color(1.0, 0.68, 0.24, 1.0) if selected else Color(accent.r, accent.g, accent.b, 0.95)
		normal.set_corner_radius_all(4)
		normal.shadow_color = Color(accent.r, accent.g, accent.b, 0.3 if selected else 0.14)
		normal.shadow_size = 9 if selected else 5
	else:
		normal.bg_color = Color(0.025, 0.065, 0.085, 0.95)
		normal.border_color = Color(accent.r, accent.g, accent.b, 0.38)
		normal.set_corner_radius_all(4)
	normal.set_border_width_all(2 if selected or connected else 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.32, 0.44, 0.5) if not revealed else Color(0.62, 0.76, 0.82))
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.disabled = not revealed
	if connected and not accessible:
		button.add_theme_color_override("font_color", Color(0.62, 0.7, 0.72))

func _apply_course_button_style(accent: Color) -> void:
	var normal := UIStyle.panel_style(Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.98), Color(accent.r, accent.g, accent.b, 0.92), 2, 4)
	var hover := UIStyle.panel_style(Color(accent.r * 0.24, accent.g * 0.24, accent.b * 0.24, 1.0), Color(1.0, 0.82, 0.4, 1.0), 2, 4)
	course_button.add_theme_stylebox_override("normal", normal)
	course_button.add_theme_stylebox_override("hover", hover)
	course_button.add_theme_stylebox_override("focus", hover)

func _node_accent(node: SidebayCampaignNode) -> Color:
	match node.node_type:
		SidebayCampaignNode.NodeType.COMBAT:
			return Color(0.96, 0.27, 0.12)
		SidebayCampaignNode.NodeType.BOSS:
			return Color(1.0, 0.49, 0.12)
		SidebayCampaignNode.NodeType.SALVAGE:
			return Color(0.95, 0.66, 0.15)
		SidebayCampaignNode.NodeType.REPAIR:
			return Color(0.18, 0.78, 0.48)
		SidebayCampaignNode.NodeType.INTEL:
			return Color(0.55, 0.42, 1.0)
	return UIStyle.CYAN

func _node_icon(node: SidebayCampaignNode) -> String:
	match node.node_type:
		SidebayCampaignNode.NodeType.COMBAT:
			return "HOSTILE CONTACT"
		SidebayCampaignNode.NodeType.BOSS:
			return "COMMAND TARGET"
		SidebayCampaignNode.NodeType.SALVAGE:
			return "RECOVERY FIELD"
		SidebayCampaignNode.NodeType.REPAIR:
			return "FLEET SUPPORT"
		SidebayCampaignNode.NodeType.INTEL:
			return "SIGNAL INTERCEPT"
	return "NAVIGATION TRACK"

func _node_code(node: SidebayCampaignNode) -> String:
	match node.node_type:
		SidebayCampaignNode.NodeType.COMBAT:
			return "COM"
		SidebayCampaignNode.NodeType.BOSS:
			return "CMD"
		SidebayCampaignNode.NodeType.SALVAGE:
			return "SAL"
		SidebayCampaignNode.NodeType.REPAIR:
			return "REP"
		SidebayCampaignNode.NodeType.INTEL:
			return "INT"
	return "UNK"

func _support_objective(node: SidebayCampaignNode) -> String:
	match node.node_type:
		SidebayCampaignNode.NodeType.SALVAGE:
			return "RECOVERY"
		SidebayCampaignNode.NodeType.REPAIR:
			return "FLEET SERVICE"
		SidebayCampaignNode.NodeType.INTEL:
			return "SIGNAL ANALYSIS"
	return "NAVIGATION"

func _compact_objective(node: SidebayCampaignNode) -> String:
	if not node.is_battle():
		match node.node_type:
			SidebayCampaignNode.NodeType.SALVAGE:
				return "RECOVER"
			SidebayCampaignNode.NodeType.REPAIR:
				return "SERVICE"
			SidebayCampaignNode.NodeType.INTEL:
				return "SIGNALS"
	match node.objective_type:
		SidebayCampaignNode.ObjectiveType.INTERCEPTION:
			return "INTERCEPT"
		SidebayCampaignNode.ObjectiveType.EXTRACTION:
			return "EXTRACT"
		SidebayCampaignNode.ObjectiveType.DEFENSE:
			return "DEFEND"
		SidebayCampaignNode.ObjectiveType.ESCORT:
			return "ESCORT"
		SidebayCampaignNode.ObjectiveType.CAPTURE:
			return "CAPTURE"
		_:
			return "STRIKE"

func _mission_description(node: SidebayCampaignNode) -> String:
	if not node.is_battle():
		match node.node_type:
			SidebayCampaignNode.NodeType.SALVAGE:
				return "A recoverable debris field lies off the direct line. Recovery crews can secure material before hostile traffic closes the window."
			SidebayCampaignNode.NodeType.REPAIR:
				return "A fleet support anchorage can restore reserve stores and receive a limited draft of replacement crew."
			SidebayCampaignNode.NodeType.INTEL:
				return "A narrow-band transmission may expose deeper routes and hostile dispositions before the fleet advances."
	match node.objective_type:
		SidebayCampaignNode.ObjectiveType.INTERCEPTION:
			return "Hostile strike elements are crossing the route. Break their formation before they reach the carrier group."
		SidebayCampaignNode.ObjectiveType.EXTRACTION:
			return "Reach the extraction area, protect recoverable personnel, and clear the fleet before hostile pressure closes in."
		SidebayCampaignNode.ObjectiveType.DEFENSE:
			return "Hold the designated battlespace against an incoming assault while fleet operations complete."
		SidebayCampaignNode.ObjectiveType.ESCORT:
			return "Keep the assigned vessel inside the carrier screen and deliver it through the hostile contact zone."
		SidebayCampaignNode.ObjectiveType.CAPTURE:
			return "Seize and hold the command point while hostile fleet elements attempt to contest the area."
		_:
			return "Locate the hostile command vessel, collapse its escort screen, and destroy strategic command capability."

func _reward_text(node: SidebayCampaignNode) -> String:
	match node.node_type:
		SidebayCampaignNode.NodeType.SALVAGE:
			return "%d SALV  +  1 REQ" % node.reward_supplies
		SidebayCampaignNode.NodeType.REPAIR:
			return "%d SUP  +  CREW" % node.reward_supplies
		SidebayCampaignNode.NodeType.INTEL:
			return "%d INTEL" % node.reward_intel
		_:
			return "%d SUP%s" % [node.reward_supplies, "  +  %d INTEL" % node.reward_intel if node.reward_intel > 0 else ""]

func _threat_pips(threat: int) -> String:
	var clamped := clampi(threat, 0, 7)
	return "%s%s  T%d" % ["■".repeat(clamped), "□".repeat(7 - clamped), threat]

func _toggle_system_panel() -> void:
	if restart_confirmation_panel.visible:
		_close_system_panel()
		return
	system_panel.visible = not system_panel.visible

func _close_system_panel() -> void:
	system_panel.visible = false
	restart_confirmation_panel.visible = false

func _show_restart_confirmation() -> void:
	system_panel.visible = false
	restart_confirmation_panel.visible = true

func _cancel_restart_confirmation() -> void:
	restart_confirmation_panel.visible = false
	system_panel.visible = true

func _label(position_value: Vector2, size_value: Vector2, font_size: int, parent: Control = null, color: Color = UIStyle.TEXT_PRIMARY) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size, color)
	(parent if parent != null else self).add_child(label)
	return label

func _button(text_value: String, position_value: Vector2, size_value: Vector2, parent: Control = null, font_size: int = 13, accent: Color = UIStyle.CYAN) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	UIStyle.apply_button(button, font_size, accent)
	(parent if parent != null else self).add_child(button)
	return button
