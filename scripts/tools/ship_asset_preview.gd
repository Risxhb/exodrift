extends Node3D

@export_file("*.tres", "*.res") var visual_asset_path: String = ""
@export var rotate_model: bool = true
@export_range(0.0, 60.0) var rotation_degrees_per_second: float = 6.0

var preview_model: Node3D

func _ready() -> void:
	_build_studio()
	var requested_path := _requested_asset_path()
	if requested_path.is_empty():
		print("Ship asset studio ready. Assign visual_asset_path or launch with --asset=res://assets/ships/<id>/<id>_visual_asset.tres")
		return
	load_asset(requested_path)

func _process(delta: float) -> void:
	if rotate_model and preview_model != null:
		preview_model.rotate_y(deg_to_rad(rotation_degrees_per_second * delta))

func load_asset(path: String) -> bool:
	if preview_model != null:
		preview_model.free()
		preview_model = null
	var asset := load(path) as ShipVisualAsset
	if asset == null:
		push_error("Not a ShipVisualAsset: %s" % path)
		return false
	var errors := asset.manifest_errors()
	if not errors.is_empty():
		push_error("Invalid ship asset: %s" % "; ".join(errors))
		return false
	var model := asset.instantiate_model()
	errors = asset.instance_errors(model)
	if not errors.is_empty():
		model.free()
		push_error("Invalid ship model: %s" % "; ".join(errors))
		return false
	asset.apply_material_contract(model)
	add_child(model)
	preview_model = model
	_frame_camera(asset.authored_dimensions_m * asset.model_scale.abs())
	var metrics := asset.model_metrics(model)
	print("Previewing %s // %d triangles // %d material slots" % [asset.ship_id, metrics.triangles, metrics.material_slots])
	return true

func _requested_asset_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="):
			return argument.trim_prefix("--asset=")
	return visual_asset_path

func _build_studio() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.006, 0.009, 0.014)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.25, 0.32)
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	key.light_color = Color(0.82, 0.92, 1.0)
	key.light_energy = 2.0
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(28.0, 142.0, 0.0)
	rim.light_color = Color(0.24, 0.62, 1.0)
	rim.light_energy = 1.15
	add_child(rim)

	var camera := Camera3D.new()
	camera.name = "StudioCamera"
	camera.fov = 48.0
	camera.current = true
	add_child(camera)
	_frame_camera(Vector3(76.0, 32.0, 220.0))

func _frame_camera(dimensions: Vector3) -> void:
	var camera := get_node_or_null("StudioCamera") as Camera3D
	if camera == null:
		return
	var distance := maxf(dimensions.x, dimensions.z) * 1.15
	camera.position = Vector3(dimensions.x * 1.15, dimensions.y * 1.8, distance)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.near = maxf(0.05, dimensions.length() * 0.001)
	camera.far = maxf(1000.0, dimensions.length() * 20.0)
