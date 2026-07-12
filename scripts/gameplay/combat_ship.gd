class_name CombatShip
extends CharacterBody3D

const VERTICAL_BATTLESPACE_LIMIT_M := 1400.0

static var armor_panel_texture: Texture2D
static var deck_marking_texture: Texture2D
static var hull_texture_cache: Dictionary = {}

signal ship_destroyed(entity_id: StringName)
signal damage_received(entity_id: StringName, source_entity_id: StringName, amount: float)
signal order_acknowledged(entity_id: StringName, message: String)

var stable_entity_id: StringName = &"unconfigured"
var display_name: String = "Ship"
var team: StringName = &"neutral"
var definition: ShipDefinition
var damage_state: DamageState
var collision_radius_m: float = 20.0
var is_destroyed: bool = false
var is_command_ship: bool = false
var ai_enabled: bool = false
var current_target: CombatShip
var current_order: FleetOrder
var order_queue: Array[FleetOrder] = []
var command_link := CommandLinkState.new()
var stance: StringName = &"balanced"
var formation_name: StringName = &"wedge"
var weapon_cooldown: float = 0.0
var hold_position: Vector3 = Vector3.ZERO
var visual_color: Color = Color(0.35, 0.55, 0.7)

func configure(ship_definition: ShipDefinition, entity_id: StringName, faction: StringName, color: Color) -> void:
	definition = ship_definition
	stable_entity_id = entity_id
	display_name = definition.display_name
	team = faction
	visual_color = color
	damage_state = DamageState.new(definition.damage_layers)
	damage_state.destroyed.connect(_on_destroyed)
	collision_radius_m = maxf(definition.dimensions_m.x, definition.dimensions_m.z) * 0.35
	add_to_group("combat_entities")
	add_to_group("team_%s" % team)
	var registry := _combat_registry()
	if registry != null:
		registry.register_combat_entity(self)
	_build_visual()

func _exit_tree() -> void:
	var registry := _combat_registry()
	if registry != null:
		registry.unregister_combat_entity(self)

func _combat_registry() -> Node:
	return get_node_or_null("/root/CombatRegistry")

func _combat_vfx() -> Node:
	return get_node_or_null("/root/CombatVFX")

func _build_visual() -> void:
	var hull_dimensions := definition.dimensions_m
	var profile := ShipVisualProfile.for_ship(StringName(definition.role), team, definition.ship_id)
	var body := MeshInstance3D.new()
	body.name = "Hull"
	var mesh := BoxMesh.new()
	mesh.size = hull_dimensions * profile.core_scale
	body.mesh = mesh
	body.material_override = _make_material(visual_color, 0.1, profile.hull_texture_path)
	add_child(body)
	_add_visual_block("DorsalArmor", Vector3(0.0, hull_dimensions.y * 0.38, hull_dimensions.z * 0.05), hull_dimensions * profile.dorsal_scale, visual_color.lightened(0.08), 0.0, profile.hull_texture_path)
	_add_visual_block("Keel", Vector3(0.0, -hull_dimensions.y * 0.38, hull_dimensions.z * 0.08), hull_dimensions * profile.keel_scale, visual_color.darkened(0.22), 0.0, profile.hull_texture_path)
	for side in [-1.0, 1.0]:
		_add_visual_block("ArmorShoulder", Vector3(side * hull_dimensions.x * 0.43, 0.0, hull_dimensions.z * 0.08), hull_dimensions * profile.shoulder_scale, visual_color.darkened(0.08), 0.0, profile.hull_texture_path)
		_add_engine_nacelle(side, hull_dimensions, profile)
	var nose := MeshInstance3D.new()
	nose.name = "ArmoredBow"
	var nose_mesh := PrismMesh.new()
	nose_mesh.size = hull_dimensions * profile.bow_scale
	nose.mesh = nose_mesh
	nose.position.z = -definition.dimensions_m.z * 0.62
	nose.rotation.y = PI
	nose.material_override = _make_material(visual_color.lightened(0.15), 0.0, profile.hull_texture_path)
	add_child(nose)
	_build_hull_details(hull_dimensions, profile)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = definition.dimensions_m
	collision.shape = shape
	add_child(collision)

