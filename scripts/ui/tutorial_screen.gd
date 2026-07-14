class_name ExodriftTutorialScreen
extends CanvasLayer

signal closed
signal trial_requested

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const PORTRAIT_ATLAS := preload("res://assets/tutorial/mara_voss_atlas.png")
const TYPE_RATE := 36.0
const LESSON_TITLES := [
	"COMMAND LINK ESTABLISHED",
	"HELM AND COMBAT CAMERA",
	"SENSORS AND TARGET LOCK",
	"FIRE CONTROL",
	"HANGAR AND AIR GROUPS",
	"LIVE TACTICAL COMMAND",
	"CARRIER OPERATIONS",
	"OPERATIONAL CAMPAIGN",
	"ORIENTATION COMPLETE",
]
const POSE_ROWS := [0, 0, 0, 1, 1, 1, 1, 2, 2]
const EYE_OVERLAY_Y := [0.380, 0.405, 0.425]
const MOUTH_OVERLAY_Y := [0.575, 0.600, 0.635]

var root: Control
var portrait: TextureRect
var eye_overlay: TextureRect
var mouth_overlay: TextureRect
var title_label: Label
var dialogue_label: Label
var progress_label: Label
var next_button: Button
var back_button: Button
var lesson_index := 0
var full_text := ""
var revealed_characters := 0
var reveal_accumulator := 0.0
var punctuation_delay := 0.0
var mouth_elapsed := 0.0
var mouth_open := false
var blink_closed := false
var blink_elapsed := 0.0
var blink_hold := 0.0
var next_blink := 3.2
var last_portrait_frame := Vector2i(-1, -1)

func configure() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	ExodriftInputSettings.ensure_actions()
	_build_interface()
	_show_lesson(0)

func _build_interface() -> void:
	root = Control.new()
	root.name = "TutorialCommunications"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_root_gui_input)
	add_child(root)
	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.006, 0.014, 0.88)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)
	var frame := Panel.new()
	frame.name = "CommunicationsFrame"
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.position = Vector2(-560.0, -290.0)
	frame.size = Vector2(1120.0, 580.0)
	frame.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.004, 0.018, 0.032, 0.98), UIStyle.CYAN, 2, 8))
	root.add_child(frame)
	var header := ColorRect.new()
	header.color = Color(0.04, 0.48, 0.66, 0.72)
	header.position = Vector2(0.0, 0.0)
	header.size = Vector2(1120.0, 4.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(header)
	var comms_label := _label(frame, Vector2(30.0, 20.0), Vector2(520.0, 28.0), 14, UIStyle.CYAN)
	comms_label.text = "PRIORITY TRAINING CHANNEL // CVN SIDEBAY"
	progress_label = _label(frame, Vector2(850.0, 20.0), Vector2(240.0, 28.0), 13, UIStyle.TEXT_MUTED)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var portrait_frame := Panel.new()
	portrait_frame.position = Vector2(28.0, 66.0)
	portrait_frame.size = Vector2(350.0, 470.0)
	portrait_frame.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.006, 0.03, 0.05, 0.96), UIStyle.CYAN_SOFT, 1, 10))
	frame.add_child(portrait_frame)
	portrait = TextureRect.new()
	portrait.name = "MaraVossPortrait"
	portrait.position = Vector2(18.0, 18.0)
	portrait.size = Vector2(314.0, 418.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.material = _portrait_mask_material()
	portrait_frame.add_child(portrait)
	eye_overlay = _portrait_layer("MaraVossEyes")
	eye_overlay.material = _eye_overlay_material()
	eye_overlay.visible = false
	portrait_frame.add_child(eye_overlay)
	mouth_overlay = _portrait_layer("MaraVossMouth")
	mouth_overlay.material = _mouth_overlay_material()
	mouth_overlay.visible = false
	portrait_frame.add_child(mouth_overlay)
	var nameplate := _label(portrait_frame, Vector2(14.0, 432.0), Vector2(270.0, 26.0), 12, UIStyle.AMBER)
	nameplate.text = "CMDR. MARA VOSS"
	nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dialogue_panel := Panel.new()
	dialogue_panel.position = Vector2(318.0, 214.0)
	dialogue_panel.size = Vector2(772.0, 322.0)
	dialogue_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue_panel.gui_input.connect(_on_dialogue_input)
	dialogue_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.003, 0.016, 0.029, 0.98), UIStyle.AMBER, 2, 6))
	frame.add_child(dialogue_panel)
	title_label = _label(dialogue_panel, Vector2(28.0, 22.0), Vector2(716.0, 38.0), 22, UIStyle.AMBER)
	dialogue_label = _label(dialogue_panel, Vector2(28.0, 72.0), Vector2(716.0, 158.0), 17, UIStyle.TEXT_PRIMARY)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var hint := _label(dialogue_panel, Vector2(28.0, 236.0), Vector2(430.0, 24.0), 11, UIStyle.TEXT_MUTED)
	hint.text = "CLICK OR SPACE: COMPLETE / ADVANCE"
	back_button = _button(dialogue_panel, "BACK", Vector2(476.0, 264.0), Vector2(108.0, 38.0))
	back_button.pressed.connect(_previous_lesson)
	next_button = _button(dialogue_panel, "NEXT", Vector2(596.0, 264.0), Vector2(148.0, 38.0))
	next_button.pressed.connect(_advance)
	var exit_button := _button(frame, "EXIT TUTORIAL", Vector2(918.0, 74.0), Vector2(172.0, 38.0))
	exit_button.pressed.connect(close)

