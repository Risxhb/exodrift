class_name ExodriftPlaytestReport
extends Control

const UIStyle := preload("res://scripts/ui/ui_style.gd")

signal closed

var recorder: ExodriftPlaytestRecorder
var notes: TextEdit
var status_label: Label

func configure(source: ExodriftPlaytestRecorder) -> void:
	recorder = source
	_build_ui()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.006, 0.012, 0.9)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var panel := Panel.new()
	panel.position = Vector2(120, 42)
	panel.size = Vector2(1040, 636)
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.006, 0.024, 0.038, 0.98), UIStyle.CYAN, 2, 6))
	add_child(panel)
	var title := _label(panel, Vector2(28, 20), Vector2(984, 40), 25, UIStyle.CYAN)
	title.text = "M15 // EXTERNAL PLAYTEST DEBRIEF"
	var summary := TextEdit.new()
	summary.position = Vector2(28, 72)
	summary.size = Vector2(620, 500)
	summary.text = recorder.summary_text()
	summary.editable = false
	summary.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	summary.add_theme_font_size_override("font_size", 13)
	panel.add_child(summary)
	var prompt := _label(panel, Vector2(674, 76), Vector2(330, 46), 14, UIStyle.AMBER)
	prompt.text = "TESTER NOTES\nAnswer the six questions in the debrief."
	notes = TextEdit.new()
	notes.position = Vector2(674, 132)
	notes.size = Vector2(330, 330)
	notes.placeholder_text = "What confused you? What felt memorable? What should change?"
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.add_theme_font_size_override("font_size", 14)
	panel.add_child(notes)
	var copy_button := _button(panel, "SAVE + COPY DEBRIEF", Vector2(674, 482), Vector2(330, 44))
	copy_button.pressed.connect(_copy_report)
	var close_button := _button(panel, "RETURN TO OPERATION", Vector2(674, 536), Vector2(330, 44))
	close_button.pressed.connect(func() -> void: closed.emit())
	status_label = _label(panel, Vector2(674, 590), Vector2(330, 24), 12, UIStyle.TEXT_MUTED)
	status_label.text = "Report snapshot: %s" % recorder.report_path()
	close_button.grab_focus()

func _copy_report() -> void:
	recorder.record_feedback(notes.text)
	DisplayServer.clipboard_set(recorder.summary_text())
	status_label.text = "Debrief saved and copied to clipboard."

func _label(parent: Node, position_value: Vector2, size_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size, color)
	parent.add_child(label)
	return label

func _button(parent: Node, text_value: String, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	UIStyle.apply_button(button, 14)
	parent.add_child(button)
	return button
