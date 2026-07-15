class_name PlayerCarrier
extends CombatShip

signal bay_state_changed(status: String)
signal throttle_changed(normalized_throttle: float)
signal navigation_commanded(direction: Vector3, full_cruise: bool)
signal carrier_operations_message(message: String)

enum TargetNavigationMode {
	NONE,
	APPROACH,
	ORBIT,
	KEEP_DISTANCE,
}

const CHASE_DEFAULT_DISTANCE_M := 360.0
const CHASE_MIN_DISTANCE_M := 180.0
const CHASE_MAX_DISTANCE_M := 1200.0

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
var port_bay_markers: Array[Marker3D] = []
var starboard_bay_markers: Array[Marker3D] = []
var scout_bay_marker: Marker3D
var web_cursor_steer: Vector2 = Vector2.ZERO
var chase_distance_m: float = CHASE_DEFAULT_DISTANCE_M
var chase_target_distance_m: float = CHASE_DEFAULT_DISTANCE_M
var camera_orbit_yaw: float = 0.0
var camera_orbit_pitch: float = 0.0
var camera_orbiting: bool = false
var flak_aim_screen_position: Vector2 = Vector2.ZERO
var flak_aim_uses_pointer: bool = false
var flak_mounts: Array[Node3D] = []
var bay_closure: float = 0.0
var bay_target_closure: float = 0.0
var bay_transition_seconds: float = 2.8
var bay_assemblies: Array[Dictionary] = []
var active_flight_launches: Dictionary = {}
var active_flight_recoveries: Dictionary = {}
var flak_sequence: int = 0
var flak_burst_count: int = 7
var missile_salvo_count: int = 4
var throttle_setting: float = 0.0
var throttle_change_rate: float = 0.55
var commanded_heading: Vector3 = Vector3.FORWARD
var has_commanded_heading: bool = false
var flak_airburst_radius_m: float = 250.0
var flak_capital_damage_multiplier: float = 0.25
var flak_mount_direction: Vector3 = Vector3.FORWARD
var flak_mount_lock_seconds: float = 0.0
var nuclear_available: bool = true
var nuclear_arming_distance_m: float = 1200.0
var nuclear_blast_radius_m: float = 650.0
var engine_trails: Array[Dictionary] = []
var pending_flak_shots: Array[Dictionary] = []
var flak_round_interval_seconds: float = 0.035
var target_navigation_mode: TargetNavigationMode = TargetNavigationMode.NONE
var target_navigation_target: CombatShip
var target_navigation_distance_m: float = 1200.0
var orbit_clockwise: bool = true
var carrier_operations: CarrierOperationsState
var last_missile_salvo_count: int = 0
var point_defense_target: SidebayProjectile
var point_defense_last_tti: float = INF

func configure(ship_definition: ShipDefinition, entity_id: StringName, faction: StringName, color: Color) -> void:
	super.configure(ship_definition, entity_id, faction, color)
	if carrier_operations == null:
		carrier_operations = CarrierOperationsState.new()
	commanded_heading = -global_transform.basis.z.normalized()
	for weapon in definition.weapons:
		if weapon.role == "flak":
			flak_weapon = weapon
		elif weapon.role == "missile":
			missile_weapon = weapon
		elif weapon.role == "nuclear":
			nuclear_weapon = weapon
	_connect_carrier_operations_feedback()

func configure_carrier_operations(persisted_state: Dictionary, installed_modules: Dictionary = {}, department_leads: Dictionary = {}) -> void:
	carrier_operations = CarrierOperationsState.from_dictionary(persisted_state, installed_modules)
	carrier_operations.set_department_leads(department_leads)
	carrier_operations.reset_for_battle()
	_connect_carrier_operations_feedback()
	nuclear_available = int(carrier_operations.stores.get(&"nuclear_torpedoes", 0)) > 0

func _connect_carrier_operations_feedback() -> void:
	if carrier_operations == null:
		return
	if not carrier_operations.store_rejected.is_connected(_on_store_rejected):
		carrier_operations.store_rejected.connect(_on_store_rejected)

func _on_store_rejected(_store_id: StringName, message: String) -> void:
	carrier_operations_message.emit(message)

func _build_visual() -> void:
	var dimensions := definition.dimensions_m
	if _try_build_authored_visual():
		_bind_authored_carrier_sockets(dimensions)
		_add_default_collision()
		_add_chase_camera(dimensions)
		return
	_add_tapered_visual_block("ArmoredCore", Vector3(0.0, 0.0, dimensions.z * 0.03), Vector3(dimensions.x * 0.6, dimensions.y * 0.72, dimensions.z * 0.75), 0.58, 0.98, visual_color.darkened(0.12), visual_profile.hull_texture_path)
	_add_tapered_visual_block("RecessedWaist", Vector3(0.0, -dimensions.y * 0.05, dimensions.z * 0.08), Vector3(dimensions.x * 0.4, dimensions.y * 0.48, dimensions.z * 0.58), 0.66, 0.94, visual_color.darkened(0.3), visual_profile.hull_texture_path)
	_add_tapered_visual_block("DorsalSpine", Vector3(0.0, dimensions.y * 0.4, dimensions.z * 0.03), Vector3(dimensions.x * 0.32, dimensions.y * 0.22, dimensions.z * 0.72), 0.44, 0.92, visual_color.lightened(0.02), visual_profile.hull_texture_path)
	_add_tapered_visual_block("KeelArmor", Vector3(0.0, -dimensions.y * 0.46, dimensions.z * 0.08), Vector3(dimensions.x * 0.3, dimensions.y * 0.18, dimensions.z * 0.58), 0.54, 0.92, visual_color.darkened(0.3), visual_profile.hull_texture_path)
	_add_hull_block(Vector3(0.0, 0.0, dimensions.z * 0.47), Vector3(dimensions.x * 0.48, dimensions.y * 0.72, dimensions.z * 0.16), visual_color.darkened(0.24), "EngineCitadel")
	for rib_index in 11:
		var progress := float(rib_index) / 10.0
		var rib_z := lerpf(-dimensions.z * 0.3, dimensions.z * 0.32, progress)
		var rib_width := lerpf(dimensions.x * 0.46, dimensions.x * 0.56, progress)
		_add_hull_block(Vector3(0.0, dimensions.y * 0.485, rib_z), Vector3(rib_width, maxf(1.25, dimensions.y * 0.045), dimensions.z * 0.035), visual_color.lightened(0.015), "OverlappingArmorRib%02d" % rib_index)
	_add_armored_bow(dimensions)
	_add_command_island(dimensions)
	_add_flight_deck_details(dimensions)
	_add_scout_drone_hive(dimensions)
	_add_engine_banks(dimensions)
	_add_missile_cells(dimensions)
	var lane_spacing := dimensions.z * 0.265
	for lane_index in 3:
		var lane_z := (float(lane_index) - 1.0) * lane_spacing
		_add_bay(-1.0, "PortBay%d" % (lane_index + 1), lane_z, lane_index, dimensions)
		_add_bay(1.0, "StarboardBay%d" % (lane_index + 1), lane_z, lane_index, dimensions)
	for side in [-1.0, 1.0]:
		for hardpoint_index in 5:
			var z := lerpf(-dimensions.z * 0.34, dimensions.z * 0.35, float(hardpoint_index) / 4.0)
			var turret := MeshInstance3D.new()
			turret.name = "PointDefenseMount_%s_%02d" % ["P" if side < 0.0 else "S", hardpoint_index + 1]
			var turret_mesh := CylinderMesh.new()
			turret_mesh.top_radius = dimensions.x * 0.025
			turret_mesh.bottom_radius = dimensions.x * 0.04
			turret_mesh.height = dimensions.y * 0.15
			turret.mesh = turret_mesh
			turret.position = Vector3(side * dimensions.x * 0.38, dimensions.y * 0.52, z)
			turret.material_override = _make_material(Color(0.24, 0.3, 0.35))
			add_child(turret)
			flak_mounts.append(turret)
			var barrel := _mesh_block(Vector3(dimensions.x * 0.025, dimensions.y * 0.045, dimensions.z * 0.055), Color(0.12, 0.18, 0.23))
			barrel.position = Vector3(0.0, dimensions.y * 0.09, -dimensions.z * 0.025)
			turret.add_child(barrel)
	_add_default_collision()
	_add_chase_camera(dimensions)

