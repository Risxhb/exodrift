class_name ExodriftEncounterDirector
extends Node

var battle: Node
var sector_index: int = 0
var node_id: StringName = &""
var layout_id: StringName = &"standalone"
var is_sector_command: bool = false
var boss_phase: int = 0
var elapsed_seconds: float = 0.0
var support_ships: Array[CombatShip] = []
var reinforcement_ships: Array[CombatShip] = []
var reinforcement_triggered: bool = false
var phase_history: Array[StringName] = []

func configure(host_battle: Node) -> void:
	battle = host_battle
	sector_index = clampi(int(battle.campaign_sector_index), 0, 2)
	node_id = StringName(battle.campaign_node_id)
	is_sector_command = bool(battle.hosted_campaign) and String(node_id).ends_with("_boss")
	layout_id = _select_layout_id()
	_apply_layout()
	_apply_sensor_condition()
	if is_sector_command:
		_configure_sector_command()
	elif layout_id in [&"relay_ambush", &"needle_trap", &"breach_corridor"]:
		_spawn_fortification()

func _process(delta: float) -> void:
	if battle == null or bool(battle.battle_finished):
		return
	elapsed_seconds += delta
	if is_sector_command:
		_process_sector_command()
	elif not reinforcement_triggered and elapsed_seconds >= _reinforcement_time():
		_spawn_layout_reinforcement()


func apply_opening_doctrine() -> void:
	if battle == null:
		return
	match sector_index:
		0:
			battle.hostile_command.set_stance(&"defensive")
			battle.hostile_command.set_formation(&"column", &"tight")
			_issue_entity_order(battle.hostile_command, FleetOrder.OrderType.ATTACK, battle.carrier.stable_entity_id)
			battle.hostile_corvette.set_stance(&"defensive")
			battle.hostile_corvette.set_formation(&"screen", &"standard")
			_issue_entity_order(battle.hostile_corvette, FleetOrder.OrderType.ESCORT, battle.hostile_command.stable_entity_id)
			battle.hostile_fighters.set_stance(&"balanced")
			battle.hostile_fighters.set_formation(&"screen", &"wide")
			_issue_entity_order(battle.hostile_fighters, FleetOrder.OrderType.INTERCEPT, battle.carrier.stable_entity_id)
		1:
			battle.hostile_command.set_stance(&"balanced")
			battle.hostile_command.set_formation(&"line", &"wide")
			_issue_entity_order(battle.hostile_command, FleetOrder.OrderType.ATTACK, battle.carrier.stable_entity_id)
			battle.hostile_corvette.set_stance(&"aggressive")
			_issue_entity_order(battle.hostile_corvette, FleetOrder.OrderType.INTERCEPT, battle.carrier.stable_entity_id)
			battle.hostile_fighters.set_stance(&"aggressive")
			battle.hostile_fighters.set_formation(&"wedge", &"wide")
			_issue_entity_order(battle.hostile_fighters, FleetOrder.OrderType.ATTACK, battle.carrier.stable_entity_id)
		_:
			battle.hostile_command.set_stance(&"defensive")
			battle.hostile_command.set_formation(&"column", &"standard")
			_issue_entity_order(battle.hostile_command, FleetOrder.OrderType.ATTACK, battle.carrier.stable_entity_id)
			battle.hostile_corvette.set_stance(&"defensive")
			battle.hostile_corvette.set_formation(&"screen", &"tight")
			_issue_entity_order(battle.hostile_corvette, FleetOrder.OrderType.ESCORT, battle.hostile_command.stable_entity_id)
			battle.hostile_fighters.set_stance(&"balanced")
			battle.hostile_fighters.set_formation(&"line", &"standard")
			_issue_entity_order(battle.hostile_fighters, FleetOrder.OrderType.INTERCEPT, battle.carrier.stable_entity_id)

