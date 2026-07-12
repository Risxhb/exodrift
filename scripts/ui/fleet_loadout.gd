class_name ExodriftFleetLoadout
extends Control

signal closed
signal fleet_changed(message: String)

const SLOT_ORDER := ["weapon", "defense", "sensor", "support", "hangar"]

var run_state: SidebayRunState
var condition_label: Label
var resource_label: Label
var service_button: Button
var carrier_button: Button
var carrier_acquire_button: Button
var hangar_button: Button
var hangar_acquire_button: Button
var escort_button: Button
var acquire_button: Button
var module_buttons: Dictionary = {}

func configure(state: SidebayRunState) -> void:
	run_state = state
	_build_shell()
	refresh()

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var veil := ColorRect.new()
	veil.color = Color(0.002, 0.006, 0.014, 0.96)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var panel := Panel.new()
	panel.position = Vector2(130, 50)
	panel.size = Vector2(1020, 620)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.035, 0.055, 1.0)
	panel_style.border_color = Color(0.16, 0.68, 0.9, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	var title := _label(panel, Vector2(36, 24), Vector2(700, 42), 28)
	title.text = "EXODRIFT // FLEET CONFIGURATION"
	resource_label = _label(panel, Vector2(36, 72), Vector2(940, 30), 17)
	condition_label = _label(panel, Vector2(36, 112), Vector2(430, 178), 14)
	condition_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	condition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var section := _label(panel, Vector2(500, 116), Vector2(460, 30), 18)
	section.text = "AUTHORED MODULE LOADOUT"
	for index in SLOT_ORDER.size():
		var slot: String = SLOT_ORDER[index]
		var button := _button(panel, "", Vector2(500, 156 + index * 72), Vector2(460, 58))
		button.pressed.connect(func() -> void: _cycle_slot(slot))
		module_buttons[slot] = button
	carrier_button = _compact_button(panel, Vector2(36, 296))
	carrier_button.pressed.connect(_cycle_carrier)
	carrier_acquire_button = _compact_button(panel, Vector2(36, 336))
	carrier_acquire_button.pressed.connect(_acquire_carrier)
	hangar_button = _compact_button(panel, Vector2(36, 380))
	hangar_button.pressed.connect(_cycle_hangar)
	hangar_acquire_button = _compact_button(panel, Vector2(36, 420))
	hangar_acquire_button.pressed.connect(_acquire_hangar)
	escort_button = _compact_button(panel, Vector2(36, 464))
	escort_button.pressed.connect(_cycle_escort)
	acquire_button = _compact_button(panel, Vector2(36, 504))
	acquire_button.pressed.connect(_acquire_escort)
	service_button = _compact_button(panel, Vector2(36, 548), Vector2(430, 34))
	service_button.pressed.connect(_service_fleet)
	var close_button := _button(panel, "RETURN TO SECTOR MAP", Vector2(500, 532), Vector2(460, 48))
	close_button.pressed.connect(func() -> void: closed.emit())
	var note := _label(panel, Vector2(36, 588), Vector2(430, 22), 12)
	note.text = "Requisition unlocks sidegrades; supplies service and refit the active force."

func refresh() -> void:
	if run_state == null:
		return
	resource_label.text = "SUP %03d   REQ %02d   FRAMES %d/3   AIR GROUPS %d/3   ESCORTS %d/3   MODULES %02d/10" % [run_state.supplies, run_state.requisition, run_state.acquired_carrier_ids.size(), run_state.acquired_hangar_complement_ids.size(), run_state.acquired_escort_ids.size(), run_state.unlocked_module_ids.size()]
	var carrier_data := run_state.active_carrier_data()
	var hangar_data := run_state.active_hangar_complement_data()
	var escort_data := run_state.active_escort_data()
	var escort_name := str(escort_data.get("name", "NO ACTIVE ESCORT"))
	condition_label.text = "CARRIER  %s  //  %s\nCONDITION  S %3d%%  A %3d%%  H %3d%%\n\nAIR GROUP  %s\n  RAPTOR  %d/%d craft  %d/%d ammo\n  WATCHER %d/%d craft  %d/%d ammo\n\nESCORT  %s  //  %s" % [
		carrier_data.get("name", "Carrier"), carrier_data.get("class_name", "Frame"),
		int(round(run_state.carrier_shields * 100.0)), int(round(run_state.carrier_armor * 100.0)), int(round(run_state.carrier_hull * 100.0)),
		hangar_data.get("name", "Air Group"),
		run_state.interceptor_craft_count, run_state.maximum_interceptor_craft(), run_state.interceptor_ammunition, run_state.maximum_interceptor_ammunition(),
		run_state.scout_craft_count, run_state.maximum_scout_craft(), run_state.scout_ammunition, run_state.maximum_scout_ammunition(),
		escort_name, escort_data.get("class_name", "Replacement required")
	]
	carrier_button.text = "SELECT CARRIER FRAME  //  %s" % carrier_data.get("name", "Carrier")
	carrier_button.tooltip_text = str(carrier_data.get("summary", ""))
	carrier_button.disabled = run_state.acquired_carrier_ids.size() < 2
	_refresh_carrier_offer()
	_refresh_hangar_controls(hangar_data)
	escort_button.text = "SELECT ACTIVE ESCORT  //  %s" % escort_name
	escort_button.tooltip_text = str(escort_data.get("summary", ""))
	escort_button.disabled = run_state.acquired_escort_ids.is_empty()
	_refresh_escort_offer()
	var cost := run_state.service_cost()
	service_button.text = "FLEET SERVICE  //  %d SUPPLIES" % cost if cost > 0 else "FLEET FULLY SERVICED"
	service_button.disabled = cost == 0 or run_state.supplies < cost
	for slot in SLOT_ORDER:
		var module_id := StringName(run_state.installed_modules.get(slot, ""))
		var data := SidebayRunState.module_data(module_id)
		var button: Button = module_buttons[slot]
		button.text = "%s SLOT  //  %s\n%s" % [slot.to_upper(), data.get("name", "Empty"), data.get("effect", "")]
		button.tooltip_text = "Click to cycle through unlocked %s modules." % slot

func _refresh_carrier_offer() -> void:
	var offer := run_state.next_carrier_offer()
	if offer.is_empty():
		carrier_acquire_button.text = "CARRIER YARD  //  NO FRAME AVAILABLE"
		carrier_acquire_button.disabled = true
	else:
		var cost := int(offer.requisition_cost)
		carrier_acquire_button.text = "ACQUIRE %s  //  %d REQUISITION" % [offer.name, cost]
		carrier_acquire_button.tooltip_text = "%s — %s" % [offer.class_name, offer.summary]
		carrier_acquire_button.disabled = run_state.requisition < cost

func _refresh_hangar_controls(hangar_data: Dictionary) -> void:
	var available: Array[StringName] = []
	for complement in SidebayRunState.hangar_complement_catalog():
		if run_state.acquired_hangar_complement_ids.has(StringName(complement.id)):
			available.append(StringName(complement.id))
	var refit_cost := 0
	if available.size() > 1:
		var index := available.find(run_state.active_hangar_complement_id)
		refit_cost = run_state.hangar_refit_cost(available[(index + 1) % available.size()])
	hangar_button.text = "SELECT AIR GROUP  //  %s  //  NEXT %d SUP" % [hangar_data.get("name", "Air Group"), refit_cost]
	hangar_button.tooltip_text = str(hangar_data.get("summary", ""))
	hangar_button.disabled = available.size() < 2 or run_state.supplies < refit_cost
	var offer := run_state.next_hangar_complement_offer()
	if offer.is_empty():
		hangar_acquire_button.text = "FLIGHT-GROUP SUPPLIER  //  NO OFFER AVAILABLE"
		hangar_acquire_button.disabled = true
	else:
		var cost := int(offer.requisition_cost)
		hangar_acquire_button.text = "ACQUIRE %s  //  %d REQUISITION" % [offer.name, cost]
		hangar_acquire_button.tooltip_text = str(offer.summary)
		hangar_acquire_button.disabled = run_state.requisition < cost

func _refresh_escort_offer() -> void:
	var offer := run_state.next_escort_offer()
	if offer.is_empty():
		acquire_button.text = "ESCORT SUPPLIER  //  NO HULL AVAILABLE"
		acquire_button.disabled = true
	else:
		var cost := int(offer.requisition_cost)
		acquire_button.text = "ACQUIRE %s  //  %d REQUISITION" % [offer.name, cost]
		acquire_button.tooltip_text = "%s — %s" % [offer.class_name, offer.summary]
		acquire_button.disabled = run_state.requisition < cost

func _service_fleet() -> void:
	var cost := run_state.service_cost()
	if run_state.service_fleet():
		fleet_changed.emit("Fleet serviced for %d supplies. Carrier and air group are operational." % cost)
	else:
		fleet_changed.emit("Fleet service rejected: insufficient supplies.")
	refresh()

func _cycle_carrier() -> void:
	fleet_changed.emit(run_state.cycle_carrier())
	refresh()

func _acquire_carrier() -> void:
	fleet_changed.emit(run_state.acquire_next_carrier())
	refresh()

func _cycle_hangar() -> void:
	fleet_changed.emit(run_state.cycle_hangar_complement())
	refresh()

func _acquire_hangar() -> void:
	fleet_changed.emit(run_state.acquire_next_hangar_complement())
	refresh()

func _cycle_escort() -> void:
	fleet_changed.emit(run_state.cycle_escort())
	refresh()

func _acquire_escort() -> void:
	fleet_changed.emit(run_state.acquire_next_escort())
	refresh()

func _cycle_slot(slot: String) -> void:
	var module_id := run_state.cycle_module(slot)
	if module_id == &"":
		return
	var data := SidebayRunState.module_data(module_id)
	fleet_changed.emit("%s installed in the %s slot." % [data.get("name", "Module"), slot])
	refresh()

func _compact_button(parent: Control, position_value: Vector2, size_value: Vector2 = Vector2(430, 36)) -> Button:
	var button := _button(parent, "", position_value, size_value)
	button.add_theme_font_size_override("font_size", 12)
	return button

func _label(parent: Control, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	parent.add_child(label)
	return label

func _button(parent: Control, text_value: String, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	button.add_theme_font_size_override("font_size", 14)
	parent.add_child(button)
	return button
