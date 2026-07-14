class_name ExodriftLogisticsScreen
extends Control

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const SERVICE_ACTIONS: Array[StringName] = [&"repair", &"rearm", &"air_group", &"full_service"]

signal closed
signal logistics_changed(message: String)

var run_state: SidebayRunState
var resource_label: Label
var posture_buttons: Dictionary = {}
var allocation_buttons: Dictionary = {}
var service_buttons: Dictionary = {}

func configure(state: SidebayRunState) -> void:
	run_state = state
	_build_shell()
	refresh()

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var veil := ColorRect.new()
	veil.color = Color(0.002, 0.006, 0.014, 0.97)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var panel := Panel.new()
	panel.position = Vector2(110, 30)
	panel.size = Vector2(1060, 660)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.035, 0.055, 1.0)
	style.border_color = Color(0.85, 0.58, 0.14, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var title := _label(panel, Vector2(38, 22), Vector2(760, 40), 27)
	title.text = "EXODRIFT // ROUTE LOGISTICS"
	resource_label = _label(panel, Vector2(38, 62), Vector2(980, 30), 17)
	var service_title := _label(panel, Vector2(38, 100), Vector2(900, 28), 18)
	service_title.text = "CARRIER SERVICE // EXACT SUPPLY COST // CREW REPLACEMENTS EXCLUDED"
	for index in SERVICE_ACTIONS.size():
		var action := SERVICE_ACTIONS[index]
		var service_button := _button(panel, Vector2(38 + index * 246, 132), Vector2(232, 98))
		service_button.pressed.connect(func() -> void: _service_fleet(action))
		service_buttons[action] = service_button
	var posture_title := _label(panel, Vector2(38, 244), Vector2(800, 28), 18)
	posture_title.text = "ROUTE POSTURE // APPLIES TO THE NEXT JUMP AND RECOVERY"
	for index in SidebayRunState.logistics_posture_catalog().size():
		var posture: Dictionary = SidebayRunState.logistics_posture_catalog()[index]
		var posture_id := StringName(posture.id)
		var button := _button(panel, Vector2(38 + index * 330, 275), Vector2(310, 90))
		button.pressed.connect(func() -> void: _select_posture(posture_id))
		posture_buttons[posture_id] = button
	var allocation_title := _label(panel, Vector2(38, 378), Vector2(700, 28), 18)
	allocation_title.text = "SALVAGE ALLOCATION // FIXED CONVERSION ORDERS"
	for index in SidebayRunState.salvage_allocation_catalog().size():
		var allocation: Dictionary = SidebayRunState.salvage_allocation_catalog()[index]
		var allocation_id := StringName(allocation.id)
		var button := _button(panel, Vector2(38 + index * 330, 409), Vector2(310, 80))
		button.pressed.connect(func() -> void: _allocate_salvage(allocation_id))
		allocation_buttons[allocation_id] = button
	var close_button := _button(panel, Vector2(38, 510), Vector2(970, 44))
	close_button.text = "RETURN TO SECTOR MAP"
	close_button.pressed.connect(func() -> void: closed.emit())
	var note := _label(panel, Vector2(38, 570), Vector2(970, 48), 13)
	note.text = "All costs are deterministic. Normal fleet service restores materiel only; carrier casualties can be replaced only at repair nodes, up to 24 crew per visit."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func refresh() -> void:
	if run_state == null:
		return
	resource_label.text = "SUPPLIES %03d     FUEL %02d     REQUISITION %02d     SALVAGE %03d     CREW %03d/240" % [run_state.supplies, run_state.fuel, run_state.requisition, run_state.salvage_stock, run_state.carrier_operations.crew_current]
	var breakdown := run_state.service_cost_breakdown()
	for action in SERVICE_ACTIONS:
		var service_button: Button = service_buttons[action]
		var cost := run_state.service_action_cost(action)
		service_button.text = "%s // %d SUPPLIES\n%s" % [_service_action_label(action), cost, _service_component_text(action, breakdown)]
		service_button.disabled = cost == 0 or run_state.supplies < cost
		service_button.tooltip_text = "Normal fleet service does not replace carrier crew."
	for posture in SidebayRunState.logistics_posture_catalog():
		var posture_id := StringName(posture.id)
		var button: Button = posture_buttons[posture_id]
		var selected := posture_id == run_state.logistics_posture_id
		button.text = "%s%s\n\n%s" % ["ACTIVE // " if selected else "", posture.name, posture.summary]
		button.disabled = selected
	for allocation in SidebayRunState.salvage_allocation_catalog():
		var allocation_id := StringName(allocation.id)
		var button: Button = allocation_buttons[allocation_id]
		button.text = "%s\n\n%s" % [allocation.name, allocation.summary]
		button.disabled = not run_state.can_allocate_salvage(allocation_id)

func _select_posture(posture_id: StringName) -> void:
	logistics_changed.emit(run_state.select_logistics_posture(posture_id))
	refresh()

func _allocate_salvage(allocation_id: StringName) -> void:
	logistics_changed.emit(run_state.allocate_salvage(allocation_id))
	refresh()

func _service_fleet(action: StringName) -> void:
	var cost := run_state.service_action_cost(action)
	var crew_before := run_state.carrier_operations.crew_current
	if run_state.service_fleet(action):
		logistics_changed.emit("%s completed for %d supplies. Carrier crew remains %d; casualties require a repair node." % [_service_action_label(action).capitalize(), cost, crew_before])
	else:
		logistics_changed.emit("%s rejected: requires %d supplies." % [_service_action_label(action).capitalize(), cost])
	refresh()

func _service_action_label(action: StringName) -> String:
	match action:
		&"repair":
			return "REPAIR"
		&"rearm":
			return "REARM"
		&"air_group":
			return "AIR-GROUP RESTORATION"
	return "FULL SERVICE"

func _service_component_text(action: StringName, breakdown: Dictionary) -> String:
	var repair: Dictionary = breakdown.get("repair", {})
	var rearm: Dictionary = breakdown.get("rearm", {})
	var air_group: Dictionary = breakdown.get("air_group", {})
	match action:
		&"repair":
			return "Layers %d // Systems %d // DC spares %d" % [repair.get("layers", 0), repair.get("subsystems", 0), repair.get("damage_control_spares", 0)]
		&"rearm":
			return "Flak %d // Missiles %d // Nuclear %d" % [rearm.get("flak_rounds", 0), rearm.get("guided_missiles", 0), rearm.get("nuclear_torpedoes", 0)]
		&"air_group":
			return "Craft %d // Wing ammo %d\nOrdnance %d // Refuel %d" % [air_group.get("craft", 0), air_group.get("wing_ammunition", 0), air_group.get("aviation_ordnance", 0), air_group.get("craft_refuel", 0)]
	return "Repair %d // Rearm %d // Air group %d" % [repair.get("subtotal", 0), rearm.get("subtotal", 0), air_group.get("subtotal", 0)]

func _label(parent: Control, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size)
	parent.add_child(label)
	return label

func _button(parent: Control, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.position = position_value
	button.size = size_value
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyle.apply_button(button, 14, UIStyle.AMBER)
	parent.add_child(button)
	return button