func _select_layout_id() -> StringName:
	if not bool(battle.hosted_campaign):
		return &"standalone"
	if is_sector_command:
		return [&"acheron_command_net", &"vesper_hunt", &"crucible_citadel"][sector_index]
	var index := absi((String(node_id) + ":%d" % int(battle.campaign_objective_type)).hash()) % 3
	var layouts := [
		[&"picket_line", &"crossfire_gap", &"relay_ambush"],
		[&"high_low_pincer", &"ion_veil", &"needle_trap"],
		[&"breach_corridor", &"carapace_screen", &"fortress_approach"]
	]
	return layouts[sector_index][index]

func _apply_layout() -> void:
	var layouts := {
		&"picket_line": [Vector3(1050, 280, -6800), Vector3(-1300, -170, -5350), Vector3(100, 420, -4800)],
		&"crossfire_gap": [Vector3(-1550, 360, -6300), Vector3(1450, -260, -5150), Vector3(-880, 620, -4550)],
		&"relay_ambush": [Vector3(0, 650, -6950), Vector3(250, -320, -4900), Vector3(1350, 180, -5250)],
		&"high_low_pincer": [Vector3(-1650, 620, -6650), Vector3(1750, -420, -5100), Vector3(-620, 760, -4650)],
		&"ion_veil": [Vector3(1250, -540, -6400), Vector3(-1450, 680, -5000), Vector3(850, -720, -4450)],
		&"needle_trap": [Vector3(0, 900, -7100), Vector3(-300, -650, -5000), Vector3(1500, 120, -5350)],
		&"breach_corridor": [Vector3(150, -120, -7600), Vector3(-420, 520, -5800), Vector3(1180, -260, -5200)],
		&"carapace_screen": [Vector3(-1100, 700, -7200), Vector3(1250, -620, -5700), Vector3(-1450, -120, -5050)],
		&"fortress_approach": [Vector3(0, 0, -7900), Vector3(0, 760, -5700), Vector3(0, -780, -5000)],
		&"acheron_command_net": [Vector3(0, 350, -7050), Vector3(-1250, -120, -5400), Vector3(1100, 520, -4900)],
		&"vesper_hunt": [Vector3(-1200, 780, -7100), Vector3(1550, -520, -5300), Vector3(-950, -700, -4750)],
		&"crucible_citadel": [Vector3(0, 0, -8000), Vector3(-950, 620, -5950), Vector3(1200, -480, -5400)]
	}
	if not layouts.has(layout_id):
		return
	var positions: Array = layouts[layout_id]
	battle.hostile_command.global_position = positions[0]
	battle.hostile_corvette.global_position = positions[1]
	# _deploy_initial_forces reads the immutable sector profile, so retain an explicit override.
	battle.set_meta("encounter_fighter_position", positions[2])
	_apply_objective_geometry()

func _apply_objective_geometry() -> void:
	var offset := Vector3.ZERO
	match layout_id:
		&"crossfire_gap", &"ion_veil", &"carapace_screen":
			offset = Vector3(850.0, 260.0, -300.0)
		&"relay_ambush", &"needle_trap", &"fortress_approach":
			offset = Vector3(-720.0, -180.0, -520.0)
	if is_instance_valid(battle.objective_ship):
		battle.objective_ship.global_position += offset
	if battle.objective_destination != Vector3.ZERO:
		battle.objective_destination += offset
		if is_instance_valid(battle.objective_marker):
			battle.objective_marker.global_position = battle.objective_destination

func _apply_sensor_condition() -> void:
	if layout_id in [&"ion_veil", &"carapace_screen", &"vesper_hunt"]:
		battle.sensors.passive_range_multiplier = 0.68 if layout_id == &"ion_veil" else 0.78
		battle.sensors.uncertainty_multiplier = 1.55 if layout_id == &"ion_veil" else 1.3
		_spawn_interference_volume()

func _spawn_interference_volume() -> void:
	var volume := MeshInstance3D.new()
	volume.name = "SensorInterferenceVolume"
	var mesh := SphereMesh.new()
	mesh.radius = 950.0
	mesh.height = 1900.0
	mesh.radial_segments = 20
	mesh.rings = 10
	volume.mesh = mesh
	volume.position = Vector3(0.0, 80.0, -2600.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.42, 0.12, 0.62, 0.055)
	material.emission_enabled = true
	material.emission = Color(0.22, 0.05, 0.34) * 0.7
	volume.material_override = material
	volume.add_to_group("quality_backdrop")
	volume.set_meta("quality_layer", 2)
	battle.add_child(volume)

