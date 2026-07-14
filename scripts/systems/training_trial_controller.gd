class_name ExodriftTrainingTrialController
extends CanvasLayer

signal completed
signal exit_requested(completed_trial: bool)
signal target_lock_requested(entity_id: StringName)

enum Step { WELCOME, HELM, TACTICAL, ESCORT_MOVE, QUEUE_WAYPOINT, DOCTRINE, SENSOR, FLIGHT, ENGAGE, COMPLETE }

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const GUIDED_STEP_COUNT := 8

var carrier: PlayerCarrier
var escort: CombatShip
var interceptor: SidebaySquadron
var sensors: SidebaySensorSystem
var tactical: TacticalController
var target_dummy: CombatShip
var hud: SidebayHUD
var navigation_gate: Node3D
var current_step: Step = Step.WELCOME
var step_elapsed: float = 0.0
var starting_carrier_position: Vector3
var active_ping_observed: bool = false
var trial_complete: bool = false
var panel: Panel
var step_label: Label
var instruction_label: Label
var progress_label: Label
var footer_label: Label


func configure(
	player_carrier: PlayerCarrier,
	player_escort: CombatShip,
	interceptor_wing: SidebaySquadron,
	sensor_system: SidebaySensorSystem,
	tactical_controller: TacticalController,
	training_target: CombatShip,
	combat_hud: SidebayHUD,
	training_gate: Node3D
) -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	carrier = player_carrier
	escort = player_escort
	interceptor = interceptor_wing
	sensors = sensor_system
	tactical = tactical_controller
	target_dummy = training_target
	hud = combat_hud
	navigation_gate = training_gate
	if is_instance_valid(target_dummy):
		target_dummy.incoming_damage_multiplier = 0.0
	starting_carrier_position = carrier.global_position
	if not sensors.active_ping_emitted.is_connected(_on_active_ping):
		sensors.active_ping_emitted.connect(_on_active_ping)
	if is_instance_valid(target_dummy) and not target_dummy.ship_destroyed.is_connected(_on_target_destroyed):
		target_dummy.ship_destroyed.connect(_on_target_destroyed)
	_build_overlay()
	_set_step(Step.WELCOME)


