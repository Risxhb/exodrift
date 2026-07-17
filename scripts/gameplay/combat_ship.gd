class_name CombatShip
extends CharacterBody3D

const VERTICAL_BATTLESPACE_LIMIT_M := 1400.0
const RESOLUTE_VLS_COMPARTMENT_COUNT := 6
const RESOLUTE_SALVO_INTERVAL_SECONDS := 0.14
const RESOLUTE_SALVO_DAMAGE_SCALE := 0.34
const RESOLUTE_VERTICAL_CLEARANCE_M := 135.0
const RESOLUTE_FLAK_RANGE_M := 1800.0
const RESOLUTE_FLAK_BLAST_RADIUS_M := 115.0
const RESOLUTE_FLAK_COOLDOWN_SECONDS := 0.72

static var armor_panel_texture: Texture2D
static var deck_marking_texture: Texture2D
static var hull_texture_cache: Dictionary = {}

signal ship_destroyed(entity_id: StringName)
signal damage_received(entity_id: StringName, source_entity_id: StringName, amount: float)
signal order_acknowledged(entity_id: StringName, message: String)
signal order_status_changed(entity_id: StringName, order_id: StringName, status: FleetOrder.Status, reason: String)
signal doctrine_changed(entity_id: StringName, stance: StringName, formation: StringName, spacing: StringName)
signal damage_resolved(entity_id: StringName, source_entity_id: StringName, layers: Dictionary, impact_context: Dictionary)

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
var command_link := CommandLinkState.new()
var fleet_command := FleetCommandState.new()
var current_order: FleetOrder:
	get:
		return fleet_command.current_order
	set(value):
		fleet_command.current_order = value
var order_queue: Array[FleetOrder]:
	get:
		return fleet_command.order_queue
	set(value):
		fleet_command.order_queue = value
var stance: StringName:
	get:
		return fleet_command.stance
	set(value):
		fleet_command.stance = value
var formation_name: StringName:
	get:
		return fleet_command.formation_name
	set(value):
		fleet_command.formation_name = value
var formation_spacing: StringName:
	get:
		return fleet_command.formation_spacing
	set(value):
		fleet_command.formation_spacing = value
var weapon_cooldown: float = 0.0
var hold_position: Vector3 = Vector3.ZERO
var visual_color: Color = Color(0.35, 0.55, 0.7)
var incoming_damage_multiplier: float = 1.0
var outgoing_damage_multiplier: float = 1.0
var damage_visual_stage: int = 0
var damage_indicator_nodes: Array[MeshInstance3D] = []
var damage_effect_cooldown: float = 0.0
var visual_profile: ShipVisualProfile
var visual_asset: ShipVisualAsset
var authored_visual_root: Node3D
var authored_sockets: Dictionary = {}
var target_state_provider: Callable
var _track_lost_order_id: StringName = &""
var missile_launch_points: Array[Node3D] = []
var flak_battery_mounts: Array[Node3D] = []
var flak_battery_cooldowns: Array[float] = []
var flak_battery_fire_counts: Array[int] = []
var pending_missile_salvo: Array[Dictionary] = []
var missile_salvo_timer: float = 0.0
var resolute_flak_weapon: WeaponDefinition
var resolute_vls_hatches: Array[Dictionary] = []

func _init() -> void:
	fleet_command.order_status_changed.connect(_on_fleet_order_status_changed)
	fleet_command.doctrine_changed.connect(_on_fleet_doctrine_changed)

func configure(ship_definition: ShipDefinition, entity_id: StringName, faction: StringName, color: Color) -> void:
	definition = ship_definition
	stable_entity_id = entity_id
	fleet_command.formation_leader_id = entity_id
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
	visual_profile = ShipVisualProfile.for_ship(StringName(definition.role), team, definition.ship_id)
	_build_visual()
	if _is_resolute():
		_configure_resolute_weapons()
	_build_damage_indicators()

func configure_target_state_provider(provider: Callable) -> void:
	target_state_provider = provider

func _exit_tree() -> void:
	var registry := _combat_registry()
	if registry != null:
		registry.unregister_combat_entity(self)

func _combat_registry() -> Node:
	return get_node_or_null("/root/CombatRegistry")

func _combat_vfx() -> Node:
	return get_node_or_null("/root/CombatVFX")

func _is_resolute() -> bool:
	return definition != null and definition.ship_id == &"iss_resolute"

func _configure_resolute_weapons() -> void:
	for weapon in definition.weapons:
		if weapon.weapon_id == &"resolute_flak":
			resolute_flak_weapon = weapon
			return
	resolute_flak_weapon = WeaponDefinition.new()
	resolute_flak_weapon.weapon_id = &"resolute_flak"
	resolute_flak_weapon.display_name = "Resolute Flak Battery"
	resolute_flak_weapon.role = "flak"
	resolute_flak_weapon.range_m = RESOLUTE_FLAK_RANGE_M
	resolute_flak_weapon.cooldown_seconds = RESOLUTE_FLAK_COOLDOWN_SECONDS
	resolute_flak_weapon.damage = 10.0
	resolute_flak_weapon.projectile_speed_mps = 1900.0
	resolute_flak_weapon.can_intercept_projectiles = true
	definition.weapons.append(resolute_flak_weapon)

func _build_visual() -> void:
	if _try_build_authored_visual():
		_bind_authored_combat_sockets()
		_add_default_collision()
		return
	var hull_dimensions := definition.dimensions_m
	var profile := visual_profile
	var body := MeshInstance3D.new()
	body.name = "Hull"
	body.mesh = _tapered_hull_mesh(hull_dimensions * profile.core_scale, profile.core_fore_taper, profile.core_aft_taper, 0.82, 1.0)
	body.material_override = _make_material(visual_color, 0.1, profile.hull_texture_path)
	add_child(body)
	_add_tapered_visual_block("DorsalArmor", Vector3(0.0, hull_dimensions.y * 0.38, hull_dimensions.z * 0.05), hull_dimensions * profile.dorsal_scale, profile.dorsal_fore_taper, profile.dorsal_aft_taper, visual_color.lightened(0.08), profile.hull_texture_path)
	_add_tapered_visual_block("Keel", Vector3(0.0, -hull_dimensions.y * 0.38, hull_dimensions.z * 0.08), hull_dimensions * profile.keel_scale, profile.core_fore_taper * 0.82, profile.core_aft_taper * 0.9, visual_color.darkened(0.22), profile.hull_texture_path)
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
	_add_default_collision()

func _try_build_authored_visual() -> bool:
	if visual_profile == null or definition == null:
		return false
	var candidate := visual_profile.load_visual_asset()
	if candidate == null:
		return false
	if not candidate.enabled:
		return false
	var errors := candidate.manifest_errors(definition.ship_id, definition.dimensions_m)
	if not errors.is_empty():
		_warn_authored_asset_fallback(candidate, errors)
		return false
	var model := candidate.instantiate_model()
	if model == null:
		_warn_authored_asset_fallback(candidate, PackedStringArray(["model scene did not instantiate as Node3D"]))
		return false
	errors = candidate.instance_errors(model, _authored_socket_requirements())
	if not errors.is_empty():
		model.free()
		_warn_authored_asset_fallback(candidate, errors)
		return false
	candidate.apply_material_contract(model)
	add_child(model)
	visual_asset = candidate
	authored_visual_root = model
	authored_sockets = candidate.collect_sockets(model)
	return true

func _authored_socket_requirements() -> Dictionary:
	if _is_resolute():
		return {"socket_missile_": RESOLUTE_VLS_COMPARTMENT_COUNT, "socket_flak_": 3}
	return {}

