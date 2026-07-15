class_name FighterCraft
extends CombatShip

enum ManeuverMode { MOVE, HOLD, ESCORT, ATTACK, INTERCEPT }
enum AttackPhase { APPROACH, FIRING_RUN, BREAKAWAY, REFORM }

var deployed: bool = false
var desired_position: Vector3
var assigned_target: CombatShip
var ammunition: int = 0
var endurance_seconds: float = 0.0
var home_squadron: SidebaySquadron
var engine_trails: Array[MeshInstance3D] = []
var loadout_id: StringName = &""
var loadout_ammunition_capacity: int = -1
var loadout_damage_multiplier: float = 1.0
var loadout_cycle_multiplier: float = 1.0
var loadout_range_multiplier: float = 1.0
var identification_gain_multiplier: float = 1.0
var uncertainty_multiplier: float = 1.0
var missile_interception_enabled: bool = false
var missile_intercept_range_m: float = 650.0
var defensive_cycle_multiplier: float = 1.0
var escape_pod_recovery_range_m: float = 0.0
var interception_cooldown: float = 0.0
var maneuver_mode: ManeuverMode = ManeuverMode.MOVE
var attack_phase: AttackPhase = AttackPhase.APPROACH
var attack_phase_elapsed: float = 0.0
var breakaway_position: Vector3 = Vector3.ZERO
var reform_offset: Vector3 = Vector3.ZERO
var anchor_velocity: Vector3 = Vector3.ZERO
var desired_facing: Vector3 = Vector3.ZERO

func _build_visual() -> void:
	var identity := String(definition.ship_id)
	if _try_build_authored_visual():
		_add_engine_trails(identity)
		_add_default_collision()
		return
	if definition.role == "drone":
		_build_watcher_drone()
	elif identity.begins_with("vesper_"):
		_build_vesper_lance()
	elif identity.begins_with("crucible_"):
		_build_crucible_talon()
	else:
		_build_interceptor(identity.begins_with("acheron_"))
	_build_craft_surface_details(identity)
	_add_engine_trails(identity)
	_add_default_collision()

func _authored_socket_requirements() -> Dictionary:
	return {"socket_engine_": 2 if definition != null and definition.role == "drone" else 1}

func _build_interceptor(hostile: bool) -> void:
	var fuselage := MeshInstance3D.new()
	fuselage.name = "FighterFuselage"
	var fuselage_mesh := PrismMesh.new()
	fuselage_mesh.size = Vector3(definition.dimensions_m.x * (0.48 if hostile else 0.36), definition.dimensions_m.y * 0.72, definition.dimensions_m.z)
	fuselage.mesh = fuselage_mesh
	fuselage.rotation.y = PI
	fuselage.material_override = _make_material(visual_color, 0.08)
	add_child(fuselage)
	for side in [-1.0, 1.0]:
		var wing := _add_visual_block("SweptWing", Vector3(side * definition.dimensions_m.x * 0.3, 0.0, definition.dimensions_m.z * 0.12), Vector3(definition.dimensions_m.x * 0.58, definition.dimensions_m.y * 0.15, definition.dimensions_m.z * 0.48), visual_color.darkened(0.08))
		wing.rotation_degrees.y = side * (-16.0 if hostile else 22.0)
		var leading_edge := _add_visual_block("InterceptorLeadingEdge", Vector3(side * definition.dimensions_m.x * 0.42, definition.dimensions_m.y * 0.06, -definition.dimensions_m.z * 0.02), Vector3(definition.dimensions_m.x * 0.22, definition.dimensions_m.y * 0.035, definition.dimensions_m.z * 0.2), visual_profile.marking_color, 0.32)
		leading_edge.rotation_degrees.y = side * (-16.0 if hostile else 22.0)
	_add_visual_block("FighterEngine", Vector3(0.0, 0.0, definition.dimensions_m.z * 0.48), Vector3(definition.dimensions_m.x * 0.22, definition.dimensions_m.y * 0.24, 1.0), Color(1.0, 0.22, 0.04) if hostile else Color(0.12, 0.72, 1.0), 3.4)