func _configure_sector_command() -> void:
	match sector_index:
		0:
			battle.hostile_command.incoming_damage_multiplier = 0.12
			_set_command_objective("ACHERON COMMAND NET  Break the screen to expose the command frigate")
			_announce(&"acheron_lock", "ACHERON: Screen elements, hold the command net.")
		1:
			battle.hostile_command.incoming_damage_multiplier = 0.55
			_set_command_objective("VESPER HUNT  Strip the lance cruiser's shields and survive its pincer")
			_announce(&"vesper_stalk", "VESPER: Your carrier is already inside our firing geometry.")
		2:
			battle.hostile_command.incoming_damage_multiplier = 0.0
			_spawn_crucible_anchors()
			_set_command_objective("CRUCIBLE CITADEL  Destroy both shield anchors to expose the Regent")
			_announce(&"crucible_citadel", "SENSORS: Two carapace anchors are feeding the Regent's shield lattice.")

func _process_sector_command() -> void:
	if not is_instance_valid(battle.hostile_command):
		return
	match sector_index:
		0:
			if boss_phase == 0 and bool(battle.hostile_corvette_destroyed) and bool(battle.hostile_fighters_destroyed):
				boss_phase = 1
				battle.hostile_command.set_stance(&"aggressive")
				_issue_entity_order(battle.hostile_command, FleetOrder.OrderType.ATTACK, battle.carrier.stable_entity_id)
				battle.hostile_command.incoming_damage_multiplier = 1.0
				battle.hostile_command.outgoing_damage_multiplier = 1.15
				battle.hostile_command.definition.weapons[0].cooldown_seconds *= 0.78
				_set_command_objective("ACHERON COMMAND NET  Command frigate exposed — destroy it")
				_announce(&"acheron_exposed", "GUNNERY: Command net collapsed. The frigate is exposed.")
		1:
			var layers: Vector3 = battle.hostile_command.layer_percentages()
			if boss_phase == 0 and layers.x <= 0.15:
				boss_phase = 1
				battle.hostile_command.set_stance(&"aggressive")
				_issue_entity_order(battle.hostile_command, FleetOrder.OrderType.INTERCEPT, battle.carrier.stable_entity_id)
				battle.hostile_command.incoming_damage_multiplier = 1.0
				battle.hostile_command.definition.maximum_speed_mps *= 1.22
				battle.hostile_command.definition.weapons[0].cooldown_seconds *= 0.68
				_spawn_named_reinforcement("vesper_second_needle", "Vesper Second Needle", Vector3(1700, 720, -3000), Color(0.76, 0.18, 0.92), 0.9)
				_set_command_objective("VESPER HUNT  Lance shields broken — survive the second pincer")
				_announce(&"vesper_turn", "VESPER: Second Needle, close the other side of the trap.")
			elif boss_phase == 1 and layers.z <= 0.5:
				boss_phase = 2
				battle.hostile_command.set_stance(&"evade_return")
				var withdrawal_direction: Vector3 = battle.carrier.global_position.direction_to(battle.hostile_command.global_position)
				_issue_position_order(battle.hostile_command, FleetOrder.OrderType.WITHDRAW, battle.hostile_command.global_position + withdrawal_direction * 4200.0)
				battle.hostile_command.outgoing_damage_multiplier = 1.3
				_announce(&"vesper_desperate", "VESPER: All ships, burn through the carrier before we break.")
		2:
			if boss_phase == 0 and _living_support_count() == 0:
				boss_phase = 1
				battle.hostile_command.set_stance(&"balanced")
				_issue_entity_order(battle.hostile_command, FleetOrder.OrderType.ATTACK, battle.carrier.stable_entity_id)
				battle.hostile_command.incoming_damage_multiplier = 1.0
				_set_command_objective("CRUCIBLE CITADEL  Shield lattice broken — attack the Regent")
				_announce(&"crucible_exposed", "SENSORS: Lattice failure. Regent armor is exposed.")
			var crucible_layers: Vector3 = battle.hostile_command.layer_percentages()
			if boss_phase == 1 and crucible_layers.z <= 0.62:
				boss_phase = 2
				battle.hostile_command.set_stance(&"aggressive")
				_issue_entity_order(battle.hostile_command, FleetOrder.OrderType.INTERCEPT, battle.carrier.stable_entity_id)
				battle.hostile_command.outgoing_damage_multiplier = 1.28
				battle.hostile_command.definition.weapons[0].cooldown_seconds *= 0.7
				_spawn_named_reinforcement("crucible_bastion", "Crucible Ember Bastion", Vector3(-1450, -620, -3600), Color(0.82, 0.34, 0.08), 1.2)
				_set_command_objective("CRUCIBLE CITADEL  Core opening — destroy the Regent under reinforcement fire")
				_announce(&"crucible_core", "GUNNERY: Regent core aperture opening. Weapons free.")
			elif boss_phase == 2 and crucible_layers.z <= 0.25:
				boss_phase = 3
				battle.hostile_command.incoming_damage_multiplier = 1.3
				battle.hostile_command.outgoing_damage_multiplier = 1.45
				_announce(&"crucible_last", "CRUCIBLE: The citadel burns. The command will not yield.")