func _authored_socket_requirements() -> Dictionary:
	return {
		"socket_flak_": 10,
		"socket_engine_": 6,
		"socket_bay_port_": 3,
		"socket_bay_starboard_": 3,
		"socket_bay_scout_": 1,
	}

func _bind_authored_carrier_sockets(dimensions: Vector3) -> void:
	flak_mounts.assign(_authored_socket_nodes("socket_flak_"))
	for socket in _authored_socket_nodes("socket_bay_port_"):
		port_bay_markers.append(_marker_from_authored_socket(socket))
	for socket in _authored_socket_nodes("socket_bay_starboard_"):
		starboard_bay_markers.append(_marker_from_authored_socket(socket))
	var scout_sockets := _authored_socket_nodes("socket_bay_scout_")
	if not scout_sockets.is_empty():
		scout_bay_marker = _marker_from_authored_socket(scout_sockets[0])
	if not port_bay_markers.is_empty():
		port_bay_marker = port_bay_markers[0]
	if not starboard_bay_markers.is_empty():
		starboard_bay_marker = starboard_bay_markers[0]
	for socket in _authored_socket_nodes("socket_engine_"):
		_add_authored_engine_trail(socket, dimensions)
	_bind_authored_blast_doors(dimensions)
	_add_authored_hangar_lighting(dimensions)

func _add_authored_hangar_lighting(dimensions: Vector3) -> void:
	# Emissive GLB strips identify fixtures but do not cast light in the Web/
	# compatibility renderer. Small local lights give the deep galleries actual
	# volume and keep parked craft readable from the chase camera.
	var bay_sockets: Array[Node3D] = []
	bay_sockets.append_array(_authored_socket_nodes("socket_bay_port_"))
	bay_sockets.append_array(_authored_socket_nodes("socket_bay_starboard_"))
	for socket in bay_sockets:
		var side_sign := signf(socket.position.x)
		if is_zero_approx(side_sign):
			continue
		var light := OmniLight3D.new()
		light.name = "%sGalleryLight" % socket.name
		light.light_color = Color(0.28, 0.66, 1.0)
		light.light_energy = 20.0
		light.light_indirect_energy = 0.0
		light.light_specular = 0.45
		light.omni_range = dimensions.x * 0.34
		light.omni_attenuation = 1.35
		light.shadow_enabled = false
		light.position = Vector3(-side_sign * dimensions.x * 0.14, dimensions.y * 0.1, 0.0)
		socket.add_child(light)

func _bind_authored_blast_doors(dimensions: Vector3) -> void:
	if authored_visual_root == null:
		return
	var closed_panel_offset := maxf(0.35, dimensions.y * 0.075)
	for side_name in ["port", "starboard"]:
		for bay_index in 3:
			var prefix := "blastdoor_%s_%02d" % [side_name, bay_index + 1]
			var upper := authored_visual_root.find_child("%s_upper" % prefix, true, false) as Node3D
			var lower := authored_visual_root.find_child("%s_lower" % prefix, true, false) as Node3D
			if upper == null or lower == null:
				continue
			var upper_open := upper.position
			var lower_open := lower.position
			var center_y := (upper_open.y + lower_open.y) * 0.5
			var upper_closed := upper_open
			var lower_closed := lower_open
			upper_closed.y = center_y + closed_panel_offset
			lower_closed.y = center_y - closed_panel_offset
			bay_assemblies.append({
				"authored": true,
				"node": upper,
				"door_a": upper,
				"door_b": lower,
				"door_a_open_position": upper_open,
				"door_b_open_position": lower_open,
				"door_a_closed_position": upper_closed,
				"door_b_closed_position": lower_closed,
			})

func _marker_from_authored_socket(socket: Node3D) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = "%sRuntimeMarker" % socket.name
	add_child(marker)
	marker.global_transform = socket.global_transform
	return marker

func _add_authored_engine_trail(socket: Node3D, dimensions: Vector3) -> void:
	var outer := _engine_plume_layer("CarrierEngineOuterPlume", Vector3(0.0, 0.0, dimensions.z * 0.075), Vector3(dimensions.x * 0.12, dimensions.x * 0.12, dimensions.z * 0.15), Color(0.08, 0.3, 1.0, 0.16), 2.1, socket)
	var inner := _engine_plume_layer("CarrierEngineInnerPlume", Vector3(0.0, 0.0, dimensions.z * 0.055), Vector3(dimensions.x * 0.075, dimensions.x * 0.075, dimensions.z * 0.11), Color(0.08, 0.76, 1.0, 0.36), 3.8, socket)
	var core := _engine_plume_layer("CarrierEngineCorePlume", Vector3(0.0, 0.0, dimensions.z * 0.035), Vector3(dimensions.x * 0.038, dimensions.x * 0.038, dimensions.z * 0.07), Color(0.82, 0.97, 1.0, 0.82), 5.6, socket)
	engine_trails.append({"outer": outer, "inner": inner, "core": core, "phase": float(engine_trails.size()) * 1.73})

