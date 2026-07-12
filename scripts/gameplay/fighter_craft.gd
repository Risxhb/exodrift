class_name FighterCraft
extends CombatShip

var deployed: bool = false
var desired_position: Vector3
var assigned_target: CombatShip
var ammunition: int = 0
var endurance_seconds: float = 0.0
var home_squadron: SidebaySquadron

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
	ammunition = starting_ammunition
	endurance_seconds = starting_endurance
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func deploy(at_position: Vector3, initial_velocity: Vector3) -> void:
	global_position = at_position
	velocity = initial_velocity
	visible = true
	deployed = true
	process_mode = Node.PROCESS_MODE_INHERIT
	desired_position = at_position - global_transform.basis.z * 250.0

func dock() -> void:
	deployed = false
	visible = false
	velocity = Vector3.ZERO
	assigned_target = null
	process_mode = Node.PROCESS_MODE_DISABLED

func service(maximum_ammunition: int, maximum_endurance: float) -> void:
	ammunition = maximum_ammunition
	endurance_seconds = maximum_endurance
	damage_state.shields = damage_state.definition.max_shields
	damage_state.armor = minf(damage_state.definition.max_armor, damage_state.armor + damage_state.definition.max_armor * 0.35)

func command_move(position_value: Vector3) -> void:
	desired_position = position_value
	assigned_target = null

func command_attack(target_ship: CombatShip) -> void:
	assigned_target = target_ship

func _physics_process(delta: float) -> void:
	if not deployed or is_destroyed:
		return
	damage_state.tick(delta)
	weapon_cooldown = maxf(0.0, weapon_cooldown - delta)
	endurance_seconds = maxf(0.0, endurance_seconds - delta)
	if is_instance_valid(assigned_target) and not assigned_target.is_destroyed:
		desired_position = assigned_target.global_position
		if global_position.distance_to(assigned_target.global_position) <= _preferred_weapon_range():
			_try_fire_craft_weapon()
	_move_fighter(delta)
	_enforce_battlespace_bounds()

func _move_fighter(delta: float) -> void:
	var offset := desired_position - global_position
	if offset.length_squared() < 25.0:
		velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * delta)
	else:
		var desired_velocity := offset.normalized() * definition.maximum_speed_mps
		velocity = velocity.move_toward(desired_velocity, definition.acceleration_mps2 * delta)
		var forward := velocity.normalized()
		if forward.length_squared() > 0.1:
			look_at(global_position + forward, Vector3.UP, true)
	move_and_slide()

func _try_fire_craft_weapon() -> void:
	if ammunition <= 0 or weapon_cooldown > 0.0 or definition.weapons.is_empty():
		return
	var weapon := definition.weapons[0]
	spawn_projectile(weapon, global_position, global_position.direction_to(assigned_target.global_position), assigned_target if weapon.tracks_target else null)
	ammunition -= 1
	weapon_cooldown = weapon.cooldown_seconds
