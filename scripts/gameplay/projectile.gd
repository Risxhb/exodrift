class_name SidebayProjectile
extends Node3D

var team: StringName = &"neutral"
var source_entity_id: StringName = &""
var target: CombatShip
var direction: Vector3 = Vector3.FORWARD
var speed_mps: float = 800.0
var damage: float = 10.0
var maximum_distance_m: float = 1500.0
var tracking_strength: float = 0.0
var can_be_intercepted: bool = false
var collision_radius_m: float = 12.0
var distance_travelled_m: float = 0.0
var expired: bool = false
var projectile_role: String = ""

func configure(
	projectile_team: StringName,
	source_id: StringName,
	start_position: Vector3,
	initial_direction: Vector3,
	projectile_speed: float,
	projectile_damage: float,
	maximum_distance: float,
	tracked_target: CombatShip = null,
	tracking: float = 0.0,
	interceptable: bool = false,
	role_value: String = ""
) -> void:
	team = projectile_team
	source_entity_id = source_id
	global_position = start_position
	direction = initial_direction.normalized()
	speed_mps = projectile_speed
	damage = projectile_damage
	maximum_distance_m = maximum_distance
	target = tracked_target
	tracking_strength = tracking
	can_be_intercepted = interceptable
	projectile_role = role_value
	add_to_group("projectiles")
	add_to_group("projectiles_%s" % team)
	_build_visual(interceptable)

func _build_visual(is_missile: bool) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 2.2 if is_missile else 1.0
	mesh.height = 7.0 if is_missile else 2.0
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.35, 0.08) if is_missile else Color(0.2, 0.85, 1.0)
	material.emission_enabled = true
	material.emission = material.albedo_color * 3.0
	mesh_instance.material_override = material
	add_child(mesh_instance)

func _physics_process(delta: float) -> void:
	if expired:
		return
	if is_instance_valid(target) and not target.is_destroyed and tracking_strength > 0.0:
		var desired := global_position.direction_to(target.global_position)
		direction = direction.slerp(desired, clampf(tracking_strength * delta, 0.0, 1.0)).normalized()
	var travel := speed_mps * delta
	global_position += direction * travel
	distance_travelled_m += travel
	if _check_target_hit() or _check_proximity_hit() or distance_travelled_m >= maximum_distance_m:
		expire()

func _check_target_hit() -> bool:
	if not is_instance_valid(target) or target.is_destroyed:
		return false
	if global_position.distance_to(target.global_position) <= collision_radius_m + target.collision_radius_m:
		target.receive_damage(damage, source_entity_id)
		return true
	return false

func _check_proximity_hit() -> bool:
	if is_instance_valid(target):
		return false
	for candidate in get_tree().get_nodes_in_group("combat_entities"):
		if candidate is CombatShip and candidate.team != team and not candidate.is_destroyed:
			if global_position.distance_to(candidate.global_position) <= collision_radius_m + candidate.collision_radius_m:
				candidate.receive_damage(damage, source_entity_id)
				return true
	return false

func intercept() -> void:
	if can_be_intercepted:
		expire()

func expire() -> void:
	if expired:
		return
	expired = true
	_spawn_detonation_visual()
	queue_free()

func _spawn_detonation_visual() -> void:
	if projectile_role not in ["flak", "missile"] or get_parent() == null:
		return
	var burst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.5 if projectile_role == "flak" else 3.0
	mesh.height = mesh.radius * 2.0
	burst.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.46, 0.88, 1.0, 0.9) if projectile_role == "flak" else Color(1.0, 0.34, 0.05, 0.92)
	material.emission_enabled = true
	material.emission = Color(material.albedo_color.r, material.albedo_color.g, material.albedo_color.b) * 4.5
	burst.material_override = material
	get_parent().add_child(burst)
	burst.global_position = global_position
	var final_scale := Vector3.ONE * (10.0 if projectile_role == "flak" else 16.0)
	var tween := burst.create_tween()
	tween.tween_property(burst, "scale", final_scale, 0.20 if projectile_role == "flak" else 0.32)
	tween.parallel().tween_property(burst, "transparency", 1.0, 0.20 if projectile_role == "flak" else 0.32)
	tween.tween_callback(burst.queue_free)