func _add_chase_camera(dimensions: Vector3) -> void:
	chase_camera = Camera3D.new()
	chase_camera.name = "ChaseCamera"
	chase_camera.position = Vector3(0.0, dimensions.y * 2.15, dimensions.z * 1.02)
	chase_camera.fov = 72.0
	chase_camera.near = 1.0
	chase_camera.far = 30000.0
	add_child(chase_camera)

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

func _add_command_island(dimensions: Vector3) -> void:
	var island_x := dimensions.x * 0.13
	var island_z := dimensions.z * 0.08
	_add_hull_block(Vector3(island_x, dimensions.y * 0.64, island_z), Vector3(dimensions.x * 0.2, dimensions.y * 0.28, dimensions.z * 0.2), visual_color.lightened(0.06), "CommandIsland")
	_add_hull_block(Vector3(island_x, dimensions.y * 0.83, island_z - dimensions.z * 0.025), Vector3(dimensions.x * 0.14, dimensions.y * 0.14, dimensions.z * 0.13), visual_color.lightened(0.1), "FlagBridge")
	var bridge_glass := _add_hull_block(Vector3(island_x, dimensions.y * 0.89, island_z - dimensions.z * 0.072), Vector3(dimensions.x * 0.145, dimensions.y * 0.055, dimensions.z * 0.018), Color(0.06, 0.45, 0.68), "BridgeViewports")
	bridge_glass.material_override = _make_material(Color(0.08, 0.72, 1.0), 2.8)
	var mast := _add_hull_block(Vector3(island_x, dimensions.y * 1.05, island_z), Vector3(dimensions.x * 0.035, dimensions.y * 0.38, dimensions.z * 0.025), Color(0.13, 0.2, 0.25), "SensorMast")
	var radar := MeshInstance3D.new()
	radar.name = "LongRangeRadarDish"
	var radar_mesh := CylinderMesh.new()
	radar_mesh.top_radius = dimensions.x * 0.105
	radar_mesh.bottom_radius = dimensions.x * 0.105
	radar_mesh.height = dimensions.y * 0.035
	radar_mesh.radial_segments = 20
	radar.mesh = radar_mesh
	radar.rotation_degrees.z = 90.0
	radar.position = Vector3(0.0, dimensions.y * 0.22, 0.0)
	radar.material_override = _make_material(Color(0.16, 0.28, 0.34))
	mast.add_child(radar)
	for array_index in 3:
		var antenna := _mesh_block(Vector3(dimensions.x * 0.15, dimensions.y * 0.025, dimensions.z * 0.018), Color(0.1, 0.56, 0.68), 1.4)
		antenna.name = "EWArray%02d" % (array_index + 1)
		antenna.position = Vector3(0.0, dimensions.y * (0.08 + array_index * 0.08), 0.0)
		antenna.rotation_degrees.y = array_index * 60.0
		mast.add_child(antenna)

func _add_flight_deck_details(dimensions: Vector3) -> void:
	var deck := _add_hull_block(Vector3(0.0, dimensions.y * 0.535, dimensions.z * 0.045), Vector3(dimensions.x * 0.46, dimensions.y * 0.035, dimensions.z * 0.7), Color(0.12, 0.18, 0.22), "DorsalFlightDeck")
	if deck_marking_texture == null:
		deck_marking_texture = load("res://assets/textures/deck_markings.svg") as Texture2D
	var deck_material := _make_material(Color(0.16, 0.23, 0.27), 0.12)
	deck_material.albedo_texture = deck_marking_texture
	deck_material.uv1_scale = Vector3(2.0, 8.0, 1.0)
	deck.material_override = deck_material
	for elevator_index in 4:
		var elevator_z := lerpf(-dimensions.z * 0.24, dimensions.z * 0.28, float(elevator_index) / 3.0)
		var side := -1.0 if elevator_index % 2 == 0 else 1.0
		var elevator := _add_hull_block(Vector3(side * dimensions.x * 0.14, dimensions.y * 0.56, elevator_z), Vector3(dimensions.x * 0.15, dimensions.y * 0.025, dimensions.z * 0.09), Color(0.18, 0.24, 0.27), "AircraftElevator%02d" % (elevator_index + 1))
		elevator.material_override = _make_material(Color(0.16, 0.28, 0.31), 0.16)
	for light_index in 12:
		var guide := _mesh_block(Vector3(dimensions.x * 0.012, dimensions.y * 0.016, dimensions.z * 0.02), Color(0.16, 0.88, 1.0), 4.0)
		guide.name = "DeckCenterline%02d" % (light_index + 1)
		guide.position = Vector3(0.0, dimensions.y * 0.565, lerpf(-dimensions.z * 0.29, dimensions.z * 0.36, float(light_index) / 11.0))
		add_child(guide)

func _add_scout_drone_hive(dimensions: Vector3) -> void:
	var hive := _add_hull_block(Vector3(-dimensions.x * 0.12, dimensions.y * 0.68, -dimensions.z * 0.19), Vector3(dimensions.x * 0.17, dimensions.y * 0.16, dimensions.z * 0.13), visual_color.darkened(0.08), "ScoutEWHive")
	for tube_index in 4:
		var tube := _mesh_block(Vector3(dimensions.x * 0.028, dimensions.y * 0.035, dimensions.z * 0.08), Color(0.08, 0.32, 0.38), 0.8)
		tube.name = "ScoutLaunchTube%02d" % (tube_index + 1)
		tube.position = Vector3((float(tube_index) - 1.5) * dimensions.x * 0.037, dimensions.y * 0.09, -dimensions.z * 0.055)
		hive.add_child(tube)
	scout_bay_marker = Marker3D.new()
	scout_bay_marker.name = "ScoutEWBay"
	scout_bay_marker.position = Vector3(0.0, dimensions.y * 0.16, -dimensions.z * 0.09)
	hive.add_child(scout_bay_marker)

