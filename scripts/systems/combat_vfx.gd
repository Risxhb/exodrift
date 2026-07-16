extends Node3D

const MAX_IMPACT_SLOTS := 80
const AUTHORED_LIBRARY_PATH := "res://assets/vfx/combat/combat_effects_library.glb"

var flak_mesh: BoxMesh
var missile_mesh: Mesh
var nuclear_torpedo_mesh: Mesh
var trail_mesh: Mesh
var missile_exhaust_mesh: Mesh
var nuclear_exhaust_mesh: Mesh
var burst_mesh: QuadMesh
var blast_volume_mesh: Mesh
var blast_core_mesh: Mesh
var blast_ring_mesh: Mesh
var shield_lattice_mesh: Mesh
var armor_shard_mesh: Mesh
var warp_ring_mesh: Mesh
var warp_core_mesh: Mesh
var warp_wake_mesh: Mesh
var flak_material: StandardMaterial3D
var missile_material: StandardMaterial3D
var missile_trail_material: StandardMaterial3D
var nuclear_core_material: StandardMaterial3D
var nuclear_trail_material: StandardMaterial3D
var nuclear_wake_material: StandardMaterial3D
var materials: Dictionary = {}
var projectile_materials: Dictionary = {}
var projectile_hull_materials: Dictionary = {}
var projectile_trail_materials: Dictionary = {}
var projectile_refractory_material: StandardMaterial3D
var impact_slots: Array[Dictionary] = []
var active_impact_budget: int = 48
var spawned_effects: int = 0
var dropped_effects: int = 0
var quality_manager: Node
var burst_texture: Texture2D
var authored_library_loaded := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		if String(slot.role) in ["armor_shard", "debris"]:
			var velocity: Vector3 = slot.velocity
			var angular_velocity: Vector3 = slot.angular_velocity
			node.global_position += velocity * delta
			node.rotation_degrees += angular_velocity * delta
			slot.velocity = velocity.lerp(Vector3.ZERO, clampf(delta * 1.15, 0.0, 1.0))
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
	core.mesh = (nuclear_torpedo_mesh if is_nuclear else missile_mesh) if is_missile else flak_mesh
	if is_missile:
		_apply_projectile_surface_materials(core, palette_key, is_nuclear)
	else:
		core.material_override = projectile_materials.get("%s_flak" % palette_key, flak_material)
	core.scale = Vector3(1.65, 1.65, 1.35) if is_nuclear else Vector3.ONE
	core.set_meta("palette_key", palette_key)
	root.add_child(core)
	if is_missile:
		var trail := MeshInstance3D.new()
		trail.name = "ExhaustTrail"
		trail.mesh = nuclear_exhaust_mesh if is_nuclear else missile_exhaust_mesh
		_apply_exhaust_surface_materials(trail, palette_key, is_nuclear, false)
		trail.position.z = 4.25 if is_nuclear else 3.15
		trail.scale = Vector3(1.15, 1.15, 1.25) if is_nuclear else Vector3(0.92, 0.92, float(quality_manager.profile().get("trail_scale", 0.78)) if quality_manager != null else 0.78)
		root.add_child(trail)
		if is_nuclear:
			var wake := MeshInstance3D.new()
			wake.name = "IonWake"
			wake.mesh = missile_exhaust_mesh
			_apply_exhaust_surface_materials(wake, palette_key, true, true)
			wake.position.z = 12.5
			wake.scale = Vector3(1.55, 1.55, 1.8)
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

func _apply_projectile_surface_materials(node: MeshInstance3D, palette_key: String, is_nuclear: bool) -> void:
	var glow: Material = nuclear_core_material if is_nuclear else projectile_materials.get("%s_missile" % palette_key, missile_material)
	var hull: Material = projectile_hull_materials.get(palette_key, projectile_hull_materials.get("navy"))
	for surface in node.mesh.get_surface_count():
		var source := node.mesh.surface_get_material(surface)
		var source_name := String(source.resource_name).to_lower() if source != null else ""
		if "refractory" in source_name:
			node.set_surface_override_material(surface, projectile_refractory_material)
		elif "hull" in source_name:
			node.set_surface_override_material(surface, hull)
		else:
			node.set_surface_override_material(surface, glow)

