class_name ExodriftPersonnelScreen
extends Control

const UIStyle := preload("res://scripts/ui/ui_style.gd")

signal closed
signal personnel_changed(message: String)

var run_state: SidebayRunState
var summary_label: Label
var event_label: Label
var department_buttons: Dictionary = {}
var treatment_button: Button
var promotion_button: Button
var recruit_button: Button

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
	panel.position = Vector2(50, 26)
	panel.size = Vector2(1180, 668)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.035, 0.055, 1.0)
	style.border_color = Color(0.16, 0.68, 0.9, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var title := _label(panel, Vector2(30, 18), Vector2(760, 40), 28)
	title.text = "EXODRIFT // PERSONNEL COMMAND"
	summary_label = _label(panel, Vector2(30, 60), Vector2(800, 28), 15)
	for index in SidebayRunState.departments().size():
		var department := SidebayRunState.departments()[index]
		var column := index % 2
		var row := index / 2
		var button := _button(panel, Vector2(30 + column * 560, 104 + row * 136), Vector2(535, 118))
		button.pressed.connect(func() -> void: _cycle_department(department))
		department_buttons[String(department)] = button
	treatment_button = _button(panel, Vector2(30, 516), Vector2(265, 60))
	treatment_button.pressed.connect(_treat_next)
	promotion_button = _button(panel, Vector2(315, 516), Vector2(265, 60))
	promotion_button.pressed.connect(_promote_next)
	recruit_button = _button(panel, Vector2(600, 516), Vector2(265, 60))
	recruit_button.pressed.connect(_recruit_next)
	var event_heading := _label(panel, Vector2(30, 586), Vector2(300, 20), 12)
	event_heading.text = "LATEST PERSONNEL LOG"
	event_label = _label(panel, Vector2(30, 608), Vector2(820, 38), 12)
	event_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var close_button := _button(panel, Vector2(885, 586), Vector2(265, 54))
	close_button.text = "RETURN TO SECTOR MAP"
	close_button.pressed.connect(func() -> void: closed.emit())

func refresh() -> void:
	if run_state == null:
		return
	var active := 0
	var injured := 0
	var deceased := 0
	for person in run_state.personnel_roster:
		match person.status:
			SidebayPersonnelRecord.Status.ACTIVE:
				active += 1
			SidebayPersonnelRecord.Status.INJURED:
				injured += 1
			SidebayPersonnelRecord.Status.DECEASED:
				deceased += 1
	summary_label.text = "ACTIVE %02d     INJURED %02d     KIA %02d     REQUISITION %02d     ASSIGNMENTS APPLY NEXT DEPLOYMENT" % [active, injured, deceased, run_state.requisition]
	for department in SidebayRunState.departments():
		var assigned := run_state.assigned_person(department)
		var members := run_state.department_members(department)
		var effect := _effect_description(department, assigned.effective_skill() if assigned != null else 0)
		var button: Button = department_buttons[String(department)]
		var lead_line := "NO AVAILABLE LEAD"
		var reserve_line := "NO RESERVE PERSONNEL"
		var bond_line := "BONDS NONE"
		if assigned != null:
			lead_line = "LEAD %s %s // %s // SKILL %d // %s" % [assigned.rank, assigned.display_name, assigned.role, assigned.effective_skill(), ", ".join(assigned.traits)]
			var bond_names: Array[String] = []
			for bond_id in assigned.bonds:
				var bonded := run_state.get_personnel(bond_id)
				if bonded != null:
					bond_names.append(bonded.display_name)
			bond_line = "BONDS %s" % (", ".join(bond_names) if not bond_names.is_empty() else "NONE")
		for person in members:
			if person != assigned:
				reserve_line = "RESERVE %s // %s // ROSTER %d" % [person.display_name, person.status_label(), members.size()]
				break
		button.text = "%s  //  %s\n%s\n%s\n%s  //  CLICK TO CYCLE" % [String(department).to_upper(), effect, lead_line, reserve_line, bond_line]
		button.disabled = _available_count(members) <= 1
	var injured_person := run_state.next_injured_person()
	var treatment_cost := run_state.treatment_cost(injured_person)
	treatment_button.text = "TREAT %s\n%d SUPPLIES" % [injured_person.display_name, treatment_cost] if injured_person != null else "NO TREATMENT REQUIRED"
	treatment_button.disabled = injured_person == null or run_state.supplies < treatment_cost
	var promotion_candidate := run_state.next_promotion_candidate()
	promotion_button.text = "PROMOTE %s\n20 SUPPLIES" % promotion_candidate.display_name if promotion_candidate != null else "NO PROMOTION ELIGIBLE"
	promotion_button.disabled = promotion_candidate == null or run_state.supplies < 20
	var recruit_candidate := run_state.next_recruit_candidate()
	recruit_button.text = "RECRUIT %s%s\n%d REQUISITION" % [recruit_candidate.display_name, " // RARE" if recruit_candidate.rare_recruit else "", recruit_candidate.recruitment_cost] if recruit_candidate != null else "RECRUITMENT POOL EMPTY"
	recruit_button.disabled = recruit_candidate == null or run_state.requisition < recruit_candidate.recruitment_cost
	var events := run_state.personnel_event_log
	event_label.text = "No casualties or recovery events recorded." if events.is_empty() else "\n".join(events.slice(maxi(0, events.size() - 3), events.size()))

func _cycle_department(department: StringName) -> void:
	var selected := run_state.cycle_department_assignment(department)
	if selected != null:
		personnel_changed.emit("%s assigned to lead %s." % [selected.display_name, String(department)])
	refresh()

func _treat_next() -> void:
	var message := run_state.treat_next_injury()
	personnel_changed.emit(message)
	refresh()

func _promote_next() -> void:
	var message := run_state.promote_next_candidate()
	personnel_changed.emit(message)
	refresh()

func _recruit_next() -> void:
	var message := run_state.recruit_next_candidate()
	personnel_changed.emit(message)
	refresh()

func _available_count(members: Array[SidebayPersonnelRecord]) -> int:
	var count := 0
	for person in members:
		if person.is_available():
			count += 1
	return count

func _effect_description(department: StringName, skill: int) -> String:
	match department:
		&"Command":
			return "+%d%% COMMAND RANGE" % (skill * 3)
		&"Flight":
			return "-%d%% WING SERVICE TIME" % (skill * 4)
		&"Gunnery":
			return "+%.1f%% CARRIER WEAPON DAMAGE" % (skill * 2.5)
		&"Engineering":
			return "+%.1f%% CARRIER HULL" % (skill * 2.5)
		&"Sensors":
			return "+%d%% SENSOR RANGE" % (skill * 3)
		&"Medical":
			return "POD INJURY SEVERITY REDUCED" if skill >= 4 else "STANDARD TRIAGE"
		_:
			return "NO ACTIVE EFFECT"

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
	UIStyle.apply_button(button, 13)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(button)
	return button