func _build_hull_details(hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	_add_visual_block("AftEngineering", Vector3(0.0, -hull_dimensions.y * 0.05, hull_dimensions.z * 0.39), Vector3(hull_dimensions.x * 0.52, hull_dimensions.y * 0.58, hull_dimensions.z * 0.18), visual_color.darkened(0.18), 0.0, profile.hull_texture_path)
	_add_visual_block("LongitudinalSpine", Vector3(0.0, hull_dimensions.y * 0.46, hull_dimensions.z * 0.02), Vector3(hull_dimensions.x * 0.12, hull_dimensions.y * 0.16, hull_dimensions.z * 0.78), profile.accent_color.darkened(0.32), 0.0, profile.hull_texture_path)
	for index in profile.armor_rib_count:
		var progress := (float(index) + 1.0) / (float(profile.armor_rib_count) + 1.0)
		var z_position := lerpf(-hull_dimensions.z * 0.35, hull_dimensions.z * 0.34, progress)
		_add_visual_block("ArmorRib%02d" % index, Vector3(0.0, hull_dimensions.y * 0.34, z_position), Vector3(hull_dimensions.x * 0.78, hull_dimensions.y * 0.08, hull_dimensions.z * 0.035), profile.accent_color.darkened(0.38), 0.0, profile.hull_texture_path)
	_build_command_tower(hull_dimensions, profile)
	for turret_index in profile.turret_count:
		var turret_progress := (float(turret_index) + 1.0) / (float(profile.turret_count) + 1.0)
		var turret_z := lerpf(-hull_dimensions.z * 0.4, hull_dimensions.z * 0.24, turret_progress)
		var turret_side := -1.0 if turret_index % 2 == 0 else 1.0
		_add_weapon_turret(turret_index, Vector3(turret_side * hull_dimensions.x * 0.24, hull_dimensions.y * 0.55, turret_z), hull_dimensions, profile)
	if profile.faction_style == &"navy":
		_build_navy_details(hull_dimensions, profile)
	else:
		_build_hostile_fins(hull_dimensions, profile)

func _build_command_tower(hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	var tower_z := hull_dimensions.z * 0.08
	_add_visual_block("CommandTower", Vector3(0.0, hull_dimensions.y * 0.67, tower_z), Vector3(hull_dimensions.x * 0.3, hull_dimensions.y * 0.32, hull_dimensions.z * 0.2), visual_color.lightened(0.04), 0.0, profile.hull_texture_path)
	_add_visual_block("BridgeWindows", Vector3(0.0, hull_dimensions.y * 0.73, tower_z - hull_dimensions.z * 0.105), Vector3(hull_dimensions.x * 0.23, hull_dimensions.y * 0.06, hull_dimensions.z * 0.018), profile.bridge_color, 2.2)
	var mast := MeshInstance3D.new()
	mast.name = "SensorMast"
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = hull_dimensions.x * 0.025
	mast_mesh.bottom_radius = hull_dimensions.x * 0.035
	mast_mesh.height = hull_dimensions.y * 0.48
	mast_mesh.radial_segments = 8
	mast.mesh = mast_mesh
	mast.position = Vector3(0.0, hull_dimensions.y * 1.02, tower_z + hull_dimensions.z * 0.04)
	mast.material_override = _make_material(profile.accent_color.darkened(0.25), 0.0, profile.hull_texture_path)
	add_child(mast)
	var sensor := MeshInstance3D.new()
	sensor.name = "SensorCrown"
	var sensor_mesh := SphereMesh.new()
	sensor_mesh.radius = hull_dimensions.x * 0.075
	sensor_mesh.height = hull_dimensions.x * 0.1
	sensor_mesh.radial_segments = 8
	sensor_mesh.rings = 4
	sensor.mesh = sensor_mesh
	sensor.position = mast.position + Vector3.UP * hull_dimensions.y * 0.28
	sensor.material_override = _make_material(profile.bridge_color, 1.1)
	add_child(sensor)

func _build_navy_details(hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	for side in [-1.0, 1.0]:
		_add_visual_block("MissionPod", Vector3(side * hull_dimensions.x * 0.5, -hull_dimensions.y * 0.12, -hull_dimensions.z * 0.02), Vector3(hull_dimensions.x * 0.14, hull_dimensions.y * 0.34, hull_dimensions.z * 0.32), visual_color.darkened(0.12), 0.0, profile.hull_texture_path)
		_add_visual_block("RegistryStripe", Vector3(side * hull_dimensions.x * 0.575, hull_dimensions.y * 0.03, -hull_dimensions.z * 0.08), Vector3(hull_dimensions.x * 0.012, hull_dimensions.y * 0.08, hull_dimensions.z * 0.18), profile.accent_color, 0.18)

func _build_hostile_fins(hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		fin.name = "BladeFin"
		var fin_mesh := PrismMesh.new()
		fin_mesh.size = Vector3(hull_dimensions.x * profile.fin_scale, hull_dimensions.y * 0.14, hull_dimensions.z * 0.42)
		fin.mesh = fin_mesh
		fin.position = Vector3(side * hull_dimensions.x * 0.55, hull_dimensions.y * (0.08 if profile.faction_style == &"raider" else 0.28), hull_dimensions.z * 0.02)
		fin.rotation_degrees = Vector3(0.0, 0.0, side * (18.0 if profile.faction_style == &"raider" else 34.0))
		fin.material_override = _make_material(visual_color.darkened(0.1), 0.0, profile.hull_texture_path)
		add_child(fin)
		_add_visual_block("FactionLight", Vector3(side * hull_dimensions.x * 0.46, hull_dimensions.y * 0.26, -hull_dimensions.z * 0.18), Vector3(hull_dimensions.x * 0.025, hull_dimensions.y * 0.055, hull_dimensions.z * 0.26), profile.accent_color, 1.8)

func _add_weapon_turret(index: int, position_value: Vector3, hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	var turret := MeshInstance3D.new()
	turret.name = "WeaponTurret%02d" % index
	var turret_mesh := CylinderMesh.new()
	turret_mesh.top_radius = hull_dimensions.x * 0.08
	turret_mesh.bottom_radius = hull_dimensions.x * 0.11
	turret_mesh.height = hull_dimensions.y * 0.12
	turret_mesh.radial_segments = 8
	turret.mesh = turret_mesh
	turret.position = position_value
	turret.material_override = _make_material(visual_color.darkened(0.16), 0.0, profile.hull_texture_path)
	add_child(turret)
	var barrel := _add_visual_block("TurretBarrel%02d" % index, position_value + Vector3(0.0, hull_dimensions.y * 0.04, -hull_dimensions.z * 0.075), Vector3(hull_dimensions.x * 0.045, hull_dimensions.y * 0.045, hull_dimensions.z * 0.18), profile.accent_color.darkened(0.42), 0.0, profile.hull_texture_path)
	barrel.rotation.x = -0.03

func _add_engine_nacelle(side: float, hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	var engine_position := Vector3(side * hull_dimensions.x * 0.3, 0.0, hull_dimensions.z * 0.44)
	_add_visual_block("EngineHousing", engine_position, Vector3(hull_dimensions.x * 0.2, hull_dimensions.y * 0.48, hull_dimensions.z * 0.28), visual_color.darkened(0.25), 0.0, profile.hull_texture_path)
	var emitter := MeshInstance3D.new()
	emitter.name = "EngineEmitter"
	var emitter_mesh := CylinderMesh.new()
	emitter_mesh.top_radius = hull_dimensions.x * 0.065
	emitter_mesh.bottom_radius = hull_dimensions.x * 0.09
	emitter_mesh.height = hull_dimensions.z * 0.055
	emitter_mesh.radial_segments = 10
	emitter.mesh = emitter_mesh
	emitter.position = engine_position + Vector3(0.0, 0.0, hull_dimensions.z * 0.165)
	emitter.rotation.x = PI * 0.5
	emitter.material_override = _make_material(profile.engine_color, profile.engine_emission)
	add_child(emitter)

func _add_visual_block(node_name: String, position_value: Vector3, size_value: Vector3, color: Color, emission_energy: float = 0.0, texture_path: String = "") -> MeshInstance3D:
	var block := MeshInstance3D.new()
	block.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size_value
	block.mesh = mesh
	block.position = position_value
	block.material_override = _make_material(color, emission_energy, texture_path)
	add_child(block)
	return block

func _make_material(color: Color, emission_energy: float = 0.0, texture_path: String = "") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.65
	material.roughness = 0.42
	if emission_energy <= 0.2:
		material.albedo_color = color.lightened(0.5)
		var default_texture_path := "res://assets/textures/navy_hull.svg" if team == &"friendly" else "res://assets/textures/raider_hull.svg"
		var resolved_texture_path := texture_path if not texture_path.is_empty() else default_texture_path
		material.albedo_texture = _hull_texture(resolved_texture_path)
		material.uv1_scale = Vector3(3.0, 3.0, 3.0)
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color * emission_energy
	return material

func _hull_texture(texture_path: String) -> Texture2D:
	if not hull_texture_cache.has(texture_path):
		hull_texture_cache[texture_path] = load(texture_path) as Texture2D
	return hull_texture_cache.get(texture_path) as Texture2D

func _physics_process(delta: float) -> void:
	if is_destroyed or definition == null:
		return
	damage_state.tick(delta)
	weapon_cooldown = maxf(0.0, weapon_cooldown - delta)
	if ai_enabled:
		_process_ai(delta)
	_enforce_battlespace_bounds()

func _enforce_battlespace_bounds() -> void:
	var clamped_height := clampf(global_position.y, -VERTICAL_BATTLESPACE_LIMIT_M, VERTICAL_BATTLESPACE_LIMIT_M)
	if not is_equal_approx(global_position.y, clamped_height):
		global_position.y = clamped_height
		if (clamped_height > 0.0 and velocity.y > 0.0) or (clamped_height < 0.0 and velocity.y < 0.0):
			velocity.y = 0.0

func _process_ai(delta: float) -> void:
	if current_order == null:
		return
	match current_order.order_type:
		FleetOrder.OrderType.MOVE, FleetOrder.OrderType.WITHDRAW:
			_move_toward_position(current_order.target_position, delta)
			if global_position.distance_to(current_order.target_position) < collision_radius_m * 2.0:
				_complete_order()
		FleetOrder.OrderType.HOLD:
			velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * delta)
			move_and_slide()
		FleetOrder.OrderType.ATTACK, FleetOrder.OrderType.INTERCEPT:
			current_target = resolve_entity(current_order.target_entity_id)
			if not is_instance_valid(current_target) or current_target.is_destroyed:
				_complete_order()
				return
			var preferred_range := _preferred_weapon_range() * 0.72
			if global_position.distance_to(current_target.global_position) > preferred_range:
				_move_toward_position(current_target.global_position, delta)
			else:
				velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * delta)
				move_and_slide()
			_try_fire_at(current_target)
		FleetOrder.OrderType.ESCORT:
			var escort_target := resolve_entity(current_order.target_entity_id)
			if is_instance_valid(escort_target):
				var offset := Vector3(collision_radius_m * 3.0, 0.0, collision_radius_m * 2.0)
				_move_toward_position(escort_target.global_position + offset, delta)

func _move_toward_position(destination: Vector3, delta: float) -> void:
	var offset := destination - global_position
	if offset.length_squared() < 1.0:
		return
	var desired_velocity := offset.normalized() * definition.maximum_speed_mps
	velocity = velocity.move_toward(desired_velocity, definition.acceleration_mps2 * delta)
	if velocity.length_squared() > 1.0:
		var desired_yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(definition.rotation_speed_radians * delta, 0.0, 1.0))
	move_and_slide()

func issue_order(order: FleetOrder) -> bool:
	if order.requires_command_link and not command_link.can_accept_order():
		order_acknowledged.emit(stable_entity_id, "%s: command link lost" % display_name)
		return false
	order.stance = stance
	command_link.last_confirmed_order = order
	if order.queued and current_order != null:
		order_queue.append(order)
	else:
		current_order = order
		order_queue.clear()
	order_acknowledged.emit(stable_entity_id, "%s acknowledges %s" % [display_name, FleetOrder.OrderType.keys()[order.order_type]])
	return true

func _complete_order() -> void:
	if not order_queue.is_empty():
		current_order = order_queue.pop_front()
	else:
		current_order = FleetOrder.at_position(FleetOrder.OrderType.HOLD, global_position, Time.get_ticks_msec() / 1000.0)

func set_stance(next_stance: StringName) -> void:
	stance = next_stance
	order_acknowledged.emit(stable_entity_id, "%s stance: %s" % [display_name, String(stance).capitalize()])

func cycle_formation() -> void:
	var formations: Array[StringName] = [&"wedge", &"line", &"screen", &"column"]
	var index := formations.find(formation_name)
	formation_name = formations[(index + 1) % formations.size()]
	order_acknowledged.emit(stable_entity_id, "%s formation: %s" % [display_name, String(formation_name).capitalize()])

func _preferred_weapon_range() -> float:
	if definition.weapons.is_empty():
		return 1200.0
	return definition.weapons[0].range_m

func _try_fire_at(target_ship: CombatShip) -> void:
	if weapon_cooldown > 0.0 or definition.weapons.is_empty() or not is_instance_valid(target_ship):
		return
	var weapon := definition.weapons[0]
	if global_position.distance_to(target_ship.global_position) > weapon.range_m:
		return
	spawn_projectile(weapon, global_position + global_position.direction_to(target_ship.global_position) * collision_radius_m, global_position.direction_to(target_ship.global_position), target_ship)
	weapon_cooldown = weapon.cooldown_seconds

func spawn_projectile(weapon: WeaponDefinition, start: Vector3, fire_direction: Vector3, tracked_target: CombatShip = null) -> SidebayProjectile:
	var projectile := SidebayProjectile.new()
	var scene_owner: Node = get_parent() if get_parent() != null else get_tree().root
	scene_owner.add_child(projectile)
	projectile.configure(
		team,
		stable_entity_id,
		start,
		fire_direction,
		weapon.projectile_speed_mps,
		weapon.damage,
		weapon.range_m * 1.15,
		tracked_target,
		2.5 if weapon.tracks_target else 0.0,
		weapon.role == "missile",
		weapon.role
	)
	var vfx := _combat_vfx()
	if vfx != null:
		vfx.spawn_burst("muzzle", start, 0.72 if weapon.role == "missile" else 0.42)
	return projectile

func receive_damage(amount: float, source_entity_id: StringName = &"") -> void:
	if is_destroyed:
		return
	var shielded := damage_state.shields > 0.0
	damage_state.apply_damage(amount)
	var vfx := _combat_vfx()
	if vfx != null:
		vfx.spawn_damage_effect(global_position, shielded, clampf(amount / 24.0, 0.55, 1.8))
	damage_received.emit(stable_entity_id, source_entity_id, amount)

func resolve_entity(entity_id: StringName) -> CombatShip:
	var registry := _combat_registry()
	var candidate: Node = registry.resolve_combat_entity(entity_id) if registry != null else null
	return candidate as CombatShip

func _on_destroyed() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	velocity = Vector3.ZERO
	var vfx := _combat_vfx()
	if vfx != null:
		vfx.spawn_burst("hull", global_position, 2.2)
	ship_destroyed.emit(stable_entity_id)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.45)
	tween.tween_callback(queue_free)

func layer_percentages() -> Vector3:
	return damage_state.normalized_layers() if damage_state != null else Vector3.ZERO
