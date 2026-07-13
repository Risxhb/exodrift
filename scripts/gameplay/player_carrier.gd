class_name PlayerCarrier
extends CombatShip

signal bay_state_changed(status: String)
signal throttle_changed(normalized_throttle: float)
signal navigation_commanded(direction: Vector3, full_cruise: bool)
signal flak_screen_changed(active: bool, range_m: float)

var control_enabled: bool = true
var mouse_sensitivity: float = 0.0022
var look_yaw: float = 0.0
var look_pitch: float = -0.08
var aim_direction: Vector3 = Vector3.FORWARD
var flak_weapon: WeaponDefinition
var missile_weapon: WeaponDefinition
var nuclear_weapon: WeaponDefinition
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
var flak_aim_screen_position: Vector2 = Vector2.ZERO
var flak_aim_uses_pointer: bool = false
var flak_mounts: Array[Node3D] = []
var bay_closure: float = 0.0
var bay_target_closure: float = 0.0
var bay_transition_seconds: float = 2.2
var bay_assemblies: Array[Dictionary] = []
var flak_sequence: int = 0
var flak_burst_count: int = 7
var missile_salvo_count: int = 4
var throttle_setting: float = 0.0
var throttle_change_rate: float = 0.55
var commanded_heading: Vector3 = Vector3.FORWARD
var has_commanded_heading: bool = false
var flak_screen_active: bool = false
var flak_placement_active: bool = false
var flak_placement_valid: bool = false
var flak_screen_range_m: float = 1600.0
var flak_screen_min_range_m: float = 800.0
var flak_screen_max_range_m: float = 2400.0
var flak_screen_range_step_m: float = 200.0
var flak_airburst_radius_m: float = 150.0
var flak_screen_local_offset: Vector3 = Vector3(0.0, 0.0, -1600.0)
var flak_preview_local_offset: Vector3 = Vector3(0.0, 0.0, -1600.0)
var flak_screen_indicator: Node3D
var flak_screen_ring: MeshInstance3D
var flak_screen_label: Label3D
var flak_indicator_preview_material: StandardMaterial3D
var flak_indicator_confirmed_material: StandardMaterial3D
var flak_indicator_invalid_material: StandardMaterial3D
var flak_camera_blend: float = 0.0
var nuclear_available: bool = true
var nuclear_arming_distance_m: float = 1200.0
var nuclear_blast_radius_m: float = 650.0
var engine_trails: Array[MeshInstance3D] = []
var pending_flak_shots: Array[Dictionary] = []
var flak_round_interval_seconds: float = 0.035

func configure(ship_definition: ShipDefinition, entity_id: StringName, faction: StringName, color: Color) -> void:
	super.configure(ship_definition, entity_id, faction, color)
	commanded_heading = -global_transform.basis.z.normalized()
	for weapon in definition.weapons:
		if weapon.role == "flak":
			flak_weapon = weapon
		elif weapon.role == "missile":
			missile_weapon = weapon
		elif weapon.role == "nuclear":
			nuclear_weapon = weapon

func _build_visual() -> void:
	var dimensions := definition.dimensions_m
	_add_hull_block(Vector3(0.0, 0.0, 5.0), Vector3(dimensions.x * 0.62, dimensions.y * 0.74, dimensions.z * 0.76), visual_color.darkened(0.08), "ArmoredCore")
	_add_hull_block(Vector3(0.0, dimensions.y * 0.42, 4.0), Vector3(dimensions.x * 0.34, dimensions.y * 0.22, dimensions.z * 0.64), visual_color.lightened(0.06), "DorsalSpine")
	_add_hull_block(Vector3(0.0, dimensions.y * 0.68, 13.0), Vector3(15.0, 9.0, 30.0), visual_color.lightened(0.16), "CommandIsland")
	_add_hull_block(Vector3(0.0, -dimensions.y * 0.46, 12.0), Vector3(dimensions.x * 0.32, dimensions.y * 0.18, dimensions.z * 0.5), visual_color.darkened(0.28), "KeelArmor")
	_add_hull_block(Vector3(0.0, 0.0, dimensions.z * 0.47), Vector3(31.0, 15.0, 20.0), visual_color.darkened(0.2), "EngineCitadel")
	_add_armored_bow(dimensions)
	_add_engine_banks(dimensions)
	_add_missile_cells()
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
			flak_mounts.append(turret)
			var barrel := _mesh_block(Vector3(2.0, 1.2, 8.0), Color(0.12, 0.18, 0.23))
			barrel.position = Vector3(0.0, 2.0, -4.0)
			turret.add_child(barrel)
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
	_build_flak_screen_indicator()

