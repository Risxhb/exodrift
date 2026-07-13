class_name ExodriftCarrierOperationsConsole
extends CanvasLayer

signal closed
signal power_preset_requested(preset: StringName)
signal power_adjustment_requested(channel: StringName, delta: int)
signal damage_control_assignment_requested(team_index: int, subsystem: StringName)
signal deck_priority_requested(deck: StringName, priority: StringName)
signal wing_loadout_requested(wing: StringName, loadout: StringName)

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const CHANNELS: Array[StringName] = [&"propulsion", &"defense", &"weapons", &"flight"]
const PRESETS: Array[StringName] = [&"balanced", &"strike", &"evasive", &"recovery"]
const SUBSYSTEMS: Array[StringName] = [
	&"reactor", &"propulsion", &"shield_grid", &"fire_control", &"sensors",
	&"command_cic", &"port_deck", &"starboard_deck",
]
const PRIORITIES: Array[StringName] = [&"rapid_turn", &"balanced", &"repair_first"]
const RAPTOR_LOADOUTS: Array[StringName] = [&"raptor_cap", &"raptor_multirole", &"raptor_strike"]
const WATCHER_LOADOUTS: Array[StringName] = [&"watcher_recon", &"watcher_screen", &"watcher_rescue"]

var operations_state: Object
var interceptor_wing: Object
var scout_wing: Object
var root: Control
var frame: Panel
var preset_label: Label
var power_budget_label: Label
var power_labels: Dictionary = {}
var subsystem_labels: Dictionary = {}
var team_options: Array[OptionButton] = []
var crew_label: Label
var stores_label: Label
var incident_label: Label
var deck_labels: Dictionary = {}
var deck_priority_options: Dictionary = {}
var loadout_options: Dictionary = {}
var refresh_elapsed := 0.0


func configure(state: Object = null) -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	ExodriftInputSettings.ensure_actions()
	if root == null:
		_build_interface()
	bind_state(state)
	visible = false


func bind_state(state: Object) -> void:
	operations_state = state
	if operations_state != null:
		for signal_name in [&"changed", &"state_changed", &"incident", &"incident_changed"]:
			if operations_state.has_signal(signal_name):
				var callback := Callable(self, "refresh")
				if not operations_state.is_connected(signal_name, callback):
					operations_state.connect(signal_name, callback)
	refresh()


func bind_wings(interceptor: Object, scout: Object) -> void:
	interceptor_wing = interceptor
	scout_wing = scout
	refresh()


func open_console() -> void:
	if root == null:
		configure(operations_state)
	visible = true
	refresh()


func close_console() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle_console() -> bool:
	if visible:
		close_console()
	else:
		open_console()
	return visible


func is_open() -> bool:
	return visible


func consume_escape() -> bool:
	if not visible:
		return false
	close_console()
	return true


