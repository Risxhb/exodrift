class_name ExodriftSectorTravelScreen
extends Node

signal battle_scene_ready(scene: PackedScene)

enum Phase {
	DEPARTURE,
	TRANSIT,
	ARRIVAL,
	HANDOFF,
}

const BATTLE_SCENE_PATH := "res://scenes/main.tscn"
const DEPARTURE_SECONDS := 1.45
const MINIMUM_TRANSIT_SECONDS := 3.15
const ARRIVAL_SECONDS := 1.65

var phase: Phase = Phase.DEPARTURE
var phase_elapsed := 0.0
var destination_sector := 0
var origin_sector := 0
var destination_name := "UNRESOLVED ZONE"
var fleet_snapshot: Dictionary = {}
var load_progress := 0.0
var displayed_progress := 0.0
var loaded_scene: PackedScene
var load_failed := false
var handoff_requested := false

var stage: Node3D
var carrier: PlayerCarrier
var camera: Camera3D
var environment: Environment
var warp_root: Node3D
var warp_ring: MeshInstance3D
var warp_core: MeshInstance3D
var warp_wake: MeshInstance3D
var tunnel_rings: Array[MeshInstance3D] = []
var streaks: Array[MeshInstance3D] = []
var loading_bar: ProgressBar
var status_label: Label
var phase_label: Label
var destination_label: Label
var percent_label: Label
var blackout: ColorRect
var flash: ColorRect

func configure(node: SidebayCampaignNode, snapshot: Dictionary, from_sector: int) -> void:
	destination_sector = node.sector
	origin_sector = clampi(from_sector, 0, 2)
	destination_name = node.display_name.to_upper()
	fleet_snapshot = snapshot.duplicate(true)
	_build_stage()
	_build_carrier()
	_build_warp_field()
	_build_transit_streaks()
	_build_interface()
	_begin_scene_load()
	_enter_phase(Phase.DEPARTURE)

func _process(delta: float) -> void:
	_poll_scene_load()
	phase_elapsed += delta
	match phase:
		Phase.DEPARTURE:
			_update_departure()
			if phase_elapsed >= DEPARTURE_SECONDS:
				_enter_phase(Phase.TRANSIT)
		Phase.TRANSIT:
			_update_transit(delta)
			if phase_elapsed >= MINIMUM_TRANSIT_SECONDS and (loaded_scene != null or load_failed):
				_enter_phase(Phase.ARRIVAL)
		Phase.ARRIVAL:
			_update_arrival()
			if phase_elapsed >= ARRIVAL_SECONDS:
				_request_handoff()
	_update_loading_interface(delta)

func complete_handoff() -> void:
	if phase != Phase.HANDOFF:
		return
	if stage != null:
		stage.visible = false
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(blackout, "color:a", 0.0, 0.34)
	tween.tween_callback(queue_free)

func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "TravelStage"
	add_child(stage)

	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	ExodriftSpaceSky.apply_to_environment(environment, ExodriftSpaceSky.sector_preset(origin_sector))
	environment.glow_enabled = true
	environment.glow_intensity = 1.05
	world_environment.environment = environment
	stage.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, -28.0, 0.0)
	key.light_color = Color(0.5, 0.78, 1.0)
	key.light_energy = 2.35
	key.shadow_enabled = false
	stage.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(24.0, 152.0, 0.0)
	rim.light_color = Color(0.18, 0.46, 1.0)
	rim.light_energy = 1.2
	rim.shadow_enabled = false
	stage.add_child(rim)

	camera = Camera3D.new()
	camera.name = "TravelCamera"
	camera.position = Vector3(205.0, 92.0, 390.0)
	camera.fov = 52.0
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, -4.0, -30.0), Vector3.UP)

func _build_carrier() -> void:
	carrier = PlayerCarrier.new()
	carrier.name = "TransitCarrier"
	stage.add_child(carrier)
	carrier.configure(_carrier_definition(), &"travel_carrier", &"friendly", Color(0.18, 0.38, 0.58))
	carrier.control_enabled = false
	carrier.ai_enabled = false
	carrier.collision_layer = 0
	carrier.collision_mask = 0
	carrier.set_process(false)
	carrier.set_physics_process(false)
	carrier.position = Vector3(0.0, -8.0, 72.0)
	carrier.scale = Vector3.ONE * 0.72
	if carrier.chase_camera != null:
		carrier.chase_camera.current = false
	camera.current = true