func _add_armored_bow(dimensions: Vector3) -> void:
	var bow := _add_tapered_visual_block("TaperedArmoredBow", Vector3(0.0, -0.2, -dimensions.z * 0.42), Vector3(dimensions.x * 0.58, dimensions.y * 0.7, dimensions.z * 0.34), 0.34, 0.94, visual_color.lightened(0.015), visual_profile.hull_texture_path)
	bow.rotation_degrees.x = -1.5
	for plate_index in 3:
		var plate := _add_tapered_visual_block("BowArmorPlate%02d" % plate_index, Vector3(0.0, dimensions.y * (0.35 + plate_index * 0.075), -dimensions.z * (0.48 - plate_index * 0.055)), Vector3(dimensions.x * (0.5 - plate_index * 0.055), 1.15, dimensions.z * 0.18), 0.32, 0.92, visual_color.lightened(0.025 + plate_index * 0.01), visual_profile.hull_texture_path)
		plate.rotation_degrees.x = -2.0 + plate_index
	for side in [-1.0, 1.0]:
		var prow_cheek := _add_tapered_visual_block("ProwCheek", Vector3(side * dimensions.x * 0.24, -dimensions.y * 0.08, -dimensions.z * 0.42), Vector3(dimensions.x * 0.18, dimensions.y * 0.42, dimensions.z * 0.3), 0.28, 0.86, visual_color.darkened(0.04), visual_profile.hull_texture_path)
		prow_cheek.rotation_degrees.y = side * 4.0

func _add_engine_banks(dimensions: Vector3) -> void:
	for side in [-1.0, 1.0]:
		for height_factor in [-0.28, 0.0, 0.28]:
			var height: float = height_factor * dimensions.y
			var housing := MeshInstance3D.new()
			housing.name = "EngineHousing"
			var housing_mesh := CylinderMesh.new()
			housing_mesh.top_radius = dimensions.x * 0.055
			housing_mesh.bottom_radius = dimensions.x * 0.065
			housing_mesh.height = dimensions.z * 0.075
			housing_mesh.radial_segments = 16
			housing.mesh = housing_mesh
			housing.rotation_degrees.x = 90.0
			housing.position = Vector3(side * dimensions.x * 0.2, height, dimensions.z * 0.515)
			housing.material_override = _make_material(Color(0.055, 0.085, 0.11))
			add_child(housing)
			var engine := MeshInstance3D.new()
			engine.name = "EngineGlow"
			var mesh := CylinderMesh.new()
			mesh.top_radius = dimensions.x * 0.028
			mesh.bottom_radius = dimensions.x * 0.038
			mesh.height = dimensions.z * 0.065
			mesh.radial_segments = 16
			engine.mesh = mesh
			engine.rotation_degrees.x = 90.0
			engine.position = Vector3(side * dimensions.x * 0.2, height, dimensions.z * 0.545)
			engine.material_override = _make_material(Color(0.035, 0.34, 0.68), 2.15)
			add_child(engine)
			var origin := Vector3(side * dimensions.x * 0.2, height, dimensions.z * 0.58)
			var outer := _engine_plume_layer("CarrierEngineOuterPlume", origin + Vector3(0.0, 0.0, dimensions.z * 0.075), Vector3(dimensions.x * 0.12, dimensions.x * 0.12, dimensions.z * 0.15), Color(0.08, 0.3, 1.0, 0.16), 2.1)
			var inner := _engine_plume_layer("CarrierEngineInnerPlume", origin + Vector3(0.0, 0.0, dimensions.z * 0.055), Vector3(dimensions.x * 0.075, dimensions.x * 0.075, dimensions.z * 0.11), Color(0.08, 0.76, 1.0, 0.36), 3.8)
			var core := _engine_plume_layer("CarrierEngineCorePlume", origin + Vector3(0.0, 0.0, dimensions.z * 0.035), Vector3(dimensions.x * 0.038, dimensions.x * 0.038, dimensions.z * 0.07), Color(0.82, 0.97, 1.0, 0.82), 5.6)
			engine_trails.append({"outer": outer, "inner": inner, "core": core, "phase": float(engine_trails.size()) * 1.73})

func _engine_plume_layer(node_name: String, position_value: Vector3, size_value: Vector3, color: Color, emission: float, parent: Node3D = self) -> MeshInstance3D:
	var plume := MeshInstance3D.new()
	plume.name = node_name
	var mesh := CylinderMesh.new()
	var plume_radius := maxf(size_value.x, size_value.y) * 0.5
	mesh.bottom_radius = plume_radius
	mesh.top_radius = plume_radius * 0.06
	mesh.height = size_value.z
	mesh.radial_segments = 32
	mesh.rings = 1
	plume.mesh = mesh
	plume.position = position_value
	plume.rotation_degrees.x = 90.0
	var material := _make_material(color, emission)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	plume.material_override = material
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.set_meta(&"base_length", size_value.z)
	plume.set_meta(&"nozzle_origin_z", position_value.z - size_value.z * 0.5)
	parent.add_child(plume)
	return plume

func _add_missile_cells(dimensions: Vector3) -> void:
	for side in [-1.0, 1.0]:
		for rack in 4:
			var cell := _mesh_block(Vector3(dimensions.x * 0.09, dimensions.y * 0.06, dimensions.z * 0.065), Color(0.14, 0.19, 0.23))
			cell.name = "MissileCell"
			cell.position = Vector3(side * dimensions.x * (0.18 + float(rack % 2) * 0.1), dimensions.y * 0.58, -dimensions.z * 0.3 + float(rack) * dimensions.z * 0.07)
			add_child(cell)

