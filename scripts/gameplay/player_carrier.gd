class_name PlayerCarrier
extends CombatShip

signal bay_state_changed(status: String)

var control_enabled: bool = true
var mouse_sensitivity: float = 0.0022
var look_yaw: float = 0.0
var look_pitch: float = -0.08
var aim_direction: Vector3 = Vector3.FORWARD
var flak_weapon: WeaponDefinition
var missile_weapon: WeaponDefinition
var flak_cooldown: float = 0.0
var missile_cooldown: float = 0.0
var point_defense_cooldown: float = 0.0
var autopilot_destination: Vector3
var autopilot_active: bool = false
var chase_camera: Camera3D
var port_bay_marker: Marker3D
var starboard_bay_marker: Marker3D
var web_cursor_steer: Vector2 = Vector2.ZERO
var chase_distance_m: float = 125.0
var chase_target_distance_m: float = 125.0
var camera_orbit_yaw: float = 0.0
var camera_orbit_pitch: float = 0.0
var camera_orbiting: bool = false
var bay_closure: float = 0.0
var bay_target_closure: float = 0.0
var bay_transition_seconds: float = 2.2
var bay_assemblies: Array[Dictionary] = []
var flak_sequence: int = 0
var flak_burst_count: int = 7
var missile_salvo_count: int = 4

func configure(ship_definition: ShipDefinition, entity_id: StringName, faction: StringName, color: Color) -> void:
	super.configure(ship_definition, entity_id, faction, color)
	for weapon in definition.weapons:
		if weapon.role == "flak":
			flak_weapon = weapon
		elif weapon.role == "missile":
			missile_weapon = weapon

func _build_visual() -> void:
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = definition.dimensions_m
	hull.mesh = hull_mesh
	hull.material_override = _make_material(visual_color, 0.03)
	add_child(hull)
	_add_hull_block(Vector3(0.0, definition.dimensions_m.y * 0.6, 8.0), Vector3(15.0, 12.0, 30.0), visual_color.lightened(0.12))
	_add_hull_block(Vector3(0.0, 0.0, definition.dimensions_m.z * 0.48), Vector3(27.0, 14.0, 25.0), visual_color.darkened(0.15))
	_add_bay(-1.0, "PortBay")
	_add_bay(1.0, "StarboardBay")
	for side in [-1.0, 1.0]:
		for z in [-30.0, 0.0, 30.0]:
			var turret := MeshInstance3D.new()
			var turret_mesh := CylinderMesh.new()
			turret_mesh.top_radius = 2.0
			turret_mesh.bottom_radius = 3.2
			turret_mesh.height = 3.5
			turret.mesh = turret_mesh
			turret.position = Vector3(side * 23.0, 11.0, z)
			turret.material_override = _make_material(Color(0.24, 0.3, 0.35))
			add_child(turret)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = definition.dimensions_m
	collision.shape = shape
	add_child(collision)
	chase_camera = Camera3D.new()
	chase_camera.name = "ChaseCamera"
	chase_camera.position = Vector3(0.0, 48.0, 125.0)
	chase_camera.fov = 72.0
	chase_camera.near = 1.0
	chase_camera.far = 30000.0
	add_child(chase_camera)

func _add_hull_block(position_value: Vector3, size_value: Vector3, color: Color) -> void:
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	block.mesh = mesh
	block.position = position_value
	block.material_override = _make_material(color)
	add_child(block)

func _add_bay(side: float, bay_name: String) -> void:
	var assembly := Node3D.new()
	assembly.name = "%sAssembly" % bay_name
	assembly.position = Vector3(side * 29.0, -1.0, 4.0)
	add_child(assembly)
	var bay := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(17.0, 9.0, 72.0)
	bay.mesh = mesh
	bay.material_override = _make_material(visual_color.darkened(0.2))
	assembly.add_child(bay)
	var mouth := MeshInstance3D.new()
	var mouth_mesh := BoxMesh.new()
	mouth_mesh.size = Vector3(2.0, 6.0, 58.0)
	mouth.mesh = mouth_mesh
	mouth.position = Vector3(side * 9.0, 0.0, -4.0)
	mouth.material_override = _make_material(Color(1.0, 0.34, 0.05), 2.5)
	assembly.add_child(mouth)
	var door_a := _add_bay_door(assembly, side, -31.0)
	var door_b := _add_bay_door(assembly, side, 31.0)
	var marker := Marker3D.new()
	marker.name = bay_name
	marker.position = Vector3(side * 14.0, 0.0, -4.0)
	assembly.add_child(marker)
	bay_assemblies.append({"node": assembly, "side": side, "mouth": mouth, "door_a": door_a, "door_b": door_b})
	if side < 0.0:
		port_bay_marker = marker
	else:
		starboard_bay_marker = marker