func _carrier_definition() -> ShipDefinition:
	var carrier_id := StringName(fleet_snapshot.get("active_carrier_id", "cvn_sidebay"))
	var frame := SidebayRunState.carrier_data(carrier_id)
	if frame.is_empty():
		frame = SidebayRunState.carrier_data(&"cvn_sidebay")
	var definition := ShipDefinition.new()
	definition.ship_id = StringName(frame.id)
	definition.display_name = str(frame.name)
	definition.role = "carrier"
	definition.dimensions_m = Vector3(float(frame.width), float(frame.height), float(frame.length))
	definition.acceleration_mps2 = 14.0 * float(frame.acceleration)
	definition.maximum_speed_mps = 260.0 * float(frame.speed)
	definition.rotation_speed_radians = 0.3 * float(frame.rotation)
	definition.signature = 1.5 * float(frame.signature)
	var layers := DamageLayerDefinition.new()
	layers.max_shields = 600.0 * float(frame.shields)
	layers.max_armor = 700.0 * float(frame.armor)
	layers.max_hull = 950.0 * float(frame.hull)
	layers.shield_regeneration_per_second = 12.0 * float(frame.shield_regen)
	layers.armor_mitigation = 0.28 * float(frame.armor_mitigation)
	definition.damage_layers = layers
	definition.weapons = []
	return definition

func _build_warp_field() -> void:
	warp_root = Node3D.new()
	warp_root.name = "WarpField"
	warp_root.position = Vector3(0.0, 0.0, -250.0)
	stage.add_child(warp_root)
	var vfx := get_node_or_null("/root/CombatVFX")
	warp_ring = _warp_layer("WarpAperture", vfx.warp_ring_mesh if vfx != null else null, vfx.materials.get("warp_in_ring") if vfx != null else null)
	warp_core = _warp_layer("WarpCore", vfx.warp_core_mesh if vfx != null else null, vfx.materials.get("warp_in_core") if vfx != null else null)
	warp_wake = _warp_layer("WarpWake", vfx.warp_wake_mesh if vfx != null else null, vfx.materials.get("warp_in_wake") if vfx != null else null)
	warp_root.add_child(warp_wake)
	warp_root.add_child(warp_core)
	warp_root.add_child(warp_ring)
	for index in 7:
		var ring := _warp_layer("TransitRing%02d" % index, vfx.warp_ring_mesh if vfx != null else null, vfx.materials.get("warp_in_ring") if vfx != null else null)
		ring.position.z = -130.0 - index * 105.0
		ring.scale = Vector3.ONE * (66.0 + index * 14.0)
		ring.visible = false
		stage.add_child(ring)
		tunnel_rings.append(ring)

func _warp_layer(layer_name: String, mesh: Mesh, layer_material: Material) -> MeshInstance3D:
	var layer := MeshInstance3D.new()
	layer.name = layer_name
	if mesh == null:
		var fallback := TorusMesh.new()
		fallback.inner_radius = 0.72
		fallback.outer_radius = 1.0
		layer.mesh = fallback
	else:
		layer.mesh = mesh
	layer.material_override = layer_material if layer_material != null else _emissive_material(Color(0.18, 0.72, 1.0, 0.72), 5.0)
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return layer

func _build_transit_streaks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EC70A
	var streak_material := _emissive_material(Color(0.28, 0.78, 1.0, 0.58), 4.2)
	for index in 42:
		var streak := MeshInstance3D.new()
		streak.name = "TransitStreak%02d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.65, 0.65, rng.randf_range(24.0, 70.0))
		streak.mesh = mesh
		streak.material_override = streak_material
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		streak.position = Vector3(rng.randf_range(-330.0, 330.0), rng.randf_range(-165.0, 165.0), rng.randf_range(-900.0, 240.0))
		streak.visible = false
		stage.add_child(streak)
		streaks.append(streak)

