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
var airburst_distance_m: float = 0.0
var blast_radius_m: float = 0.0
var arming_distance_m: float = 0.0
var radial_warhead: bool = false
var friendly_fire: bool = false
var detonate_on_expiry: bool = false
var airburst_strikecraft_damage_multiplier: float = 1.0
var airburst_capital_damage_multiplier: float = 1.0
var airburst_intercepts_friendlies: bool = false
var vertical_launch_clearance_m: float = 0.0

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
	_face_direction()

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
	var cleared_launcher := vertical_launch_clearance_m <= 0.0 or distance_travelled_m >= vertical_launch_clearance_m
	if cleared_launcher and is_instance_valid(target) and not target.is_destroyed and tracking_strength > 0.0:
		var desired := global_position.direction_to(target.global_position)
		direction = direction.slerp(desired, clampf(tracking_strength * delta, 0.0, 1.0)).normalized()
	var travel := speed_mps * delta
	global_position += direction * travel
	_face_direction()
	distance_travelled_m += travel
	var contact_hit := _check_target_hit() or _check_proximity_hit()
	var reached_airburst := airburst_distance_m > 0.0 and distance_travelled_m >= airburst_distance_m
	var reached_maximum := distance_travelled_m >= maximum_distance_m
	if contact_hit or reached_airburst or reached_maximum:
		if (radial_warhead or airburst_distance_m > 0.0) and distance_travelled_m >= arming_distance_m and (not reached_maximum or detonate_on_expiry or reached_airburst or contact_hit):
			detonate()
		else:
			expire("missile" if radial_warhead and not is_armed() else "")

func configure_vertical_launch(clearance_distance_m: float) -> void:
	vertical_launch_clearance_m = maxf(0.0, clearance_distance_m)

func is_clearing_launcher() -> bool:
	return vertical_launch_clearance_m > 0.0 and distance_travelled_m < vertical_launch_clearance_m

func _face_direction() -> void:
	var up_axis := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.96 else Vector3.UP
	look_at(global_position + direction, up_axis)

func _check_target_hit() -> bool:
	if not is_instance_valid(target) or target.is_destroyed:
		return false
	if global_position.distance_to(target.global_position) <= collision_radius_m + target.collision_radius_m:
		if not radial_warhead and airburst_distance_m <= 0.0:
			target.receive_damage(damage, source_entity_id, _impact_context())
		return true
	return false

func _check_proximity_hit() -> bool:
	if is_instance_valid(target):
		return false
	var registry := _combat_registry()
	var candidates: Array = registry.active_combat_entities() if registry != null else get_tree().get_nodes_in_group("combat_entities")
	for candidate in candidates:
		if not candidate is CombatShip or candidate.is_destroyed:
			continue
		if candidate.stable_entity_id == source_entity_id:
			continue
		if candidate.team == team and not friendly_fire:
			continue
		if global_position.distance_to(candidate.global_position) <= collision_radius_m + candidate.collision_radius_m:
			if not radial_warhead and airburst_distance_m <= 0.0:
				candidate.receive_damage(damage, source_entity_id, _impact_context())
			return true
	return false

func configure_airburst(
	distance_m: float,
	radius_m: float,
	strikecraft_damage_multiplier: float = 1.0,
	capital_damage_multiplier: float = 1.0,
	harms_friendlies: bool = false,
	intercepts_friendly_projectiles: bool = false
) -> void:
	airburst_distance_m = clampf(distance_m, 1.0, maximum_distance_m)
	blast_radius_m = maxf(1.0, radius_m)
	airburst_strikecraft_damage_multiplier = maxf(0.0, strikecraft_damage_multiplier)
	airburst_capital_damage_multiplier = maxf(0.0, capital_damage_multiplier)
	friendly_fire = harms_friendlies
	airburst_intercepts_friendlies = intercepts_friendly_projectiles
	detonate_on_expiry = true

func configure_warhead(arming_distance: float, radius_m: float, harms_friendlies: bool, explode_at_max_range: bool) -> void:
	arming_distance_m = maxf(0.0, arming_distance)
	blast_radius_m = maxf(1.0, radius_m)
	radial_warhead = true
	friendly_fire = harms_friendlies
	detonate_on_expiry = explode_at_max_range

func is_armed() -> bool:
	return distance_travelled_m >= arming_distance_m

func detonate() -> void:
	if expired:
		return
	expired = true
	var registry := _combat_registry()
	var projectiles: Array = registry.active_projectiles() if registry != null else get_tree().get_nodes_in_group("projectiles")
	for candidate in projectiles:
		if candidate is SidebayProjectile and candidate != self and candidate.can_be_intercepted and (candidate.team != team or airburst_intercepts_friendlies):
			if global_position.distance_to(candidate.global_position) <= blast_radius_m:
				candidate.intercept()
	var entities: Array = registry.active_combat_entities() if registry != null else get_tree().get_nodes_in_group("combat_entities")
	for candidate in entities:
		if not (candidate is CombatShip) or candidate.is_destroyed:
			continue
		if not friendly_fire and candidate.team == team:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance > blast_radius_m + candidate.collision_radius_m:
			continue
		var falloff := lerpf(1.0, 0.18, clampf(distance / blast_radius_m, 0.0, 1.0))
		var target_damage_multiplier := _airburst_target_damage_multiplier(candidate)
		candidate.receive_damage(damage * falloff * target_damage_multiplier, source_entity_id, _impact_context(distance, falloff, target_damage_multiplier))
	var vfx := _combat_vfx()
	if vfx != null:
		if projectile_role == "flak" and vfx.has_method("spawn_flak_airburst"):
			vfx.spawn_flak_airburst(global_position, team, source_visual_id, 1.15)
		else:
			vfx.spawn_faction_burst(projectile_role, global_position, team, source_visual_id, 4.8 if projectile_role == "nuclear" else 1.15)
	queue_free()

func _airburst_target_damage_multiplier(candidate: CombatShip) -> float:
	if airburst_distance_m <= 0.0:
		return 1.0
	var role := String(candidate.definition.role).to_lower() if candidate.definition != null else ""
	var strikecraft := candidate is FighterCraft or role in ["fighter", "drone", "interceptor", "scout"] or role.contains("fighter") or role.contains("drone")
	return airburst_strikecraft_damage_multiplier if strikecraft else airburst_capital_damage_multiplier

func _impact_context(distance_from_blast_m: float = 0.0, radial_falloff: float = 1.0, target_damage_multiplier: float = 1.0) -> Dictionary:
	return {
		"position": global_position,
		"weapon_role": projectile_role,
		"projectile_damage": damage,
		"source_visual_id": source_visual_id,
		"projectile_direction": direction,
		"distance_from_blast_m": distance_from_blast_m,
		"radial_falloff": radial_falloff,
		"target_damage_multiplier": target_damage_multiplier,
		"radial_warhead": radial_warhead or airburst_distance_m > 0.0,
	}

func intercept() -> void:
	if can_be_intercepted:
		expire("missile" if projectile_role == "nuclear" else projectile_role)

func expire(effect_role: String = "") -> void:
	if expired:
		return
	expired = true
	var vfx := _combat_vfx()
	if vfx != null:
		vfx.spawn_faction_burst(effect_role if not effect_role.is_empty() else projectile_role, global_position, team, source_visual_id)
	queue_free()
