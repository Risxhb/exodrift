class_name CombatShip
extends CharacterBody3D

const VERTICAL_BATTLESPACE_LIMIT_M := 1400.0

static var armor_panel_texture: Texture2D
static var deck_marking_texture: Texture2D

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
	var profile := ShipVisualProfile.for_ship(StringName(definition.role), team)
	var body := MeshInstance3D.new()
	body.name = "Hull"
	var mesh := BoxMesh.new()
	mesh.size = hull_dimensions * profile.core_scale
	body.mesh = mesh
	body.material_override = _make_material(visual_color, 0.1)
	add_child(body)
	_add_visual_block("DorsalArmor", Vector3(0.0, hull_dimensions.y * 0.38, hull_dimensions.z * 0.05), hull_dimensions * profile.dorsal_scale, visual_color.lightened(0.08))
	_add_visual_block("Keel", Vector3(0.0, -hull_dimensions.y * 0.38, hull_dimensions.z * 0.08), hull_dimensions * profile.keel_scale, visual_color.darkened(0.22))
	for side in [-1.0, 1.0]:
		_add_visual_block("ArmorShoulder", Vector3(side * hull_dimensions.x * 0.43, 0.0, hull_dimensions.z * 0.08), hull_dimensions * profile.shoulder_scale, visual_color.darkened(0.08))
		_add_visual_block("EngineBank", Vector3(side * hull_dimensions.x * 0.28, 0.0, hull_dimensions.z * 0.46), hull_dimensions * profile.engine_scale, profile.engine_color, profile.engine_emission)
	var nose := MeshInstance3D.new()
	nose.name = "ArmoredBow"
	var nose_mesh := PrismMesh.new()
	nose_mesh.size = hull_dimensions * profile.bow_scale
	nose.mesh = nose_mesh
	nose.position.z = -definition.dimensions_m.z * 0.62
	nose.rotation.y = PI
	nose.material_override = _make_material(visual_color.lightened(0.15), 0.0)
	add_child(nose)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = definition.dimensions_m
	collision.shape = shape
	add_child(collision)

func _add_visual_block(node_name: String, position_value: Vector3, size_value: Vector3, color: Color, emission_energy: float = 0.0) -> MeshInstance3D:
	var block := MeshInstance3D.new()
	block.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size_value
	block.mesh = mesh
	block.position = position_value
	block.material_override = _make_material(color, emission_energy)
	add_child(block)
	return block

func _make_material(color: Color, emission_energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.65
	material.roughness = 0.42
	if emission_energy <= 0.2:
		material.albedo_color = color.lightened(0.34)
		if armor_panel_texture == null:
			armor_panel_texture = load("res://assets/textures/armor_panels.svg") as Texture2D
		material.albedo_texture = armor_panel_texture
		material.uv1_scale = Vector3(3.0, 3.0, 3.0)
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color * emission_energy
	return material

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