func _add_bay(side: float, bay_name: String, z_position: float, lane_index: int, dimensions: Vector3) -> void:
	var gallery_length := dimensions.z * 0.205
	var open_x := side * dimensions.x * 0.43
	var closed_x := side * dimensions.x * 0.31
	var assembly := Node3D.new()
	assembly.name = "%sAssembly" % bay_name
	assembly.position = Vector3(open_x, -dimensions.y * 0.04, z_position)
	add_child(assembly)
	var bay := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(dimensions.x * 0.22, dimensions.y * 0.38, gallery_length)
	bay.mesh = mesh
	bay.material_override = _make_material(visual_color.darkened(0.2))
	assembly.add_child(bay)
	var mouth := MeshInstance3D.new()
	var mouth_mesh := BoxMesh.new()
	mouth_mesh.size = Vector3(dimensions.x * 0.025, dimensions.y * 0.26, gallery_length * 0.78)
	mouth.mesh = mouth_mesh
	mouth.position = Vector3(side * dimensions.x * 0.125, 0.0, 0.0)
	var mouth_material := _make_material(Color(0.12, 0.82, 1.0), 3.6)
	if deck_marking_texture == null:
		deck_marking_texture = load("res://assets/textures/deck_markings.svg") as Texture2D
	mouth_material.albedo_texture = deck_marking_texture
	mouth_material.emission_texture = deck_marking_texture
	mouth_material.uv1_scale = Vector3(1.0, 3.0, 1.0)
	mouth.material_override = mouth_material
	assembly.add_child(mouth)
	var gallery_roof := _mesh_block(Vector3(dimensions.x * 0.2, dimensions.y * 0.07, gallery_length * 0.94), visual_color.lightened(0.06))
	gallery_roof.name = "GalleryArmor"
	gallery_roof.position.y = dimensions.y * 0.22
	assembly.add_child(gallery_roof)
	var rail_lights: Array[MeshInstance3D] = []
	for rail_index in 5:
		var rail := _mesh_block(Vector3(dimensions.x * 0.014, dimensions.y * 0.025, gallery_length * 0.08), Color(0.12, 0.9, 1.0), 4.0)
		rail.name = "ApproachLight"
		rail.position = Vector3(side * dimensions.x * 0.12, -dimensions.y * 0.1, lerpf(-gallery_length * 0.34, gallery_length * 0.34, float(rail_index) / 4.0))
		assembly.add_child(rail)
		rail_lights.append(rail)
	var door_open_z := gallery_length * 0.41
	var door_closed_z := gallery_length * 0.19
	var door_a := _add_bay_door(assembly, side, -door_open_z, dimensions, gallery_length)
	var door_b := _add_bay_door(assembly, side, door_open_z, dimensions, gallery_length)
	var marker := Marker3D.new()
	marker.name = bay_name
	marker.position = Vector3(side * dimensions.x * 0.18, 0.0, 0.0)
	assembly.add_child(marker)
	bay_assemblies.append({"node": assembly, "side": side, "mouth": mouth, "door_a": door_a, "door_b": door_b, "lights": rail_lights, "open_x": open_x, "closed_x": closed_x, "door_open_z": door_open_z, "door_closed_z": door_closed_z})
	if side < 0.0:
		port_bay_markers.append(marker)
		if lane_index == 0:
			port_bay_marker = marker
	else:
		starboard_bay_markers.append(marker)
		if lane_index == 0:
			starboard_bay_marker = marker

func _add_bay_door(parent: Node3D, side: float, z_position: float, dimensions: Vector3, gallery_length: float) -> MeshInstance3D:
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(dimensions.x * 0.035, dimensions.y * 0.32, gallery_length * 0.43)
	door.mesh = door_mesh
	door.position = Vector3(side * dimensions.x * 0.135, 0.0, z_position)
	door.material_override = _make_material(visual_color.lightened(0.05), 0.04)
	parent.add_child(door)
	return door

func _physics_process(delta: float) -> void:
	if is_destroyed:
		return
	if carrier_operations != null:
		carrier_operations.tick(delta)
	damage_state.tick(delta, _operations_multiplier(&"defense", &"shield_grid"))
	var weapon_delta := delta * _operations_multiplier(&"weapons", &"fire_control")
	var defense_delta := delta * _operations_multiplier(&"defense", &"shield_grid")
	flak_cooldown = maxf(0.0, flak_cooldown - weapon_delta)
	flak_mount_lock_seconds = maxf(0.0, flak_mount_lock_seconds - delta)
	missile_cooldown = maxf(0.0, missile_cooldown - weapon_delta)
	point_defense_cooldown = maxf(0.0, point_defense_cooldown - defense_delta)
	_process_flak_salvo_queue(delta)
	_update_bay_retraction(delta)
	if target_navigation_mode != TargetNavigationMode.NONE:
		_process_target_navigation(delta)
	elif control_enabled:
		_process_player_flight(delta)
	elif autopilot_active:
		_process_autopilot(delta)
	else:
		move_and_slide()
	_enforce_battlespace_bounds()
	_update_camera()
	_update_engine_trails()
	_process_point_defense()

func _process_player_flight(delta: float) -> void:
	_process_throttle_input(delta)
	if has_commanded_heading:
		_steer_toward(commanded_heading, delta)
	var propulsion_output := _operations_multiplier(&"propulsion", &"propulsion")
	var desired := -global_transform.basis.z.normalized() * definition.maximum_speed_mps * throttle_setting * clampf(0.55 + propulsion_output * 0.45, 0.25, 1.35)
	if Input.is_action_pressed("boost"):
		desired *= 1.6
	velocity = velocity.move_toward(desired, definition.acceleration_mps2 * propulsion_output * delta)
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
	var propulsion_output := _operations_multiplier(&"propulsion", &"propulsion")
	var distance := global_position.distance_to(autopilot_destination)
	if distance < collision_radius_m:
		autopilot_active = false
		velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * propulsion_output * delta)
		move_and_slide()
		return
	var desired := global_position.direction_to(autopilot_destination) * definition.maximum_speed_mps * clampf(0.55 + propulsion_output * 0.45, 0.25, 1.35)
	velocity = velocity.move_toward(desired, definition.acceleration_mps2 * propulsion_output * delta)
	if desired.length_squared() > 1.0:
		_steer_toward(desired, delta)
	move_and_slide()