func _build_interface() -> void:
	root = Control.new()
	root.name = "CarrierOperationsConsole"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.006, 0.012, 0.72)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(veil)

	frame = Panel.new()
	frame.name = "OperationsFrame"
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.position = Vector2(-610.0, -340.0)
	frame.size = Vector2(1220.0, 680.0)
	frame.pivot_offset = frame.size * 0.5
	frame.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.003, 0.016, 0.028, 0.985), UIStyle.CYAN, 2, 7))
	root.add_child(frame)
	root.resized.connect(_fit_to_viewport)

	var header := ColorRect.new()
	header.color = Color(UIStyle.CYAN.r, UIStyle.CYAN.g, UIStyle.CYAN.b, 0.75)
	header.size = Vector2(frame.size.x, 4.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(header)
	_label(frame, "CARRIER OPERATIONS // CVN SIDEBAY", Vector2(24, 16), Vector2(600, 32), 20, UIStyle.CYAN)
	incident_label = _label(frame, "NO ACTIVE INTERNAL INCIDENTS", Vector2(550, 19), Vector2(442, 27), 12, UIStyle.TEXT_MUTED)
	incident_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var close_button := _button(frame, "CLOSE  [ESC]", Vector2(1010, 13), Vector2(184, 38), UIStyle.AMBER)
	close_button.pressed.connect(close_console)

	_build_power_panel()
	_build_subsystem_panel()
	_build_crew_stores_panel()
	_build_deck_panel()
	call_deferred("_fit_to_viewport")


func _fit_to_viewport() -> void:
	if root == null or frame == null:
		return
	var available := root.size - Vector2(24.0, 24.0)
	var fit := minf(1.0, minf(available.x / frame.size.x, available.y / frame.size.y))
	frame.scale = Vector2.ONE * maxf(0.25, fit)


func _build_power_panel() -> void:
	var panel := _section_panel("PowerManagement", "REACTOR DISTRIBUTION", Vector2(20, 64), Vector2(575, 244), UIStyle.CYAN)
	preset_label = _label(panel, "PRESET  BALANCED", Vector2(18, 32), Vector2(260, 24), 14, UIStyle.AMBER)
	power_budget_label = _label(panel, "8 / 8 REACTOR POINTS", Vector2(300, 32), Vector2(255, 24), 12, UIStyle.TEXT_MUTED)
	power_budget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in PRESETS.size():
		var preset := PRESETS[index]
		var button := _button(panel, _display_name(preset), Vector2(16 + index * 136, 65), Vector2(126, 34), UIStyle.CYAN_SOFT)
		button.name = "%sPreset" % _display_name(preset).replace(" ", "")
		button.pressed.connect(_on_preset_pressed.bind(preset))
	for index in CHANNELS.size():
		var channel := CHANNELS[index]
		var y := 114.0 + index * 34.0
		_label(panel, _display_name(channel).to_upper(), Vector2(18, y + 4), Vector2(150, 25), 12, UIStyle.TEXT_PRIMARY)
		var minus := _button(panel, "-", Vector2(330, y), Vector2(42, 28), UIStyle.CYAN_SOFT)
		minus.pressed.connect(_on_power_adjustment.bind(channel, -1))
		var value := _label(panel, "2", Vector2(382, y + 2), Vector2(76, 24), 15, UIStyle.AMBER)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		power_labels[channel] = value
		var plus := _button(panel, "+", Vector2(468, y), Vector2(42, 28), UIStyle.CYAN_SOFT)
		plus.pressed.connect(_on_power_adjustment.bind(channel, 1))


func _build_subsystem_panel() -> void:
	var panel := _section_panel("SubsystemStatus", "SUBSYSTEM CONDITION / HAZARDS", Vector2(615, 64), Vector2(585, 330), UIStyle.AMBER)
	for index in SUBSYSTEMS.size():
		var subsystem := SUBSYSTEMS[index]
		var column := index % 2
		var row := index / 2
		var label := _label(panel, "%s  100%%  //  NOMINAL" % _display_name(subsystem).to_upper(), Vector2(16 + column * 278, 34 + row * 39), Vector2(266, 31), 11, UIStyle.TEXT_PRIMARY)
		subsystem_labels[subsystem] = label
	_label(panel, "DAMAGE-CONTROL ASSIGNMENTS  //  4 SEC TRANSIT", Vector2(16, 197), Vector2(550, 22), 11, UIStyle.TEXT_MUTED)
	for team_index in 2:
		_label(panel, "TEAM %d" % (team_index + 1), Vector2(18, 232 + team_index * 53), Vector2(90, 30), 12, UIStyle.AMBER)
		var selector := OptionButton.new()
		selector.position = Vector2(112, 228 + team_index * 53)
		selector.size = Vector2(440, 38)
		UIStyle.apply_option_button(selector, 12)
		selector.add_item("AUTOMATIC / HIGHEST PRIORITY")
		for subsystem in SUBSYSTEMS:
			selector.add_item(_display_name(subsystem).to_upper())
		selector.item_selected.connect(_on_team_assignment.bind(team_index))
		panel.add_child(selector)
		team_options.append(selector)


func _build_crew_stores_panel() -> void:
	var panel := _section_panel("CrewAndStores", "CREW / MAGAZINES", Vector2(20, 328), Vector2(575, 332), UIStyle.AMBER)
	crew_label = _label(panel, "CREW  240 / 240  //  FULL EFFECTIVENESS\nDC SPARES  60", Vector2(18, 35), Vector2(540, 54), 14, UIStyle.TEXT_PRIMARY)
	stores_label = _label(panel, "FLAK             2,100 ROUNDS\nGUIDED MISSILES       24\nNUCLEAR TORPEDO         1\nAVIATION ORDNANCE    100%\nCRAFT REFUEL            14", Vector2(18, 105), Vector2(540, 152), 13, UIStyle.TEXT_PRIMARY)
	stores_label.add_theme_constant_override("line_spacing", 7)
	var note := _label(panel, "Hazards cause casualties until contained. Repair nodes can recover up to 24 missing crew; ordinary fleet service cannot replace losses.", Vector2(18, 264), Vector2(540, 54), 11, UIStyle.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_deck_panel() -> void:
	var panel := _section_panel("FlightDeck", "FLIGHT-DECK CONTROL", Vector2(615, 414), Vector2(585, 246), UIStyle.CYAN)
	for deck_index in 2:
		var deck: StringName = &"port" if deck_index == 0 else &"starboard"
		var wing: StringName = &"interceptor" if deck_index == 0 else &"scout"
		var x := 16.0 + deck_index * 281.0
		var label := _label(panel, "%s DECK  //  READY\nQUEUE  IDLE" % _display_name(deck).to_upper(), Vector2(x, 32), Vector2(267, 48), 12, UIStyle.TEXT_PRIMARY)
		deck_labels[deck] = label
		_label(panel, "SERVICE PRIORITY", Vector2(x, 92), Vector2(267, 20), 10, UIStyle.TEXT_MUTED)
		var priority := OptionButton.new()
		priority.position = Vector2(x, 114)
		priority.size = Vector2(267, 35)
		UIStyle.apply_option_button(priority, 11)
		for entry in PRIORITIES:
			priority.add_item(_display_name(entry).to_upper())
		priority.select(1)
		priority.item_selected.connect(_on_priority_selected.bind(deck))
		panel.add_child(priority)
		deck_priority_options[deck] = priority
		_label(panel, "WING PACKAGE", Vector2(x, 158), Vector2(267, 20), 10, UIStyle.TEXT_MUTED)
		var loadout := OptionButton.new()
		loadout.position = Vector2(x, 180)
		loadout.size = Vector2(267, 35)
		UIStyle.apply_option_button(loadout, 11)
		var choices: Array[StringName] = RAPTOR_LOADOUTS if wing == &"interceptor" else WATCHER_LOADOUTS
		for entry in choices:
			loadout.add_item(_display_name(entry).to_upper())
		loadout.select(1 if wing == &"interceptor" else 0)
		loadout.item_selected.connect(_on_loadout_selected.bind(wing))
		panel.add_child(loadout)
		loadout_options[wing] = loadout
	var restriction := _label(panel, "LOADOUT CHANGES REQUIRE AN ABOARD WING BEFORE REARMING", Vector2(16, 218), Vector2(550, 24), 10, UIStyle.AMBER)
	restriction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func refresh(_unused = null) -> void:
	if root == null:
		return
	var allocations: Dictionary = _dictionary_value([&"power_allocation", &"power_allocations", &"power"])
	var preset := String(_value([&"current_power_preset", &"power_preset", &"current_preset"], "balanced"))
	preset_label.text = "PRESET  %s" % _display_name(preset).to_upper()
	var available := int(_value([&"available_power_points", &"available_power", &"available_reactor_points", &"power_budget"], 8))
	var used := 0
	for channel in CHANNELS:
		var points := int(allocations.get(channel, allocations.get(String(channel), 2)))
		used += points
		(power_labels[channel] as Label).text = "%d / 4" % points
	power_budget_label.text = "%d / %d REACTOR POINTS" % [used, available]

	var conditions: Dictionary = _dictionary_value([&"subsystem_condition", &"subsystem_conditions", &"subsystems"])
	var hazards: Dictionary = _dictionary_value([&"hazards", &"active_hazards"])
	var incident_count := 0
	for subsystem in SUBSYSTEMS:
		var raw_condition = conditions.get(subsystem, conditions.get(String(subsystem), 1.0))
		if raw_condition is Dictionary:
			raw_condition = (raw_condition as Dictionary).get("condition", 1.0)
		var condition := clampf(float(raw_condition), 0.0, 1.0)
		var hazard_text := _hazard_text(hazards.get(subsystem, hazards.get(String(subsystem), null)))
		if hazard_text != "NOMINAL":
			incident_count += 1
		var label := subsystem_labels[subsystem] as Label
		label.text = "%s  %d%%  //  %s" % [_display_name(subsystem).to_upper(), roundi(condition * 100.0), hazard_text]
		label.add_theme_color_override("font_color", _condition_color(condition, hazard_text != "NOMINAL"))
	var trapped_incident := _active_officer_incident()
	if not trapped_incident.is_empty():
		incident_label.text = "RESCUE  %s  //  %s  //  %.1f SEC" % [
			String(trapped_incident.get("display_name", "OFFICER")).to_upper(),
			_display_name(trapped_incident.get("subsystem", "")).to_upper(),
			maxf(0.0, float(trapped_incident.get("time_remaining", 0.0))),
		]
		incident_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.22))
	else:
		incident_label.text = "NO ACTIVE INTERNAL INCIDENTS" if incident_count == 0 else "%d ACTIVE INTERNAL INCIDENT%s" % [incident_count, "" if incident_count == 1 else "S"]
		incident_label.add_theme_color_override("font_color", UIStyle.TEXT_MUTED if incident_count == 0 else UIStyle.AMBER)

	var teams = _value([&"damage_control_teams", &"teams"], [])
	for team_index in team_options.size():
		var assignment := StringName()
		if teams is Array and team_index < teams.size():
			assignment = _team_assignment(teams[team_index])
		elif teams is Dictionary:
			assignment = _team_assignment(teams.get(team_index, teams.get(String.num_int64(team_index), null)))
		var option := team_options[team_index]
		option.select(maxi(0, SUBSYSTEMS.find(assignment) + 1))

	var crew_current := int(_value([&"crew", &"surviving_crew", &"crew_current"], 240))
	var crew_max := int(_value([&"crew_capacity", &"max_crew"], 240))
	var spares := int(_value([&"damage_control_spares", &"spares"], 60))
	crew_label.text = "CREW  %d / %d  //  %s\nDC SPARES  %d" % [crew_current, crew_max, _crew_effectiveness(crew_current, crew_max), spares]
	var stores: Dictionary = _dictionary_value([&"stores", &"carrier_stores"])
	var capacities: Dictionary = _dictionary_value([&"store_capacities"])
	var aviation_remaining := int(stores.get("aviation_ordnance", 0))
	var aviation_capacity := int(capacities.get("aviation_ordnance", maxi(aviation_remaining, 1)))
	stores_label.text = "FLAK             %s ROUNDS\nGUIDED MISSILES       %d\nNUCLEAR TORPEDO         %d\nAVIATION ORDNANCE  %3d / %-3d\nCRAFT REFUEL            %d" % [
		_format_integer(int(stores.get("flak", stores.get("flak_rounds", 2100)))),
		int(stores.get("guided_missiles", stores.get("missiles", 24))),
		int(stores.get("nuclear_torpedoes", stores.get("nuclear", 1))),
		aviation_remaining,
		aviation_capacity,
		int(stores.get("craft_refuel", stores.get("refuel_units", 14))),
	]

	var decks: Dictionary = _dictionary_value([&"deck_states", &"decks", &"deck_queues"])
	for deck in [&"port", &"starboard"]:
		var wing := interceptor_wing if deck == &"port" else scout_wing
		var data = _wing_queue_snapshot(wing)
		if data.is_empty():
			data = decks.get(deck, decks.get(String(deck), {}))
		var status := "READY"
		var queue := "IDLE"
		if data is Dictionary:
			status = String((data as Dictionary).get("state", (data as Dictionary).get("status", status)))
			queue = String((data as Dictionary).get("task", (data as Dictionary).get("queue", queue)))
		(deck_labels[deck] as Label).text = "%s DECK  //  %s\nQUEUE  %s" % [_display_name(deck).to_upper(), status.to_upper(), queue.to_upper()]
		var priority_text := String((data as Dictionary).get("priority", _value([&"service_priority"], "balanced"))).to_lower().replace(" ", "_")
		var priority_index := PRIORITIES.find(StringName(priority_text))
		if priority_index >= 0:
			(deck_priority_options[deck] as OptionButton).select(priority_index)
	var wing_loadouts: Dictionary = _dictionary_value([&"wing_loadouts"])
	_refresh_loadout_selector(&"interceptor", interceptor_wing, wing_loadouts)
	_refresh_loadout_selector(&"scout", scout_wing, wing_loadouts)


