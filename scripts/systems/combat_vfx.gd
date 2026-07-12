extends Node3D

const MAX_IMPACT_SLOTS := 80

var flak_mesh: BoxMesh
var missile_mesh: CylinderMesh
var trail_mesh: BoxMesh
var burst_mesh: QuadMesh
var flak_material: StandardMaterial3D
var missile_material: StandardMaterial3D
var missile_trail_material: StandardMaterial3D
var materials: Dictionary = {}
var impact_slots: Array[Dictionary] = []
var active_impact_budget: int = 48
var spawned_effects: int = 0
var dropped_effects: int = 0
var quality_manager: Node
var burst_texture: Texture2D

func _ready() -> void:
	quality_manager = get_node_or_null("/root/GraphicsQualityManager")
	burst_texture = load("res://assets/textures/burst_billboard.svg") as Texture2D
	_build_shared_resources()
	_build_impact_pool()
	_apply_profile()
	if quality_manager != null:
		quality_manager.quality_changed.connect(_on_quality_changed)
		quality_manager.reduced_flashes_changed.connect(_on_reduced_flashes_changed)

func _process(delta: float) -> void:
	for slot in impact_slots:
		if not bool(slot.active):
			continue
		slot.age = float(slot.age) + delta
		var duration := maxf(0.01, float(slot.duration))
		var progress := clampf(float(slot.age) / duration, 0.0, 1.0)
		var node: MeshInstance3D = slot.node
		node.scale = Vector3.ONE * lerpf(float(slot.start_scale), float(slot.end_scale), ease(progress, -1.7))
		node.transparency = progress
		if progress >= 1.0:
			slot.active = false
			node.visible = false