func _authored_socket_nodes(prefix: String) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	var normalized_prefix := prefix.to_lower()
	var names: Array[String] = []
	for socket_name in authored_sockets:
		if String(socket_name).begins_with(normalized_prefix):
			names.append(String(socket_name))
	names.sort()
	for socket_name in names:
		var socket := authored_sockets.get(StringName(socket_name)) as Node3D
		if socket != null:
			nodes.append(socket)
	return nodes

func _bind_authored_combat_sockets() -> void:
	missile_launch_points.assign(_authored_socket_nodes("socket_missile_"))
	flak_battery_mounts.assign(_authored_socket_nodes("socket_flak_"))
	flak_battery_cooldowns.resize(flak_battery_mounts.size())
	flak_battery_fire_counts.resize(flak_battery_mounts.size())
	flak_battery_cooldowns.fill(0.0)
	flak_battery_fire_counts.fill(0)
	_bind_resolute_vls_hatches()

func _bind_resolute_vls_hatches() -> void:
	resolute_vls_hatches.clear()
	if not _is_resolute() or authored_visual_root == null:
		return
	for cell_index in RESOLUTE_VLS_COMPARTMENT_COUNT:
		var cell_number := cell_index + 1
		var port := authored_visual_root.find_child("VLS_%02d_DoorPort_Hinge" % cell_number, true, false) as Node3D
		var starboard := authored_visual_root.find_child("VLS_%02d_DoorStarboard_Hinge" % cell_number, true, false) as Node3D
		if port == null or starboard == null:
			continue
		resolute_vls_hatches.append({
			"port": port,
			"starboard": starboard,
			"port_closed_rotation": port.rotation,
			"starboard_closed_rotation": starboard.rotation,
		})