func _apply_exhaust_surface_materials(node: MeshInstance3D, palette_key: String, is_nuclear: bool, wake_only: bool) -> void:
	var soft: Material = nuclear_wake_material if is_nuclear else projectile_trail_materials.get(palette_key, missile_trail_material)
	var hot: Material = nuclear_trail_material if is_nuclear else projectile_materials.get("%s_missile" % palette_key, missile_material)
	for surface in node.mesh.get_surface_count():
		var source := node.mesh.surface_get_material(surface)
		var source_name := String(source.resource_name).to_lower() if source != null else ""
		node.set_surface_override_material(surface, soft if wake_only or "plume" in source_name or "wake" in source_name else hot)

func _apply_burst_surface_materials(node: MeshInstance3D, role: String) -> void:
	for surface in node.mesh.get_surface_count():
		var source := node.mesh.surface_get_material(surface)
		var source_name := String(source.resource_name).to_lower() if source != null else ""
		if role == "shield":
			node.set_surface_override_material(surface, materials["shield_hot"] if "impact" in source_name else materials["shield"])
		elif role == "blast_core":
			node.set_surface_override_material(surface, materials["blast_core_hot"] if "hot" in source_name else materials["blast_core"])
		else:
			node.set_surface_override_material(surface, materials["armor_hot"] if "fracture" in source_name else materials["armor_metal"])

func spawn_faction_burst(role: String, world_position: Vector3, team: StringName, visual_id: StringName, magnitude: float = 1.0) -> bool:
	if role == "nuclear":
		var spawned := spawn_burst("nuclear", world_position, magnitude)
		spawn_burst("nuclear_ring", world_position, magnitude * 0.72)
		spawn_burst("blast_core", world_position, magnitude * 0.5)
		return spawned
	var palette_key := _projectile_palette_key(team, visual_id)
	var faction_role := "%s_impact" % palette_key
	return spawn_burst(faction_role if materials.has(faction_role) else role, world_position, magnitude)

func spawn_flak_airburst(world_position: Vector3, team: StringName = &"friendly", visual_id: StringName = &"", magnitude: float = 1.0) -> bool:
	var spawned := spawn_burst("flak_flash", world_position, magnitude * 1.2)
	var density := float(quality_manager.profile().get("effect_density", 0.75)) if quality_manager != null else 0.75
	var smoke_count := 1 if density < 0.7 else (2 if density < 0.9 else 3)
	for index in smoke_count:
		var phase := float(spawned_effects * 13 + index * 29)
		var offset := Vector3(sin(phase * 0.73), cos(phase * 1.17), sin(phase * 1.61)).normalized() * (7.0 + index * 5.0) * magnitude
		spawn_burst("flak_smoke", world_position + offset, magnitude * (0.92 + index * 0.12))
	if density >= 0.7:
		spawn_burst("flak_pressure", world_position, magnitude)
	if density >= 0.9:
		var palette_key := _projectile_palette_key(team, visual_id)
		var shrapnel_role := "%s_impact" % palette_key
		spawn_burst(shrapnel_role if materials.has(shrapnel_role) else "flak_shrapnel", world_position, magnitude * 0.62)
	return spawned

func spawn_shockwave(world_position: Vector3, magnitude: float = 1.0) -> bool:
	return spawn_burst("shockwave", world_position, magnitude)

