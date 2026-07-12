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
var source_visual_id: StringName = &""

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
	role_value: String = "",
	visual_id: StringName = &""
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
	source_visual_id = visual_id
	add_to_group("projectiles")
	add_to_group("projectiles_%s" % team)
	var registry := _combat_registry()
	if registry != null:
		registry.register_projectile(self)
	_build_visual(interceptable)
	look_at(global_position + direction, Vector3.UP)

func _exit_tree() -> void:
	var registry := _combat_registry()
	if registry != null:
		registry.unregister_projectile(self)

func _combat_registry() -> Node:
	return get_node_or_null("/root/CombatRegistry")

func _combat_vfx() -> Node:
	return get_node_or_null("/root/CombatVFX")

func _build_visual(is_missile: bool) -> void:
	var vfx := _combat_vfx()
	if vfx != null:
		add_child(vfx.create_projectile_visual(projectile_role, is_missile, team, source_visual_id))

func _physics_process(delta: float) -> void:
	if expired:
		return
	if is_instance_valid(target) and not target.is_destroyed and tracking_strength > 0.0:
		var desired := global_position.direction_to(target.global_position)
		direction = direction.slerp(desired, clampf(tracking_strength * delta, 0.0, 1.0)).normalized()
	var travel := speed_mps * delta
	global_position += direction * travel
	look_at(global_position + direction, Vector3.UP)
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
	var registry := _combat_registry()
	var candidates: Array = registry.active_combat_entities() if registry != null else get_tree().get_nodes_in_group("combat_entities")
	for candidate in candidates:
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
	var vfx := _combat_vfx()
	if vfx != null:
		vfx.spawn_faction_burst(projectile_role, global_position, team, source_visual_id)
	queue_free()