func _process(delta: float) -> void:
	if not visible:
		return
	refresh_elapsed -= delta
	if refresh_elapsed <= 0.0:
		refresh_elapsed = 0.2
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		close_console()
		get_viewport().set_input_as_handled()


func _on_preset_pressed(preset: StringName) -> void:
	power_preset_requested.emit(preset)
	_call_state([&"apply_power_preset", &"set_power_preset"], [preset])
	refresh()


func _on_power_adjustment(channel: StringName, delta: int) -> void:
	power_adjustment_requested.emit(channel, delta)
	if not _call_state([&"adjust_power"], [channel, delta]):
		_call_state([&"set_power_allocation"], [channel, _current_power(channel) + delta])
	refresh()


func _on_team_assignment(selected_index: int, team_index: int) -> void:
	var subsystem := StringName() if selected_index == 0 else SUBSYSTEMS[selected_index - 1]
	damage_control_assignment_requested.emit(team_index, subsystem)
	if subsystem == &"":
		_call_state([&"clear_damage_control_team", &"clear_team"], [team_index])
	else:
		_call_state([&"assign_damage_control_team", &"assign_team"], [team_index, subsystem])
	refresh()


func _on_priority_selected(selected_index: int, deck: StringName) -> void:
	var priority := PRIORITIES[clampi(selected_index, 0, PRIORITIES.size() - 1)]
	deck_priority_requested.emit(deck, priority)
	if not _call_state([&"set_deck_priority"], [deck, priority]):
		_call_state([&"set_service_priority"], [priority])


