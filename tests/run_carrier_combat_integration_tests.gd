extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier := PlayerCarrier.new()
	root.add_child(carrier)
	carrier.configure(_carrier_definition(), &"test_carrier", &"friendly", Color(0.2, 0.4, 0.6))
	carrier.configure_carrier_operations({}, {}, {})
	var healthy_command_range := carrier.effective_command_range_m()
	carrier.carrier_operations.subsystem_condition["command_cic"] = 0.25
	_assert_true(carrier.effective_command_range_m() < healthy_command_range * 0.3, "command/CIC condition directly constrains carrier command-link reach")
	carrier.carrier_operations.subsystem_condition["command_cic"] = 1.0

	var impact_world := carrier.global_transform * Vector3(-18.0, 0.0, 0.0)
	var layer_damage := carrier.receive_damage(48.0, &"test_hostile", {
		"position": impact_world,
		"weapon_role": "missile",
		"projectile_damage": 48.0,
	})
	_assert_true(float(layer_damage.get("hull", 0.0)) == 48.0, "receive_damage returns the resolved layer-damage result")
	_assert_true(float(carrier.carrier_operations.subsystem_condition.port_deck) < 1.0, "localized hull penetration damages the deterministic port-deck subsystem")
	_assert_true(carrier.carrier_operations.hazard_severity(&"port_deck", &"fire") > 0.0, "missile penetration forwards its role and creates an internal fire")

	carrier.carrier_operations.subsystem_condition["port_deck"] = 0.0
	_assert_true(not carrier.is_flight_deck_operational(&"port"), "failed deck blocks normal launch operations")
	carrier.carrier_operations.assign_damage_control_team(0, &"port_deck")
	carrier.carrier_operations.tick(4.1)
	_assert_true(carrier.is_flight_deck_operational(&"port"), "arrived damage control restores emergency deck functionality")

	var target := CombatShip.new()
	root.add_child(target)
	target.configure(_target_definition(), &"test_target", &"hostile", Color(0.7, 0.2, 0.15))
	target.global_position = Vector3(0.0, 0.0, -800.0)
	carrier.carrier_operations.stores["guided_missiles"] = 3
	_assert_true(carrier.fire_missile(target), "carrier fires a partial final missile salvo when stores remain")
	_assert_true(carrier.last_missile_salvo_count == 3 and int(carrier.carrier_operations.stores.guided_missiles) == 0, "missile salvo count and magazine consumption match actual stores")
	carrier.missile_cooldown = 0.0
	_assert_true(not carrier.fire_missile(target) and carrier.carrier_operations.last_store_message.contains("depleted"), "empty guided magazine rejects fire with a clear explanation")

	carrier.carrier_operations.stores["flak_rounds"] = 7
	carrier.flak_cooldown = 0.0
	_assert_true(carrier.fire_flak(target), "seven-round flak pattern fires toward a locked target when exactly one spread remains")
	_assert_true(int(carrier.carrier_operations.stores.flak_rounds) == 0 and carrier.pending_flak_shots.size() == 6, "flak spread consumes seven actual rounds and retains its authored pattern")
	carrier.flak_cooldown = 0.0
	_assert_true(not carrier.fire_flak(target), "empty flak magazine rejects the next flak-wall burst")

	carrier.free()
	if is_instance_valid(target):
		target.free()
	for node in root.get_children():
		if node is SidebayProjectile:
			node.free()
	if failures.is_empty():
		print("PASS: carrier damage context, emergency operations, and finite weapon stores")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d carrier combat integration assertion(s)" % failures.size())
		quit(1)


func _carrier_definition() -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"cvn_sidebay"
	definition.display_name = "Test Sidebay"
	definition.role = "carrier"
	definition.dimensions_m = Vector3(42.0, 20.0, 120.0)
	definition.maximum_speed_mps = 100.0
	definition.acceleration_mps2 = 20.0
	definition.rotation_speed_radians = 0.5
	definition.command_range_m = 7000.0
	var layers := DamageLayerDefinition.new()
	layers.max_shields = 0.0
	layers.max_armor = 0.0
	layers.max_hull = 1000.0
	layers.armor_mitigation = 0.0
	definition.damage_layers = layers
	definition.weapons = [
		_weapon(&"test_flak", "flak", 3200.0, 0.24, 12.0, 1900.0, false),
		_weapon(&"test_missile", "missile", 8500.0, 6.5, 62.0, 720.0, true),
		_weapon(&"test_nuclear", "nuclear", 10000.0, 999.0, 520.0, 520.0, true),
	]
	return definition


func _target_definition() -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"test_target"
	definition.display_name = "Test Target"
	definition.role = "frigate"
	definition.dimensions_m = Vector3(20.0, 8.0, 50.0)
	definition.damage_layers = DamageLayerDefinition.new()
	return definition


func _weapon(id: StringName, role: String, range_m: float, cooldown: float, damage: float, speed: float, tracks: bool) -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.weapon_id = id
	weapon.role = role
	weapon.range_m = range_m
	weapon.cooldown_seconds = cooldown
	weapon.damage = damage
	weapon.projectile_speed_mps = speed
	weapon.tracks_target = tracks
	return weapon


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