func _build_watcher_drone() -> void:
	for side in [-1.0, 1.0]:
		var boom := _add_visual_block("WatcherBoom", Vector3(side * definition.dimensions_m.x * 0.28, 0.0, 0.0), Vector3(definition.dimensions_m.x * 0.2, definition.dimensions_m.y * 0.44, definition.dimensions_m.z * 0.86), visual_color.darkened(0.06))
		boom.rotation_degrees.y = side * 5.0
	var sensor := MeshInstance3D.new()
	sensor.name = "WatcherSensorEye"
	var sensor_mesh := SphereMesh.new()
	sensor_mesh.radius = definition.dimensions_m.y * 0.36
	sensor_mesh.height = definition.dimensions_m.y * 0.48
	sensor_mesh.radial_segments = 8
	sensor_mesh.rings = 4
	sensor.mesh = sensor_mesh
	sensor.position.z = -definition.dimensions_m.z * 0.42
	sensor.material_override = _make_material(Color(0.2, 1.0, 0.78), 3.2)
	add_child(sensor)
	_add_visual_block("WatcherCrossplane", Vector3.ZERO, Vector3(definition.dimensions_m.x * 0.82, definition.dimensions_m.y * 0.12, definition.dimensions_m.z * 0.28), visual_color)

func _build_vesper_lance() -> void:
	var needle := MeshInstance3D.new()
	needle.name = "VesperNeedleFuselage"
	var needle_mesh := PrismMesh.new()
	needle_mesh.size = Vector3(definition.dimensions_m.x * 0.26, definition.dimensions_m.y * 0.58, definition.dimensions_m.z * 1.12)
	needle.mesh = needle_mesh
	needle.rotation.y = PI
	needle.material_override = _make_material(visual_color, 0.1, visual_profile.hull_texture_path)
	add_child(needle)
	for side in [-1.0, 1.0]:
		var blade := _add_visual_block("VesperBladeWing", Vector3(side * definition.dimensions_m.x * 0.34, 0.0, definition.dimensions_m.z * 0.18), Vector3(definition.dimensions_m.x * 0.68, definition.dimensions_m.y * 0.1, definition.dimensions_m.z * 0.36), visual_color.lightened(0.04))
		blade.rotation_degrees.y = side * 32.0
	_add_visual_block("VesperDrive", Vector3(0.0, 0.0, definition.dimensions_m.z * 0.52), Vector3(definition.dimensions_m.x * 0.14, definition.dimensions_m.y * 0.2, 0.8), Color(0.95, 0.18, 1.0), 3.8)

func _build_crucible_talon() -> void:
	var body := MeshInstance3D.new()
	body.name = "CrucibleCarapace"
	var body_mesh := PrismMesh.new()
	body_mesh.size = Vector3(definition.dimensions_m.x * 0.58, definition.dimensions_m.y * 0.76, definition.dimensions_m.z)
	body.mesh = body_mesh
	body.rotation.y = PI
	body.material_override = _make_material(visual_color, 0.1, visual_profile.hull_texture_path)
	add_child(body)
	var delta_wing := _add_visual_block("CrucibleDeltaWing", Vector3(0.0, 0.0, definition.dimensions_m.z * 0.16), Vector3(definition.dimensions_m.x, definition.dimensions_m.y * 0.16, definition.dimensions_m.z * 0.56), visual_color.darkened(0.08), 0.0, visual_profile.hull_texture_path)
	delta_wing.rotation_degrees.z = 5.0
	for side in [-1.0, 1.0]:
		var fin := _add_visual_block("CrucibleTalonFin", Vector3(side * definition.dimensions_m.x * 0.28, definition.dimensions_m.y * 0.3, definition.dimensions_m.z * 0.22), Vector3(definition.dimensions_m.x * 0.08, definition.dimensions_m.y * 0.72, definition.dimensions_m.z * 0.32), visual_color.lightened(0.06), 0.0, visual_profile.hull_texture_path)
		fin.rotation_degrees.z = side * 18.0
	_add_visual_block("CrucibleDrive", Vector3(0.0, 0.0, definition.dimensions_m.z * 0.5), Vector3(definition.dimensions_m.x * 0.24, definition.dimensions_m.y * 0.22, 1.0), Color(0.68, 0.18, 1.0), 3.8)