func _add_hull_block(position_value: Vector3, size_value: Vector3, color: Color, node_name: String = "HullModule") -> MeshInstance3D:
	var block := MeshInstance3D.new()
	block.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size_value
	block.mesh = mesh
	block.position = position_value
	block.material_override = _make_material(color)
	add_child(block)
	return block

func _mesh_block(size_value: Vector3, color: Color, emission_energy: float = 0.0) -> MeshInstance3D:
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	block.mesh = mesh
	block.material_override = _make_material(color, emission_energy)
	return block

func _add_armored_bow(dimensions: Vector3) -> void:
	var bow := MeshInstance3D.new()
	bow.name = "TaperedArmoredBow"
	var mesh := PrismMesh.new()
	mesh.size = Vector3(dimensions.x * 0.58, dimensions.y * 0.7, dimensions.z * 0.27)
	bow.mesh = mesh
	bow.position.z = -dimensions.z * 0.47
	bow.rotation.y = PI
	bow.material_override = _make_material(visual_color.lightened(0.04), 0.02)
	add_child(bow)

func _add_engine_banks(dimensions: Vector3) -> void:
	for side in [-1.0, 1.0]:
		for height in [-5.0, 5.0]:
			var housing := MeshInstance3D.new()
			housing.name = "EngineHousing"
			var housing_mesh := CylinderMesh.new()
			housing_mesh.top_radius = 4.2
			housing_mesh.bottom_radius = 5.0
			housing_mesh.height = 9.5
			housing_mesh.radial_segments = 16
			housing.mesh = housing_mesh
			housing.rotation_degrees.x = 90.0
			housing.position = Vector3(side * 13.0, height, dimensions.z * 0.55)
			housing.material_override = _make_material(Color(0.055, 0.085, 0.11))
			add_child(housing)
			var engine := MeshInstance3D.new()
			engine.name = "EngineGlow"
			var mesh := CylinderMesh.new()
			mesh.top_radius = 2.1
			mesh.bottom_radius = 2.8
			mesh.height = 8.2
			mesh.radial_segments = 16
			engine.mesh = mesh
			engine.rotation_degrees.x = 90.0
			engine.position = Vector3(side * 13.0, height, dimensions.z * 0.575)
			engine.material_override = _make_material(Color(0.035, 0.34, 0.68), 2.15)
			add_child(engine)
			var trail := MeshInstance3D.new()
			trail.name = "CarrierEngineTrail"
			var trail_mesh := PrismMesh.new()
			trail_mesh.size = Vector3(1.7, 1.7, 22.0)
			trail.mesh = trail_mesh
			trail.position = Vector3(side * 13.0, height, dimensions.z * 0.73)
			trail.rotation.y = PI
			trail.material_override = _make_material(Color(0.05, 0.5, 1.0, 0.28), 2.9)
			trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(trail)
			engine_trails.append(trail)

func _build_flak_screen_indicator() -> void:
	flak_screen_indicator = Node3D.new()
	flak_screen_indicator.name = "FlakScreenIndicator"
	flak_screen_indicator.top_level = true
	flak_screen_indicator.visible = false
	add_child(flak_screen_indicator)
	flak_screen_ring = MeshInstance3D.new()
	flak_screen_ring.name = "AirburstRadius"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = flak_airburst_radius_m - 4.0
	ring_mesh.outer_radius = flak_airburst_radius_m
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	flak_screen_ring.mesh = ring_mesh
	flak_screen_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flak_screen_indicator.add_child(flak_screen_ring)
	flak_indicator_preview_material = _indicator_material(Color(0.95, 0.56, 0.12, 0.78))
	flak_indicator_confirmed_material = _indicator_material(Color(0.12, 0.82, 1.0, 0.55))
	flak_indicator_invalid_material = _indicator_material(Color(1.0, 0.15, 0.08, 0.86))
	flak_screen_label = Label3D.new()
	flak_screen_label.name = "FuseReadout"
	flak_screen_label.position = Vector3(0.0, 22.0, 0.0)
	flak_screen_label.font_size = 22
	flak_screen_label.outline_size = 8
	flak_screen_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flak_screen_label.no_depth_test = true
	flak_screen_indicator.add_child(flak_screen_label)
	_update_flak_indicator(false)