func _on_loadout_selected(selected_index: int, wing: StringName) -> void:
	var choices: Array[StringName] = RAPTOR_LOADOUTS if wing == &"interceptor" else WATCHER_LOADOUTS
	var loadout := choices[clampi(selected_index, 0, choices.size() - 1)]
	var delegated := not get_signal_connection_list(&"wing_loadout_requested").is_empty()
	wing_loadout_requested.emit(wing, loadout)
	if not delegated:
		_call_state([&"set_wing_loadout", &"select_wing_package"], [wing, loadout])


func _current_power(channel: StringName) -> int:
	var allocations := _dictionary_value([&"power_allocation", &"power_allocations", &"power"])
	return int(allocations.get(channel, allocations.get(String(channel), 2)))


func _wing_queue_snapshot(wing: Object) -> Dictionary:
	if wing != null and wing.has_method("deck_queue_snapshot"):
		var snapshot = wing.call("deck_queue_snapshot")
		if snapshot is Dictionary:
			return snapshot
	return {}


func _refresh_loadout_selector(role: StringName, wing: Object, persisted: Dictionary) -> void:
	if not loadout_options.has(role):
		return
	var current := StringName(persisted.get(String(role), ""))
	if wing != null and wing.has_method("current_loadout_id"):
		current = StringName(wing.call("current_loadout_id"))
	var choices: Array[StringName] = RAPTOR_LOADOUTS if role == &"interceptor" else WATCHER_LOADOUTS
	var selected := choices.find(current)
	if selected >= 0:
		(loadout_options[role] as OptionButton).select(selected)