func _build_craft_surface_details(identity: String) -> void:
	if definition.role != "drone":
		_add_visual_block("CanopyOrSensorShroud", Vector3(0.0, definition.dimensions_m.y * 0.38, -definition.dimensions_m.z * 0.25), Vector3(definition.dimensions_m.x * 0.16, definition.dimensions_m.y * 0.12, definition.dimensions_m.z * 0.22), visual_profile.bridge_color, 1.0)
	_add_visual_block("CraftRecognitionMark", Vector3(0.0, definition.dimensions_m.y * 0.42, definition.dimensions_m.z * 0.08), Vector3(definition.dimensions_m.x * 0.18, definition.dimensions_m.y * 0.026, definition.dimensions_m.z * 0.24), visual_profile.marking_color, 0.55)
	match visual_profile.faction_style:
		&"acheron":
			for side in [-1.0, 1.0]:
				var tooth := _add_visual_block("AcheronWingTooth", Vector3(side * definition.dimensions_m.x * 0.38, -definition.dimensions_m.y * 0.11, -definition.dimensions_m.z * 0.17), Vector3(definition.dimensions_m.x * 0.2, definition.dimensions_m.y * 0.08, definition.dimensions_m.z * 0.2), visual_color.darkened(0.18), 0.0, visual_profile.hull_texture_path)
				tooth.rotation_degrees.y = side * 24.0
		&"vesper":
			for side in [-1.0, 1.0]:
				var vein := _add_visual_block("VesperPhaseVein", Vector3(side * definition.dimensions_m.x * 0.24, definition.dimensions_m.y * 0.12, definition.dimensions_m.z * 0.03), Vector3(definition.dimensions_m.x * 0.025, definition.dimensions_m.y * 0.025, definition.dimensions_m.z * 0.58), visual_profile.marking_color, 1.45)
				vein.rotation_degrees.y = side * 9.0
		&"crucible":
			for side in [-1.0, 1.0]:
				var facet := _add_visual_block("CrucibleWingFacet", Vector3(side * definition.dimensions_m.x * 0.3, definition.dimensions_m.y * 0.12, definition.dimensions_m.z * 0.12), Vector3(definition.dimensions_m.x * 0.3, definition.dimensions_m.y * 0.045, definition.dimensions_m.z * 0.28), visual_color.lightened(0.03), 0.0, visual_profile.hull_texture_path)
				facet.rotation_degrees.y = side * 12.0

func _add_engine_trails(identity: String) -> void:
	var trail_color := Color(0.12, 0.72, 1.0, 0.52)
	if identity.begins_with("vesper_"):
		trail_color = Color(0.95, 0.18, 1.0, 0.5)
	elif identity.begins_with("crucible_"):
		trail_color = Color(0.65, 0.16, 1.0, 0.52)
	elif team == &"hostile":
		trail_color = Color(1.0, 0.28, 0.04, 0.48)
	var authored_engines := _authored_socket_nodes("socket_engine_")
	if not authored_engines.is_empty():
		for socket in authored_engines:
			_add_engine_trail(socket, Vector3(0.0, 0.0, definition.dimensions_m.z * 0.4), trail_color)
		return
	for side in ([-1.0, 1.0] if definition.role == "drone" else [0.0]):
		_add_engine_trail(self, Vector3(side * definition.dimensions_m.x * 0.28, 0.0, definition.dimensions_m.z * 0.88), trail_color)

func _add_engine_trail(parent: Node3D, local_position: Vector3, trail_color: Color) -> void:
	var trail := MeshInstance3D.new()
	trail.name = "EngineTrail"
	var trail_mesh := PrismMesh.new()
	trail_mesh.size = Vector3(definition.dimensions_m.x * 0.12, definition.dimensions_m.y * 0.12, definition.dimensions_m.z * 0.8)
	trail.mesh = trail_mesh
	trail.position = local_position
	trail.rotation.y = PI
	var material := _make_material(trail_color, 2.2)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = material
	parent.add_child(trail)
	engine_trails.append(trail)