func _add_bay_door(parent: Node3D, side: float, z_position: float) -> MeshInstance3D:
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(2.4, 7.5, 28.0)
	door.mesh = door_mesh
	door.position = Vector3(side * 9.6, 0.0, z_position)
	door.material_override = _make_material(visual_color.lightened(0.05), 0.04)
	parent.add_child(door)
	return door

func _physics_process(delta: float) -> void:
	if is_destroyed:
		return
	damage_state.tick(delta)
	flak_cooldown = maxf(0.0, flak_cooldown - delta)
	missile_cooldown = maxf(0.0, missile_cooldown - delta)
	point_defense_cooldown = maxf(0.0, point_defense_cooldown - delta)
	_update_bay_retraction(delta)
	if control_enabled:
		_process_player_flight(delta)
	elif autopilot_active:
		_process_autopilot(delta)
	else:
		move_and_slide()
	_enforce_battlespace_bounds()
	_update_camera()
	_process_point_defense()

func _process_player_flight(delta: float) -> void:
	if OS.has_feature("web"):
		look_yaw -= web_cursor_steer.x * 1.15 * delta
		look_pitch = clampf(look_pitch - web_cursor_steer.y * 0.85 * delta, -0.75, 0.75)
	rotation = Vector3(look_pitch, look_yaw, 0.0)
	var input := Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"),
		-Input.get_axis("move_backward", "move_forward")
	)
	if input.length_squared() > 1.0:
		input = input.normalized()
	var desired := global_transform.basis * input * definition.maximum_speed_mps
	if Input.is_action_pressed("boost"):
		desired *= 1.6
	if input.length_squared() > 0.01:
		velocity = velocity.move_toward(desired, definition.acceleration_mps2 * delta)
	if Input.is_action_pressed("brake"):
		velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * 2.5 * delta)
	move_and_slide()

func _process_autopilot(delta: float) -> void:
	var distance := global_position.distance_to(autopilot_destination)
	if distance < collision_radius_m:
		autopilot_active = false
		velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * delta)
		move_and_slide()
		return
	var desired := global_position.direction_to(autopilot_destination) * definition.maximum_speed_mps
	velocity = velocity.move_toward(desired, definition.acceleration_mps2 * delta)
	if velocity.length_squared() > 1.0:
		look_yaw = lerp_angle(look_yaw, atan2(-velocity.x, -velocity.z), clampf(definition.rotation_speed_radians * delta, 0.0, 1.0))
		look_pitch = lerpf(look_pitch, -asin(clampf(velocity.normalized().y, -1.0, 1.0)), clampf(delta, 0.0, 1.0))
		rotation = Vector3(look_pitch, look_yaw, 0.0)
	move_and_slide()

func apply_mouse_look(relative_motion: Vector2) -> void:
	if not control_enabled:
		return
	look_yaw -= relative_motion.x * mouse_sensitivity
	look_pitch = clampf(look_pitch - relative_motion.y * mouse_sensitivity, -0.75, 0.75)

func set_camera_orbiting(enabled: bool) -> void:
	camera_orbiting = enabled

func apply_camera_orbit(relative_motion: Vector2) -> void:
	camera_orbit_yaw = wrapf(camera_orbit_yaw - relative_motion.x * 0.004, -PI, PI)
	camera_orbit_pitch = clampf(camera_orbit_pitch - relative_motion.y * 0.0035, -0.85, 0.65)

func reset_camera_orbit() -> void:
	camera_orbit_yaw = 0.0
	camera_orbit_pitch = 0.0

func set_web_cursor_steering(cursor_position: Vector2, viewport_size: Vector2) -> void:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		web_cursor_steer = Vector2.ZERO
		return
	var normalized := Vector2(cursor_position.x / viewport_size.x, cursor_position.y / viewport_size.y) * 2.0 - Vector2.ONE
	var deadzone := 0.12
	web_cursor_steer.x = signf(normalized.x) * maxf(0.0, absf(normalized.x) - deadzone) / (1.0 - deadzone)
	web_cursor_steer.y = signf(normalized.y) * maxf(0.0, absf(normalized.y) - deadzone) / (1.0 - deadzone)
	web_cursor_steer = web_cursor_steer.limit_length(1.0)

func _update_camera() -> void:
	if chase_camera == null:
		return
	chase_distance_m = lerpf(chase_distance_m, chase_target_distance_m, 0.18)
	var height := lerpf(34.0, 76.0, inverse_lerp(70.0, 260.0, chase_distance_m))
	var camera_offset := Vector3(0.0, height, chase_distance_m)
	camera_offset = camera_offset.rotated(Vector3.RIGHT, camera_orbit_pitch)
	camera_offset = camera_offset.rotated(Vector3.UP, camera_orbit_yaw)
	chase_camera.position = camera_offset
	chase_camera.look_at(global_position + global_transform.basis.y * 3.0, Vector3.UP)
	aim_direction = -global_transform.basis.z.normalized()