func create_projectile_visual(role: String, is_missile: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "MissileVisual" if is_missile else "FlakVisual"
	var core := MeshInstance3D.new()
	core.mesh = missile_mesh if is_missile else flak_mesh
	core.material_override = missile_material if is_missile else flak_material
	root.add_child(core)
	if is_missile:
		var trail := MeshInstance3D.new()
		trail.name = "ExhaustTrail"
		trail.mesh = trail_mesh
		trail.material_override = missile_trail_material
		trail.position.z = 5.5
		trail.scale.z = float(quality_manager.profile().get("trail_scale", 0.78)) if quality_manager != null else 0.78
		root.add_child(trail)
	elif role == "flak":
		var tracer := MeshInstance3D.new()
		tracer.name = "TracerTail"
		tracer.mesh = trail_mesh
		tracer.material_override = flak_material
		tracer.position.z = 3.8
		tracer.scale = Vector3(0.38, 0.38, 0.62)
		root.add_child(tracer)
	return root

func spawn_burst(role: String, world_position: Vector3, magnitude: float = 1.0) -> bool:
	var used := 0
	for slot in impact_slots:
		if bool(slot.active):
			used += 1
	if used >= active_impact_budget:
		dropped_effects += 1
		return false
	for slot in impact_slots:
		if bool(slot.active):
			continue
		var node: MeshInstance3D = slot.node
		slot.active = true
		slot.age = 0.0
		slot.duration = _duration_for(role)
		slot.start_scale = 0.35 * magnitude
		slot.end_scale = _end_scale_for(role) * magnitude
		node.material_override = materials.get(role, materials["flak"])
		node.global_position = world_position
		node.scale = Vector3.ONE * float(slot.start_scale)
		node.transparency = 0.0
		node.visible = true
		spawned_effects += 1
		return true
	dropped_effects += 1
	return false

func spawn_damage_effect(world_position: Vector3, shielded: bool, magnitude: float = 1.0) -> void:
	spawn_burst("shield" if shielded else "hull", world_position, magnitude)
	if shielded or quality_manager == null or not bool(quality_manager.profile().get("secondary_debris", false)):
		return
	for index in 3:
		var phase := float(spawned_effects + index * 7)
		var offset := Vector3(sin(phase) * 5.0, cos(phase * 1.7) * 4.0, sin(phase * 0.63) * 5.0)
		spawn_burst("spark", world_position + offset, magnitude * 0.32)

func active_effect_count() -> int:
	var count := 0
	for slot in impact_slots:
		if bool(slot.active):
			count += 1
	return count

func _build_shared_resources() -> void:
	flak_mesh = BoxMesh.new()
	flak_mesh.size = Vector3(1.1, 1.1, 4.8)
	missile_mesh = CylinderMesh.new()
	missile_mesh.top_radius = 0.75
	missile_mesh.bottom_radius = 1.15
	missile_mesh.height = 6.5
	missile_mesh.radial_segments = 8
	trail_mesh = BoxMesh.new()
	trail_mesh.size = Vector3(0.8, 0.8, 9.0)
	burst_mesh = QuadMesh.new()
	burst_mesh.size = Vector2(2.0, 2.0)
	flak_material = _emissive_material(Color(0.22, 0.78, 1.0), 5.0)
	missile_material = _emissive_material(Color(1.0, 0.28, 0.045), 4.8)
	missile_trail_material = _emissive_material(Color(1.0, 0.58, 0.14, 0.82), 3.5, true)
	materials["flak"] = _emissive_material(Color(0.32, 0.82, 1.0, 0.9), 4.4, true)
	materials["missile"] = _emissive_material(Color(1.0, 0.26, 0.035, 0.92), 5.0, true)
	materials["muzzle"] = _emissive_material(Color(0.72, 0.93, 1.0, 0.94), 5.4, true)
	materials["shield"] = _emissive_material(Color(0.08, 0.72, 1.0, 0.72), 4.2, true)
	materials["hull"] = _emissive_material(Color(1.0, 0.48, 0.08, 0.9), 4.7, true)
	materials["spark"] = _emissive_material(Color(1.0, 0.76, 0.26, 0.94), 4.2, true)
	materials["bay"] = _emissive_material(Color(0.18, 0.92, 1.0, 0.72), 3.8, true)
	for key in materials:
		var burst_material: StandardMaterial3D = materials[key]
		burst_material.albedo_texture = burst_texture
		burst_material.emission_texture = burst_texture
		burst_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

func _build_impact_pool() -> void:
	for index in MAX_IMPACT_SLOTS:
		var node := MeshInstance3D.new()
		node.name = "PooledBurst%02d" % index
		node.mesh = burst_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		add_child(node)
		impact_slots.append({
			"node": node,
			"active": false,
			"age": 0.0,
			"duration": 0.2,
			"start_scale": 0.25,
			"end_scale": 8.0
		})

func _apply_profile() -> void:
	active_impact_budget = clampi(int(quality_manager.profile().get("impact_budget", 48)), 1, MAX_IMPACT_SLOTS) if quality_manager != null else 48

func _on_quality_changed(_profile_name: StringName) -> void:
	_apply_profile()

func _on_reduced_flashes_changed(_enabled: bool) -> void:
	_update_emission_strengths()

func _update_emission_strengths() -> void:
	var multiplier := 0.48 if quality_manager != null and bool(quality_manager.reduced_flashes) else 1.0
	flak_material.emission_energy_multiplier = 5.0 * multiplier
	missile_material.emission_energy_multiplier = 4.8 * multiplier
	missile_trail_material.emission_energy_multiplier = 3.5 * multiplier
	for key in materials:
		var material: StandardMaterial3D = materials[key]
		material.emission_energy_multiplier = 3.2 * multiplier

func _emissive_material(color: Color, energy: float, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = energy * (0.48 if quality_manager != null and bool(quality_manager.reduced_flashes) else 1.0)
	return material

func _duration_for(role: String) -> float:
	match role:
		"missile": return 0.42
		"shield": return 0.24
		"hull": return 0.34
		"spark": return 0.28
		"bay": return 0.26
		"muzzle": return 0.1
		_: return 0.22

func _end_scale_for(role: String) -> float:
	match role:
		"missile": return 17.0
		"shield": return 8.5
		"hull": return 10.0
		"spark": return 2.2
		"bay": return 5.5
		"muzzle": return 4.2
		_: return 10.0