func spawn_warp_effect(world_position: Vector3, warp_out: bool = false, magnitude: float = 1.0) -> bool:
	var direction := "out" if warp_out else "in"
	var spawned := spawn_burst("warp_%s_ring" % direction, world_position, magnitude)
	spawn_burst("warp_%s_core" % direction, world_position, magnitude * 0.72)
	spawn_burst("warp_%s_wake" % direction, world_position, magnitude * 0.82)
	return spawned

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
		slot.role = role
		slot.start_scale = _start_scale_for(role) * magnitude
		slot.end_scale = _end_scale_for(role) * magnitude
		slot.velocity = Vector3.ZERO
		slot.angular_velocity = Vector3.ZERO
		node.mesh = _burst_mesh_for(role)
		var uses_authored_surfaces := role in ["shield", "blast_core", "armor_shard", "debris"] and authored_library_loaded
		node.material_override = null if uses_authored_surfaces else materials.get(role, materials["flak"])
		if uses_authored_surfaces:
			_apply_burst_surface_materials(node, role)
		node.global_position = world_position
		node.scale = Vector3.ONE * float(slot.start_scale)
		if role in ["shield", "armor_shard", "debris"]:
			node.rotation_degrees = Vector3(
				fposmod(float(spawned_effects * 47), 360.0),
				fposmod(float(spawned_effects * 83), 360.0),
				fposmod(float(spawned_effects * 29), 360.0)
			)
			if role in ["armor_shard", "debris"]:
				var phase := float(spawned_effects * 17 + 3)
				var direction := Vector3(sin(phase * 0.73), cos(phase * 1.19), sin(phase * 1.61)).normalized()
				slot.velocity = direction * (11.0 + magnitude * 5.0)
				slot.angular_velocity = Vector3(170.0 + fposmod(phase * 11.0, 120.0), -210.0 + fposmod(phase * 7.0, 180.0), 140.0 + fposmod(phase * 13.0, 160.0))
		elif role.begins_with("warp_"):
			node.rotation_degrees = Vector3.ZERO
			var camera := get_viewport().get_camera_3d()
			if camera != null and not node.global_position.is_equal_approx(camera.global_position):
				node.look_at(camera.global_position, Vector3.UP)
			node.rotate_object_local(Vector3.FORWARD, deg_to_rad(fposmod(float(spawned_effects * 19), 360.0)))
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
		spawn_burst("armor_shard", world_position + offset, magnitude * (0.28 + index * 0.04))

func spawn_ship_explosion(world_position: Vector3, magnitude: float = 1.0) -> void:
	spawn_burst("hull", world_position, magnitude * 1.2)
	spawn_burst("blast_core", world_position, magnitude * 0.9)
	spawn_burst("blast_ring", world_position, magnitude)
	var debris_count := 6 if quality_manager != null and bool(quality_manager.profile().get("secondary_debris", false)) else 3
	for index in debris_count:
		var phase := float(spawned_effects + index * 11)
		var offset := Vector3(sin(phase * 0.72), cos(phase * 1.13), sin(phase * 1.67)) * (5.0 + index * 2.2) * magnitude
		spawn_burst("debris", world_position + offset, magnitude * 0.42)

func active_effect_count() -> int:
	var count := 0
	for slot in impact_slots:
		if bool(slot.active):
			count += 1
	return count

