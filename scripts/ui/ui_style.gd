class_name ExodriftUIStyle
extends RefCounted

const TEXT_PRIMARY := Color(0.78, 0.93, 1.0)
const TEXT_MUTED := Color(0.48, 0.68, 0.78)
const CYAN := Color(0.12, 0.78, 1.0)
const CYAN_SOFT := Color(0.08, 0.42, 0.58)
const AMBER := Color(1.0, 0.62, 0.18)
const PANEL_BACKGROUND := Color(0.006, 0.024, 0.038, 0.92)

static func panel_style(background: Color = PANEL_BACKGROUND, accent: Color = CYAN_SOFT, border_width: int = 1, radius: int = 5) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = accent
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
	style.shadow_size = 8
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

static func apply_label(label: Label, font_size: int, color: Color = TEXT_PRIMARY) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.03, 0.8))

static func apply_button(button: Button, font_size: int = 14, accent: Color = CYAN) -> void:
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.34, 0.46, 0.52))
	button.add_theme_stylebox_override("normal", panel_style(Color(0.012, 0.045, 0.066, 0.96), Color(accent.r, accent.g, accent.b, 0.48), 1, 4))
	button.add_theme_stylebox_override("hover", panel_style(Color(0.02, 0.09, 0.13, 0.98), Color(accent.r, accent.g, accent.b, 0.95), 2, 4))
	button.add_theme_stylebox_override("pressed", panel_style(Color(0.025, 0.13, 0.18, 1.0), accent, 2, 4))
	button.add_theme_stylebox_override("focus", panel_style(Color(0.01, 0.07, 0.1, 0.72), Color(0.72, 0.95, 1.0, 0.95), 2, 4))
	button.add_theme_stylebox_override("disabled", panel_style(Color(0.01, 0.025, 0.035, 0.8), Color(0.16, 0.24, 0.28, 0.7), 1, 4))

static func apply_option_button(button: OptionButton, font_size: int = 14) -> void:
	apply_button(button, font_size, CYAN)

static func apply_check_button(button: CheckButton, font_size: int = 14) -> void:
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", CYAN)