func adjust_chase_zoom(wheel_steps: float) -> void:
	chase_target_distance_m = clampf(chase_target_distance_m * pow(0.86, wheel_steps), 70.0, 260.0)

func chase_zoom_percent() -> int:
	return int(round(inverse_lerp(260.0, 70.0, chase_target_distance_m) * 100.0))

func fire_flak() -> bool:
	if flak_weapon == null or flak_cooldown > 0.0:
		return false
	_spawn_flak_barrage(aim_direction, flak_burst_count, 0.52)
	flak_cooldown = flak_weapon.cooldown_seconds
	return true

func fire_missile(target_ship: CombatShip) -> bool:
	if missile_weapon == null or missile_cooldown > 0.0 or not is_instance_valid(target_ship):
		return false
	if global_position.distance_to(target_ship.global_position) > missile_weapon.range_m:
		return false
	for index in missile_salvo_count:
		var side := -1.0 if index % 2 == 0 else 1.0
		var rack := index / 2
		var local_offset := Vector3(side * (14.0 + rack * 4.0), 11.0 + rack * 5.0, -32.0 + rack * 8.0)
		var start := global_transform * local_offset
		var missile := spawn_projectile(missile_weapon, start, start.direction_to(target_ship.global_position), target_ship)
		missile.direction = missile.direction.rotated(global_transform.basis.z.normalized(), side * 0.018)
	missile_cooldown = missile_weapon.cooldown_seconds
	return true

func _spawn_flak_barrage(direction_value: Vector3, count: int, damage_scale: float) -> void:
	if flak_weapon == null:
		return
	var base_direction := direction_value.normalized()
	for index in count:
		var pattern_index := flak_sequence + index
		var yaw := (float(pattern_index % 5) - 2.0) * 0.018
		var pitch := (float((pattern_index * 3) % 5) - 2.0) * 0.014
		var shot_direction := base_direction.rotated(Vector3.UP, yaw).rotated(global_transform.basis.x.normalized(), pitch).normalized()
		var side := -1.0 if pattern_index % 2 == 0 else 1.0
		var local_start := Vector3(side * 23.0, 11.0, -30.0 + float(pattern_index % 3) * 30.0)
		var projectile := spawn_projectile(flak_weapon, global_transform * local_start, shot_direction)
		projectile.damage *= damage_scale
	flak_sequence += count

func _process_point_defense() -> void:
	if point_defense_cooldown > 0.0:
		return
	for candidate in get_tree().get_nodes_in_group("projectiles"):
		if candidate is SidebayProjectile and candidate.team != team and candidate.can_be_intercepted:
			if global_position.distance_to(candidate.global_position) <= 900.0:
				_spawn_flak_barrage(global_position.direction_to(candidate.global_position), 3, 0.28)
				candidate.intercept()
				point_defense_cooldown = 0.28
				return

func set_autopilot(destination: Vector3) -> void:
	autopilot_destination = destination
	autopilot_active = true

func get_bay_marker(side: StringName) -> Marker3D:
	return port_bay_marker if side == &"port" else starboard_bay_marker

func request_bays_closed() -> void:
	if is_equal_approx(bay_target_closure, 1.0):
		return
	bay_target_closure = 1.0
	bay_state_changed.emit("CLOSING")

func request_bays_open() -> void:
	if is_equal_approx(bay_target_closure, 0.0):
		return
	bay_target_closure = 0.0
	bay_state_changed.emit("OPENING")

func are_bays_closed() -> bool:
	return bay_closure >= 0.995 and bay_target_closure >= 0.995

func are_bays_open() -> bool:
	return bay_closure <= 0.005 and bay_target_closure <= 0.005

func bay_status() -> String:
	if are_bays_closed():
		return "CLOSED / JUMP SAFE"
	if are_bays_open():
		return "OPEN / FLIGHT OPS"
	return "CLOSING" if bay_target_closure > bay_closure else "OPENING"

func _update_bay_retraction(delta: float) -> void:
	var previous := bay_closure
	bay_closure = move_toward(bay_closure, bay_target_closure, delta / bay_transition_seconds)
	if is_equal_approx(previous, bay_closure):
		return
	for bay_data in bay_assemblies:
		var assembly: Node3D = bay_data.node
		var side := float(bay_data.side)
		assembly.position.x = lerpf(side * 29.0, side * 20.0, bay_closure)
		var door_a: MeshInstance3D = bay_data.door_a
		var door_b: MeshInstance3D = bay_data.door_b
		door_a.position.z = lerpf(-31.0, -15.0, bay_closure)
		door_b.position.z = lerpf(31.0, 15.0, bay_closure)
		var mouth: MeshInstance3D = bay_data.mouth
		mouth.visible = bay_closure < 0.94
	if are_bays_closed():
		bay_state_changed.emit("CLOSED / JUMP SAFE")
	elif are_bays_open():
		bay_state_changed.emit("OPEN / FLIGHT OPS")
