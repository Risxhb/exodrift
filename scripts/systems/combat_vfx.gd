extends Node3D

const MAX_IMPACT_SLOTS := 80

var flak_mesh: BoxMesh
var missile_mesh: CylinderMesh
var trail_mesh: BoxMesh
var burst_mesh: QuadMesh
var blast_volume_mesh: SphereMesh
var blast_ring_mesh: TorusMesh
var flak_material: StandardMaterial3D
var missile_material: StandardMaterial3D
var missile_trail_material: StandardMaterial3D
var nuclear_core_material: StandardMaterial3D
var nuclear_trail_material: StandardMaterial3D
var nuclear_wake_material: StandardMaterial3D
var materials: Dictionary = {}
var projectile_materials: Dictionary = {}
var projectile_trail_materials: Dictionary = {}
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

func create_projectile_visual(role: String, is_missile: bool, team: StringName = &"neutral", visual_id: StringName = &"") -> Node3D:
	var root := Node3D.new()
	var is_nuclear := role == "nuclear"
	root.name = "NuclearTorpedoVisual" if is_nuclear else ("MissileVisual" if is_missile else "FlakVisual")
	var palette_key := _projectile_palette_key(team, visual_id)
	var core := MeshInstance3D.new()
	core.mesh = missile_mesh if is_missile else flak_mesh
	core.material_override = nuclear_core_material if is_nuclear else projectile_materials.get("%s_%s" % [palette_key, "missile" if is_missile else "flak"], missile_material if is_missile else flak_material)
	core.scale = Vector3(1.65, 1.65, 1.35) if is_nuclear else Vector3.ONE
	root.add_child(core)
	if is_missile:
		var trail := MeshInstance3D.new()
		trail.name = "ExhaustTrail"
		trail.mesh = trail_mesh
		trail.material_override = nuclear_trail_material if is_nuclear else projectile_trail_materials.get(palette_key, missile_trail_material)
		trail.position.z = 5.5
		trail.scale = Vector3(1.7, 1.7, 2.8) if is_nuclear else Vector3(0.9, 0.9, (float(quality_manager.profile().get("trail_scale", 0.78)) if quality_manager != null else 0.78) * 1.8)
		root.add_child(trail)
		if is_nuclear:
			var wake := MeshInstance3D.new()
			wake.name = "IonWake"
			wake.mesh = trail_mesh
			wake.material_override = nuclear_wake_material
			wake.position.z = 18.0
			wake.scale = Vector3(2.8, 2.8, 3.2)
			root.add_child(wake)
	elif role == "flak":
		var tracer := MeshInstance3D.new()
		tracer.name = "TracerTail"
		tracer.mesh = trail_mesh
		tracer.material_override = projectile_materials.get("%s_flak" % palette_key, flak_material)
		tracer.position.z = 3.8
		tracer.scale = Vector3(0.38, 0.38, 0.62)
		root.add_child(tracer)
	return root

func spawn_faction_burst(role: String, world_position: Vector3, team: StringName, visual_id: StringName, magnitude: float = 1.0) -> bool:
	if role == "nuclear":
		var spawned := spawn_burst("nuclear", world_position, magnitude)
		spawn_burst("nuclear_ring", world_position, magnitude * 0.72)
		spawn_burst("blast_core", world_position, magnitude * 0.5)
		return spawned
	var palette_key := _projectile_palette_key(team, visual_id)
	var faction_role := "%s_impact" % palette_key
	return spawn_burst(faction_role if materials.has(faction_role) else role, world_position, magnitude)

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
		node.mesh = _burst_mesh_for(role)
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
	if shielded:
		return
	spawn_burst("blast_core", world_position, magnitude * 0.58)
	if quality_manager == null or not bool(quality_manager.profile().get("secondary_debris", false)):
		return
	for index in 3:
		var phase := float(spawned_effects + index * 7)
		var offset := Vector3(sin(phase) * 5.0, cos(phase * 1.7) * 4.0, sin(phase * 0.63) * 5.0)
		spawn_burst("spark", world_position + offset, magnitude * 0.32)

