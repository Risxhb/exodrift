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
var incoming_damage_multiplier: float = 1.0
var outgoing_damage_multiplier: float = 1.0
var damage_visual_stage: int = 0
var damage_indicator_nodes: Array[MeshInstance3D] = []
var damage_effect_cooldown: float = 0.0
var visual_profile: ShipVisualProfile

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
	visual_profile = ShipVisualProfile.for_ship(StringName(definition.role), team, definition.ship_id)
	_build_visual()
	_build_damage_indicators()

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
	var profile := visual_profile
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
	_build_surface_language(hull_dimensions, profile)
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
			for side in [-1.0, 1.0]:
				_add_visual_block("ResoluteMissileRack", Vector3(side * hull_dimensions.x * 0.22, hull_dimensions.y * 0.65, -hull_dimensions.z * 0.08), Vector3(hull_dimensions.x * 0.16, hull_dimensions.y * 0.12, hull_dimensions.z * 0.26), Color(0.18, 0.28, 0.34), 0.0, profile.hull_texture_path)
				_add_visual_block("ResoluteCellLight", Vector3(side * hull_dimensions.x * 0.22, hull_dimensions.y * 0.72, -hull_dimensions.z * 0.2), Vector3(hull_dimensions.x * 0.09, hull_dimensions.y * 0.03, hull_dimensions.z * 0.025), Color(0.18, 0.78, 1.0), 1.4)
				for cell in 3:
					_add_visual_block("ResoluteLaunchCell%02d" % cell, Vector3(side * hull_dimensions.x * (0.16 + cell * 0.06), hull_dimensions.y * 0.73, -hull_dimensions.z * 0.07), Vector3(hull_dimensions.x * 0.045, hull_dimensions.y * 0.022, hull_dimensions.z * 0.11), Color(0.055, 0.11, 0.14), 0.0)
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

func _make_material(color: Color, emission_energy: float = 0.0, texture_path: String = "") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var profile := visual_profile
	material.albedo_color = color
	material.metallic = profile.surface_metallic if profile != null else 0.65
	material.roughness = profile.surface_roughness if profile != null else 0.42
	if emission_energy <= 0.2:
		material.albedo_color = color.lightened(profile.albedo_lift if profile != null else 0.2)
		var default_texture_path := profile.hull_texture_path if profile != null else ("res://assets/textures/navy_refit_hull.svg" if team == &"friendly" else "res://assets/textures/acheron_forged_hull.svg")
		var resolved_texture_path := texture_path if not texture_path.is_empty() else default_texture_path
		material.albedo_texture = _hull_texture(resolved_texture_path)
		var texture_scale := profile.texture_scale if profile != null else 3.0
		material.uv1_scale = Vector3(texture_scale, texture_scale, texture_scale)
	if emission_energy > 0.0:
		if emission_energy > 0.2:
			material.metallic = 0.18
			material.roughness = 0.2
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
	damage_effect_cooldown = maxf(0.0, damage_effect_cooldown - delta)
	if damage_visual_stage >= 3 and damage_effect_cooldown <= 0.0:
		damage_effect_cooldown = 1.35 if damage_visual_stage == 3 else 0.72
		var damage_vfx := _combat_vfx()
		if damage_vfx != null:
			damage_vfx.spawn_burst("spark", global_position + Vector3(sin(float(Time.get_ticks_msec())) * collision_radius_m * 0.35, collision_radius_m * 0.18, cos(float(Time.get_ticks_msec()) * 0.7) * collision_radius_m * 0.32), 0.5)
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
		weapon.damage * outgoing_damage_multiplier,
		weapon.range_m * 1.15,
		tracked_target,
		2.5 if weapon.tracks_target else 0.0,
		weapon.role == "missile",
		weapon.role,
		definition.ship_id
	)
	var vfx := _combat_vfx()
	if vfx != null:
		vfx.spawn_burst("muzzle", start, 0.72 if weapon.role == "missile" else 0.42)
	return projectile

func receive_damage(amount: float, source_entity_id: StringName = &"") -> void:
	if is_destroyed:
		return
	var resolved_amount := maxf(0.0, amount * incoming_damage_multiplier)
	if resolved_amount <= 0.0:
		var blocked_vfx := _combat_vfx()
		if blocked_vfx != null:
			blocked_vfx.spawn_damage_effect(global_position, true, 0.45)
		return
	var shielded := damage_state.shields > 0.0
	damage_state.apply_damage(resolved_amount)
	_update_damage_presentation()
	var vfx := _combat_vfx()
	if vfx != null:
		vfx.spawn_damage_effect(global_position, shielded, clampf(resolved_amount / 24.0, 0.55, 1.8))
	damage_received.emit(stable_entity_id, source_entity_id, resolved_amount)

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