func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TravelInterface"
	canvas.layer = 90
	add_child(canvas)

	var frame_tint := ColorRect.new()
	frame_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame_tint.color = Color(0.005, 0.018, 0.035, 0.18)
	frame_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(frame_tint)

	destination_label = _label(canvas, Vector2(42.0, 34.0), Vector2(820.0, 42.0), 26)
	destination_label.text = "JUMP VECTOR // %s" % destination_name
	phase_label = _label(canvas, Vector2(44.0, 75.0), Vector2(720.0, 26.0), 13)
	phase_label.modulate = Color(0.46, 0.78, 1.0)

	var bottom_panel := Panel.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 28.0
	bottom_panel.offset_right = -28.0
	bottom_panel.offset_top = -104.0
	bottom_panel.offset_bottom = -24.0
	bottom_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.004, 0.018, 0.034, 0.94), Color(0.08, 0.62, 0.92, 0.78), 1))
	canvas.add_child(bottom_panel)

	status_label = _label(bottom_panel, Vector2(18.0, 10.0), Vector2(950.0, 24.0), 13)
	status_label.text = "VECTOR LOCKED // CHARGING WARP FIELD"
	percent_label = _label(bottom_panel, Vector2(1090.0, 10.0), Vector2(105.0, 24.0), 13)
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	loading_bar = ProgressBar.new()
	loading_bar.name = "TravelLoadingBar"
	loading_bar.position = Vector2(18.0, 44.0)
	loading_bar.size = Vector2(1172.0, 18.0)
	loading_bar.min_value = 0.0
	loading_bar.max_value = 100.0
	loading_bar.show_percentage = false
	loading_bar.add_theme_stylebox_override("background", _panel_style(Color(0.01, 0.04, 0.07, 0.96), Color(0.08, 0.22, 0.32), 1))
	loading_bar.add_theme_stylebox_override("fill", _panel_style(Color(0.1, 0.72, 1.0, 0.96), Color(0.56, 0.94, 1.0), 1))
	bottom_panel.add_child(loading_bar)

	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.58, 0.9, 1.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	blackout = ColorRect.new()
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout.color = Color(0.0, 0.0, 0.0, 0.0)
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(blackout)

func _begin_scene_load() -> void:
	var error := ResourceLoader.load_threaded_request(BATTLE_SCENE_PATH)
	if error != OK:
		loaded_scene = load(BATTLE_SCENE_PATH) as PackedScene
		load_progress = 1.0 if loaded_scene != null else 0.0
		load_failed = loaded_scene == null

func _poll_scene_load() -> void:
	if loaded_scene != null or load_failed:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(BATTLE_SCENE_PATH, progress)
	if not progress.is_empty():
		load_progress = clampf(float(progress[0]), 0.0, 1.0)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		loaded_scene = ResourceLoader.load_threaded_get(BATTLE_SCENE_PATH) as PackedScene
		load_progress = 1.0
		load_failed = loaded_scene == null
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		loaded_scene = load(BATTLE_SCENE_PATH) as PackedScene
		load_progress = 1.0 if loaded_scene != null else 0.0
		load_failed = loaded_scene == null

func _enter_phase(next_phase: Phase) -> void:
	phase = next_phase
	phase_elapsed = 0.0
	match phase:
		Phase.DEPARTURE:
			phase_label.text = "PHASE 01 // FLEET DEPARTURE"
			_set_warp_visibility(true, false)
		Phase.TRANSIT:
			phase_label.text = "PHASE 02 // WARP TRANSIT"
			carrier.position = Vector3(0.0, -8.0, 25.0)
			warp_root.visible = false
			for streak in streaks:
				streak.visible = true
			for ring in tunnel_rings:
				ring.visible = true
			status_label.text = "IN TRANSIT // STREAMING %s" % destination_name
		Phase.ARRIVAL:
			phase_label.text = "PHASE 03 // WARP ARRIVAL"
			ExodriftSpaceSky.apply_to_environment(environment, ExodriftSpaceSky.sector_preset(destination_sector))
			for streak in streaks:
				streak.visible = false
			for ring in tunnel_rings:
				ring.visible = false
			warp_root.visible = true
			warp_root.position = Vector3(0.0, 0.0, -305.0)
			carrier.position = Vector3(0.0, -8.0, -245.0)
			status_label.text = "LOAD COMPLETE // EXECUTING WARP ARRIVAL"
		Phase.HANDOFF:
			phase_label.text = "PHASE 04 // TACTICAL HANDOFF"