func _build_overlay() -> void:
	panel = Panel.new()
	panel.name = "CombatTrialGuide"
	panel.position = Vector2(328.0, 526.0)
	panel.size = Vector2(624.0, 166.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UIStyle.panel_style(Color(0.003, 0.019, 0.032, 0.96), UIStyle.CYAN, 2, 6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.82)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var phase_bar := ColorRect.new()
	phase_bar.color = UIStyle.AMBER
	phase_bar.position = Vector2(0.0, 0.0)
	phase_bar.size = Vector2(7.0, panel.size.y)
	phase_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(phase_bar)

	var channel_label := _label(Vector2(22.0, 10.0), Vector2(360.0, 18.0), 10, UIStyle.CYAN)
	channel_label.text = "CVN SIDEBAY // SAFE COMBAT TRIAL"
	step_label = _label(Vector2(22.0, 31.0), Vector2(420.0, 26.0), 16, UIStyle.AMBER)
	progress_label = _label(Vector2(438.0, 13.0), Vector2(164.0, 22.0), 11, UIStyle.TEXT_MUTED)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	instruction_label = _label(Vector2(22.0, 62.0), Vector2(580.0, 64.0), 14, UIStyle.TEXT_PRIMARY)
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_label = _label(Vector2(22.0, 137.0), Vector2(580.0, 18.0), 10, UIStyle.TEXT_MUTED)
	footer_label.text = "[F9] RETURN TO TITLE  //  THE TRAINING DRONE CANNOT RETURN FIRE"


func _label(position_value: Vector2, size_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size, color)
	panel.add_child(label)
	return label


func _process(delta: float) -> void:
	if trial_complete or not is_instance_valid(carrier):
		return
	step_elapsed += delta
	match current_step:
		Step.WELCOME:
			if step_elapsed >= 2.5:
				_set_step(Step.HELM)
		Step.HELM:
			if step_elapsed >= 0.8 and (carrier.global_position.distance_to(starting_carrier_position) >= 120.0 or carrier.velocity.length() >= 35.0):
				_set_step(Step.TACTICAL)
		Step.TACTICAL:
			if step_elapsed >= 0.8 and tactical.enabled:
				_set_step(Step.ESCORT_MOVE)
		Step.ESCORT_MOVE:
			if step_elapsed >= 0.8 and _escort_move_observed():
				_set_step(Step.QUEUE_WAYPOINT)
		Step.QUEUE_WAYPOINT:
			if step_elapsed >= 0.8 and _queued_waypoint_observed():
				_set_step(Step.DOCTRINE)
		Step.DOCTRINE:
			if step_elapsed >= 0.8 and _doctrine_change_observed():
				_set_step(Step.SENSOR)
		Step.SENSOR:
			if step_elapsed >= 0.8 and active_ping_observed:
				_set_step(Step.FLIGHT)
		Step.FLIGHT:
			if step_elapsed >= 0.8 and interceptor.operation.state != BayOperation.State.READY:
				_set_step(Step.ENGAGE)


func _escort_move_observed() -> bool:
	if not is_instance_valid(escort):
		return false
	var order := escort.command_link.last_confirmed_order
	return order != null and order.order_type == FleetOrder.OrderType.MOVE


func _queued_waypoint_observed() -> bool:
	return is_instance_valid(escort) and escort.fleet_command != null and not escort.fleet_command.order_queue.is_empty()


func _doctrine_change_observed() -> bool:
	if not is_instance_valid(escort):
		return false
	return escort.stance != &"balanced" or escort.formation_name != &"wedge" or escort.formation_spacing != &"standard"


func _on_active_ping(_position: Vector3, _radius_m: float) -> void:
	active_ping_observed = true
	if is_instance_valid(target_dummy) and sensors.is_targetable(target_dummy.stable_entity_id):
		target_lock_requested.emit(target_dummy.stable_entity_id)


func _on_target_destroyed(_entity_id: StringName) -> void:
	complete_trial()


func complete_trial() -> void:
	if trial_complete:
		return
	trial_complete = true
	_set_step(Step.COMPLETE)
	completed.emit()


func _set_step(next_step: Step) -> void:
	current_step = next_step
	step_elapsed = 0.0
	if panel == null:
		return
	step_label.text = _step_title(next_step)
	instruction_label.text = _step_instruction(next_step)
	progress_label.text = "CALIBRATING" if next_step == Step.WELCOME else ("TRIAL COMPLETE" if next_step == Step.COMPLETE else "%02d / %02d" % [int(next_step), GUIDED_STEP_COUNT])
	if is_instance_valid(hud):
		hud.set_objective(_objective_text(next_step))
	if is_instance_valid(navigation_gate):
		navigation_gate.visible = next_step in [Step.WELCOME, Step.HELM]
	if next_step == Step.COMPLETE:
		footer_label.text = "PRESS [ENTER] OR [F9] TO RETURN TO TITLE"
	elif next_step == Step.ENGAGE and is_instance_valid(target_dummy):
		target_dummy.incoming_damage_multiplier = 1.0


func _step_title(step: Step) -> String:
	match step:
		Step.WELCOME: return "COMBAT SYSTEMS CALIBRATION"
		Step.HELM: return "01  //  MOVE THE CARRIER"
		Step.TACTICAL: return "02  //  OPEN TACTICAL COMMAND"
		Step.ESCORT_MOVE: return "03  //  MOVE THE ESCORT"
		Step.QUEUE_WAYPOINT: return "04  //  QUEUE A WAYPOINT"
		Step.DOCTRINE: return "05  //  SET FLEET DOCTRINE"
		Step.SENSOR: return "06  //  IDENTIFY THE TARGET"
		Step.FLIGHT: return "07  //  LAUNCH A WING"
		Step.ENGAGE: return "08  //  DISABLE THE TARGET DUMMY"
		_: return "COMBAT TRIAL COMPLETE"


func _objective_text(step: Step) -> String:
	match step:
		Step.WELCOME: return "COMBAT TRIAL  Calibrating safe-range systems"
		Step.HELM: return "COMBAT TRIAL  01/08 Move the carrier"
		Step.TACTICAL: return "COMBAT TRIAL  02/08 Open tactical command"
		Step.ESCORT_MOVE: return "COMBAT TRIAL  03/08 Move ISS Resolute"
		Step.QUEUE_WAYPOINT: return "COMBAT TRIAL  04/08 Queue a second waypoint"
		Step.DOCTRINE: return "COMBAT TRIAL  05/08 Change doctrine or spacing"
		Step.SENSOR: return "COMBAT TRIAL  06/08 Identify the target dummy"
		Step.FLIGHT: return "COMBAT TRIAL  07/08 Launch Raptor wing"
		Step.ENGAGE: return "COMBAT TRIAL  08/08 Disable the target dummy"
		_: return "COMBAT TRIAL COMPLETE  Target dummy disabled"


func _step_instruction(step: Step) -> String:
	match step:
		Step.WELCOME:
			return "This range is inert: the amber drone cannot fire and the trial never changes your campaign or supplies. Follow each live prompt."
		Step.HELM:
			return "Use %s / %s to set persistent throttle and move toward the cyan navigation gate. %s stops the carrier." % [_key("accelerate"), _key("decelerate"), _key("brake")]
		Step.TACTICAL:
			return "Press %s to open the live tactical map. Its grid is anchored to the carrier; [HOME] recenters it after [SHIFT]+middle-mouse panning. Combat keeps running." % _key("toggle_tactical")
		Step.ESCORT_MOVE:
			return "Press [F2] to select ISS Resolute. Hold right mouse on empty grid space, flick toward MOVE and release; releasing near the center leaves the wheel open for precise clicking."
		Step.QUEUE_WAYPOINT:
			return "Hold [SHIFT] and use the right-click command wheel to add a second MOVE leg. The numbered path shows the active leg and queued waypoint."
		Step.DOCTRINE:
			return "Open the command wheel and choose DOCTRINE. Change stance, formation, or spacing; these choices alter pursuit, return thresholds, and fleet geometry."
		Step.SENSOR:
			return "Press %s for an active ping. The trial computer will identify and lock the amber target drone." % _key("sensor_ping")
		Step.FLIGHT:
			return "Press %s to launch the Raptor interceptor wing from the port bay." % _key("interceptor_wing")
		Step.ENGAGE:
			return "Fire a guided salvo with %s, or select Raptor with [F3] and use ATTACK or INTERCEPT on the identified target. Disable the drone to pass." % _key("missile_salvo")
		_:
			return "Helm, fleet doctrine, sensors, flight operations, and weapons are responding. You are cleared for a live operation."


func _key(action: String) -> String:
	return "[%s]" % ExodriftInputSettings.key_label(action)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		exit_requested.emit(trial_complete)
		get_viewport().set_input_as_handled()
