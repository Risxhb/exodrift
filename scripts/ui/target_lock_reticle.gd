class_name ExodriftTargetLockReticle
extends Control

var bracket_span: float = 72.0
var solution_color: Color = Color(0.2, 0.9, 1.0, 0.95)
var lead_offset: Vector2 = Vector2.ZERO
var locked: bool = false
var pulse: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(160.0, 160.0)
	set_process(true)

func _process(delta: float) -> void:
	pulse = fmod(pulse + delta, TAU)
	queue_redraw()

func set_solution(span: float, color: Color, lead: Vector2, has_lock: bool) -> void:
	bracket_span = clampf(span, 48.0, 132.0)
	solution_color = color
	lead_offset = lead.limit_length(54.0)
	locked = has_lock
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var half := bracket_span * 0.5
	var corner := clampf(bracket_span * 0.2, 10.0, 22.0)
	var alpha := 0.82 + sin(pulse * 2.0) * (0.08 if locked else 0.16)
	var color := Color(solution_color.r, solution_color.g, solution_color.b, alpha)
	var weight := 2.0 if locked else 1.35
	var left := center.x - half
	var right := center.x + half
	var top := center.y - half
	var bottom := center.y + half
	for segment in [
		[Vector2(left, top + corner), Vector2(left, top), Vector2(left + corner, top)],
		[Vector2(right - corner, top), Vector2(right, top), Vector2(right, top + corner)],
		[Vector2(left, bottom - corner), Vector2(left, bottom), Vector2(left + corner, bottom)],
		[Vector2(right - corner, bottom), Vector2(right, bottom), Vector2(right, bottom - corner)],
	]:
		draw_polyline(PackedVector2Array(segment), color, weight, true)
	draw_arc(center, maxf(13.0, half * 0.34), -PI * 0.2 + pulse * 0.08, PI * 1.35 + pulse * 0.08, 28, Color(color.r, color.g, color.b, alpha * 0.52), 1.0, true)
	draw_line(center + Vector2(-7.0, 0.0), center + Vector2(7.0, 0.0), Color(color.r, color.g, color.b, alpha * 0.68), 1.0)
	draw_line(center + Vector2(0.0, -7.0), center + Vector2(0.0, 7.0), Color(color.r, color.g, color.b, alpha * 0.68), 1.0)
	var lead := center + lead_offset
	draw_circle(lead, 4.5, Color(color.r, color.g, color.b, alpha * 0.26))
	draw_arc(lead, 8.0, 0.0, TAU, 16, color, 1.5, true)