func _indicator_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 2.2
	return material

func _add_missile_cells() -> void:
	for side in [-1.0, 1.0]:
		for rack in 2:
			var cell := _mesh_block(Vector3(7.0, 2.0, 12.0), Color(0.14, 0.19, 0.23))
			cell.name = "MissileCell"
			cell.position = Vector3(side * (12.0 + rack * 6.0), 12.5, -20.0 + rack * 15.0)
			add_child(cell)

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
	var mouth_material := _make_material(Color(0.12, 0.82, 1.0), 3.6)
	if deck_marking_texture == null:
		deck_marking_texture = load("res://assets/textures/deck_markings.svg") as Texture2D
	mouth_material.albedo_texture = deck_marking_texture
	mouth_material.emission_texture = deck_marking_texture
	mouth_material.uv1_scale = Vector3(1.0, 5.0, 1.0)
	mouth.material_override = mouth_material
	assembly.add_child(mouth)
	var gallery_roof := _mesh_block(Vector3(15.0, 2.0, 68.0), visual_color.lightened(0.06))
	gallery_roof.name = "GalleryArmor"
	gallery_roof.position.y = 5.5
	assembly.add_child(gallery_roof)
	var rail_lights: Array[MeshInstance3D] = []
	for rail_index in 8:
		var rail := _mesh_block(Vector3(1.2, 0.65, 4.5), Color(0.12, 0.9, 1.0), 4.0)
		rail.name = "ApproachLight"
		rail.position = Vector3(side * 8.8, -2.3, -28.0 + rail_index * 8.0)
		assembly.add_child(rail)
		rail_lights.append(rail)
	var door_a := _add_bay_door(assembly, side, -31.0)
	var door_b := _add_bay_door(assembly, side, 31.0)
	var marker := Marker3D.new()
	marker.name = bay_name
	marker.position = Vector3(side * 14.0, 0.0, -4.0)
	assembly.add_child(marker)
	bay_assemblies.append({"node": assembly, "side": side, "mouth": mouth, "door_a": door_a, "door_b": door_b, "lights": rail_lights})
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
	_process_flak_salvo_queue(delta)
	_update_bay_retraction(delta)
	if control_enabled:
		_process_player_flight(delta)
	elif autopilot_active:
		_process_autopilot(delta)
	else:
		move_and_slide()
	_enforce_battlespace_bounds()
	_update_camera()
	_update_engine_trails()
	_process_flak_screen()
	_process_point_defense()

func _process_player_flight(delta: float) -> void:
	_process_throttle_input(delta)
	if has_commanded_heading:
		_steer_toward(commanded_heading, delta)
	var desired := -global_transform.basis.z.normalized() * definition.maximum_speed_mps * throttle_setting
	if Input.is_action_pressed("boost"):
		desired *= 1.6
	velocity = velocity.move_toward(desired, definition.acceleration_mps2 * delta)
	move_and_slide()

func _process_throttle_input(delta: float) -> void:
	var throttle_axis := Input.get_axis("decelerate", "accelerate")
	if not is_zero_approx(throttle_axis):
		set_throttle(throttle_setting + throttle_axis * throttle_change_rate * delta)
	if Input.is_action_pressed("brake"):
		set_throttle(0.0)

func _steer_toward(direction_value: Vector3, delta: float) -> void:
	var direction := direction_value.normalized()
	if direction.length_squared() < 0.5:
		return
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.985:
		up = global_transform.basis.x.normalized()
	var target_basis := Basis.looking_at(direction, up)
	var angular_error := global_transform.basis.get_rotation_quaternion().angle_to(target_basis.get_rotation_quaternion())
	var turn_alpha := clampf(definition.rotation_speed_radians * delta / maxf(0.12, angular_error), 0.0, 0.18)
	global_transform.basis = global_transform.basis.slerp(target_basis, turn_alpha).orthonormalized()
	look_pitch = rotation.x
	look_yaw = rotation.y

func _process_autopilot(delta: float) -> void:
	var distance := global_position.distance_to(autopilot_destination)
	if distance < collision_radius_m:
		autopilot_active = false
		velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * delta)
		move_and_slide()
		return
	var desired := global_position.direction_to(autopilot_destination) * definition.maximum_speed_mps
	velocity = velocity.move_toward(desired, definition.acceleration_mps2 * delta)
	if desired.length_squared() > 1.0:
		_steer_toward(desired, delta)
	move_and_slide()