func _active_officer_incident() -> Dictionary:
	var incidents = _value([&"officer_incidents"], [])
	if incidents is Array:
		for incident in incidents:
			if incident is Dictionary and String((incident as Dictionary).get("outcome", "")) == "trapped":
				return incident
	return {}


func _call_state(methods: Array[StringName], arguments: Array) -> bool:
	if operations_state == null:
		return false
	for method in methods:
		if operations_state.has_method(method):
			operations_state.callv(method, arguments)
			return true
	return false


func _value(names: Array[StringName], fallback):
	if operations_state == null:
		return fallback
	for property_name in names:
		if _has_property(operations_state, property_name):
			var value = operations_state.get(property_name)
			if value != null:
				return value
		if operations_state.has_method(property_name):
			return operations_state.call(property_name)
	return fallback


func _dictionary_value(names: Array[StringName]) -> Dictionary:
	var value = _value(names, {})
	return value if value is Dictionary else {}


func _has_property(object: Object, property_name: StringName) -> bool:
	for entry in object.get_property_list():
		if StringName(entry.name) == property_name:
			return true
	return false


func _team_assignment(team) -> StringName:
	if team is Dictionary:
		return StringName((team as Dictionary).get("target_subsystem", (team as Dictionary).get("subsystem", (team as Dictionary).get("assignment", ""))))
	if team is String or team is StringName:
		return StringName(team)
	return StringName()


