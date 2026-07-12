class_name ExodriftOperationalEvent
extends Control

signal choice_selected(choice_id: StringName)

var run_state: SidebayRunState
var event_data: Dictionary
var choice_buttons: Array[Button] = []

func configure(state: SidebayRunState, operational_event: Dictionary) -> void:
	run_state = state
	event_data = operational_event.duplicate(true)
	_build_shell()

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var veil := ColorRect.new()
	veil.color = Color(0.001, 0.004, 0.01, 0.94)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var panel := Panel.new()
	panel.position = Vector2(190, 92)
	panel.size = Vector2(900, 536)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.035, 0.055, 1.0)
	style.border_color = Color(0.75, 0.52, 0.16, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.78)
	style.shadow_size = 20
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var kicker := _label(panel, Vector2(40, 28), Vector2(820, 24), 13)
	kicker.text = "OPERATIONAL EVENT // COMMAND DECISION REQUIRED"
	kicker.add_theme_color_override("font_color", Color(0.95, 0.7, 0.28))
	var title := _label(panel, Vector2(40, 62), Vector2(820, 48), 30)
	title.text = str(event_data.get("title", "OPERATIONAL EVENT"))
	var body := _label(panel, Vector2(40, 126), Vector2(820, 108), 17)
	body.text = str(event_data.get("body", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var radio := _label(panel, Vector2(40, 232), Vector2(820, 28), 14)
	radio.text = str(event_data.get("radio", ""))
	radio.add_theme_color_override("font_color", Color(0.95, 0.7, 0.28))
	var choices: Array = event_data.get("choices", [])
	for index in mini(2, choices.size()):
		var choice: Dictionary = choices[index]
		var button := Button.new()
		button.position = Vector2(40 + index * 415, 274)
		button.size = Vector2(405, 150)
		button.text = "%s\n\n%s" % [choice.get("label", "DECIDE"), choice.get("summary", "")]
		button.add_theme_font_size_override("font_size", 15)
		button.disabled = not run_state.can_resolve_event_choice(StringName(choice.get("id", "")))
		button.tooltip_text = "Insufficient supplies for this decision." if button.disabled else "Commit this operational decision."
		var choice_id := StringName(choice.get("id", ""))
		button.pressed.connect(func() -> void: choice_selected.emit(choice_id))
		panel.add_child(button)
		choice_buttons.append(button)
	var resources := _label(panel, Vector2(40, 462), Vector2(820, 30), 14)
	resources.text = "SUPPLIES %03d     FUEL %02d     INTEL %02d     REQUISITION %02d" % [run_state.supplies, run_state.fuel, run_state.intel, run_state.requisition]
	resources.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not choice_buttons.is_empty():
		for button in choice_buttons:
			if not button.disabled:
				button.grab_focus()
				break

func _label(parent: Control, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.76, 0.92, 1.0))
	parent.add_child(label)
	return label