func _build_shared_resources() -> void:
	flak_mesh = BoxMesh.new()
	flak_mesh.size = Vector3(1.1, 1.1, 4.8)
	var procedural_missile := CylinderMesh.new()
	procedural_missile.top_radius = 0.75
	procedural_missile.bottom_radius = 1.15
	procedural_missile.height = 6.5
	procedural_missile.radial_segments = 8
	missile_mesh = procedural_missile
	nuclear_torpedo_mesh = procedural_missile
	trail_mesh = BoxMesh.new()
	trail_mesh.size = Vector3(0.8, 0.8, 9.0)
	missile_exhaust_mesh = trail_mesh
	nuclear_exhaust_mesh = trail_mesh
	burst_mesh = QuadMesh.new()
	burst_mesh.size = Vector2(2.0, 2.0)
	var procedural_volume := SphereMesh.new()
	procedural_volume.radius = 1.0
	procedural_volume.height = 2.0
	procedural_volume.radial_segments = 16
	procedural_volume.rings = 8
	blast_volume_mesh = procedural_volume
	blast_core_mesh = procedural_volume
	var procedural_ring := TorusMesh.new()
	procedural_ring.inner_radius = 0.72
	procedural_ring.outer_radius = 1.0
	procedural_ring.rings = 20
	procedural_ring.ring_segments = 8
	blast_ring_mesh = procedural_ring
	shield_lattice_mesh = procedural_volume
	armor_shard_mesh = flak_mesh
	warp_ring_mesh = procedural_ring
	warp_core_mesh = procedural_volume
	warp_wake_mesh = procedural_volume
	_load_authored_meshes()
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
	projectile_hull_materials["navy"] = _hull_material(Color(0.045, 0.105, 0.145), Color(0.08, 0.36, 0.5))
	projectile_hull_materials["acheron"] = _hull_material(Color(0.16, 0.035, 0.022), Color(0.5, 0.08, 0.02))
	projectile_hull_materials["vesper"] = _hull_material(Color(0.12, 0.025, 0.16), Color(0.38, 0.06, 0.5))
	projectile_hull_materials["crucible"] = _hull_material(Color(0.08, 0.025, 0.13), Color(0.26, 0.05, 0.48))
	projectile_refractory_material = _hull_material(Color(0.012, 0.018, 0.024), Color(0.025, 0.04, 0.05))
	projectile_trail_materials["navy"] = _emissive_material(Color(0.22, 0.72, 1.0, 0.76), 3.4, true)
	projectile_trail_materials["acheron"] = _emissive_material(Color(1.0, 0.32, 0.04, 0.8), 3.6, true)
	projectile_trail_materials["vesper"] = _emissive_material(Color(0.92, 0.18, 1.0, 0.78), 3.8, true)
	projectile_trail_materials["crucible"] = _emissive_material(Color(0.62, 0.14, 1.0, 0.82), 4.0, true)
	materials["flak"] = _emissive_material(Color(0.32, 0.82, 1.0, 0.9), 4.4, true)
	materials["flak_flash"] = _emissive_material(Color(1.0, 0.84, 0.48, 0.96), 6.8, true)
	materials["flak_smoke"] = _smoke_material(Color(0.075, 0.08, 0.085, 0.76))
	materials["flak_pressure"] = _emissive_material(Color(1.0, 0.44, 0.1, 0.42), 3.8, true)
	materials["flak_shrapnel"] = _emissive_material(Color(1.0, 0.62, 0.18, 0.86), 4.8, true)
	materials["missile"] = _emissive_material(Color(1.0, 0.26, 0.035, 0.92), 5.0, true)
	materials["muzzle"] = _emissive_material(Color(0.72, 0.93, 1.0, 0.94), 5.4, true)
	materials["shield"] = _emissive_material(Color(0.08, 0.72, 1.0, 0.72), 4.2, true)
	materials["shield_hot"] = _emissive_material(Color(0.62, 0.96, 1.0, 0.9), 7.2, true)
	materials["hull"] = _emissive_material(Color(1.0, 0.48, 0.08, 0.9), 4.7, true)
	materials["spark"] = _emissive_material(Color(1.0, 0.76, 0.26, 0.94), 4.2, true)
	materials["blast_core"] = _emissive_material(Color(1.0, 0.9, 0.62, 0.98), 6.4, true)
	materials["blast_core_hot"] = _emissive_material(Color(1.0, 0.34, 0.035, 0.94), 7.4, true)
	materials["blast_ring"] = _emissive_material(Color(1.0, 0.32, 0.045, 0.78), 5.6, true)
	materials["shockwave"] = _emissive_material(Color(0.18, 0.72, 1.0, 0.66), 5.8, true)
	materials["nuclear"] = _emissive_material(Color(0.18, 0.7, 1.0, 0.56), 4.4, true)
	materials["nuclear_ring"] = _emissive_material(Color(0.16, 0.82, 1.0, 0.72), 5.2, true)
	materials["armor_shard"] = _emissive_material(Color(1.0, 0.48, 0.1, 0.88), 3.8, true)
	materials["debris"] = _emissive_material(Color(1.0, 0.26, 0.04, 0.82), 3.4, true)
	materials["armor_metal"] = _emissive_material(Color(0.2, 0.075, 0.025, 0.96), 1.25, true)
	materials["armor_hot"] = _emissive_material(Color(1.0, 0.2, 0.02, 0.94), 6.2, true)
	materials["warp_in_ring"] = _emissive_material(Color(0.12, 0.74, 1.0, 0.72), 6.4, true)
	materials["warp_in_core"] = _emissive_material(Color(0.62, 0.94, 1.0, 0.58), 7.2, true)
	materials["warp_in_wake"] = _emissive_material(Color(0.08, 0.32, 1.0, 0.34), 4.2, true)
	materials["warp_out_ring"] = _emissive_material(Color(0.68, 0.28, 1.0, 0.74), 6.4, true)
	materials["warp_out_core"] = _emissive_material(Color(0.94, 0.62, 1.0, 0.6), 7.2, true)
	materials["warp_out_wake"] = _emissive_material(Color(0.42, 0.1, 1.0, 0.34), 4.2, true)
	materials["bay"] = _emissive_material(Color(0.18, 0.92, 1.0, 0.72), 3.8, true)
	materials["navy_impact"] = _emissive_material(Color(0.18, 0.82, 1.0, 0.88), 4.5, true)
	materials["acheron_impact"] = _emissive_material(Color(1.0, 0.24, 0.025, 0.9), 4.8, true)
	materials["vesper_impact"] = _emissive_material(Color(1.0, 0.18, 0.88, 0.88), 4.9, true)
	materials["crucible_impact"] = _emissive_material(Color(0.68, 0.18, 1.0, 0.92), 5.1, true)
	for key in materials:
		var burst_material: StandardMaterial3D = materials[key]
		if String(key) in ["nuclear", "nuclear_ring", "blast_core", "blast_core_hot", "blast_ring", "flak_pressure", "shield", "shield_hot", "shockwave", "armor_shard", "debris", "armor_metal", "armor_hot", "warp_in_ring", "warp_in_core", "warp_in_wake", "warp_out_ring", "warp_out_core", "warp_out_wake"]:
			burst_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		else:
			burst_material.albedo_texture = burst_texture
			if String(key) != "flak_smoke":
				burst_material.emission_texture = burst_texture
			burst_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Impact cards are luminous volumes. Additive, depth-write-free rendering
		# prevents the transparent perimeter of large nuclear/shockwave sprites from
		# presenting as an opaque dark quad when it crosses other geometry.
		burst_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if String(key) in ["flak_smoke", "armor_metal"] else BaseMaterial3D.BLEND_MODE_ADD
		burst_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