func _hazard_text(hazard) -> String:
	if hazard == null:
		return "NOMINAL"
	if hazard is String or hazard is StringName:
		return String(hazard).replace("_", " ").to_upper()
	if hazard is Array:
		if hazard.is_empty():
			return "NOMINAL"
		var names: PackedStringArray = []
		for entry in hazard:
			names.append(String(entry).replace("_", " ").to_upper())
		return " + ".join(names)
	if hazard is Dictionary:
		var names: PackedStringArray = []
		for key in hazard:
			if bool((hazard as Dictionary)[key]):
				names.append(String(key).replace("_", " ").to_upper())
		return " + ".join(names) if not names.is_empty() else "NOMINAL"
	return "INCIDENT"


func _condition_color(condition: float, has_hazard: bool) -> Color:
	if has_hazard or condition < 0.25:
		return Color(1.0, 0.3, 0.22)
	if condition < 0.75:
		return UIStyle.AMBER
	return UIStyle.TEXT_PRIMARY


func _crew_effectiveness(current: int, maximum: int) -> String:
	var ratio := float(current) / maxf(float(maximum), 1.0)
	if ratio < 0.25:
		return "CRITICAL CREWING"
	if ratio < 0.5:
		return "SEVERE PENALTY"
	if ratio < 0.75:
		return "REDUCED EFFECTIVENESS"
	return "FULL EFFECTIVENESS"


func _section_panel(node_name: String, title: String, position_value: Vector2, size_value: Vector2, accent: Color) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = position_value
	panel.size = size_value
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.006, 0.027, 0.043, 0.92), Color(accent.r, accent.g, accent.b, 0.7), 1, 5))
	frame.add_child(panel)
	_label(panel, title, Vector2(14, 7), Vector2(size_value.x - 28, 22), 11, accent)
	return panel


func _label(parent: Control, text_value: String, position_value: Vector2, size_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size, color)
	parent.add_child(label)
	return label


func _button(parent: Control, text_value: String, position_value: Vector2, size_value: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	UIStyle.apply_button(button, 11, accent)
	parent.add_child(button)
	return button


func _display_name(value) -> String:
	return String(value).replace("_", " ").capitalize()


func _format_integer(value: int) -> String:
	var digits := String.num_int64(absi(value))
	var output := ""
	while digits.length() > 3:
		output = ",%s%s" % [digits.right(3), output]
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + output
