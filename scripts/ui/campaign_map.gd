class_name SidebayCampaignMap
extends Control

const UIStyle := preload("res://scripts/ui/ui_style.gd")

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
var resource_label: Label
var status_label: Label
var run_label: Label

func configure(state: SidebayRunState, campaign_generator: SidebayCampaignGenerator) -> void:
	run_state = state
	generator = campaign_generator
	_build_shell()
	refresh()

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.004, 0.009, 0.02, 1.0)
	background.show_behind_parent = true
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var title := _label(Vector2(24, 18), Vector2(420, 38), 22)
	title.text = "EXODRIFT // OPERATION DEEP STRIKE"
	resource_label = _label(Vector2(24, 62), Vector2(760, 34), 19)
	run_label = _label(Vector2(24, 96), Vector2(1000, 30), 14)
	status_label = _label(Vector2(24, 650), Vector2(920, 42), 17)
	var new_button := _button("NEW RUN", Vector2(1090, 20), Vector2(160, 38))
	new_button.pressed.connect(func() -> void: new_run_requested.emit())
	var save_button := _button("SAVE RUN", Vector2(1060, 66), Vector2(92, 36))
	save_button.pressed.connect(func() -> void: save_requested.emit())
	var load_button := _button("LOAD", Vector2(1158, 66), Vector2(92, 36))
	load_button.pressed.connect(func() -> void: load_requested.emit())
	var forecast_button := _button("SPEND 1 INTEL: DEEP FORECAST", Vector2(720, 66), Vector2(320, 36))
	forecast_button.name = "ForecastButton"
	forecast_button.pressed.connect(func() -> void: forecast_requested.emit())
	var logistics_button := _button("LOGISTICS", Vector2(460, 20), Vector2(130, 38))
	logistics_button.pressed.connect(func() -> void: logistics_requested.emit())
	var fleet_button := _button("FLEET", Vector2(600, 20), Vector2(130, 38))
	fleet_button.pressed.connect(func() -> void: fleet_requested.emit())
	var personnel_button := _button("PERSONNEL", Vector2(740, 20), Vector2(140, 38))
	personnel_button.pressed.connect(func() -> void: personnel_requested.emit())
	var playtest_button := _button("DEBRIEF", Vector2(890, 20), Vector2(100, 38))
	playtest_button.pressed.connect(func() -> void: playtest_requested.emit())
	var title_button := _button("TITLE", Vector2(1000, 20), Vector2(80, 38))
	title_button.pressed.connect(func() -> void: title_requested.emit())
	for sector in 3:
		var label := _label(Vector2(90 + sector * 410, 132), Vector2(360, 34), 18)
		label.text = ["SECTOR I — OUTER LINE", "SECTOR II — CONTESTED", "SECTOR III — COMMAND ZONE"][sector]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func refresh() -> void:
	if run_state == null or generator == null:
		return
	for button in node_buttons.values():
		button.queue_free()
	node_buttons.clear()
	var reachable := generator.reachable_node_ids(run_state)
	for node_value in generator.nodes.values():
		var node: SidebayCampaignNode = node_value
		var position_value := _node_position(node)
		var button := _button("", position_value - Vector2(58, 25), Vector2(116, 50))
		button.name = String(node.node_id)
		var completed := run_state.completed_node_ids.has(node.node_id)
		var connected := reachable.has(node.node_id)
		var accessible := connected and run_state.can_afford_route(node.fuel_cost) and not run_state.run_completed and not run_state.run_failed
		var revealed := connected or completed or run_state.revealed_node_ids.has(node.node_id)
		button.disabled = not accessible
		button.text = _node_button_text(node, revealed, completed)
		button.tooltip_text = _node_tooltip(node, revealed, accessible, connected)
		button.pressed.connect(func() -> void: node_selected.emit(node.node_id))
		_apply_node_style(button, node, completed, accessible, revealed)
		node_buttons[node.node_id] = button
	resource_label.text = "SUP %03d   FUEL %02d   INTEL %02d   REQ %02d   SALV %03d   WINS %02d   WD %02d" % [run_state.supplies, run_state.fuel, run_state.intel, run_state.requisition, run_state.salvage_stock, run_state.battles_won, run_state.withdrawals]
	run_label.text = "RUN %s     CURRENT %s     LOGISTICS %s" % [run_state.run_id, String(run_state.current_node_id) if run_state.current_node_id != &"" else "DEPLOYMENT", run_state.active_logistics_posture_data().get("name", "Balanced Stores")]
	var forecast_button := get_node_or_null("ForecastButton") as Button
	if forecast_button != null:
		forecast_button.disabled = run_state.intel < 1 or run_state.run_completed or run_state.run_failed
	if run_state.run_completed:
		status_label.text = "OPERATION COMPLETE — strategic command destroyed. Begin a new run when ready."
	elif run_state.run_failed:
		status_label.text = "OPERATION FAILED — carrier lost. Load a manual save or begin a new run."
	elif reachable.is_empty():
		status_label.text = "No reachable nodes. Load a save or begin a new run."
	queue_redraw()