func configure_craft(
	ship_definition: ShipDefinition,
	entity_id: StringName,
	faction: StringName,
	color: Color,
	squadron: SidebaySquadron,
	starting_ammunition: int,
	starting_endurance: float
) -> void:
	configure(ship_definition, entity_id, faction, color)
	home_squadron = squadron
	ammunition = mini(starting_ammunition, maximum_ammunition())
	endurance_seconds = starting_endurance
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func apply_loadout_profile(profile: Dictionary, discard_loaded_ordnance: bool = false) -> void:
	loadout_id = StringName(profile.get("loadout_id", profile.get("id", loadout_id)))
	loadout_ammunition_capacity = maxi(0, int(profile.get("ammunition_per_craft", profile.get("ammo_per_craft", maximum_ammunition()))))
	loadout_damage_multiplier = maxf(0.0, float(profile.get("damage_multiplier", 1.0)))
	loadout_cycle_multiplier = maxf(0.05, float(profile.get("cycle_multiplier", 1.0)))
	loadout_range_multiplier = maxf(0.05, float(profile.get("range_multiplier", 1.0)))
	identification_gain_multiplier = maxf(0.0, float(profile.get("identification_gain_multiplier", 1.0)))
	uncertainty_multiplier = maxf(0.0, float(profile.get("uncertainty_multiplier", 1.0)))
	missile_interception_enabled = bool(profile.get("missile_interception", profile.get("can_intercept_missiles", false)))
	missile_intercept_range_m = maxf(50.0, float(profile.get("missile_intercept_range_m", 650.0)))
	defensive_cycle_multiplier = maxf(0.05, float(profile.get("defensive_cycle_multiplier", 1.0)))
	escape_pod_recovery_range_m = maxf(0.0, float(profile.get("escape_pod_recovery_range_m", 0.0)))
	if discard_loaded_ordnance:
		ammunition = 0
	else:
		ammunition = mini(ammunition, maximum_ammunition())

func maximum_ammunition() -> int:
	if loadout_ammunition_capacity >= 0:
		return loadout_ammunition_capacity
	if home_squadron != null and home_squadron.definition != null:
		return home_squadron.definition.ammunition_per_craft
	return maxi(0, ammunition)

func deploy(at_position: Vector3, initial_velocity: Vector3) -> void:
	global_position = at_position
	velocity = initial_velocity
	visible = true
	deployed = true
	process_mode = Node.PROCESS_MODE_INHERIT
	desired_position = at_position - global_transform.basis.z * 250.0
	maneuver_mode = ManeuverMode.MOVE
	attack_phase = AttackPhase.APPROACH

func dock() -> void:
	deployed = false
	visible = false
	velocity = Vector3.ZERO
	assigned_target = null
	maneuver_mode = ManeuverMode.MOVE
	process_mode = Node.PROCESS_MODE_DISABLED

func service(maximum_ammunition_value: int, maximum_endurance: float) -> void:
	# Compatibility path for callers that have not adopted finite deck stores yet.
	service_repair(0.35)
	service_refuel(maximum_endurance)
	service_rearm(maximum_ammunition_value, maximum_ammunition_value)

func service_repair(armor_recovery_fraction: float) -> void:
	if damage_state == null or damage_state.definition == null:
		return
	damage_state.shields = damage_state.definition.max_shields
	damage_state.armor = minf(
		damage_state.definition.max_armor,
		damage_state.armor + damage_state.definition.max_armor * maxf(0.0, armor_recovery_fraction)
	)

func service_refuel(maximum_endurance: float) -> void:
	endurance_seconds = maxf(0.0, maximum_endurance)

func service_rearm(maximum_ammunition_value: int, available_rounds: int) -> int:
	var target := mini(maxi(0, maximum_ammunition_value), maximum_ammunition())
	var loaded := mini(maxi(0, available_rounds), maxi(0, target - ammunition))
	ammunition += loaded
	return loaded

func command_move(position_value: Vector3) -> void:
	desired_position = position_value
	assigned_target = null
	anchor_velocity = Vector3.ZERO
	desired_facing = Vector3.ZERO
	maneuver_mode = ManeuverMode.MOVE

func command_hold(position_value: Vector3, facing: Vector3 = Vector3.ZERO) -> void:
	desired_position = position_value
	assigned_target = null
	anchor_velocity = Vector3.ZERO
	desired_facing = facing
	maneuver_mode = ManeuverMode.HOLD

func command_escort(position_value: Vector3, velocity_value: Vector3) -> void:
	desired_position = position_value
	assigned_target = null
	anchor_velocity = velocity_value
	desired_facing = velocity_value.normalized()
	maneuver_mode = ManeuverMode.ESCORT

