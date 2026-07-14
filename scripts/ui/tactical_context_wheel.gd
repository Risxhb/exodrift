class_name TacticalContextWheel
extends Control

signal action_selected(action_id: StringName, queued: bool)
signal cancelled

const OUTER_RADIUS := 126.0
const INNER_RADIUS := 34.0
const FLICK_RADIUS := 48.0

var active: bool = false
var choices: Array[Dictionary] = []
var wheel_center: Vector2 = Vector2.ZERO
var highlighted_index: int = -1
var queued: bool = false
var title: String = "COMMAND"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func open_at(screen_position: Vector2, next_choices: Array[Dictionary], queued_order: bool, caption: String = "COMMAND") -> void:
	choices = next_choices.duplicate(true)
	queued = queued_order
	title = caption
	var viewport_size := get_viewport_rect().size
	wheel_center = Vector2(
		clampf(screen_position.x, OUTER_RADIUS + 12.0, viewport_size.x - OUTER_RADIUS - 12.0),
		clampf(screen_position.y, OUTER_RADIUS + 12.0, viewport_size.y - OUTER_RADIUS - 12.0)
	)
	highlighted_index = -1
	active = not choices.is_empty()
	visible = active
	queue_redraw()

func close(emit_cancel: bool = false) -> void:
	var was_active := active
	active = false
	visible = false
	choices.clear()
	highlighted_index = -1
	queue_redraw()
	if was_active and emit_cancel:
		cancelled.emit()

func update_pointer(screen_position: Vector2, queued_order: bool) -> void:
	if not active:
		return
	queued = queued_order
	highlighted_index = _choice_at(screen_position)
	queue_redraw()

func release_flick(screen_position: Vector2, queued_order: bool) -> bool:
	if not active:
		return false
	update_pointer(screen_position, queued_order)
	if screen_position.distance_to(wheel_center) >= FLICK_RADIUS and highlighted_index >= 0:
		_execute(highlighted_index)
		return true
	queue_redraw()
	return true

func click(screen_position: Vector2, queued_order: bool) -> bool:
	if not active:
		return false
	update_pointer(screen_position, queued_order)
	if highlighted_index >= 0:
		_execute(highlighted_index)
	else:
		close(true)
	return true

func _choice_at(screen_position: Vector2) -> int:
	if choices.is_empty():
		return -1
	var offset := screen_position - wheel_center
	var distance := offset.length()
	if distance < INNER_RADIUS or distance > OUTER_RADIUS * 1.25:
		return -1
	var angle := wrapf(offset.angle() + PI * 0.5, 0.0, TAU)
	return clampi(int(floor(angle / (TAU / float(choices.size())))), 0, choices.size() - 1)

func _execute(index: int) -> void:
	if index < 0 or index >= choices.size():
		return
	var action_id := StringName(choices[index].get("id", ""))
	var queued_order := queued
	close(false)
	action_selected.emit(action_id, queued_order)

func _draw() -> void:
	if not active or choices.is_empty():
		return
	var dim := Color(0.006, 0.024, 0.038, 0.96)
	var cyan := Color(0.08, 0.72, 0.94, 0.96)
	var amber := Color(1.0, 0.58, 0.12, 0.98)
	var segment_angle := TAU / float(choices.size())
	for index in choices.size():
		var start_angle := -PI * 0.5 + segment_angle * float(index)
		var points := PackedVector2Array([wheel_center])
		for step in 9:
			var angle := start_angle + segment_angle * float(step) / 8.0
			points.append(wheel_center + Vector2(cos(angle), sin(angle)) * OUTER_RADIUS)
		var fill := Color(0.04, 0.30, 0.42, 0.94) if index == highlighted_index else dim
		draw_colored_polygon(points, fill)
		draw_arc(wheel_center, OUTER_RADIUS, start_angle, start_angle + segment_angle, 12, cyan if index == highlighted_index else Color(0.04, 0.35, 0.5, 0.8), 2.0)
		var label_angle := start_angle + segment_angle * 0.5
		var label_position := wheel_center + Vector2(cos(label_angle), sin(label_angle)) * 82.0
		var label := String(choices[index].get("label", choices[index].get("id", ""))).to_upper()
		var font := ThemeDB.fallback_font
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, label_position - Vector2(text_size.x * 0.5, -4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, amber if index == highlighted_index else Color(0.74, 0.9, 0.96))
	draw_circle(wheel_center, INNER_RADIUS, Color(0.002, 0.014, 0.024, 1.0))
	draw_arc(wheel_center, INNER_RADIUS, 0.0, TAU, 28, amber if queued else cyan, 2.0)
	var center_text := "QUEUE" if queued else title
	var center_font := ThemeDB.fallback_font
	var center_size := center_font.get_string_size(center_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	draw_string(center_font, wheel_center - Vector2(center_size.x * 0.5, -4.0), center_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, amber if queued else cyan)