func _portrait_layer(layer_name: String) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = layer_name
	layer.position = Vector2(18.0, 18.0)
	layer.size = Vector2(314.0, 418.0)
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer

func _portrait_mask_material() -> ShaderMaterial:
	var mask_shader := Shader.new()
	mask_shader.code = """
shader_type canvas_item;
uniform vec2 atlas_offset = vec2(0.0);
uniform vec2 atlas_scale = vec2(0.25, 0.3333333333);
float portrait_mask(vec2 uv) {
	vec2 p = abs(uv - vec2(0.5)) - vec2(0.43, 0.44) + vec2(0.08);
	float d = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - 0.08;
	return 1.0 - smoothstep(-0.006, 0.006, d);
}
void fragment() {
	vec2 local_uv = (UV - atlas_offset) / atlas_scale;
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb, tex.a * portrait_mask(local_uv));
}
"""
	var mask_material := ShaderMaterial.new()
	mask_material.shader = mask_shader
	return mask_material

func _eye_overlay_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float feature_y = 0.38;
uniform vec2 atlas_offset = vec2(0.5, 0.0);
uniform vec2 atlas_scale = vec2(0.25, 0.3333333333);
float portrait_mask(vec2 uv) {
	vec2 p = abs(uv - vec2(0.5)) - vec2(0.43, 0.44) + vec2(0.08);
	float d = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - 0.08;
	return 1.0 - smoothstep(-0.006, 0.006, d);
}
float patch_mask(vec2 uv, vec2 center, vec2 half_size) {
	vec2 q = abs(uv - center) - half_size;
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.025;
	return 1.0 - smoothstep(-0.018, 0.018, d);
}
void fragment() {
	vec2 local_uv = (UV - atlas_offset) / atlas_scale;
	float eyes = max(
		patch_mask(local_uv, vec2(0.355, feature_y), vec2(0.135, 0.060)),
		patch_mask(local_uv, vec2(0.645, feature_y), vec2(0.135, 0.060))
	);
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb, tex.a * portrait_mask(local_uv) * eyes);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _mouth_overlay_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float feature_y = 0.575;
uniform vec2 atlas_offset = vec2(0.25, 0.0);
uniform vec2 atlas_scale = vec2(0.25, 0.3333333333);
float portrait_mask(vec2 uv) {
	vec2 p = abs(uv - vec2(0.5)) - vec2(0.43, 0.44) + vec2(0.08);
	float d = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - 0.08;
	return 1.0 - smoothstep(-0.006, 0.006, d);
}
float patch_mask(vec2 uv, vec2 center, vec2 half_size) {
	vec2 q = abs(uv - center) - half_size;
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.025;
	return 1.0 - smoothstep(-0.018, 0.018, d);
}
void fragment() {
	vec2 local_uv = (UV - atlas_offset) / atlas_scale;
	float mouth = patch_mask(local_uv, vec2(0.5, feature_y), vec2(0.145, 0.070));
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb, tex.a * portrait_mask(local_uv) * mouth);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _process(delta: float) -> void:
	_process_blink(delta)
	if revealed_characters >= full_text.length():
		if mouth_open:
			mouth_open = false
			_update_portrait()
		return
	if punctuation_delay > 0.0:
		punctuation_delay = maxf(0.0, punctuation_delay - delta)
		return
	reveal_accumulator += delta * TYPE_RATE
	while reveal_accumulator >= 1.0 and revealed_characters < full_text.length():
		reveal_accumulator -= 1.0
		revealed_characters += 1
		dialogue_label.visible_characters = revealed_characters
		var character := full_text.substr(revealed_characters - 1, 1)
		if character in [".", "!", "?", ":"]:
			punctuation_delay = 0.18
			break
	mouth_elapsed += delta
	if mouth_elapsed >= 0.09:
		mouth_elapsed = 0.0
		mouth_open = not mouth_open
		_update_portrait()