func command_attack(target_ship: CombatShip, intercept_mode: bool = false) -> void:
	var next_mode := ManeuverMode.INTERCEPT if intercept_mode else ManeuverMode.ATTACK
	if assigned_target != target_ship or maneuver_mode != next_mode:
		attack_phase = AttackPhase.APPROACH
		attack_phase_elapsed = 0.0
	assigned_target = target_ship
	maneuver_mode = next_mode

func _physics_process(delta: float) -> void:
	if not deployed or is_destroyed:
		return
	damage_state.tick(delta)
	weapon_cooldown = maxf(0.0, weapon_cooldown - delta)
	interception_cooldown = maxf(0.0, interception_cooldown - delta)
	endurance_seconds = maxf(0.0, endurance_seconds - delta)
	attack_phase_elapsed += delta
	_update_engine_trails()
	_process_missile_interception()
	if is_instance_valid(assigned_target) and not assigned_target.is_destroyed:
		_process_attack_maneuver()
	elif assigned_target != null:
		assigned_target = null
		maneuver_mode = ManeuverMode.HOLD
		desired_position = global_position
	_move_fighter(delta)
	_enforce_battlespace_bounds()

func _process_attack_maneuver() -> void:
	var distance_to_target := global_position.distance_to(assigned_target.global_position)
	var preferred_range := _preferred_weapon_range()
	if maneuver_mode == ManeuverMode.INTERCEPT:
		var intercept_seconds := distance_to_target / maxf(1.0, definition.maximum_speed_mps + assigned_target.velocity.length())
		desired_position = assigned_target.global_position + assigned_target.velocity * clampf(intercept_seconds, 0.0, 6.0)
		if distance_to_target <= preferred_range:
			_try_fire_craft_weapon()
		return
	match attack_phase:
		AttackPhase.APPROACH:
			var lead_seconds := distance_to_target / maxf(1.0, definition.maximum_speed_mps)
			desired_position = assigned_target.global_position + assigned_target.velocity * clampf(lead_seconds, 0.0, 4.0)
			if distance_to_target <= preferred_range * 1.08:
				attack_phase = AttackPhase.FIRING_RUN
				attack_phase_elapsed = 0.0
		AttackPhase.FIRING_RUN:
			desired_position = assigned_target.global_position + assigned_target.velocity * 0.35
			if distance_to_target <= preferred_range:
				_try_fire_craft_weapon()
			if distance_to_target <= maxf(150.0, assigned_target.collision_radius_m * 4.0) or attack_phase_elapsed >= 2.4:
				_begin_breakaway(preferred_range)
		AttackPhase.BREAKAWAY:
			desired_position = breakaway_position
			if global_position.distance_to(breakaway_position) <= 75.0 or distance_to_target >= preferred_range * 1.15:
				_begin_reform(preferred_range)
		AttackPhase.REFORM:
			desired_position = assigned_target.global_position + reform_offset
			if global_position.distance_to(desired_position) <= 110.0 or attack_phase_elapsed >= 2.2:
				attack_phase = AttackPhase.APPROACH
				attack_phase_elapsed = 0.0

func _begin_breakaway(preferred_range: float) -> void:
	var forward := velocity.normalized()
	if forward.length_squared() < 0.1:
		forward = assigned_target.global_position.direction_to(global_position)
	var lateral := forward.cross(Vector3.UP).normalized()
	if stable_entity_id.hash() % 2 == 0:
		lateral = -lateral
	breakaway_position = global_position + forward * preferred_range * 0.85 + lateral * preferred_range * 0.42
	breakaway_position.y = clampf(breakaway_position.y + (45.0 if stable_entity_id.hash() % 3 == 0 else -45.0), -VERTICAL_BATTLESPACE_LIMIT_M, VERTICAL_BATTLESPACE_LIMIT_M)
	attack_phase = AttackPhase.BREAKAWAY
	attack_phase_elapsed = 0.0


func _begin_reform(preferred_range: float) -> void:
	var target_forward := assigned_target.velocity.normalized()
	if target_forward.length_squared() < 0.1:
		target_forward = -assigned_target.global_transform.basis.z.normalized()
	var lateral := target_forward.cross(Vector3.UP).normalized()
	if stable_entity_id.hash() % 2 == 0:
		lateral = -lateral
	reform_offset = -target_forward * preferred_range * 1.05 + lateral * preferred_range * 0.3
	attack_phase = AttackPhase.REFORM
	attack_phase_elapsed = 0.0