func _process_target_navigation(delta: float) -> void:
	var propulsion_output := _operations_multiplier(&"propulsion", &"propulsion")
	if not is_instance_valid(target_navigation_target) or target_navigation_target.is_destroyed:
		clear_target_navigation()
		velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * propulsion_output * delta)
		move_and_slide()
		return
	var offset := target_navigation_target.global_position - global_position
	var distance := maxf(1.0, offset.length())
	var toward_target := offset / distance
	var target_velocity := target_navigation_target.velocity
	var desired_velocity := target_velocity
	match target_navigation_mode:
		TargetNavigationMode.APPROACH:
			var approach_error := distance - target_navigation_distance_m
			if approach_error > 40.0:
				var approach_speed := definition.maximum_speed_mps * clampf(approach_error / maxf(400.0, target_navigation_distance_m), 0.2, 1.0)
				desired_velocity += toward_target * approach_speed
		TargetNavigationMode.KEEP_DISTANCE:
			var range_error := distance - target_navigation_distance_m
			if absf(range_error) > 60.0:
				var correction_speed := definition.maximum_speed_mps * clampf(absf(range_error) / maxf(350.0, target_navigation_distance_m), 0.18, 0.8)
				desired_velocity += toward_target * correction_speed * signf(range_error)
		TargetNavigationMode.ORBIT:
			var radial := -toward_target
			var orbit_up := Vector3.UP if absf(radial.dot(Vector3.UP)) < 0.94 else global_transform.basis.y.normalized()
			var tangent := orbit_up.cross(radial).normalized() * (-1.0 if orbit_clockwise else 1.0)
			var orbit_error := (distance - target_navigation_distance_m) / maxf(1.0, target_navigation_distance_m)
			var orbit_direction := (tangent - radial * clampf(orbit_error * 1.45, -0.85, 0.85)).normalized()
			desired_velocity += orbit_direction * definition.maximum_speed_mps * 0.68
	if desired_velocity.length() > definition.maximum_speed_mps * 1.15:
		desired_velocity = desired_velocity.normalized() * definition.maximum_speed_mps * 1.15
	velocity = velocity.move_toward(desired_velocity, definition.acceleration_mps2 * propulsion_output * delta)
	if velocity.length_squared() > 1.0:
		_steer_toward(velocity.normalized(), delta)
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
		"target_navigation_mode": TargetNavigationMode.keys()[target_navigation_mode],
		"target_navigation_distance_m": target_navigation_distance_m,
	}


func command_snapshot() -> Dictionary:
	var snapshot := super.command_snapshot()
	var order_type := "Hold"
	var target_position := global_position
	if target_navigation_mode != TargetNavigationMode.NONE and is_instance_valid(target_navigation_target):
		order_type = TargetNavigationMode.keys()[target_navigation_mode].capitalize()
		target_position = target_navigation_target.global_position
	elif autopilot_active:
		order_type = "Set Course"
		target_position = autopilot_destination
	elif has_commanded_heading and throttle_setting > 0.0:
		order_type = "Helm Course"
		target_position = global_position + commanded_heading * 1000.0
	var ammunition_total := 0
	if carrier_operations != null:
		ammunition_total = int(carrier_operations.stores.get(&"flak_rounds", 0)) + int(carrier_operations.stores.get(&"guided_missiles", 0)) + int(carrier_operations.stores.get(&"nuclear_torpedoes", 0))
	snapshot["current_order"] = {
		"order_id": "carrier_navigation",
		"type": order_type,
		"status": "Active",
		"target_position": target_position,
		"queued": false,
		"stance": String(stance)
	}
	snapshot["queue"] = []
	snapshot["link"] = "Local"
	snapshot["link_latency_seconds"] = 0.0
	snapshot["ammunition"] = ammunition_total
	return snapshot

func command_heading(direction_value: Vector3, full_cruise: bool = false) -> bool:
	if direction_value.length_squared() < 0.25:
		return false
	commanded_heading = direction_value.normalized()
	clear_target_navigation()
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

func _update_camera() -> void:
	if chase_camera == null:
		return
	chase_distance_m = lerpf(chase_distance_m, chase_target_distance_m, 0.18)
	var height := lerpf(55.0, 220.0, inverse_lerp(CHASE_MIN_DISTANCE_M, CHASE_MAX_DISTANCE_M, chase_distance_m))
	var camera_offset := Vector3(0.0, height, chase_distance_m)
	camera_offset = camera_offset.rotated(Vector3.RIGHT, camera_orbit_pitch)
	camera_offset = camera_offset.rotated(Vector3.UP, camera_orbit_yaw)
	chase_camera.position = camera_offset
	var carrier_focus := global_position + global_transform.basis.y * 3.0
	chase_camera.look_at(carrier_focus, Vector3.UP)
	var viewport_size := get_viewport().get_visible_rect().size
	var director_position := flak_aim_screen_position if flak_aim_uses_pointer else viewport_size * 0.5
	director_position.x = clampf(director_position.x, 0.0, viewport_size.x)
	director_position.y = clampf(director_position.y, 0.0, viewport_size.y)
	aim_direction = chase_camera.project_ray_normal(director_position).normalized()
	_update_flak_mounts()

func _update_flak_mounts() -> void:
	var mount_aim := flak_mount_direction if flak_mount_lock_seconds > 0.0 else aim_direction
	var turret_up := Vector3.FORWARD if absf(mount_aim.dot(Vector3.UP)) > 0.98 else Vector3.UP
	for mount in flak_mounts:
		if is_instance_valid(mount):
			mount.look_at(mount.global_position + mount_aim, turret_up)

func adjust_chase_zoom(wheel_steps: float) -> void:
	chase_target_distance_m = clampf(chase_target_distance_m * pow(0.86, wheel_steps), CHASE_MIN_DISTANCE_M, CHASE_MAX_DISTANCE_M)

func chase_zoom_percent() -> int:
	if chase_target_distance_m <= CHASE_DEFAULT_DISTANCE_M:
		return int(round(inverse_lerp(CHASE_DEFAULT_DISTANCE_M, CHASE_MIN_DISTANCE_M, chase_target_distance_m) * 100.0))
	return -int(round(inverse_lerp(CHASE_DEFAULT_DISTANCE_M, CHASE_MAX_DISTANCE_M, chase_target_distance_m) * 100.0))

func fire_flak(target_ship: CombatShip) -> bool:
	if flak_weapon == null or flak_cooldown > 0.0 or not is_instance_valid(target_ship):
		return false
	if target_ship.is_destroyed or target_ship.team == team:
		return false
	var target_distance := global_position.distance_to(target_ship.global_position)
	if target_distance > flak_weapon.range_m:
		return false
	var rounds_to_fire := mini(flak_burst_count, _available_store(&"flak_rounds", flak_burst_count))
	if rounds_to_fire <= 0:
		_consume_store(&"flak_rounds", flak_burst_count)
		return false
	if not _consume_store(&"flak_rounds", rounds_to_fire):
		return false
	var intercept_seconds := CombatShip.intercept_time_seconds(global_position, target_ship.global_position, target_ship.velocity, flak_weapon.projectile_speed_mps)
	var target_point := target_ship.global_position + target_ship.velocity * clampf(intercept_seconds, 0.0, 8.0)
	var shot_direction := global_position.direction_to(target_point)
	var shot_distance := minf(flak_weapon.range_m, global_position.distance_to(target_point))
	flak_mount_direction = shot_direction
	flak_mount_lock_seconds = maxf(0.35, flak_weapon.cooldown_seconds)
	_queue_flak_barrage(shot_direction, rounds_to_fire, 0.52, shot_distance, flak_airburst_radius_m)
	flak_cooldown = flak_weapon.cooldown_seconds
	return true

