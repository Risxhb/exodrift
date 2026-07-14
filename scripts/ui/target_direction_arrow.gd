class_name ExodriftTargetDirectionArrow
extends Control

var arrow_color := Color(0.25, 0.92, 1.0, 0.96)
var pulse := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(38.0, 38.0)
	set_process(true)

func _process(delta: float) -> void:
	pulse = fmod(pulse + delta, TAU)
	queue_redraw()

func _draw() -> void:
	var center_x := size.x * 0.5
	var top := 2.0
	var shoulder_y := size.y * 0.48
	var shaft_top := size.y * 0.46
	var bottom := size.y - 3.0
	var half_head := minf(size.x * 0.42, 16.0)
	var half_shaft := minf(size.x * 0.14, 5.5)
	var points := PackedVector2Array([
		Vector2(center_x, top),
		Vector2(center_x + half_head, shoulder_y),
		Vector2(center_x + half_shaft, shaft_top),
		Vector2(center_x + half_shaft, bottom),
		Vector2(center_x - half_shaft, bottom),
		Vector2(center_x - half_shaft, shaft_top),
		Vector2(center_x - half_head, shoulder_y),
	])
	var alpha := arrow_color.a * (0.82 + sin(pulse * 2.4) * 0.12)
	var fill := Color(arrow_color.r, arrow_color.g, arrow_color.b, alpha * 0.24)
	var line := Color(arrow_color.r, arrow_color.g, arrow_color.b, alpha)
	draw_colored_polygon(points, fill)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, line, 2.2, true)
	draw_line(Vector2(center_x, 8.0), Vector2(center_x, bottom - 5.0), Color(line.r, line.g, line.b, alpha * 0.64), 1.0, true)