func set_throttle(value: float) -> void:
	var next_throttle := clampf(value, 0.0, 1.0)
	if is_equal_approx(next_throttle, throttle_setting):
		return
	throttle_setting = next_throttle
	throttle_changed.emit(throttle_setting)

func throttle_percent() -> int:
	return int(round(throttle_setting * 100.0))

func control_state() -> Dictionary:
	return {
		"throttle": throttle_setting,
		"throttle_percent": throttle_percent(),
		"heading": commanded_heading,
		"heading_commanded": has_commanded_heading,
	}

func command_heading(direction_value: Vector3, full_cruise: bool = false) -> bool:
	if direction_value.length_squared() < 0.25:
		return false
	commanded_heading = direction_value.normalized()
	has_commanded_heading = true
	autopilot_active = false
	if full_cruise:
		set_throttle(1.0)
	elif throttle_setting < 0.05:
		set_throttle(0.35)
	navigation_commanded.emit(commanded_heading, full_cruise)
	return true

func command_flight_from_screen(screen_position: Vector2, full_cruise: bool = false, only_empty_space: bool = true) -> bool:
	if chase_camera == null or not chase_camera.current:
		return false
	var ray_origin := chase_camera.project_ray_origin(screen_position)
	var ray_direction := chase_camera.project_ray_normal(screen_position).normalized()
	if only_empty_space:
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * chase_camera.far)
		query.exclude = [get_rid()]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false
	return command_heading(ray_direction, full_cruise)

func apply_mouse_look(relative_motion: Vector2) -> void:
	if not control_enabled:
		return
	apply_camera_orbit(relative_motion)

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
		flak_aim_uses_pointer = false
		return
	flak_aim_screen_position = cursor_position
	flak_aim_uses_pointer = true
	web_cursor_steer = Vector2.ZERO
	if flak_placement_active:
		update_flak_placement_from_screen(cursor_position)

func _update_camera() -> void:
	if chase_camera == null:
		return
	chase_distance_m = lerpf(chase_distance_m, chase_target_distance_m, 0.18)
	var height := lerpf(34.0, 76.0, inverse_lerp(70.0, 260.0, chase_distance_m))
	var camera_offset := Vector3(0.0, height, chase_distance_m)
	camera_offset = camera_offset.rotated(Vector3.RIGHT, camera_orbit_pitch)
	camera_offset = camera_offset.rotated(Vector3.UP, camera_orbit_yaw)
	flak_camera_blend = lerpf(flak_camera_blend, 1.0 if flak_placement_active else 0.0, 0.18)
	var placement_camera_offset := flak_preview_local_offset * 0.72 + Vector3(0.0, 52.0, 180.0)
	chase_camera.position = camera_offset.lerp(placement_camera_offset, flak_camera_blend)
	var carrier_focus := global_position + global_transform.basis.y * 3.0
	var placement_focus := global_transform * flak_preview_local_offset
	chase_camera.look_at(carrier_focus.lerp(placement_focus, flak_camera_blend), Vector3.UP)
	var viewport_size := get_viewport().get_visible_rect().size
	var director_position := flak_aim_screen_position if flak_aim_uses_pointer else viewport_size * 0.5
	director_position.x = clampf(director_position.x, 0.0, viewport_size.x)
	director_position.y = clampf(director_position.y, 0.0, viewport_size.y)
	aim_direction = chase_camera.project_ray_normal(director_position).normalized()
	_update_flak_mounts()