func _spawn_crucible_anchors() -> void:
	for index in 2:
		var side := -1.0 if index == 0 else 1.0
		var definition := _support_definition(StringName("crucible_anchor_%d" % (index + 1)), "Crucible Shield Anchor %d" % (index + 1), "anchor", 0.9, true)
		_spawn_support(definition, StringName("crucible_anchor_%d" % (index + 1)), Vector3(side * 1150.0, side * 260.0, -5200.0), Color(0.58, 0.16, 0.86), false, support_ships)

func _spawn_fortification() -> void:
	var definition := _support_definition(StringName("%s_platform" % String(layout_id)), "Hostile Fire-Control Platform", "installation", 0.72, true)
	definition.weapons = [_weapon_definition(&"platform_beam", "Platform Lance", "cannon", 2600.0, 1.4, 22.0, 980.0)]
	_spawn_support(definition, StringName("%s_platform" % String(layout_id)), Vector3(0.0, 420.0, -3000.0), Color(0.72, 0.16, 0.16), true, support_ships)

func _spawn_layout_reinforcement() -> void:
	reinforcement_triggered = true
	match layout_id:
		&"crossfire_gap":
			_spawn_named_reinforcement("acheron_flanker", "Acheron Flank Corvette", Vector3(1850, 150, -2800), Color(0.72, 0.18, 0.08), 0.7)
		&"ion_veil":
			_spawn_named_reinforcement("vesper_veil_needle", "Vesper Veil Needle", Vector3(-1650, -500, -2500), Color(0.7, 0.16, 0.86), 0.75)
		&"carapace_screen":
			_spawn_named_reinforcement("crucible_screen", "Crucible Carapace Screen", Vector3(1500, 580, -3100), Color(0.76, 0.38, 0.08), 1.05)

func _reinforcement_time() -> float:
	return 18.0 if layout_id in [&"crossfire_gap", &"ion_veil", &"carapace_screen"] else INF

func _spawn_named_reinforcement(entity_name: String, display_name: String, position_value: Vector3, color: Color, strength: float) -> CombatShip:
	var entity_id := StringName(entity_name)
	var definition := _support_definition(entity_id, display_name, "corvette", strength, false)
	definition.weapons = [_weapon_definition(StringName("%s_weapon" % entity_name), "Reinforcement Cannon", "cannon", 2100.0, 0.9, 20.0 * strength, 960.0)]
	var ship := _spawn_support(definition, entity_id, position_value, color, true, reinforcement_ships)
	_issue_entity_order(ship, FleetOrder.OrderType.INTERCEPT, battle.carrier.stable_entity_id)
	_announce(StringName("%s_arrival" % entity_name), "%s entering the battlespace." % display_name.to_upper())
	return ship