func _animate_resolute_vls_hatch(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= resolute_vls_hatches.size():
		return
	var hatch: Dictionary = resolute_vls_hatches[cell_index]
	var port := hatch.get("port") as Node3D
	var starboard := hatch.get("starboard") as Node3D
	if not is_instance_valid(port) or not is_instance_valid(starboard):
		return
	var port_closed := hatch.get("port_closed_rotation", port.rotation) as Vector3
	var starboard_closed := hatch.get("starboard_closed_rotation", starboard.rotation) as Vector3
	var port_open := port_closed + Vector3(0.0, 0.0, deg_to_rad(108.0))
	var starboard_open := starboard_closed + Vector3(0.0, 0.0, -deg_to_rad(108.0))
	port.rotation = port_open
	starboard.rotation = starboard_open
	_reseal_resolute_vls_hatch(port, starboard, port_closed, starboard_closed)

func _reseal_resolute_vls_hatch(port: Node3D, starboard: Node3D, port_closed: Vector3, starboard_closed: Vector3) -> void:
	await get_tree().create_timer(0.48).timeout
	if is_instance_valid(port):
		port.rotation = port_closed
	if is_instance_valid(starboard):
		starboard.rotation = starboard_closed

func _add_default_collision() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "GameplayCollision"
	var shape := BoxShape3D.new()
	shape.size = definition.dimensions_m
	collision.shape = shape
	add_child(collision)

func _warn_authored_asset_fallback(candidate: ShipVisualAsset, errors: PackedStringArray) -> void:
	push_warning("Authored ship asset '%s' rejected; using procedural fallback: %s" % [candidate.ship_id, "; ".join(errors)])

func _build_hull_details(hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	_add_visual_block("AftEngineering", Vector3(0.0, -hull_dimensions.y * 0.05, hull_dimensions.z * 0.39), Vector3(hull_dimensions.x * 0.52, hull_dimensions.y * 0.58, hull_dimensions.z * 0.18), visual_color.darkened(0.18), 0.0, profile.hull_texture_path)
	_add_visual_block("LongitudinalSpine", Vector3(0.0, hull_dimensions.y * 0.46, hull_dimensions.z * 0.02), Vector3(hull_dimensions.x * 0.12, hull_dimensions.y * 0.16, hull_dimensions.z * 0.78), profile.accent_color.darkened(0.32), 0.0, profile.hull_texture_path)
	for index in profile.armor_rib_count:
		var progress := (float(index) + 1.0) / (float(profile.armor_rib_count) + 1.0)
		var z_position := lerpf(-hull_dimensions.z * 0.35, hull_dimensions.z * 0.34, progress)
		_add_visual_block("ArmorRib%02d" % index, Vector3(0.0, hull_dimensions.y * 0.34, z_position), Vector3(hull_dimensions.x * 0.78, hull_dimensions.y * 0.08, hull_dimensions.z * 0.035), profile.accent_color.darkened(0.38), 0.0, profile.hull_texture_path)
	_build_surface_language(hull_dimensions, profile)
	_build_command_tower(hull_dimensions, profile)
	if not _is_resolute():
		for turret_index in profile.turret_count:
			var turret_progress := (float(turret_index) + 1.0) / (float(profile.turret_count) + 1.0)
			var turret_z := lerpf(-hull_dimensions.z * 0.4, hull_dimensions.z * 0.24, turret_progress)
			var turret_side := -1.0 if turret_index % 2 == 0 else 1.0
			_add_weapon_turret(turret_index, Vector3(turret_side * hull_dimensions.x * 0.24, hull_dimensions.y * 0.55, turret_z), hull_dimensions, profile)
	if profile.faction_style == &"navy":
		_build_navy_details(hull_dimensions, profile)
	else:
		_build_hostile_fins(hull_dimensions, profile)

func _build_surface_language(hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	# A few broad plates read more clearly than dozens of tiny greebles at combat zoom.
	for side in [-1.0, 1.0]:
		_add_visual_block(
			"HullIdentityPanel",
			Vector3(side * hull_dimensions.x * 0.506, hull_dimensions.y * 0.13, -hull_dimensions.z * 0.12),
			Vector3(hull_dimensions.x * 0.018, hull_dimensions.y * 0.2, hull_dimensions.z * 0.34),
			profile.marking_color,
			0.26
		)
		_add_visual_block(
			"LowerArmorInset",
			Vector3(side * hull_dimensions.x * 0.505, -hull_dimensions.y * 0.27, hull_dimensions.z * 0.17),
			Vector3(hull_dimensions.x * 0.02, hull_dimensions.y * 0.24, hull_dimensions.z * 0.3),
			visual_color.darkened(0.2 + profile.wear_level * 0.12),
			0.0,
			profile.hull_texture_path
		)
	var wear_patch_count := clampi(roundi(profile.wear_level * 4.0), 0, 3)
	for index in wear_patch_count:
		var side := -1.0 if index % 2 == 0 else 1.0
		var patch := _add_visual_block(
			"ServiceWear%02d" % index,
			Vector3(side * hull_dimensions.x * 0.34, hull_dimensions.y * (0.405 + index * 0.012), lerpf(-hull_dimensions.z * 0.31, hull_dimensions.z * 0.28, float(index) / 2.0)),
			Vector3(hull_dimensions.x * (0.2 + index * 0.035), hull_dimensions.y * 0.025, hull_dimensions.z * 0.13),
			visual_color.darkened(0.28),
			0.0,
			profile.hull_texture_path
		)
		patch.rotation_degrees.y = side * (4.0 + index * 3.0)

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
	match definition.ship_id:
		&"cvn_sidebay":
			_add_visual_block("SidebayFlightDeck", Vector3(0.0, hull_dimensions.y * 0.59, hull_dimensions.z * 0.13), Vector3(hull_dimensions.x * 0.5, hull_dimensions.y * 0.055, hull_dimensions.z * 0.58), visual_color.darkened(0.14), 0.0, profile.hull_texture_path)
			_add_visual_block("SidebayDeckCenterline", Vector3(0.0, hull_dimensions.y * 0.625, hull_dimensions.z * 0.08), Vector3(hull_dimensions.x * 0.04, hull_dimensions.y * 0.018, hull_dimensions.z * 0.48), profile.marking_color, 0.3)
			for side in [-1.0, 1.0]:
				_add_visual_block("SidebayHangarMouth", Vector3(side * hull_dimensions.x * 0.515, -hull_dimensions.y * 0.06, hull_dimensions.z * 0.04), Vector3(hull_dimensions.x * 0.025, hull_dimensions.y * 0.34, hull_dimensions.z * 0.38), Color(0.035, 0.08, 0.11), 0.0)
				_add_visual_block("SidebayApproachLight", Vector3(side * hull_dimensions.x * 0.531, hull_dimensions.y * 0.12, -hull_dimensions.z * 0.03), Vector3(hull_dimensions.x * 0.012, hull_dimensions.y * 0.035, hull_dimensions.z * 0.25), profile.accent_color, 1.2)
		&"cvn_vanguard":
			for side in [-1.0, 1.0]:
				_add_visual_block("VanguardStrikeRail", Vector3(side * hull_dimensions.x * 0.24, hull_dimensions.y * 0.61, -hull_dimensions.z * 0.29), Vector3(hull_dimensions.x * 0.095, hull_dimensions.y * 0.11, hull_dimensions.z * 0.5), Color(0.11, 0.18, 0.22), 0.0, profile.hull_texture_path)
				_add_visual_block("VanguardRailCharge", Vector3(side * hull_dimensions.x * 0.24, hull_dimensions.y * 0.68, -hull_dimensions.z * 0.52), Vector3(hull_dimensions.x * 0.035, hull_dimensions.y * 0.035, hull_dimensions.z * 0.07), profile.accent_color, 1.4)
			var vanguard_blade := _add_visual_block("VanguardProwBlade", Vector3(0.0, -hull_dimensions.y * 0.18, -hull_dimensions.z * 0.61), Vector3(hull_dimensions.x * 0.32, hull_dimensions.y * 0.32, hull_dimensions.z * 0.3), visual_color.lightened(0.06), 0.0, profile.hull_texture_path)
			vanguard_blade.rotation_degrees.x = -9.0
		&"cvn_citadel":
			for layer in 3:
				_add_visual_block("CitadelBastionLayer%02d" % layer, Vector3(0.0, hull_dimensions.y * (0.48 + layer * 0.16), hull_dimensions.z * (0.14 - layer * 0.055)), Vector3(hull_dimensions.x * (0.72 - layer * 0.14), hull_dimensions.y * 0.15, hull_dimensions.z * (0.5 - layer * 0.08)), visual_color.darkened(0.04 + layer * 0.04), 0.0, profile.hull_texture_path)
			for side in [-1.0, 1.0]:
				_add_visual_block("CitadelFormationBeacon", Vector3(side * hull_dimensions.x * 0.47, hull_dimensions.y * 0.47, -hull_dimensions.z * 0.24), Vector3(hull_dimensions.x * 0.035, hull_dimensions.y * 0.08, hull_dimensions.z * 0.16), profile.accent_color, 1.1)
		&"iss_resolute":
			_add_tapered_visual_block(
				"ResoluteDorsalDeck",
				Vector3(0.0, hull_dimensions.y * 0.55, -hull_dimensions.z * 0.1),
				Vector3(hull_dimensions.x * 0.7, hull_dimensions.y * 0.11, hull_dimensions.z * 0.62),
				0.64,
				0.94,
				visual_color.lightened(0.04),
				profile.hull_texture_path
			)
			for side in [-1.0, 1.0]:
				_add_visual_block("ResoluteBroadsideArmor", Vector3(side * hull_dimensions.x * 0.51, hull_dimensions.y * 0.08, -hull_dimensions.z * 0.08), Vector3(hull_dimensions.x * 0.075, hull_dimensions.y * 0.48, hull_dimensions.z * 0.56), visual_color.darkened(0.1), 0.0, profile.hull_texture_path)
			for cell_index in RESOLUTE_VLS_COMPARTMENT_COUNT:
				var column := cell_index % 2
				var row := cell_index / 2
				var side := -1.0 if column == 0 else 1.0
				var cell_position := Vector3(
					side * hull_dimensions.x * 0.19,
					hull_dimensions.y * 0.66,
					lerpf(-hull_dimensions.z * 0.34, -hull_dimensions.z * 0.06, float(row) / 2.0)
				)
				_add_visual_block(
					"ResoluteMissileCompartment%02d" % cell_index,
					cell_position,
					Vector3(hull_dimensions.x * 0.24, hull_dimensions.y * 0.075, hull_dimensions.z * 0.105),
					Color(0.045, 0.09, 0.115),
					0.0
				)
				var launch_point := Node3D.new()
				launch_point.name = "ResoluteMissileLaunch%02d" % cell_index
				launch_point.position = cell_position + Vector3.UP * hull_dimensions.y * 0.085
				add_child(launch_point)
				missile_launch_points.append(launch_point)
			_add_resolute_flak_battery(0, Vector3(-hull_dimensions.x * 0.31, hull_dimensions.y * 0.67, hull_dimensions.z * 0.09), true, hull_dimensions, profile)
			_add_resolute_flak_battery(1, Vector3(hull_dimensions.x * 0.31, hull_dimensions.y * 0.67, hull_dimensions.z * 0.27), true, hull_dimensions, profile)
			_add_resolute_flak_battery(2, Vector3(0.0, -hull_dimensions.y * 0.58, -hull_dimensions.z * 0.02), false, hull_dimensions, profile)
			_add_visual_block("ResoluteRangefinder", Vector3(0.0, hull_dimensions.y * 0.91, -hull_dimensions.z * 0.17), Vector3(hull_dimensions.x * 0.16, hull_dimensions.y * 0.08, hull_dimensions.z * 0.15), profile.accent_color, 0.42)
		&"iss_harrier":
			for side in [-1.0, 1.0]:
				var vane := _add_visual_block("HarrierInterceptVane", Vector3(side * hull_dimensions.x * 0.58, 0.0, -hull_dimensions.z * 0.24), Vector3(hull_dimensions.x * 0.34, hull_dimensions.y * 0.09, hull_dimensions.z * 0.38), visual_color.lightened(0.05), 0.0, profile.hull_texture_path)
				vane.rotation_degrees.y = side * 14.0
			_add_visual_block("HarrierGunSpine", Vector3(0.0, -hull_dimensions.y * 0.5, -hull_dimensions.z * 0.18), Vector3(hull_dimensions.x * 0.16, hull_dimensions.y * 0.18, hull_dimensions.z * 0.52), Color(0.1, 0.2, 0.26), 0.0, profile.hull_texture_path)
			for side in [-1.0, 1.0]:
				_add_visual_block("HarrierScreenCannon", Vector3(side * hull_dimensions.x * 0.37, -hull_dimensions.y * 0.11, -hull_dimensions.z * 0.47), Vector3(hull_dimensions.x * 0.055, hull_dimensions.y * 0.065, hull_dimensions.z * 0.36), Color(0.08, 0.15, 0.18), 0.0, profile.hull_texture_path)
			_add_visual_block("HarrierCockpit", Vector3(0.0, hull_dimensions.y * 0.55, -hull_dimensions.z * 0.38), Vector3(hull_dimensions.x * 0.18, hull_dimensions.y * 0.07, hull_dimensions.z * 0.18), profile.bridge_color, 1.25)
		&"iss_bulwark":
			for side in [-1.0, 1.0]:
				_add_visual_block("BulwarkCitadelPlate", Vector3(side * hull_dimensions.x * 0.54, 0.0, hull_dimensions.z * 0.02), Vector3(hull_dimensions.x * 0.2, hull_dimensions.y * 0.82, hull_dimensions.z * 0.64), visual_color.lightened(0.02), 0.0, profile.hull_texture_path)
				var shield_vane := _add_visual_block("BulwarkShieldVane", Vector3(side * hull_dimensions.x * 0.46, hull_dimensions.y * 0.2, -hull_dimensions.z * 0.45), Vector3(hull_dimensions.x * 0.22, hull_dimensions.y * 0.18, hull_dimensions.z * 0.22), profile.accent_color, 0.12, profile.hull_texture_path)
				shield_vane.rotation_degrees.y = side * 24.0
				_add_visual_block("BulwarkArmorCourse", Vector3(side * hull_dimensions.x * 0.6, -hull_dimensions.y * 0.15, hull_dimensions.z * 0.13), Vector3(hull_dimensions.x * 0.07, hull_dimensions.y * 0.58, hull_dimensions.z * 0.54), visual_color.darkened(0.13), 0.0, profile.hull_texture_path)
			_add_visual_block("BulwarkCommandBastion", Vector3(0.0, hull_dimensions.y * 0.78, hull_dimensions.z * 0.12), Vector3(hull_dimensions.x * 0.4, hull_dimensions.y * 0.22, hull_dimensions.z * 0.28), visual_color.lightened(0.03), 0.0, profile.hull_texture_path)

func _build_hostile_fins(hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		fin.name = "BladeFin"
		var fin_mesh := PrismMesh.new()
		fin_mesh.size = Vector3(hull_dimensions.x * profile.fin_scale, hull_dimensions.y * 0.14, hull_dimensions.z * 0.42)
		fin.mesh = fin_mesh
		fin.position = Vector3(side * hull_dimensions.x * 0.55, hull_dimensions.y * (0.08 if profile.faction_style == &"acheron" else 0.28), hull_dimensions.z * 0.02)
		fin.rotation_degrees = Vector3(0.0, 0.0, side * (18.0 if profile.faction_style == &"acheron" else 34.0))
		fin.material_override = _make_material(visual_color.darkened(0.1), 0.0, profile.hull_texture_path)
		add_child(fin)
		_add_visual_block("FactionLight", Vector3(side * hull_dimensions.x * 0.46, hull_dimensions.y * 0.26, -hull_dimensions.z * 0.18), Vector3(hull_dimensions.x * 0.025, hull_dimensions.y * 0.055, hull_dimensions.z * 0.26), profile.accent_color, 1.8)
	match profile.faction_style:
		&"acheron":
			for side in [-1.0, 1.0]:
				var jaw := _add_visual_block("AcheronJawPlate", Vector3(side * hull_dimensions.x * 0.28, -hull_dimensions.y * 0.28, -hull_dimensions.z * 0.5), Vector3(hull_dimensions.x * 0.28, hull_dimensions.y * 0.14, hull_dimensions.z * 0.36), visual_color.darkened(0.16), 0.0, profile.hull_texture_path)
				jaw.rotation_degrees.y = side * 13.0
				_add_visual_block("AcheronWeldBeacon", Vector3(side * hull_dimensions.x * 0.4, hull_dimensions.y * 0.43, hull_dimensions.z * 0.24), Vector3(hull_dimensions.x * 0.04, hull_dimensions.y * 0.055, hull_dimensions.z * 0.16), profile.marking_color, 1.25)
		&"vesper":
			for side in [-1.0, 1.0]:
				var phase_rail := _add_visual_block("VesperPhaseRail", Vector3(side * hull_dimensions.x * 0.37, hull_dimensions.y * 0.38, -hull_dimensions.z * 0.08), Vector3(hull_dimensions.x * 0.035, hull_dimensions.y * 0.05, hull_dimensions.z * 0.7), profile.marking_color, 1.75)
				phase_rail.rotation_degrees.y = side * 5.0
				var crescent := _add_visual_block("VesperCrescent", Vector3(side * hull_dimensions.x * 0.23, hull_dimensions.y * 0.62, hull_dimensions.z * 0.18), Vector3(hull_dimensions.x * 0.18, hull_dimensions.y * 0.08, hull_dimensions.z * 0.34), visual_color.lightened(0.06), 0.0, profile.hull_texture_path)
				crescent.rotation_degrees = Vector3(0.0, side * 24.0, side * 16.0)
		&"crucible":
			for side in [-1.0, 1.0]:
				_add_visual_block("CrucibleCarapacePlate", Vector3(side * hull_dimensions.x * 0.3, hull_dimensions.y * 0.45, hull_dimensions.z * 0.08), Vector3(hull_dimensions.x * 0.3, hull_dimensions.y * 0.11, hull_dimensions.z * 0.56), visual_color.darkened(0.02), 0.0, profile.hull_texture_path)
				_add_visual_block("CrucibleLatticeMark", Vector3(side * hull_dimensions.x * 0.3, hull_dimensions.y * 0.52, -hull_dimensions.z * 0.1), Vector3(hull_dimensions.x * 0.16, hull_dimensions.y * 0.025, hull_dimensions.z * 0.24), profile.marking_color, 1.45)
			_add_visual_block("CrucibleCoreFacet", Vector3(0.0, hull_dimensions.y * 0.69, -hull_dimensions.z * 0.12), Vector3(hull_dimensions.x * 0.22, hull_dimensions.y * 0.13, hull_dimensions.z * 0.2), profile.bridge_color, 1.1)

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

func _add_resolute_flak_battery(index: int, position_value: Vector3, dorsal: bool, hull_dimensions: Vector3, profile: ShipVisualProfile) -> void:
	var battery := MeshInstance3D.new()
	battery.name = "ResoluteDorsalFlakBattery%02d" % index if dorsal else "ResoluteVentralFlakBattery"
	var battery_mesh := CylinderMesh.new()
	battery_mesh.top_radius = hull_dimensions.x * 0.075
	battery_mesh.bottom_radius = hull_dimensions.x * 0.1
	battery_mesh.height = hull_dimensions.y * 0.11
	battery_mesh.radial_segments = 8
	battery.mesh = battery_mesh
	battery.position = position_value
	battery.material_override = _make_material(visual_color.lightened(0.08), 0.0, profile.hull_texture_path)
	add_child(battery)
	var surface_direction := Vector3.UP if dorsal else Vector3.DOWN
	var barrel := _add_visual_block(
		"ResoluteFlakBarrel%02d" % index,
		position_value + surface_direction * hull_dimensions.y * 0.055 + Vector3(0.0, 0.0, -hull_dimensions.z * 0.06),
		Vector3(hull_dimensions.x * 0.045, hull_dimensions.y * 0.045, hull_dimensions.z * 0.15),
		profile.accent_color.darkened(0.28),
		0.28,
		profile.hull_texture_path
	)
	if not dorsal:
		barrel.rotation.z = PI
	var muzzle := Node3D.new()
	muzzle.name = "ResoluteFlakMuzzle%02d" % index
	muzzle.position = position_value + surface_direction * hull_dimensions.y * 0.075 + Vector3(0.0, 0.0, -hull_dimensions.z * 0.14)
	add_child(muzzle)
	flak_battery_mounts.append(muzzle)
	flak_battery_cooldowns.append(float(index) * RESOLUTE_FLAK_COOLDOWN_SECONDS / 3.0)
	flak_battery_fire_counts.append(0)

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
	var plume := MeshInstance3D.new()
	plume.name = "EnginePlume"
	var plume_mesh := PrismMesh.new()
	plume_mesh.size = Vector3(hull_dimensions.x * 0.1, hull_dimensions.y * 0.16, hull_dimensions.z * 0.26)
	plume.mesh = plume_mesh
	plume.position = engine_position + Vector3(0.0, 0.0, hull_dimensions.z * 0.32)
	plume.rotation.y = PI
	var plume_color := Color(profile.engine_color.r, profile.engine_color.g, profile.engine_color.b, 0.42)
	var plume_material := _make_material(plume_color, profile.engine_emission * 0.72)
	plume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume.material_override = plume_material
	add_child(plume)

func _build_damage_indicators() -> void:
	if definition == null or String(definition.role) in ["fighter", "drone", "interceptor", "scout"]:
		return
	var dimensions := definition.dimensions_m
	var positions := [
		Vector3(-dimensions.x * 0.31, dimensions.y * 0.34, -dimensions.z * 0.12),
		Vector3(dimensions.x * 0.27, dimensions.y * 0.4, dimensions.z * 0.18),
		Vector3(-dimensions.x * 0.18, -dimensions.y * 0.38, dimensions.z * 0.04),
		Vector3(dimensions.x * 0.12, dimensions.y * 0.28, -dimensions.z * 0.34)
	]
	for index in positions.size():
		var breach := MeshInstance3D.new()
		breach.name = "DamageBreach%02d" % index
		var breach_mesh := BoxMesh.new()
		breach_mesh.size = Vector3(dimensions.x * 0.16, dimensions.y * 0.045, dimensions.z * 0.11)
		breach.mesh = breach_mesh
		breach.position = positions[index]
		breach.material_override = _make_material(Color(0.9, 0.15 + index * 0.04, 0.025), 0.55 + index * 0.15)
		breach.visible = false
		add_child(breach)
		damage_indicator_nodes.append(breach)

func _update_damage_presentation() -> void:
	if damage_state == null or damage_indicator_nodes.is_empty():
		return
	var layers := damage_state.normalized_layers()
	var next_stage := 0
	if layers.y < 0.68:
		next_stage = 1
	if layers.y < 0.28:
		next_stage = 2
	if layers.z < 0.7:
		next_stage = 3
	if layers.z < 0.35:
		next_stage = 4
	damage_visual_stage = next_stage
	for index in damage_indicator_nodes.size():
		damage_indicator_nodes[index].visible = index < damage_visual_stage

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

func _add_tapered_visual_block(node_name: String, position_value: Vector3, size_value: Vector3, fore_taper: float, aft_taper: float, color: Color, texture_path: String = "") -> MeshInstance3D:
	var block := MeshInstance3D.new()
	block.name = node_name
	block.mesh = _tapered_hull_mesh(size_value, fore_taper, aft_taper, 0.82, 1.0)
	block.position = position_value
	block.material_override = _make_material(color, 0.0, texture_path)
	add_child(block)
	return block

func _tapered_hull_mesh(size_value: Vector3, fore_width: float, aft_width: float, fore_height: float, aft_height: float) -> ArrayMesh:
	var half := size_value * 0.5
	var front_x := half.x * clampf(fore_width, 0.25, 1.0)
	var back_x := half.x * clampf(aft_width, 0.25, 1.0)
	var front_y := half.y * clampf(fore_height, 0.25, 1.0)
	var back_y := half.y * clampf(aft_height, 0.25, 1.0)
	var vertices := [
		Vector3(-front_x, -front_y, -half.z), Vector3(-front_x, front_y, -half.z),
		Vector3(front_x, front_y, -half.z), Vector3(front_x, -front_y, -half.z),
		Vector3(-back_x, -back_y, half.z), Vector3(-back_x, back_y, half.z),
		Vector3(back_x, back_y, half.z), Vector3(back_x, -back_y, half.z),
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_mesh_quad(surface, vertices[0], vertices[1], vertices[2], vertices[3])
	_add_mesh_quad(surface, vertices[7], vertices[6], vertices[5], vertices[4])
	_add_mesh_quad(surface, vertices[0], vertices[4], vertices[5], vertices[1])
	_add_mesh_quad(surface, vertices[3], vertices[2], vertices[6], vertices[7])
	_add_mesh_quad(surface, vertices[1], vertices[5], vertices[6], vertices[2])
	_add_mesh_quad(surface, vertices[0], vertices[3], vertices[7], vertices[4])
	surface.generate_normals()
	return surface.commit()

func _add_mesh_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	surface.set_uv(Vector2(0.0, 1.0)); surface.add_vertex(a)
	surface.set_uv(Vector2(0.0, 0.0)); surface.add_vertex(b)
	surface.set_uv(Vector2(1.0, 0.0)); surface.add_vertex(c)
	surface.set_uv(Vector2(0.0, 1.0)); surface.add_vertex(a)
	surface.set_uv(Vector2(1.0, 0.0)); surface.add_vertex(c)
	surface.set_uv(Vector2(1.0, 1.0)); surface.add_vertex(d)

func _make_material(color: Color, emission_energy: float = 0.0, texture_path: String = "") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var profile := visual_profile
	material.albedo_color = color
	material.metallic = profile.surface_metallic if profile != null else 0.65
	material.roughness = profile.surface_roughness if profile != null else 0.42
	material.metallic_specular = 0.38
	material.rim_enabled = true
	material.rim = profile.rim_strength if profile != null else 0.14
	material.rim_tint = 0.42
	if emission_energy <= 0.2:
		material.albedo_color = color.lightened(profile.albedo_lift if profile != null else 0.2)
		var default_texture_path := profile.hull_texture_path if profile != null else ("res://assets/textures/navy_refit_hull.svg" if team == &"friendly" else "res://assets/textures/acheron_forged_hull.svg")
		var resolved_texture_path := texture_path if not texture_path.is_empty() else default_texture_path
		material.albedo_texture = _hull_texture(resolved_texture_path)
		var texture_scale := profile.texture_scale if profile != null else 3.0
		material.uv1_scale = Vector3(texture_scale, texture_scale, texture_scale)
		material.uv1_triplanar = true
		material.uv1_triplanar_sharpness = 3.6
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if emission_energy > 0.0:
		if emission_energy > 0.2:
			material.metallic = 0.18
			material.roughness = 0.2
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material

func _hull_texture(texture_path: String) -> Texture2D:
	if not hull_texture_cache.has(texture_path):
		hull_texture_cache[texture_path] = load(texture_path) as Texture2D
	return hull_texture_cache.get(texture_path) as Texture2D

func _physics_process(delta: float) -> void:
	if is_destroyed or definition == null:
		return
	fleet_command.tick(_now_seconds())
	damage_state.tick(delta)
	damage_effect_cooldown = maxf(0.0, damage_effect_cooldown - delta)
	if damage_visual_stage >= 3 and damage_effect_cooldown <= 0.0:
		damage_effect_cooldown = 1.35 if damage_visual_stage == 3 else 0.72
		var damage_vfx := _combat_vfx()
		if damage_vfx != null:
			damage_vfx.spawn_burst("spark", global_position + Vector3(sin(float(Time.get_ticks_msec())) * collision_radius_m * 0.35, collision_radius_m * 0.18, cos(float(Time.get_ticks_msec()) * 0.7) * collision_radius_m * 0.32), 0.5)
	weapon_cooldown = maxf(0.0, weapon_cooldown - delta)
	if _is_resolute():
		_process_pending_missile_salvo(delta)
		_process_resolute_flak(delta)
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
			_move_toward_position(current_order.target_position, delta, collision_radius_m * 1.5)
			if global_position.distance_to(current_order.target_position) < collision_radius_m * 1.6 and velocity.length() < definition.maximum_speed_mps * 0.18:
				_complete_order()
		FleetOrder.OrderType.HOLD:
			_hold_at(current_order.target_position, delta, current_order.target_facing)
		FleetOrder.OrderType.ATTACK:
			_process_attack_order(delta, false)
		FleetOrder.OrderType.INTERCEPT:
			_process_attack_order(delta, true)
		FleetOrder.OrderType.ESCORT:
			_process_escort_order(delta)
		FleetOrder.OrderType.INTERACT:
			var interaction_radius := maxf(current_order.interaction_radius_m, collision_radius_m * 1.5)
			if global_position.distance_to(current_order.target_position) > interaction_radius * 0.72:
				_move_toward_position(current_order.target_position, delta, interaction_radius * 0.55)
			else:
				_hold_at(current_order.target_position, delta)
		FleetOrder.OrderType.RECALL:
			_complete_order()

func _process_attack_order(delta: float, intercept: bool) -> void:
	var target_state := _resolve_order_target_state(current_order)
	if bool(target_state.get("destroyed", false)):
		order_acknowledged.emit(stable_entity_id, "%s: designated target destroyed" % display_name)
		_complete_order()
		return
	var target_visible := bool(target_state.get("visible", false))
	var target_position: Vector3 = target_state.get("position", current_order.target_position)
	var target_velocity: Vector3 = target_state.get("velocity", current_order.target_velocity)
	var target_node := target_state.get("node") as CombatShip
	if target_visible and is_instance_valid(target_node) and not target_node.is_destroyed:
		current_target = target_node
		current_order.target_position = target_position
		current_order.target_velocity = target_velocity
		_track_lost_order_id = &""
	else:
		current_target = null
		if _track_lost_order_id != current_order.order_id:
			_track_lost_order_id = current_order.order_id
			order_acknowledged.emit(stable_entity_id, "%s: TRACK LOST — proceeding to last confirmed position" % display_name)
		if global_position.distance_to(target_position) <= collision_radius_m * 2.0:
			_hold_at(target_position, delta)
		else:
			_move_toward_position(target_position, delta, collision_radius_m * 1.5)
		return
	var leash := maxf(2400.0, _preferred_weapon_range() * 4.0) * _stance_pursuit_multiplier()
	if current_order.origin_position != Vector3.ZERO and current_order.origin_position.distance_to(target_position) > leash:
		order_acknowledged.emit(stable_entity_id, "%s: pursuit leash reached" % display_name)
		_complete_order()
		return
	var distance_to_target := global_position.distance_to(target_position)
	var desired_range := _preferred_weapon_range() * _stance_range_ratio()
	if intercept:
		var intercept_seconds := distance_to_target / maxf(1.0, definition.maximum_speed_mps + target_velocity.length())
		var intercept_point := target_position + target_velocity * clampf(intercept_seconds, 0.0, 8.0)
		if distance_to_target > desired_range * 0.72:
			_move_toward_position(intercept_point, delta, collision_radius_m * 1.2, target_velocity)
		else:
			_match_velocity(target_velocity, delta)
	else:
		if distance_to_target > desired_range * 1.08:
			var lead_seconds := distance_to_target / maxf(1.0, definition.maximum_speed_mps)
			_move_toward_position(target_position + target_velocity * clampf(lead_seconds, 0.0, 5.0), delta, collision_radius_m * 1.5, target_velocity)
		elif distance_to_target < desired_range * 0.58:
			var retreat_point := global_position + target_position.direction_to(global_position) * desired_range * 0.45
			_move_toward_position(retreat_point, delta, collision_radius_m, target_velocity)
		else:
			_match_velocity(target_velocity * 0.65, delta)
	_try_fire_at(target_node)

func _process_escort_order(delta: float) -> void:
	var escort_target := resolve_entity(current_order.target_entity_id)
	if not is_instance_valid(escort_target) or escort_target.is_destroyed:
		_complete_order()
		return
	var spacing := fleet_command.spacing_multiplier()
	var clearance := (collision_radius_m + escort_target.collision_radius_m) * 2.1 * spacing
	var side := -1.0 if stable_entity_id.hash() % 2 == 0 else 1.0
	var relative_offset := escort_target.global_transform.basis.x.normalized() * side * clearance
	relative_offset += escort_target.global_transform.basis.z.normalized() * clearance * 0.38
	var slot := escort_target.global_position + relative_offset
	_move_toward_position(slot, delta, collision_radius_m * 1.4, escort_target.velocity)
	if stance == &"evade_return":
		return
	var threat := _nearest_hostile_to(escort_target.global_position, _preferred_weapon_range() * (1.35 if stance == &"defensive" else 1.0))
	if is_instance_valid(threat):
		_try_fire_at(threat)

func _hold_at(destination: Vector3, delta: float, facing: Vector3 = Vector3.ZERO) -> void:
	if global_position.distance_to(destination) > collision_radius_m * 1.15:
		_move_toward_position(destination, delta, collision_radius_m)
		return
	velocity = velocity.move_toward(Vector3.ZERO, definition.acceleration_mps2 * delta)
	if facing.length_squared() > 0.5:
		var desired_yaw := atan2(-facing.x, -facing.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(definition.rotation_speed_radians * delta, 0.0, 1.0))
	move_and_slide()

func _match_velocity(target_velocity: Vector3, delta: float) -> void:
	velocity = velocity.move_toward(target_velocity.limit_length(definition.maximum_speed_mps), definition.acceleration_mps2 * delta)
	_face_velocity(delta)
	move_and_slide()

func _move_toward_position(destination: Vector3, delta: float, arrival_radius: float = 0.0, target_velocity: Vector3 = Vector3.ZERO) -> void:
	var offset := destination - global_position
	if offset.length_squared() < 1.0:
		return
	var slow_radius := maxf(maxf(collision_radius_m * 8.0, arrival_radius * 4.0), 280.0)
	var speed_ratio := clampf((offset.length() - arrival_radius) / slow_radius, 0.0, 1.0)
	var desired_velocity := offset.normalized() * definition.maximum_speed_mps * speed_ratio
	desired_velocity += target_velocity.limit_length(definition.maximum_speed_mps) * (1.0 - speed_ratio) * 0.75
	desired_velocity += _separation_velocity() * definition.maximum_speed_mps * 0.55
	desired_velocity = desired_velocity.limit_length(definition.maximum_speed_mps)
	velocity = velocity.move_toward(desired_velocity, definition.acceleration_mps2 * delta)
	_face_velocity(delta)
	move_and_slide()

func _face_velocity(delta: float) -> void:
	if velocity.length_squared() <= 1.0:
		return
	var desired_yaw := atan2(-velocity.x, -velocity.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(definition.rotation_speed_radians * delta, 0.0, 1.0))

func _separation_velocity(excluded_entity: CombatShip = null) -> Vector3:
	var separation := Vector3.ZERO
	var registry := _combat_registry()
	var candidates: Array = registry.active_combat_entities() if registry != null else get_tree().get_nodes_in_group("combat_entities")
	for candidate in candidates:
		if candidate == self or candidate == excluded_entity or not candidate is CombatShip or candidate.is_destroyed:
			continue
		var safe_distance: float = (collision_radius_m + candidate.collision_radius_m) * 2.2
		var distance := global_position.distance_to(candidate.global_position)
		if distance <= 0.01 or distance >= safe_distance:
			continue
		separation += candidate.global_position.direction_to(global_position) * (1.0 - distance / safe_distance)
	return separation.limit_length(1.0)

func issue_order(order: FleetOrder) -> bool:
	if order == null:
		return false
	order.origin_position = global_position
	if order.order_type == FleetOrder.OrderType.HOLD and order.target_facing.length_squared() < 0.5:
		order.target_facing = -global_transform.basis.z.normalized()
	if not order.target_entity_id.is_empty():
		var target := resolve_entity(order.target_entity_id)
		if is_instance_valid(target):
			order.target_position = target.global_position
			order.target_velocity = target.velocity
	order.stance = stance
	return fleet_command.submit(order, command_link, _now_seconds())

func _complete_order() -> void:
	fleet_command.complete_current(_now_seconds())
	if current_order == null:
		var hold := FleetOrder.at_position(FleetOrder.OrderType.HOLD, global_position, _now_seconds())
		hold.requires_command_link = false
		hold.target_facing = -global_transform.basis.z.normalized()
		fleet_command.submit(hold, command_link, _now_seconds())

func cancel_orders(reason: String = "CANCELLED") -> void:
	fleet_command.cancel_all(reason)

func set_stance(next_stance: StringName) -> void:
	if fleet_command.set_stance(next_stance):
		order_acknowledged.emit(stable_entity_id, "%s stance: %s" % [display_name, String(stance).replace("_", " ").capitalize()])

func cycle_formation() -> void:
	var index := FleetCommandState.VALID_FORMATIONS.find(formation_name)
	set_formation(FleetCommandState.VALID_FORMATIONS[(index + 1) % FleetCommandState.VALID_FORMATIONS.size()], formation_spacing)

func set_formation(next_formation: StringName, spacing: StringName = &"") -> void:
	if fleet_command.set_formation(next_formation, spacing):
		order_acknowledged.emit(stable_entity_id, "%s formation: %s / %s" % [display_name, String(formation_name).capitalize(), String(formation_spacing).capitalize()])

func set_formation_spacing(next_spacing: StringName) -> void:
	if fleet_command.set_spacing(next_spacing):
		order_acknowledged.emit(stable_entity_id, "%s spacing: %s" % [display_name, String(formation_spacing).capitalize()])

func command_snapshot() -> Dictionary:
	var snapshot := fleet_command.snapshot(_now_seconds())
	var layers := layer_percentages()
	snapshot.merge({
		"entity_id": String(stable_entity_id),
		"display_name": display_name,
		"link": command_link.label(),
		"link_latency_seconds": command_link.latency_seconds,
		"health": {"shields": layers.x, "armor": layers.y, "hull": layers.z},
		"ammunition": -1,
		"endurance_seconds": -1.0,
		"leader_id": String(fleet_command.formation_leader_id)
	}, true)
	return snapshot

func _preferred_weapon_range() -> float:
	if definition.weapons.is_empty():
		return 1200.0
	return definition.weapons[0].range_m

func _stance_range_ratio() -> float:
	match stance:
		&"aggressive":
			return 0.70
		&"defensive":
			return 0.95
		&"evade_return":
			return 1.1
		_:
			return 0.82

func _stance_pursuit_multiplier() -> float:
	match stance:
		&"aggressive":
			return 1.5
		&"defensive":
			return 0.6
		&"evade_return":
			return 0.0
		_:
			return 1.0

func _resolve_order_target_state(order: FleetOrder) -> Dictionary:
	if target_state_provider.is_valid():
		var provided: Variant = target_state_provider.call(order.target_entity_id)
		if provided is Dictionary:
			var state: Dictionary = provided
			if bool(state.get("visible", false)):
				return state
			return {
				"visible": false,
				"destroyed": bool(state.get("destroyed", false)),
				"position": state.get("position", order.target_position),
				"velocity": state.get("velocity", order.target_velocity),
				"node": state.get("node")
			}
	var target := resolve_entity(order.target_entity_id)
	if is_instance_valid(target) and not target.is_destroyed:
		return {"visible": true, "position": target.global_position, "velocity": target.velocity, "node": target}
	return {"visible": false, "destroyed": is_instance_valid(target) and target.is_destroyed, "position": order.target_position, "velocity": order.target_velocity, "node": target}

func _nearest_hostile_to(center: Vector3, range_m: float) -> CombatShip:
	var best: CombatShip
	var best_distance := range_m
	var registry := _combat_registry()
	var candidates: Array = registry.active_combat_entities() if registry != null else get_tree().get_nodes_in_group("combat_entities")
	for candidate in candidates:
		if not candidate is CombatShip or candidate.team == team or candidate.is_destroyed:
			continue
		var distance := center.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _on_fleet_order_status_changed(order: FleetOrder) -> void:
	if order.status == FleetOrder.Status.ACTIVE:
		command_link.last_confirmed_order = order
		if order.origin_position == Vector3.ZERO:
			order.origin_position = global_position
		if order.order_type == FleetOrder.OrderType.HOLD:
			hold_position = order.target_position
		order_acknowledged.emit(stable_entity_id, "%s acknowledges %s" % [display_name, order.type_label().to_upper()])
	elif order.status == FleetOrder.Status.TRANSMITTING:
		var remaining := maxf(0.0, order.activation_time_seconds - _now_seconds())
		order_acknowledged.emit(stable_entity_id, "%s transmitting %s — %.1fs" % [display_name, order.type_label().to_upper(), remaining])
	elif order.status == FleetOrder.Status.QUEUED:
		order_acknowledged.emit(stable_entity_id, "%s queues %s" % [display_name, order.type_label().to_upper()])
	elif order.status == FleetOrder.Status.REJECTED:
		order_acknowledged.emit(stable_entity_id, "%s rejects %s — %s" % [display_name, order.type_label().to_upper(), order.rejection_reason])
	order_status_changed.emit(stable_entity_id, order.order_id, order.status, order.rejection_reason)

func _on_fleet_doctrine_changed(next_stance: StringName, next_formation: StringName, next_spacing: StringName) -> void:
	doctrine_changed.emit(stable_entity_id, next_stance, next_formation, next_spacing)

func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _try_fire_at(target_ship: CombatShip) -> void:
	if weapon_cooldown > 0.0 or definition.weapons.is_empty() or not is_instance_valid(target_ship):
		return
	var weapon := definition.weapons[0]
	if global_position.distance_to(target_ship.global_position) > weapon.range_m:
		return
	if _is_resolute() and weapon.role == "missile" and not missile_launch_points.is_empty():
		_queue_resolute_missile_salvo(weapon, target_ship)
		weapon_cooldown = weapon.cooldown_seconds
		return
	var fire_direction := intercept_direction(global_position, target_ship.global_position, target_ship.velocity, weapon.projectile_speed_mps)
	spawn_projectile(weapon, global_position + fire_direction * collision_radius_m, fire_direction, target_ship if weapon.tracks_target else null)
	weapon_cooldown = weapon.cooldown_seconds

func _queue_resolute_missile_salvo(weapon: WeaponDefinition, target_ship: CombatShip) -> void:
	pending_missile_salvo.clear()
	for cell_index in mini(RESOLUTE_VLS_COMPARTMENT_COUNT, missile_launch_points.size()):
		pending_missile_salvo.append({"cell_index": cell_index, "weapon": weapon, "target": target_ship})
	missile_salvo_timer = 0.0
	_launch_next_resolute_missile()

func _process_pending_missile_salvo(delta: float) -> void:
	if pending_missile_salvo.is_empty():
		return
	missile_salvo_timer -= delta
	while missile_salvo_timer <= 0.0 and not pending_missile_salvo.is_empty():
		_launch_next_resolute_missile()

func _launch_next_resolute_missile() -> void:
	if pending_missile_salvo.is_empty():
		return
	var launch_data: Dictionary = pending_missile_salvo.pop_front()
	var target_ship := launch_data.get("target") as CombatShip
	if not is_instance_valid(target_ship) or target_ship.is_destroyed:
		pending_missile_salvo.clear()
		return
	var cell_index := int(launch_data.get("cell_index", 0))
	if cell_index < 0 or cell_index >= missile_launch_points.size():
		return
	var launch_point := missile_launch_points[cell_index]
	_animate_resolute_vls_hatch(cell_index)
	var local_direction := Vector3(-0.055 if launch_point.position.x < 0.0 else 0.055, 1.0, -0.02 + 0.02 * float(cell_index / 2)).normalized()
	var launch_direction := (global_transform.basis * local_direction).normalized()
	var weapon := launch_data.get("weapon") as WeaponDefinition
	var missile := spawn_projectile(weapon, launch_point.global_position, launch_direction, target_ship if weapon.tracks_target else null)
	missile.damage *= RESOLUTE_SALVO_DAMAGE_SCALE
	missile.configure_vertical_launch(RESOLUTE_VERTICAL_CLEARANCE_M)
	missile_salvo_timer += RESOLUTE_SALVO_INTERVAL_SECONDS

func _process_resolute_flak(delta: float) -> void:
	if resolute_flak_weapon == null or flak_battery_mounts.size() != 3:
		return
	for index in flak_battery_cooldowns.size():
		flak_battery_cooldowns[index] = maxf(0.0, flak_battery_cooldowns[index] - delta)
	var reserved_targets: Dictionary = {}
	for battery_index in flak_battery_mounts.size():
		if flak_battery_cooldowns[battery_index] > 0.0:
			continue
		var threat := _resolute_flak_target(battery_index, reserved_targets)
		if threat == null:
			continue
		reserved_targets[threat.get_instance_id()] = true
		_fire_resolute_flak_battery(battery_index, threat)

func _resolute_flak_target(battery_index: int, reserved_targets: Dictionary = {}) -> SidebayProjectile:
	var best: SidebayProjectile
	var best_distance := RESOLUTE_FLAK_RANGE_M
	var registry := _combat_registry()
	var candidates: Array = registry.active_projectiles() if registry != null else get_tree().get_nodes_in_group("projectiles")
	for candidate in candidates:
		if not candidate is SidebayProjectile or candidate.expired or not candidate.can_be_intercepted or candidate.team == team:
			continue
		if reserved_targets.has(candidate.get_instance_id()) or not _resolute_flak_can_engage(battery_index, candidate.global_position):
			continue
		var distance := flak_battery_mounts[battery_index].global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _resolute_flak_can_engage(battery_index: int, world_position: Vector3) -> bool:
	if battery_index < 0 or battery_index >= flak_battery_mounts.size():
		return false
	var local_position := to_local(world_position)
	var horizon_overlap := definition.dimensions_m.y * 0.08
	if battery_index < 2:
		if local_position.y < -horizon_overlap:
			return false
		var opposite_side_limit := definition.dimensions_m.x * 0.42
		if battery_index == 0 and local_position.x > opposite_side_limit:
			return false
		if battery_index == 1 and local_position.x < -opposite_side_limit:
			return false
	else:
		if local_position.y > horizon_overlap:
			return false
	return flak_battery_mounts[battery_index].global_position.distance_to(world_position) <= RESOLUTE_FLAK_RANGE_M

func _fire_resolute_flak_battery(battery_index: int, threat: SidebayProjectile) -> void:
	var muzzle := flak_battery_mounts[battery_index]
	var threat_velocity := threat.direction * threat.speed_mps
	var intercept_seconds := intercept_time_seconds(muzzle.global_position, threat.global_position, threat_velocity, resolute_flak_weapon.projectile_speed_mps)
	var intercept_point := threat.global_position + threat_velocity * intercept_seconds
	var fire_direction := muzzle.global_position.direction_to(intercept_point)
	var airburst_distance := minf(RESOLUTE_FLAK_RANGE_M, resolute_flak_weapon.projectile_speed_mps * intercept_seconds)
	var flak_round := spawn_projectile(resolute_flak_weapon, muzzle.global_position, fire_direction)
	flak_round.collision_radius_m = 4.0
	flak_round.configure_airburst(maxf(25.0, airburst_distance), RESOLUTE_FLAK_BLAST_RADIUS_M)
	flak_battery_cooldowns[battery_index] = RESOLUTE_FLAK_COOLDOWN_SECONDS
	flak_battery_fire_counts[battery_index] += 1

static func intercept_direction(origin: Vector3, target_position: Vector3, target_velocity: Vector3, projectile_speed: float) -> Vector3:
	var intercept_time := intercept_time_seconds(origin, target_position, target_velocity, projectile_speed)
	var aim_point := target_position + target_velocity * clampf(intercept_time, 0.0, 12.0)
	return origin.direction_to(aim_point)

static func intercept_time_seconds(origin: Vector3, target_position: Vector3, target_velocity: Vector3, projectile_speed: float) -> float:
	var offset := target_position - origin
	var speed := maxf(1.0, projectile_speed)
	var a := target_velocity.length_squared() - speed * speed
	var b := 2.0 * offset.dot(target_velocity)
	var c := offset.length_squared()
	var intercept_time := 0.0
	if absf(a) < 0.0001:
		if absf(b) > 0.0001:
			intercept_time = maxf(0.0, -c / b)
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root := sqrt(discriminant)
			var first := (-b - root) / (2.0 * a)
			var second := (-b + root) / (2.0 * a)
			if first > 0.0 and second > 0.0:
				intercept_time = minf(first, second)
			else:
				intercept_time = maxf(maxf(first, second), 0.0)
	return intercept_time

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
		weapon.damage * outgoing_damage_multiplier,
		weapon.range_m * 1.15,
		tracked_target,
		2.5 if weapon.tracks_target else 0.0,
		weapon.role in ["missile", "nuclear"],
		weapon.role,
		definition.ship_id
	)
	var vfx := _combat_vfx()
	if vfx != null:
		vfx.spawn_burst("muzzle", start, 1.25 if weapon.role == "nuclear" else (0.72 if weapon.role == "missile" else 0.42))
	return projectile

func receive_damage(amount: float, source_entity_id: StringName = &"", impact_context: Dictionary = {}) -> Dictionary:
	var layer_damage := {"shields": 0.0, "armor": 0.0, "hull": 0.0}
	if is_destroyed:
		return layer_damage
	var resolved_amount := maxf(0.0, amount * incoming_damage_multiplier)
	if resolved_amount <= 0.0:
		var blocked_vfx := _combat_vfx()
		if blocked_vfx != null:
			blocked_vfx.spawn_damage_effect(global_position, true, 0.45)
		return layer_damage
	var shielded := damage_state.shields > 0.0
	layer_damage = damage_state.apply_damage(resolved_amount)
	_update_damage_presentation()
	var vfx := _combat_vfx()
	if vfx != null:
		var effect_position: Vector3 = impact_context.get("position", global_position)
		vfx.spawn_damage_effect(effect_position, shielded, clampf(resolved_amount / 24.0, 0.55, 1.8))
	damage_received.emit(stable_entity_id, source_entity_id, resolved_amount)
	damage_resolved.emit(stable_entity_id, source_entity_id, layer_damage.duplicate(true), impact_context.duplicate(true))
	return layer_damage

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
		vfx.spawn_ship_explosion(global_position, 2.2)
	ship_destroyed.emit(stable_entity_id)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.45)
	tween.tween_callback(queue_free)

func layer_percentages() -> Vector3:
	return damage_state.normalized_layers() if damage_state != null else Vector3.ZERO