func set_status(message: String) -> void:
	status_label.text = message

func replace_state(state: SidebayRunState, campaign_generator: SidebayCampaignGenerator) -> void:
	run_state = state
	generator = campaign_generator
	refresh()

func _draw() -> void:
	if generator == null or run_state == null:
		return
	for node_value in generator.nodes.values():
		var node: SidebayCampaignNode = node_value
		for destination_id in node.connections:
			var destination := generator.get_node(destination_id)
			if destination == null:
				continue
			var color := Color(0.08, 0.28, 0.42, 0.75)
			if run_state.completed_node_ids.has(node.node_id):
				color = Color(0.1, 0.66, 0.86, 0.9)
			draw_line(_node_position(node), _node_position(destination), color, 2.0, true)

func _node_position(node: SidebayCampaignNode) -> Vector2:
	return Vector2(92.0 + node.sector * 410.0 + node.column * 132.0, 225.0 + node.row * 145.0)

func _node_button_text(node: SidebayCampaignNode, revealed: bool, completed: bool) -> String:
	if completed:
		return "✓ %s" % node.display_name
	if not revealed:
		return "UNKNOWN"
	var fuel_cost := run_state.route_fuel_cost(node.fuel_cost) if run_state != null else node.fuel_cost
	var supply_cost := run_state.route_supply_cost() if run_state != null else 0
	return "%s\nT%d  F%d%s" % [node.type_label(), node.threat, fuel_cost, " S%d" % supply_cost if supply_cost > 0 else ""]

func _node_tooltip(node: SidebayCampaignNode, revealed: bool, accessible: bool, connected: bool) -> String:
	if not revealed:
		return "Spend intel to reveal this forecast."
	var objective := "\nObjective: %s" % node.objective_label() if node.is_battle() else ""
	var fuel_cost := run_state.route_fuel_cost(node.fuel_cost)
	var supply_cost := run_state.route_supply_cost()
	var route_status := "Reachable" if accessible else ("Insufficient route resources" if connected else "Not on current route")
	return "%s — %s\nThreat %d, route cost %d fuel + %d supplies%s\n%s" % [node.display_name, node.type_label(), node.threat, fuel_cost, supply_cost, objective, route_status]

func _apply_node_style(button: Button, node: SidebayCampaignNode, completed: bool, accessible: bool, revealed: bool) -> void:
	var color := Color(0.08, 0.12, 0.17)
	if completed:
		color = Color(0.06, 0.4, 0.55)
	elif accessible:
		match node.node_type:
			SidebayCampaignNode.NodeType.COMBAT, SidebayCampaignNode.NodeType.BOSS:
				color = Color(0.55, 0.12, 0.08)
			SidebayCampaignNode.NodeType.SALVAGE:
				color = Color(0.55, 0.38, 0.06)
			SidebayCampaignNode.NodeType.REPAIR:
				color = Color(0.08, 0.45, 0.28)
			SidebayCampaignNode.NodeType.INTEL:
				color = Color(0.26, 0.18, 0.56)
	elif revealed:
		color = Color(0.12, 0.18, 0.24)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.border_color = Color(0.18, 0.62, 0.82) if accessible else Color(0.18, 0.28, 0.36)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_color_override("font_color", Color(0.82, 0.94, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.66, 0.72) if revealed else Color(0.28, 0.34, 0.38))

func _label(position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size)
	add_child(label)
	return label

func _button(text_value: String, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	UIStyle.apply_button(button, 13)
	add_child(button)
	return button
