class_name ExodriftOnboardingController
extends CanvasLayer

enum Step { WELCOME, HELM, SENSOR, FLIGHT, COMMAND, ORDERS, COMPLETE }

var carrier: PlayerCarrier
var interceptor: SidebaySquadron
var scout: SidebaySquadron
var sensors: SidebaySensorSystem
var tactical: TacticalController
var current_step: Step = Step.WELCOME
var step_elapsed: float = 0.0
var starting_position: Vector3
var active_ping_observed: bool = false
var dismissed: bool = false
var panel: Panel
var step_label: Label
var instruction_label: Label
var progress_label: Label

func configure(
	player_carrier: PlayerCarrier,
	interceptor_wing: SidebaySquadron,
	scout_wing: SidebaySquadron,
	sensor_system: SidebaySensorSystem,
	tactical_controller: TacticalController
) -> void:
	carrier = player_carrier
	interceptor = interceptor_wing
	scout = scout_wing
	sensors = sensor_system
	tactical = tactical_controller
	starting_position = carrier.global_position
	if not sensors.active_ping_emitted.is_connected(_on_active_ping):
		sensors.active_ping_emitted.connect(_on_active_ping)
	_build_overlay()
	_set_step(Step.WELCOME)

func _build_overlay() -> void:
	layer = 18
	panel = Panel.new()
	panel.name = "GuidedOnboarding"
	panel.position = Vector2(360.0, 500.0)
	panel.size = Vector2(560.0, 116.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.022, 0.034, 0.95)
	style.border_color = Color(0.12, 0.72, 0.92, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.75)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var accent := ColorRect.new()
	accent.color = Color(0.95, 0.62, 0.16, 0.95)
	accent.position = Vector2(0.0, 0.0)
	accent.size = Vector2(6.0, 116.0)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(accent)
	step_label = _label(Vector2(20.0, 10.0), Vector2(360.0, 22.0), 13, Color(0.95, 0.68, 0.22))
	progress_label = _label(Vector2(390.0, 10.0), Vector2(148.0, 22.0), 11, Color(0.48, 0.72, 0.82))
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	instruction_label = _label(Vector2(20.0, 36.0), Vector2(518.0, 64.0), 15, Color(0.82, 0.94, 1.0))
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _label(position_value: Vector2, size_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(label)
	return label

func _process(delta: float) -> void:
	if dismissed or not is_instance_valid(carrier):
		return
	step_elapsed += delta
	match current_step:
		Step.WELCOME:
			if step_elapsed >= 3.0:
				_set_step(Step.HELM)
		Step.HELM:
			if step_elapsed >= 1.25 and (carrier.velocity.length() >= 30.0 or carrier.global_position.distance_to(starting_position) >= 60.0):
				_set_step(Step.SENSOR)
		Step.SENSOR:
			if step_elapsed >= 1.25 and active_ping_observed:
				_set_step(Step.FLIGHT)
		Step.FLIGHT:
			if step_elapsed >= 1.25 and (interceptor.operation.state != BayOperation.State.READY or scout.operation.state != BayOperation.State.READY):
				_set_step(Step.COMMAND)
		Step.COMMAND:
			if step_elapsed >= 1.25 and tactical.enabled:
				_set_step(Step.ORDERS)
		Step.ORDERS:
			if step_elapsed >= 1.25 and _player_order_observed():
				_set_step(Step.COMPLETE)
		Step.COMPLETE:
			if step_elapsed >= 7.0:
				dismiss()

func _player_order_observed() -> bool:
	return carrier.autopilot_active or interceptor.current_order != null or scout.current_order != null

func _on_active_ping(_position: Vector3, _radius_m: float) -> void:
	if current_step == Step.SENSOR:
		active_ping_observed = true

func _set_step(next_step: Step) -> void:
	current_step = next_step
	step_elapsed = 0.0
	if panel == null:
		return
	step_label.text = _step_title(next_step)
	instruction_label.text = _step_instruction(next_step)
	progress_label.text = "ORIENTATION   [F3] HIDE" if next_step == Step.WELCOME else "%d / 6   [F3] HIDE" % mini(int(next_step), 6)
	var recorder := get_node_or_null("/root/PlaytestRecorder") as ExodriftPlaytestRecorder
	if recorder != null:
		recorder.record_event(&"onboarding_step", {"step": Step.keys()[next_step]})
		if next_step == Step.COMPLETE:
			recorder.increment(&"onboarding_completed")

func _step_title(step: Step) -> String:
	match step:
		Step.WELCOME: return "FLIGHT ORIENTATION"
		Step.HELM: return "01  //  HELM CONTROL"
		Step.SENSOR: return "02  //  SENSOR PICTURE"
		Step.FLIGHT: return "03  //  FLIGHT OPERATIONS"
		Step.COMMAND: return "04  //  LIVE COMMAND"
		Step.ORDERS: return "05  //  ISSUE INTENT"
		_: return "ORIENTATION COMPLETE"

func _step_instruction(step: Step) -> String:
	match step:
		Step.WELCOME:
			return "Your carrier is the fleet's command node and its most important hull. Opening the tactical map never pauses combat."
		Step.HELM:
			return "Use W/S to set the carrier's persistent throttle. Double-click empty space to order a full-cruise heading; middle-drag orbits the command camera."
		Step.SENSOR:
			return "Contacts begin uncertain. Press P for an active ping: it identifies nearby targets, but broadcasts your position."
		Step.FLIGHT:
			return "Launch with Z or X. Re-press during servicing to queue an automatic redeploy after the craft recover and rearm."
		Step.COMMAND:
			return "Press Tab for the live tactical map. Combat continues while you inspect contacts and command the fleet."
		Step.ORDERS:
			return "Select a wing or the carrier, then right-click a contact or position. Shift queues orders; I orders an intercept."
		_:
			return "Command link established. Recall deployed wings before jump preparation; damaged or empty wings need time to service."

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		dismiss()
		get_viewport().set_input_as_handled()

func dismiss() -> void:
	dismissed = true
	if panel != null:
		panel.visible = false