func spawn_ship_explosion(world_position: Vector3, magnitude: float = 1.0) -> void:
	spawn_burst("hull", world_position, magnitude * 1.2)
	spawn_burst("blast_core", world_position, magnitude * 0.9)
	spawn_burst("blast_ring", world_position, magnitude)
	var debris_count := 6 if quality_manager != null and bool(quality_manager.profile().get("secondary_debris", false)) else 3
	for index in debris_count:
		var phase := float(spawned_effects + index * 11)
		var offset := Vector3(sin(phase * 0.72), cos(phase * 1.13), sin(phase * 1.67)) * (5.0 + index * 2.2) * magnitude
		spawn_burst("spark", world_position + offset, magnitude * 0.42)

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
	blast_volume_mesh = SphereMesh.new()
	blast_volume_mesh.radius = 1.0
	blast_volume_mesh.height = 2.0
	blast_volume_mesh.radial_segments = 16
	blast_volume_mesh.rings = 8
	blast_ring_mesh = TorusMesh.new()
	blast_ring_mesh.inner_radius = 0.72
	blast_ring_mesh.outer_radius = 1.0
	blast_ring_mesh.rings = 20
	blast_ring_mesh.ring_segments = 8
	flak_material = _emissive_material(Color(0.22, 0.78, 1.0), 5.0)
	missile_material = _emissive_material(Color(1.0, 0.28, 0.045), 4.8)
	missile_trail_material = _emissive_material(Color(1.0, 0.58, 0.14, 0.82), 3.5, true)
	nuclear_core_material = _emissive_material(Color(0.88, 0.98, 1.0), 7.4)
	nuclear_trail_material = _emissive_material(Color(0.25, 0.82, 1.0, 0.88), 5.4, true)
	nuclear_wake_material = _emissive_material(Color(0.08, 0.38, 1.0, 0.32), 3.6, true)
	projectile_materials["navy_flak"] = _emissive_material(Color(0.18, 0.82, 1.0), 5.1)
	projectile_materials["navy_missile"] = _emissive_material(Color(0.58, 0.9, 1.0), 5.0)
	projectile_materials["acheron_flak"] = _emissive_material(Color(1.0, 0.3, 0.035), 5.0)
	projectile_materials["acheron_missile"] = _emissive_material(Color(1.0, 0.12, 0.02), 5.3)
	projectile_materials["vesper_flak"] = _emissive_material(Color(1.0, 0.18, 0.92), 5.2)
	projectile_materials["vesper_missile"] = _emissive_material(Color(0.82, 0.22, 1.0), 5.5)
	projectile_materials["crucible_flak"] = _emissive_material(Color(0.86, 0.38, 1.0), 5.3)
	projectile_materials["crucible_missile"] = _emissive_material(Color(0.66, 0.16, 1.0), 5.7)
	projectile_trail_materials["navy"] = _emissive_material(Color(0.22, 0.72, 1.0, 0.76), 3.4, true)
	projectile_trail_materials["acheron"] = _emissive_material(Color(1.0, 0.32, 0.04, 0.8), 3.6, true)
	projectile_trail_materials["vesper"] = _emissive_material(Color(0.92, 0.18, 1.0, 0.78), 3.8, true)
	projectile_trail_materials["crucible"] = _emissive_material(Color(0.62, 0.14, 1.0, 0.82), 4.0, true)
	materials["flak"] = _emissive_material(Color(0.32, 0.82, 1.0, 0.9), 4.4, true)
	materials["missile"] = _emissive_material(Color(1.0, 0.26, 0.035, 0.92), 5.0, true)
	materials["muzzle"] = _emissive_material(Color(0.72, 0.93, 1.0, 0.94), 5.4, true)
	materials["shield"] = _emissive_material(Color(0.08, 0.72, 1.0, 0.72), 4.2, true)
	materials["hull"] = _emissive_material(Color(1.0, 0.48, 0.08, 0.9), 4.7, true)
	materials["spark"] = _emissive_material(Color(1.0, 0.76, 0.26, 0.94), 4.2, true)
	materials["blast_core"] = _emissive_material(Color(1.0, 0.9, 0.62, 0.98), 6.4, true)
	materials["blast_ring"] = _emissive_material(Color(1.0, 0.32, 0.045, 0.78), 5.6, true)
	materials["nuclear"] = _emissive_material(Color(0.18, 0.7, 1.0, 0.56), 4.4, true)
	materials["nuclear_ring"] = _emissive_material(Color(0.16, 0.82, 1.0, 0.72), 5.2, true)
	materials["bay"] = _emissive_material(Color(0.18, 0.92, 1.0, 0.72), 3.8, true)
	materials["navy_impact"] = _emissive_material(Color(0.18, 0.82, 1.0, 0.88), 4.5, true)
	materials["acheron_impact"] = _emissive_material(Color(1.0, 0.24, 0.025, 0.9), 4.8, true)
	materials["vesper_impact"] = _emissive_material(Color(1.0, 0.18, 0.88, 0.88), 4.9, true)
	materials["crucible_impact"] = _emissive_material(Color(0.68, 0.18, 1.0, 0.92), 5.1, true)
	for key in materials:
		var burst_material: StandardMaterial3D = materials[key]
		if String(key) in ["nuclear", "nuclear_ring", "blast_core", "blast_ring"]:
			burst_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		else:
			burst_material.albedo_texture = burst_texture
			burst_material.emission_texture = burst_texture
			burst_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Impact cards are luminous volumes. Additive, depth-write-free rendering
		# prevents the transparent perimeter of large nuclear/shockwave sprites from
		# presenting as an opaque dark quad when it crosses other geometry.
		burst_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		burst_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

func _burst_mesh_for(role: String) -> PrimitiveMesh:
	if role in ["nuclear", "blast_core"]:
		return blast_volume_mesh
	if role in ["nuclear_ring", "blast_ring"]:
		return blast_ring_mesh
	return burst_mesh

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

func _projectile_palette_key(team: StringName, visual_id: StringName) -> String:
	var identity := String(visual_id)
	if identity.begins_with("vesper_"):
		return "vesper"
	if identity.begins_with("crucible_"):
		return "crucible"
	if team == &"hostile":
		return "acheron"
	return "navy"

func _duration_for(role: String) -> float:
	match role:
		"nuclear": return 1.25
		"nuclear_ring": return 1.05
		"blast_ring": return 0.52
		"blast_core": return 0.28
		"missile": return 0.42
		"shield": return 0.24
		"hull": return 0.34
		"spark": return 0.28
		"bay": return 0.26
		"muzzle": return 0.1
		_: return 0.22

func _end_scale_for(role: String) -> float:
	match role:
		"nuclear": return 34.0
		"nuclear_ring": return 46.0
		"blast_ring": return 22.0
		"blast_core": return 7.5
		"missile": return 17.0
		"shield": return 8.5
		"hull": return 10.0
		"spark": return 2.2
		"bay": return 5.5
		"muzzle": return 4.2
		_: return 10.0