func _burst_mesh_for(role: String) -> Mesh:
	if role == "shield":
		return shield_lattice_mesh
	if role in ["armor_shard", "debris"]:
		return armor_shard_mesh
	if role in ["warp_in_ring", "warp_out_ring"]:
		return warp_ring_mesh
	if role in ["warp_in_core", "warp_out_core"]:
		return warp_core_mesh
	if role in ["warp_in_wake", "warp_out_wake"]:
		return warp_wake_mesh
	if role == "blast_core":
		return blast_core_mesh
	if role == "nuclear":
		return blast_volume_mesh
	if role in ["nuclear_ring", "blast_ring", "flak_pressure", "shockwave"]:
		return blast_ring_mesh
	return burst_mesh

func _load_authored_meshes() -> void:
	if not ResourceLoader.exists(AUTHORED_LIBRARY_PATH):
		return
	var library_scene := load(AUTHORED_LIBRARY_PATH) as PackedScene
	if library_scene == null:
		return
	var library := library_scene.instantiate()
	if not library is Node:
		return
	missile_mesh = _mesh_from_library(library, "GuidedMissile", missile_mesh)
	nuclear_torpedo_mesh = _mesh_from_library(library, "NuclearTorpedo", nuclear_torpedo_mesh)
	missile_exhaust_mesh = _mesh_from_library(library, "MissileExhaust", missile_exhaust_mesh)
	nuclear_exhaust_mesh = _mesh_from_library(library, "NuclearExhaust", nuclear_exhaust_mesh)
	shield_lattice_mesh = _mesh_from_library(library, "ShieldLattice", shield_lattice_mesh)
	blast_volume_mesh = _mesh_from_library(library, "NuclearCore", blast_volume_mesh)
	blast_core_mesh = _mesh_from_library(library, "BlastCore", blast_core_mesh)
	blast_ring_mesh = _mesh_from_library(library, "ShockwaveRing", blast_ring_mesh)
	armor_shard_mesh = _mesh_from_library(library, "ArmorShard", armor_shard_mesh)
	warp_ring_mesh = _mesh_from_library(library, "WarpRing", warp_ring_mesh)
	warp_core_mesh = _mesh_from_library(library, "WarpCore", warp_core_mesh)
	warp_wake_mesh = _mesh_from_library(library, "WarpWake", warp_wake_mesh)
	authored_library_loaded = missile_mesh != null and missile_exhaust_mesh != trail_mesh and blast_core_mesh != blast_volume_mesh
	library.free()