func _update_flak_mounts() -> void:
	var turret_up := Vector3.FORWARD if absf(aim_direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	for mount in flak_mounts:
		if is_instance_valid(mount):
			mount.look_at(mount.global_position + aim_direction, turret_up)

func adjust_chase_zoom(wheel_steps: float) -> void:
	chase_target_distance_m = clampf(chase_target_distance_m * pow(0.86, wheel_steps), 70.0, 260.0)

func chase_zoom_percent() -> int:
	return int(round(inverse_lerp(260.0, 70.0, chase_target_distance_m) * 100.0))

func fire_flak() -> bool:
	if flak_weapon == null or flak_cooldown > 0.0:
		return false
	var target_point := flak_screen_world_position() if flak_screen_active else global_position + aim_direction * flak_screen_range_m
	var shot_distance := global_position.distance_to(target_point)
	_queue_flak_barrage(global_position.direction_to(target_point), flak_burst_count, 0.52, shot_distance, flak_airburst_radius_m)
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

func fire_nuclear(target_ship: CombatShip) -> bool:
	if nuclear_weapon == null or not nuclear_available or not is_instance_valid(target_ship):
		return false
	if global_position.distance_to(target_ship.global_position) > nuclear_weapon.range_m:
		return false
	var start := global_transform * Vector3(0.0, 5.0, -42.0)
	var torpedo := spawn_projectile(nuclear_weapon, start, start.direction_to(target_ship.global_position), target_ship)
	torpedo.configure_warhead(nuclear_arming_distance_m, nuclear_blast_radius_m, true, true)
	nuclear_available = false
	return true

func _spawn_flak_barrage(direction_value: Vector3, count: int, damage_scale: float, airburst_distance_m: float = 0.0, airburst_radius_m: float = 0.0) -> void:
	if flak_weapon == null:
		return
	for index in count:
		_spawn_flak_round(direction_value, flak_sequence + index, damage_scale, airburst_distance_m, airburst_radius_m)
	flak_sequence += count

func _queue_flak_barrage(direction_value: Vector3, count: int, damage_scale: float, airburst_distance_m: float, airburst_radius_m: float) -> void:
	if flak_weapon == null or count <= 0:
		return
	_spawn_flak_round(direction_value, flak_sequence, damage_scale, airburst_distance_m, airburst_radius_m)
	for index in range(1, count):
		pending_flak_shots.append({
			"delay": float(index) * flak_round_interval_seconds,
			"direction": direction_value.normalized(),
			"pattern": flak_sequence + index,
			"damage_scale": damage_scale,
			"airburst_distance": airburst_distance_m,
			"airburst_radius": airburst_radius_m,
		})
	flak_sequence += count

func _process_flak_salvo_queue(delta: float) -> void:
	for index in range(pending_flak_shots.size() - 1, -1, -1):
		var shot: Dictionary = pending_flak_shots[index]
		shot.delay = float(shot.delay) - delta
		if float(shot.delay) > 0.0:
			pending_flak_shots[index] = shot
			continue
		_spawn_flak_round(Vector3(shot.direction), int(shot.pattern), float(shot.damage_scale), float(shot.airburst_distance), float(shot.airburst_radius))
		pending_flak_shots.remove_at(index)

func _spawn_flak_round(direction_value: Vector3, pattern_index: int, damage_scale: float, airburst_distance_m: float, airburst_radius_m: float) -> void:
	var base_direction := direction_value.normalized()
	var yaw := (float(pattern_index % 5) - 2.0) * 0.018
	var pitch := (float((pattern_index * 3) % 5) - 2.0) * 0.014
	var yaw_direction := base_direction.rotated(Vector3.UP, yaw).normalized()
	var director_right := yaw_direction.cross(Vector3.UP).normalized()
	if director_right.length_squared() < 0.01:
		director_right = global_transform.basis.x.normalized()
	var shot_direction := yaw_direction.rotated(director_right, pitch).normalized()
	var side := -1.0 if pattern_index % 2 == 0 else 1.0
	var local_start := Vector3(side * 23.0, 11.0, -30.0 + float(pattern_index % 3) * 30.0)
	var projectile := spawn_projectile(flak_weapon, global_transform * local_start, shot_direction)
	projectile.damage *= damage_scale
	if airburst_distance_m > 0.0:
		projectile.configure_airburst(airburst_distance_m, airburst_radius_m)

func begin_flak_placement(screen_position: Vector2) -> bool:
	flak_placement_active = true
	flak_placement_valid = update_flak_placement_from_screen(screen_position)
	_update_flak_indicator(true)
	return flak_placement_valid

func update_flak_placement_from_screen(screen_position: Vector2) -> bool:
	if chase_camera == null or not chase_camera.current:
		flak_placement_valid = false
		_update_flak_indicator(true)
		return false
	var ray_direction := chase_camera.project_ray_normal(screen_position).normalized()
	var candidate := global_position + ray_direction * flak_screen_range_m
	flak_preview_local_offset = to_local(candidate)
	flak_placement_valid = absf(candidate.y) <= CombatShip.VERTICAL_BATTLESPACE_LIMIT_M
	_update_flak_indicator(true)
	return flak_placement_valid

func confirm_flak_placement() -> bool:
	if not flak_placement_active or not flak_placement_valid:
		return false
	flak_screen_local_offset = flak_preview_local_offset
	flak_screen_active = true
	flak_placement_active = false
	_update_flak_indicator(false)
	flak_screen_changed.emit(true, flak_screen_range_m)
	return true

func cancel_flak_placement() -> bool:
	if not flak_placement_active:
		return false
	flak_placement_active = false
	_update_flak_indicator(false)
	return true

func clear_flak_screen() -> void:
	flak_placement_active = false
	flak_screen_active = false
	_update_flak_indicator(false)
	flak_screen_changed.emit(false, flak_screen_range_m)

func adjust_flak_screen_range(steps: int) -> float:
	var old_range := flak_screen_range_m
	flak_screen_range_m = clampf(flak_screen_range_m + float(steps) * flak_screen_range_step_m, flak_screen_min_range_m, flak_screen_max_range_m)
	if not is_equal_approx(old_range, flak_screen_range_m):
		var local_direction := flak_preview_local_offset.normalized() if flak_placement_active else flak_screen_local_offset.normalized()
		if local_direction.length_squared() < 0.5:
			local_direction = Vector3.FORWARD
		if flak_placement_active:
			flak_preview_local_offset = local_direction * flak_screen_range_m
		elif flak_screen_active:
			flak_screen_local_offset = local_direction * flak_screen_range_m
	_update_flak_indicator(flak_placement_active)
	flak_screen_changed.emit(flak_screen_active, flak_screen_range_m)
	return flak_screen_range_m

func flak_screen_world_position() -> Vector3:
	var local_offset := flak_preview_local_offset if flak_placement_active else flak_screen_local_offset
	return global_transform * local_offset

func flak_screen_status() -> String:
	if flak_placement_active:
		return "PLACEMENT %s" % ("VALID" if flak_placement_valid else "INVALID")
	return "SCREENING" if flak_screen_active else "STANDBY"

func _process_flak_screen() -> void:
	if flak_screen_active and not flak_placement_active and flak_cooldown <= 0.0:
		fire_flak()
	_update_flak_indicator(flak_placement_active)

func _update_flak_indicator(preview: bool) -> void:
	if flak_screen_indicator == null:
		return
	flak_screen_indicator.visible = flak_screen_active or flak_placement_active
	if not flak_screen_indicator.visible:
		return
	flak_screen_indicator.global_position = flak_screen_world_position()
	var color := Color(0.95, 0.56, 0.12, 0.78) if preview else Color(0.12, 0.82, 1.0, 0.55)
	if preview and not flak_placement_valid:
		color = Color(1.0, 0.15, 0.08, 0.86)
	flak_screen_ring.material_override = flak_indicator_invalid_material if preview and not flak_placement_valid else (flak_indicator_preview_material if preview else flak_indicator_confirmed_material)
	flak_screen_label.modulate = color
	flak_screen_label.text = "%s  //  %.1f km  //  R %.0f m" % [flak_screen_status(), flak_screen_range_m / 1000.0, flak_airburst_radius_m]

func _update_engine_trails() -> void:
	var speed_ratio := clampf(velocity.length() / maxf(1.0, definition.maximum_speed_mps), 0.0, 1.6)
	for trail in engine_trails:
		if is_instance_valid(trail):
			trail.scale.z = lerpf(0.08, 1.35, speed_ratio)
			trail.transparency = lerpf(0.86, 0.18, clampf(speed_ratio, 0.0, 1.0))

func _process_point_defense() -> void:
	if point_defense_cooldown > 0.0:
		return
	var registry := _combat_registry()
	var projectiles: Array = registry.active_projectiles() if registry != null else get_tree().get_nodes_in_group("projectiles")
	for candidate in projectiles:
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
		var lights: Array = bay_data.lights
		for light in lights:
			light.visible = bay_closure < 0.9
	if are_bays_closed():
		if previous < 0.995:
			for bay_data in bay_assemblies:
				var vfx := _combat_vfx()
				if vfx != null:
					vfx.spawn_burst("bay", (bay_data.node as Node3D).global_position, 0.7)
		bay_state_changed.emit("CLOSED / JUMP SAFE")
	elif are_bays_open():
		if previous > 0.005:
			for bay_data in bay_assemblies:
				var vfx := _combat_vfx()
				if vfx != null:
					vfx.spawn_burst("bay", (bay_data.node as Node3D).global_position, 0.55)
		bay_state_changed.emit("OPEN / FLIGHT OPS")