func _process_blink(delta: float) -> void:
	if blink_closed:
		blink_hold -= delta
		if blink_hold <= 0.0:
			blink_closed = false
			blink_elapsed = 0.0
			next_blink = randf_range(2.5, 4.5)
			_update_portrait()
		return
	blink_elapsed += delta
	if blink_elapsed >= next_blink:
		blink_closed = true
		blink_hold = 0.12
		_update_portrait()

func _show_lesson(index: int) -> void:
	lesson_index = clampi(index, 0, LESSON_TITLES.size() - 1)
	full_text = _lesson_text(lesson_index)
	revealed_characters = 0
	reveal_accumulator = 0.0
	punctuation_delay = 0.0
	mouth_open = false
	title_label.text = LESSON_TITLES[lesson_index]
	dialogue_label.text = full_text
	dialogue_label.visible_characters = 0
	progress_label.text = "ORIENTATION  %02d / %02d" % [lesson_index + 1, LESSON_TITLES.size()]
	back_button.disabled = lesson_index == 0
	next_button.text = "START TRIAL" if lesson_index == LESSON_TITLES.size() - 1 else "NEXT"
	_update_portrait(true)

func _lesson_text(index: int) -> String:
	match index:
		0:
			return "Commander, welcome aboard CVN Sidebay. This channel covers the controls that keep the carrier alive and the task force coordinated. Combat never pauses, even while the tactical map is open."
		1:
			return "Use %s and %s to set persistent throttle; %s orders a full stop and %s engages boost. Double-click empty space for a full-cruise heading. Middle-drag rotates the combat camera, and the wheel changes zoom." % [_key("accelerate"), _key("decelerate"), _key("brake"), _key("boost")]
		2:
			return "Contacts begin uncertain. Press %s for an active sensor ping: nearby tracks become identifiable, but the emission reveals Sidebay. Left-click an identified contact to select or lock it before launching guided weapons." % _key("sensor_ping")
		3:
			return "%s places the flak fuse plane; %s and %s move it between one kilometer and the battery's effective range. %s launches four guided missiles at the current lock. %s releases the single nuclear torpedo—respect its arming distance and friendly-fire radius." % [_key("flak_screen"), _key("flak_range_decrease"), _key("flak_range_increase"), _key("missile_salvo"), _key("nuclear_torpedo")]
		4:
			return "%s controls both hangar wings. %s operates the interceptor group and %s operates the scouts. Re-issuing a wing command during servicing queues redeployment; recall every craft before jump preparation with %s." % [_key("toggle_all_wings"), _key("interceptor_wing"), _key("scout_wing"), _key("jump_prep")]
		5:
			return "Open the live tactical map with %s. The full battlespace grid is anchored to the carrier; [HOME] recenters and resumes following it after [SHIFT]+middle-mouse panning. F1-F4 select Carrier, Escort, Interceptors, and Scouts. Hold right mouse for the command wheel; Shift queues numbered legs, while Doctrine sets stance, formation, and spacing." % _key("toggle_tactical")
		6:
			return "Press %s for the live Carrier Operations console; the battle continues behind it. Use Balanced, Strike, Evasive, or Recovery power, and assign either damage-control team to fires, breaches, or disabled systems. Set each deck to Rapid Turn, Balanced, or Repair First, watch finite weapon and aviation stores, and act before a trapped officer's rescue countdown expires." % _key("carrier_operations")
		7:
			return "Between engagements, choose connected campaign nodes and watch fuel, supplies, and intel. Service damage before it compounds, assign officers to strengthen departments, and use manual saves before committing to a dangerous route."
		_:
			return "That is the command picture. Keep Sidebay mobile, use flak to shape incoming fire, and treat every air-group recovery as part of the battle. The tutorial remains available from the title screen whenever you need it."

