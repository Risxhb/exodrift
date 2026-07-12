class_name ExodriftAfterActionReport
extends Control

signal decision_selected(decision: StringName)

var run_state: SidebayRunState
var campaign_node: SidebayCampaignNode
var battle_report: Dictionary
var summary_label: Label
var rescue_button: Button
var salvage_button: Button
var withdraw_button: Button

func configure(state: SidebayRunState, node: SidebayCampaignNode, report: Dictionary) -> void:
	run_state = state
	campaign_node = node
	battle_report = report.duplicate(true)
	_build_shell()
	_refresh()

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var veil := ColorRect.new()
	veil.color = Color(0.002, 0.006, 0.014, 0.97)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var panel := Panel.new()
	panel.position = Vector2(165, 42)
	panel.size = Vector2(950, 636)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.035, 0.055, 1.0)
	panel_style.border_color = Color(0.16, 0.68, 0.9, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	var title := _label(panel, Vector2(34, 22), Vector2(880, 40), 28)
	title.text = "EXODRIFT // AFTER-ACTION REPORT"
	summary_label = _label(panel, Vector2(34, 78), Vector2(882, 320), 17)
	summary_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	rescue_button = _button(panel, Vector2(34, 418), Vector2(280, 112))
	rescue_button.pressed.connect(func() -> void: decision_selected.emit(&"rescue"))
	salvage_button = _button(panel, Vector2(335, 418), Vector2(280, 112))
	salvage_button.pressed.connect(func() -> void: decision_selected.emit(&"salvage"))
	withdraw_button = _button(panel, Vector2(636, 418), Vector2(280, 112))
	withdraw_button.pressed.connect(func() -> void: decision_selected.emit(&"immediate"))
	var note := _label(panel, Vector2(34, 552), Vector2(882, 54), 14)
	note.text = "One decision is final. Unrecovered craft and personnel remain lost when the task force departs."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _refresh() -> void:
	var outcome := str(battle_report.get("outcome", "unknown")).replace("_", " ").to_upper()
	var objective := campaign_node.objective_label() if campaign_node != null else "UNKNOWN OBJECTIVE"
	var interceptor_stragglers := int(battle_report.get("interceptor_stragglers", 0))
	var scout_stragglers := int(battle_report.get("scout_stragglers", 0))
	var escort_straggler := bool(battle_report.get("escort_straggler", false))
	var craft_stragglers := interceptor_stragglers + scout_stragglers
	var survivors_rescued := int(battle_report.get("survivors_rescued", 0))
	var survivors_adrift := int(battle_report.get("survivors_adrift", 0))
	var salvage_value := run_state.adjusted_salvage_yield(int(battle_report.get("salvage_value", 0))) if run_state != null else int(battle_report.get("salvage_value", 0))
	var named_risk := run_state.personnel_risk_summary(battle_report) if run_state != null else "NONE"
	summary_label.text = "%s // %s\n\nCARRIER  SHIELDS %3d%%  ARMOR %3d%%  HULL %3d%%\nAIR GROUP  INTERCEPTORS %d/%d  SCOUTS %d/%d\nESCORT  %s  //  %s\n\nSTRAGGLERS  %d interceptor  %d scout  %s\nESCAPE PODS  %d recovered / %d adrift  (%d personnel safe, %d awaiting recovery)\nNAMED PERSONNEL  %s\nHOSTILES DESTROYED  %d\nPROJECTED SALVAGE  %d allocation stock" % [
		outcome, objective,
		int(round(float(battle_report.get("carrier_shields", 0.0)) * 100.0)),
		int(round(float(battle_report.get("carrier_armor", 0.0)) * 100.0)),
		int(round(float(battle_report.get("carrier_hull", 0.0)) * 100.0)),
		int(battle_report.get("interceptor_craft_count", 0)), run_state.maximum_interceptor_craft() if run_state != null else SidebayRunState.MAX_INTERCEPTOR_CRAFT,
		int(battle_report.get("scout_craft_count", 0)), run_state.maximum_scout_craft() if run_state != null else SidebayRunState.MAX_SCOUT_CRAFT,
		str(battle_report.get("escort_name", "Escort")), "OPERATIONAL" if bool(battle_report.get("escort_active", false)) else "LOST OR SEPARATED",
		interceptor_stragglers, scout_stragglers, "escort separated" if escort_straggler else "escort accounted for",
		int(battle_report.get("escape_pods_rescued", 0)), int(battle_report.get("escape_pods_adrift", 0)), survivors_rescued, survivors_adrift,
		named_risk, int(battle_report.get("destroyed_hostile_count", 0)), salvage_value
	]
	var can_rescue := craft_stragglers > 0 or escort_straggler or survivors_adrift > 0
	rescue_button.text = "RESCUE OPERATION\n1 FUEL\nRecover all stragglers and pods"
	rescue_button.disabled = not can_rescue or run_state == null or run_state.fuel < 1 or str(battle_report.get("outcome", "")) == "carrier_lost"
	salvage_button.text = "SALVAGE SWEEP\n+%d SALVAGE STOCK\nAllocate later in Logistics" % salvage_value
	salvage_button.disabled = salvage_value <= 0 or str(battle_report.get("outcome", "")) == "carrier_lost"
	withdraw_button.text = "END RUN" if str(battle_report.get("outcome", "")) == "carrier_lost" else "WITHDRAW IMMEDIATELY\nNo fuel cost\nLeave the combat zone now"

func _label(parent: Control, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	parent.add_child(label)
	return label

func _button(parent: Control, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.position = position_value
	button.size = size_value
	button.add_theme_font_size_override("font_size", 14)
	parent.add_child(button)
	return button