func _mesh_from_library(library: Node, node_name: String, fallback: Mesh) -> Mesh:
	var mesh_node := library.find_child(node_name, true, false) as MeshInstance3D
	return mesh_node.mesh if mesh_node != null and mesh_node.mesh != null else fallback

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
			"role": "",
			"age": 0.0,
			"duration": 0.2,
			"start_scale": 0.25,
			"end_scale": 8.0,
			"velocity": Vector3.ZERO,
			"angular_velocity": Vector3.ZERO
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
	nuclear_core_material.emission_energy_multiplier = 7.4 * multiplier
	nuclear_trail_material.emission_energy_multiplier = 5.4 * multiplier
	nuclear_wake_material.emission_energy_multiplier = 3.6 * multiplier
	for key in projectile_materials:
		var projectile_material: StandardMaterial3D = projectile_materials[key]
		projectile_material.emission_energy_multiplier = 5.3 * multiplier
	for key in projectile_trail_materials:
		var trail_material: StandardMaterial3D = projectile_trail_materials[key]
		trail_material.emission_energy_multiplier = 3.7 * multiplier
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

func _smoke_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = false
	return material

func _hull_material(color: Color, rim_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.78
	material.roughness = 0.32
	material.emission_enabled = true
	material.emission = rim_color
	material.emission_energy_multiplier = 0.32
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
		"flak_flash": return 0.13
		"flak_smoke": return 0.82
		"flak_pressure": return 0.46
		"flak_shrapnel": return 0.34
		"nuclear": return 1.25
		"nuclear_ring": return 1.05
		"shockwave": return 0.72
		"blast_ring": return 0.52
		"blast_core": return 0.28
		"missile": return 0.42
		"shield": return 0.24
		"hull": return 0.34
		"spark": return 0.28
		"armor_shard": return 0.68
		"debris": return 0.92
		"warp_in_ring", "warp_out_ring": return 1.15
		"warp_in_core", "warp_out_core": return 0.82
		"warp_in_wake", "warp_out_wake": return 1.28
		"bay": return 0.26
		"muzzle": return 0.1
		_: return 0.22

func _end_scale_for(role: String) -> float:
	match role:
		"flak_flash": return 18.0
		"flak_smoke": return 64.0
		"flak_pressure": return 176.0
		"flak_shrapnel": return 26.0
		"nuclear": return 34.0
		"nuclear_ring": return 46.0
		"shockwave": return 34.0
		"blast_ring": return 22.0
		"blast_core": return 7.5
		"missile": return 17.0
		"shield": return 8.5
		"hull": return 10.0
		"spark": return 2.2
		"armor_shard": return 0.72
		"debris": return 0.88
		"warp_in_ring": return 54.0
		"warp_in_core": return 38.0
		"warp_in_wake": return 42.0
		"warp_out_ring", "warp_out_core", "warp_out_wake": return 0.12
		"bay": return 5.5
		"muzzle": return 4.2
		_: return 10.0

func _start_scale_for(role: String) -> float:
	match role:
		"nuclear": return 1.8
		"nuclear_ring": return 1.15
		"blast_core": return 0.9
		"shield": return 0.62
		"shockwave": return 0.8
		"warp_in_ring": return 2.8
		"warp_in_core": return 2.0
		"warp_in_wake": return 2.2
		"warp_out_ring": return 54.0
		"warp_out_core": return 38.0
		"warp_out_wake": return 42.0
		"armor_shard", "debris": return 0.42
		_: return 0.35