func _key(action: String) -> String:
	return "[%s]" % ExodriftInputSettings.key_label(action)

func _update_portrait(force: bool = false) -> void:
	var column := (2 if blink_closed else 0) + (1 if mouth_open else 0)
	var row := int(POSE_ROWS[lesson_index])
	var frame := Vector2i(column, row)
	if not force and frame == last_portrait_frame:
		return
	var pose_changed := force or row != last_portrait_frame.y
	last_portrait_frame = frame
	if pose_changed:
		portrait.texture = _portrait_frame(0, row)
		eye_overlay.texture = _portrait_frame(2, row)
		mouth_overlay.texture = _portrait_frame(1, row)
		var eye_material := eye_overlay.material as ShaderMaterial
		var mouth_material := mouth_overlay.material as ShaderMaterial
		var base_material := portrait.material as ShaderMaterial
		var row_offset := float(row) / 3.0
		base_material.set_shader_parameter("atlas_offset", Vector2(0.0, row_offset))
		eye_material.set_shader_parameter("atlas_offset", Vector2(0.5, row_offset))
		mouth_material.set_shader_parameter("atlas_offset", Vector2(0.25, row_offset))
		eye_material.set_shader_parameter("feature_y", EYE_OVERLAY_Y[row])
		mouth_material.set_shader_parameter("feature_y", MOUTH_OVERLAY_Y[row])
	eye_overlay.visible = blink_closed
	mouth_overlay.visible = mouth_open

func _portrait_frame(column: int, row: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = PORTRAIT_ATLAS
	atlas.region = Rect2(column * 300.0, row * 400.0, 300.0, 400.0)
	return atlas

func _advance() -> void:
	if revealed_characters < full_text.length():
		revealed_characters = full_text.length()
		dialogue_label.visible_characters = -1
		mouth_open = false
		_update_portrait()
		return
	if lesson_index >= LESSON_TITLES.size() - 1:
		trial_requested.emit()
		queue_free()
	else:
		_show_lesson(lesson_index + 1)

func _previous_lesson() -> void:
	if lesson_index > 0:
		_show_lesson(lesson_index - 1)

func _on_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()

func _on_dialogue_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		dialogue_label.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_SPACE, KEY_ENTER]:
		_advance()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_BACKSPACE:
		_previous_lesson()
		get_viewport().set_input_as_handled()

func close() -> void:
	closed.emit()
	queue_free()

func _label(parent: Control, position_value: Vector2, size_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	UIStyle.apply_label(label, font_size, color)
	parent.add_child(label)
	return label

func _button(parent: Control, text_value: String, position_value: Vector2, size_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	UIStyle.apply_button(button, 13)
	parent.add_child(button)
	return button
