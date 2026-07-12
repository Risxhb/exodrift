class_name ExodriftLogisticsScreen
extends Control

signal closed
signal logistics_changed(message: String)

var run_state: SidebayRunState
var resource_label: Label
var posture_buttons: Dictionary = {}
var allocation_buttons: Dictionary = {}

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
	panel.position = Vector2(110, 70)
	panel.size = Vector2(1060, 580)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.035, 0.055, 1.0)
	style.border_color = Color(0.85, 0.58, 0.14, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var title := _label(panel, Vector2(38, 22), Vector2(760, 40), 27)
	title.text = "EXODRIFT // ROUTE LOGISTICS"
	resource_label = _label(panel, Vector2(38, 66), Vector2(980, 30), 18)
	var posture_title := _label(panel, Vector2(38, 108), Vector2(600, 30), 18)
	posture_title.text = "ROUTE POSTURE // APPLIES TO THE NEXT JUMP AND RECOVERY"
	for index in SidebayRunState.logistics_posture_catalog().size():
		var posture: Dictionary = SidebayRunState.logistics_posture_catalog()[index]
		var posture_id := StringName(posture.id)
		var button := _button(panel, Vector2(38 + index * 330, 146), Vector2(310, 118))
		button.pressed.connect(func() -> void: _select_posture(posture_id))
		posture_buttons[posture_id] = button
	var allocation_title := _label(panel, Vector2(38, 292), Vector2(600, 30), 18)
	allocation_title.text = "SALVAGE ALLOCATION // FIXED CONVERSION ORDERS"
	for index in SidebayRunState.salvage_allocation_catalog().size():
		var allocation: Dictionary = SidebayRunState.salvage_allocation_catalog()[index]
		var allocation_id := StringName(allocation.id)
		var button := _button(panel, Vector2(38 + index * 330, 330), Vector2(310, 108))
		button.pressed.connect(func() -> void: _allocate_salvage(allocation_id))
		allocation_buttons[allocation_id] = button
	var close_button := _button(panel, Vector2(38, 474), Vector2(970, 48))
	close_button.text = "RETURN TO SECTOR MAP"
	close_button.pressed.connect(func() -> void: closed.emit())
	var note := _label(panel, Vector2(38, 536), Vector2(970, 24), 13)
	note.text = "All conversions and route costs are deterministic. No randomized loot or permanent power is introduced."

func refresh() -> void:
	if run_state == null:
		return
	resource_label.text = "SUPPLIES %03d     FUEL %02d     REQUISITION %02d     SALVAGE STOCK %03d" % [run_state.supplies, run_state.fuel, run_state.requisition, run_state.salvage_stock]
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

func _label(parent: Control, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.82, 0.94, 1.0))
	parent.add_child(label)
	return label

func _button(parent: Control, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.position = position_value
	button.size = size_value
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", 14)
	parent.add_child(button)
	return button