func fire_missile(target_ship: CombatShip) -> bool:
	if missile_weapon == null or missile_cooldown > 0.0 or not is_instance_valid(target_ship):
		return false
	if global_position.distance_to(target_ship.global_position) > missile_weapon.range_m:
		return false
	last_missile_salvo_count = mini(missile_salvo_count, _available_store(&"guided_missiles", missile_salvo_count))
	if last_missile_salvo_count <= 0:
		_consume_store(&"guided_missiles", 1)
		return false
	if not _consume_store(&"guided_missiles", last_missile_salvo_count):
		last_missile_salvo_count = 0
		return false
	var missile_sockets := _authored_socket_nodes("socket_missile_")
	for index in last_missile_salvo_count:
		var side := -1.0 if index % 2 == 0 else 1.0
		var rack := index / 2
		var local_offset := Vector3(side * definition.dimensions_m.x * 0.18, definition.dimensions_m.y * (0.375 + rack * 0.06), lerpf(-definition.dimensions_m.z * 0.29, definition.dimensions_m.z * 0.27, clampf(float(rack), 0.0, 1.0)))
		var start := global_transform * local_offset
		if index < missile_sockets.size():
			start = missile_sockets[index].global_position
		var missile := spawn_projectile(missile_weapon, start, start.direction_to(target_ship.global_position), target_ship)
		missile.direction = missile.direction.rotated(global_transform.basis.z.normalized(), side * 0.018)
	missile_cooldown = missile_weapon.cooldown_seconds
	return true

func fire_nuclear(target_ship: CombatShip) -> bool:
	if nuclear_weapon == null or not nuclear_available or not is_instance_valid(target_ship):
		return false
	if global_position.distance_to(target_ship.global_position) > nuclear_weapon.range_m:
		return false
	if not _consume_store(&"nuclear_torpedoes", 1):
		nuclear_available = false
		return false
	var start := global_transform * Vector3(0.0, definition.dimensions_m.y * 0.2, -definition.dimensions_m.z * 0.32)
	var missile_sockets := _authored_socket_nodes("socket_missile_")
	if not missile_sockets.is_empty():
		start = missile_sockets[0].global_position
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
	var local_start := Vector3(side * definition.dimensions_m.x * 0.38, definition.dimensions_m.y * 0.38, -definition.dimensions_m.z * 0.32 + float(pattern_index % 3) * definition.dimensions_m.z * 0.3)
	var start := global_transform * local_start
	if not flak_mounts.is_empty():
		start = flak_mounts[pattern_index % flak_mounts.size()].global_position
	var projectile := spawn_projectile(flak_weapon, start, shot_direction)
	projectile.damage *= damage_scale
	if airburst_distance_m > 0.0:
		projectile.configure_airburst(airburst_distance_m, airburst_radius_m, 1.0, flak_capital_damage_multiplier, true, true)

func _update_engine_trails() -> void:
	var speed_ratio := clampf(velocity.length() / maxf(1.0, definition.maximum_speed_mps), 0.0, 1.6)
	var acceleration_demand := absf(throttle_setting - clampf(speed_ratio, 0.0, 1.0)) * 1.35
	var output := clampf(maxf(0.07, maxf(throttle_setting * 0.32, acceleration_demand)), 0.0, 1.25)
	var now := Time.get_ticks_msec() * 0.001
	for trail_data in engine_trails:
		var flicker := 0.94 + sin(now * 18.0 + float(trail_data.phase)) * 0.06
		var outer: MeshInstance3D = trail_data.outer
		var inner: MeshInstance3D = trail_data.inner
		var core: MeshInstance3D = trail_data.core
		if is_instance_valid(outer):
			_scale_engine_plume(outer, 0.82 + output * 0.2, lerpf(0.08, 1.42, output) * flicker)
			outer.transparency = lerpf(0.88, 0.34, clampf(output, 0.0, 1.0))
		if is_instance_valid(inner):
			_scale_engine_plume(inner, 0.9 + output * 0.14, lerpf(0.1, 1.24, output) * (2.0 - flicker))
			inner.transparency = lerpf(0.76, 0.18, clampf(output, 0.0, 1.0))
		if is_instance_valid(core):
			_scale_engine_plume(core, 0.94, lerpf(0.12, 1.05, output) * flicker)
			core.transparency = lerpf(0.62, 0.04, clampf(output, 0.0, 1.0))

func _scale_engine_plume(plume: MeshInstance3D, radial_scale: float, length_scale: float) -> void:
	# CylinderMesh length is local Y before the 90-degree rotation. Keep the near end
	# locked to the nozzle while engine output expands the trail aft.
	plume.scale = Vector3(radial_scale, length_scale, 1.0)
	var base_length := float(plume.get_meta(&"base_length", 0.0))
	var nozzle_origin_z := float(plume.get_meta(&"nozzle_origin_z", plume.position.z))
	plume.position.z = nozzle_origin_z + base_length * length_scale * 0.5

func _process_point_defense() -> void:
	if point_defense_cooldown > 0.0:
		return
	var registry := _combat_registry()
	var projectiles: Array = registry.active_projectiles() if registry != null else get_tree().get_nodes_in_group("projectiles")
	var best: SidebayProjectile
	var best_score := INF
	for candidate in projectiles:
		if not candidate is SidebayProjectile or candidate.team == team or not candidate.can_be_intercepted:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance > 900.0:
			continue
		var aimed_at_carrier: bool = is_instance_valid(candidate.target) and candidate.target == self
		var closest_approach: float = candidate.direction.dot(candidate.global_position.direction_to(global_position))
		var time_to_impact: float = distance / maxf(1.0, candidate.speed_mps)
		var score: float = time_to_impact - (6.0 if aimed_at_carrier else 0.0) - maxf(0.0, closest_approach) * 2.0
		if candidate.radial_warhead:
			score -= 4.0
		if score < best_score:
			best = candidate
			best_score = score
			point_defense_last_tti = time_to_impact
	point_defense_target = best
	if not is_instance_valid(best):
		point_defense_last_tti = INF
		return
	var rounds_to_fire := mini(3, _available_store(&"flak_rounds", 3))
	if rounds_to_fire <= 0 or not _consume_store(&"flak_rounds", rounds_to_fire):
		return
	_spawn_flak_barrage(global_position.direction_to(best.global_position), rounds_to_fire, 0.28)
	best.intercept()
	point_defense_cooldown = 0.28

