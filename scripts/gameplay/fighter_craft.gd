class_name FighterCraft
extends CombatShip

var deployed: bool = false
var desired_position: Vector3
var assigned_target: CombatShip
var ammunition: int = 0
var endurance_seconds: float = 0.0
var home_squadron: SidebaySquadron
var engine_trails: Array[MeshInstance3D] = []

func _build_visual() -> void:
	var identity := String(definition.ship_id)
	if definition.role == "drone":
		_build_watcher_drone()
	elif identity.begins_with("vesper_"):
		_build_vesper_lance()
	elif identity.begins_with("crucible_"):
		_build_crucible_talon()
	else:
		_build_interceptor(identity.begins_with("acheron_"))
	_add_engine_trails(identity)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = definition.dimensions_m
	collision.shape = shape
	add_child(collision)

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
	needle.material_override = _make_material(visual_color, 0.1)
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
	body.material_override = _make_material(visual_color, 0.1, "res://assets/textures/vanta_hull.svg")
	add_child(body)
	var delta_wing := _add_visual_block("CrucibleDeltaWing", Vector3(0.0, 0.0, definition.dimensions_m.z * 0.16), Vector3(definition.dimensions_m.x, definition.dimensions_m.y * 0.16, definition.dimensions_m.z * 0.56), visual_color.darkened(0.08), 0.0, "res://assets/textures/vanta_hull.svg")
	delta_wing.rotation_degrees.z = 5.0
	for side in [-1.0, 1.0]:
		var fin := _add_visual_block("CrucibleTalonFin", Vector3(side * definition.dimensions_m.x * 0.28, definition.dimensions_m.y * 0.3, definition.dimensions_m.z * 0.22), Vector3(definition.dimensions_m.x * 0.08, definition.dimensions_m.y * 0.72, definition.dimensions_m.z * 0.32), visual_color.lightened(0.06), 0.0, "res://assets/textures/vanta_hull.svg")
		fin.rotation_degrees.z = side * 18.0
	_add_visual_block("CrucibleDrive", Vector3(0.0, 0.0, definition.dimensions_m.z * 0.5), Vector3(definition.dimensions_m.x * 0.24, definition.dimensions_m.y * 0.22, 1.0), Color(0.68, 0.18, 1.0), 3.8)

func _add_engine_trails(identity: String) -> void:
	var trail_color := Color(0.12, 0.72, 1.0, 0.52)
	if identity.begins_with("vesper_"):
		trail_color = Color(0.95, 0.18, 1.0, 0.5)
	elif identity.begins_with("crucible_"):
		trail_color = Color(0.65, 0.16, 1.0, 0.52)
	elif team == &"hostile":
		trail_color = Color(1.0, 0.28, 0.04, 0.48)
	for side in ([-1.0, 1.0] if definition.role == "drone" else [0.0]):
		var trail := MeshInstance3D.new()
		trail.name = "EngineTrail"
		var trail_mesh := PrismMesh.new()
		trail_mesh.size = Vector3(definition.dimensions_m.x * 0.12, definition.dimensions_m.y * 0.12, definition.dimensions_m.z * 0.8)
		trail.mesh = trail_mesh
		trail.position = Vector3(side * definition.dimensions_m.x * 0.28, 0.0, definition.dimensions_m.z * 0.88)
		trail.rotation.y = PI
		var material := _make_material(trail_color, 2.2)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail.material_override = material
		add_child(trail)
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
	_update_engine_trails()
	if is_instance_valid(assigned_target) and not assigned_target.is_destroyed:
		desired_position = assigned_target.global_position
		if global_position.distance_to(assigned_target.global_position) <= _preferred_weapon_range():
			_try_fire_craft_weapon()
	_move_fighter(delta)
	_enforce_battlespace_bounds()

func _update_engine_trails() -> void:
	var speed_ratio := clampf(velocity.length() / maxf(1.0, definition.maximum_speed_mps), 0.15, 1.0)
	for trail in engine_trails:
		trail.scale.z = lerpf(0.25, 1.35, speed_ratio)
		trail.transparency = lerpf(0.55, 0.08, speed_ratio)

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