func _issue_entity_order(group: Node, order_type: FleetOrder.OrderType, entity_id: StringName) -> void:
	if not is_instance_valid(group):
		return
	var order := FleetOrder.at_entity(order_type, entity_id, battle.elapsed_seconds)
	order.requires_command_link = false
	group.issue_order(order)


func _issue_position_order(group: Node, order_type: FleetOrder.OrderType, position_value: Vector3) -> void:
	if not is_instance_valid(group):
		return
	var order := FleetOrder.at_position(order_type, position_value, battle.elapsed_seconds)
	order.requires_command_link = false
	group.issue_order(order)

func _spawn_support(definition: ShipDefinition, entity_id: StringName, position_value: Vector3, color: Color, armed: bool, collection: Array[CombatShip]) -> CombatShip:
	var ship := CombatShip.new()
	battle.add_child(ship)
	ship.configure(definition, entity_id, &"hostile", color)
	ship.global_position = position_value
	ship.ai_enabled = armed
	ship.set_stance(&"aggressive" if armed else &"defensive")
	ship.set_formation(&"column", &"wide")
	ship.ship_destroyed.connect(_on_support_destroyed.bind(ship))
	if armed:
		var order := FleetOrder.at_entity(FleetOrder.OrderType.ATTACK, battle.carrier.stable_entity_id, battle.elapsed_seconds)
		order.requires_command_link = false
		ship.issue_order(order)
	collection.append(ship)
	return ship

func _on_support_destroyed(_entity_id: StringName, _ship: CombatShip) -> void:
	battle.destroyed_hostile_count += 1

func _living_support_count() -> int:
	var living := 0
	for ship in support_ships:
		if is_instance_valid(ship) and not ship.is_destroyed:
			living += 1
	return living

func _support_definition(id_value: StringName, name_value: String, role_value: String, strength: float, stationary: bool) -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = id_value
	definition.display_name = name_value
	definition.role = role_value
	definition.dimensions_m = Vector3(18.0, 12.0, 38.0) * clampf(strength, 0.7, 1.3)
	definition.acceleration_mps2 = 0.0 if stationary else 52.0
	definition.maximum_speed_mps = 0.0 if stationary else 285.0
	definition.rotation_speed_radians = 0.0 if stationary else 1.1
	definition.signature = 0.92
	var layers := DamageLayerDefinition.new()
	layers.max_shields = 140.0 * strength * battle.campaign_threat_multiplier
	layers.max_armor = 175.0 * strength * battle.campaign_threat_multiplier
	layers.max_hull = 210.0 * strength * battle.campaign_threat_multiplier
	layers.shield_regeneration_per_second = 3.0
	layers.armor_mitigation = 0.18
	definition.damage_layers = layers
	return definition

func _weapon_definition(id_value: StringName, name_value: String, role_value: String, range_value: float, cooldown: float, damage_value: float, speed: float) -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.weapon_id = id_value
	weapon.display_name = name_value
	weapon.role = role_value
	weapon.range_m = range_value
	weapon.cooldown_seconds = cooldown
	weapon.damage = damage_value * battle.campaign_threat_multiplier
	weapon.projectile_speed_mps = speed
	return weapon

func _set_command_objective(message: String) -> void:
	if is_instance_valid(battle.hud):
		battle.hud.set_objective(message)

func _announce(event_id: StringName, message: String) -> void:
	phase_history.append(event_id)
	var recorder := get_node_or_null("/root/PlaytestRecorder") as ExodriftPlaytestRecorder
	if recorder != null:
		recorder.record_event(&"encounter_phase", {"phase_id": String(event_id), "sector": sector_index, "layout": String(layout_id), "boss_phase": boss_phase})
	if is_instance_valid(battle.hud):
		battle.hud.notify(message)
	if is_instance_valid(battle.audio):
		battle.audio.play_radio(message, 0.75 if is_sector_command else 0.5)