func receive_damage(amount: float, source_entity_id: StringName = &"", impact_context: Dictionary = {}) -> Dictionary:
	var localized_context := impact_context.duplicate(true)
	var world_impact: Vector3 = localized_context.get("position", global_position)
	localized_context["position"] = to_local(world_impact)
	localized_context["world_position"] = world_impact
	var layer_damage := super.receive_damage(amount, source_entity_id, impact_context)
	if carrier_operations != null and float(layer_damage.get("hull", 0.0)) > 0.0:
		carrier_operations.apply_hull_impact(layer_damage, localized_context)
	return layer_damage

func _operations_multiplier(channel: StringName, subsystem: StringName) -> float:
	if carrier_operations == null:
		return 1.0
	return carrier_operations.power_multiplier(channel) * carrier_operations.subsystem_multiplier(subsystem)

func flight_operations_multiplier(side: StringName) -> float:
	var deck_id := &"port_deck" if side == &"port" else &"starboard_deck"
	if carrier_operations == null:
		return 1.0
	return _operations_multiplier(&"flight", deck_id) * carrier_operations.crew_efficiency_multiplier(&"deck")


func effective_command_range_m() -> float:
	if carrier_operations == null:
		return definition.command_range_m
	var command_health := carrier_operations.subsystem_multiplier(&"command_cic")
	var crew_effect := carrier_operations.crew_efficiency_multiplier(&"general")
	return definition.command_range_m * maxf(0.1, command_health * crew_effect)

func is_flight_deck_operational(side: StringName) -> bool:
	if carrier_operations == null:
		return true
	var deck_id := &"port_deck" if side == &"port" else &"starboard_deck"
	return carrier_operations.subsystem_multiplier(deck_id) >= 0.2

func _available_store(store_id: StringName, fallback: int) -> int:
	if carrier_operations == null:
		return fallback
	return maxi(0, int(carrier_operations.stores.get(store_id, 0)))

func _consume_store(store_id: StringName, amount: int) -> bool:
	return carrier_operations == null or carrier_operations.consume_store(store_id, amount)

func set_autopilot(destination: Vector3) -> void:
	clear_target_navigation()
	autopilot_destination = destination
	autopilot_active = true

func command_approach(target_ship: CombatShip, stop_distance_m: float = 500.0) -> bool:
	return _command_target_navigation(TargetNavigationMode.APPROACH, target_ship, stop_distance_m, 0.82)

func command_orbit(target_ship: CombatShip, orbit_distance_m: float = 1200.0) -> bool:
	return _command_target_navigation(TargetNavigationMode.ORBIT, target_ship, orbit_distance_m, 0.68)

func command_keep_distance(target_ship: CombatShip, distance_m: float = 2500.0) -> bool:
	return _command_target_navigation(TargetNavigationMode.KEEP_DISTANCE, target_ship, distance_m, 0.58)

func _command_target_navigation(mode: TargetNavigationMode, target_ship: CombatShip, distance_m: float, throttle: float) -> bool:
	if not is_instance_valid(target_ship) or target_ship.is_destroyed:
		return false
	target_navigation_mode = mode
	target_navigation_target = target_ship
	target_navigation_distance_m = clampf(distance_m, 250.0, 25000.0)
	autopilot_active = false
	has_commanded_heading = false
	set_throttle(throttle)
	return true

func clear_target_navigation() -> void:
	target_navigation_mode = TargetNavigationMode.NONE
	target_navigation_target = null

func get_bay_marker(side: StringName, lane_index: int = 0) -> Marker3D:
	if side == &"scout" and is_instance_valid(scout_bay_marker):
		return scout_bay_marker
	var markers := port_bay_markers if side == &"port" else starboard_bay_markers
	if not markers.is_empty():
		return markers[clampi(lane_index, 0, markers.size() - 1)]
	return port_bay_marker if side == &"port" else starboard_bay_marker

func get_bay_launch_vector(side: StringName) -> Vector3:
	if side == &"scout":
		return global_transform.basis.y.normalized()
	return -global_transform.basis.x.normalized() if side == &"port" else global_transform.basis.x.normalized()

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

func notify_flight_launch_started(squadron_id: StringName) -> void:
	active_flight_launches[squadron_id] = true
	request_bays_open()

func notify_flight_launch_finished(squadron_id: StringName) -> void:
	active_flight_launches.erase(squadron_id)
	_seal_bays_if_flight_ops_idle()

func notify_flight_recovery_started(squadron_id: StringName) -> void:
	active_flight_recoveries[squadron_id] = true
	request_bays_open()

func notify_flight_recovery_finished(squadron_id: StringName) -> void:
	active_flight_recoveries.erase(squadron_id)
	_seal_bays_if_flight_ops_idle()

func _seal_bays_if_flight_ops_idle() -> void:
	if active_flight_launches.is_empty() and active_flight_recoveries.is_empty():
		request_bays_closed()

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
		if bool(bay_data.get("authored", false)):
			var authored_door_a := bay_data.door_a as Node3D
			var authored_door_b := bay_data.door_b as Node3D
			var door_a_open: Vector3 = bay_data.door_a_open_position
			var door_b_open: Vector3 = bay_data.door_b_open_position
			var door_a_closed: Vector3 = bay_data.door_a_closed_position
			var door_b_closed: Vector3 = bay_data.door_b_closed_position
			authored_door_a.position = door_a_open.lerp(door_a_closed, bay_closure)
			authored_door_b.position = door_b_open.lerp(door_b_closed, bay_closure)
			continue
		var assembly: Node3D = bay_data.node
		assembly.position.x = lerpf(float(bay_data.open_x), float(bay_data.closed_x), bay_closure)
		var door_a: MeshInstance3D = bay_data.door_a
		var door_b: MeshInstance3D = bay_data.door_b
		door_a.position.z = lerpf(-float(bay_data.door_open_z), -float(bay_data.door_closed_z), bay_closure)
		door_b.position.z = lerpf(float(bay_data.door_open_z), float(bay_data.door_closed_z), bay_closure)
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