func _update_departure() -> void:
	var progress := clampf(phase_elapsed / DEPARTURE_SECONDS, 0.0, 1.0)
	var aperture := smoothstep(0.0, 0.56, progress)
	warp_ring.scale = Vector3.ONE * lerpf(4.0, 146.0, aperture)
	warp_core.scale = Vector3.ONE * lerpf(2.0, 102.0, aperture)
	warp_wake.scale = Vector3.ONE * lerpf(3.0, 118.0, aperture)
	carrier.position.z = lerpf(72.0, -345.0, ease(progress, 2.25))
	carrier.scale = Vector3.ONE * lerpf(0.72, 0.42, progress)
	if progress > 0.46:
		status_label.text = "JUMP COMMITTED // ENTERING WARP APERTURE"
	flash.color.a = _flash_strength() * smoothstep(0.72, 0.92, progress) * (1.0 - smoothstep(0.92, 1.0, progress))

func _update_transit(delta: float) -> void:
	carrier.position.y = -8.0 + sin(phase_elapsed * 1.8) * 2.5
	carrier.rotation.z = sin(phase_elapsed * 0.8) * 0.012
	for streak in streaks:
		streak.position.z += delta * 980.0
		if streak.position.z > 330.0:
			streak.position.z -= 1250.0
	for ring in tunnel_rings:
		ring.position.z += delta * 310.0
		if ring.position.z > 180.0:
			ring.position.z -= 820.0
	if loaded_scene != null:
		status_label.text = "NAVIGATION SOLUTION READY // APPROACHING %s" % destination_name

func _update_arrival() -> void:
	var progress := clampf(phase_elapsed / ARRIVAL_SECONDS, 0.0, 1.0)
	var exit_motion := ease(progress, -2.0)
	carrier.position.z = lerpf(-245.0, 32.0, exit_motion)
	carrier.scale = Vector3.ONE * lerpf(0.42, 0.72, exit_motion)
	warp_ring.scale = Vector3.ONE * lerpf(150.0, 13.0, progress)
	warp_core.scale = Vector3.ONE * lerpf(104.0, 8.0, progress)
	warp_wake.scale = Vector3.ONE * lerpf(122.0, 10.0, progress)
	flash.color.a = _flash_strength() * (1.0 - smoothstep(0.0, 0.38, progress))
	blackout.color.a = smoothstep(0.8, 1.0, progress)

func _set_warp_visibility(visible_value: bool, tunnel_visible: bool) -> void:
	warp_root.visible = visible_value
	for ring in tunnel_rings:
		ring.visible = tunnel_visible

func _update_loading_interface(delta: float) -> void:
	var target := 0.0
	match phase:
		Phase.DEPARTURE:
			target = lerpf(0.02, 0.2, clampf(phase_elapsed / DEPARTURE_SECONDS, 0.0, 1.0))
		Phase.TRANSIT:
			var travel_progress := clampf(phase_elapsed / MINIMUM_TRANSIT_SECONDS, 0.0, 1.0)
			target = 0.2 + minf(load_progress, travel_progress) * 0.62
		Phase.ARRIVAL:
			target = lerpf(0.84, 1.0, clampf(phase_elapsed / ARRIVAL_SECONDS, 0.0, 1.0))
		Phase.HANDOFF:
			target = 1.0
	displayed_progress = move_toward(displayed_progress, target, delta * 0.7)
	loading_bar.value = displayed_progress * 100.0
	percent_label.text = "%03d%%" % roundi(displayed_progress * 100.0)

func _request_handoff() -> void:
	if handoff_requested:
		return
	handoff_requested = true
	phase = Phase.HANDOFF
	phase_elapsed = 0.0
	loading_bar.value = 100.0
	percent_label.text = "100%"
	status_label.text = "TACTICAL FIELD READY // TRANSFERRING COMMAND"
	blackout.color.a = 1.0
	set_process(false)
	if loaded_scene != null:
		battle_scene_ready.emit(loaded_scene)

func _flash_strength() -> float:
	var graphics := get_node_or_null("/root/GraphicsQualityManager")
	return 0.34 if graphics != null and bool(graphics.reduced_flashes) else 0.72

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = energy
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material

func _label(parent: Node, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.76, 0.9, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.025, 0.055, 0.96))
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	return label

func _panel_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