func _update_engine_trails() -> void:
	var speed_ratio := clampf(velocity.length() / maxf(1.0, definition.maximum_speed_mps), 0.15, 1.0)
	for trail in engine_trails:
		trail.scale.z = lerpf(0.25, 1.35, speed_ratio)
		trail.transparency = lerpf(0.55, 0.08, speed_ratio)

func _move_fighter(delta: float) -> void:
	var offset := desired_position - global_position
	if offset.length_squared() < 25.0:
		var target_velocity := anchor_velocity if maneuver_mode == ManeuverMode.ESCORT else Vector3.ZERO
		velocity = velocity.move_toward(target_velocity, definition.acceleration_mps2 * delta)
		if maneuver_mode == ManeuverMode.HOLD and desired_facing.length_squared() > 0.5:
			var desired_yaw := atan2(-desired_facing.x, -desired_facing.z)
			rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(definition.rotation_speed_radians * delta, 0.0, 1.0))
	else:
		var slow_radius := maxf(180.0, _preferred_weapon_range() * 0.3)
		var speed_ratio := clampf(offset.length() / slow_radius, 0.18, 1.0)
		var desired_velocity := offset.normalized() * definition.maximum_speed_mps * speed_ratio
		if maneuver_mode == ManeuverMode.ESCORT:
			desired_velocity += anchor_velocity * (1.0 - speed_ratio) * 0.8
		desired_velocity += _separation_velocity() * definition.maximum_speed_mps * 0.42
		desired_velocity = desired_velocity.limit_length(definition.maximum_speed_mps)
		velocity = velocity.move_toward(desired_velocity, definition.acceleration_mps2 * delta)
		var forward := velocity.normalized()
		if forward.length_squared() > 0.1:
			look_at(global_position + forward, Vector3.UP, true)
	move_and_slide()

func _try_fire_craft_weapon() -> void:
	if ammunition <= 0 or weapon_cooldown > 0.0 or definition.weapons.is_empty():
		return
	var weapon := definition.weapons[0]
	var fire_direction := CombatShip.intercept_direction(global_position, assigned_target.global_position, assigned_target.velocity, weapon.projectile_speed_mps)
	var projectile := spawn_projectile(weapon, global_position, fire_direction, assigned_target if weapon.tracks_target else null)
	projectile.damage *= loadout_damage_multiplier
	projectile.maximum_distance_m *= loadout_range_multiplier
	ammunition -= 1
	weapon_cooldown = weapon_cycle_seconds(weapon.cooldown_seconds)


func weapon_cycle_seconds(base_cooldown_seconds: float) -> float:
	var defensive_cycle := defensive_cycle_multiplier if loadout_id == &"watcher_screen" else 1.0
	return base_cooldown_seconds * loadout_cycle_multiplier * defensive_cycle

func _preferred_weapon_range() -> float:
	if definition == null or definition.weapons.is_empty():
		return 1200.0 * loadout_range_multiplier
	return definition.weapons[0].range_m * loadout_range_multiplier

func _process_missile_interception() -> void:
	if not missile_interception_enabled or interception_cooldown > 0.0 or ammunition <= 0:
		return
	var registry := _combat_registry()
	var projectiles: Array = registry.active_projectiles() if registry != null else get_tree().get_nodes_in_group("projectiles")
	var best: SidebayProjectile
	var best_score := INF
	for candidate in projectiles:
		if not candidate is SidebayProjectile or candidate.team == team or not candidate.can_be_intercepted:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance > missile_intercept_range_m:
			continue
		var protected_target: CombatShip = candidate.target if is_instance_valid(candidate.target) and candidate.target.team == team else home_squadron.home_carrier
		var threat_distance: float = candidate.global_position.distance_to(protected_target.global_position) if is_instance_valid(protected_target) else distance
		var time_to_impact: float = threat_distance / maxf(1.0, candidate.speed_mps)
		var score: float = time_to_impact - (5.0 if is_instance_valid(protected_target) and protected_target == home_squadron.home_carrier else 0.0)
		if candidate.radial_warhead:
			score -= 3.0
		if score < best_score:
			best = candidate
			best_score = score
	if is_instance_valid(best):
		best.intercept()
		ammunition -= 1
		interception_cooldown = 0.65 * defensive_cycle_multiplier
