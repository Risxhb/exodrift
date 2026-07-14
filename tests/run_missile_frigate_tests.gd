extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var frigate := CombatShip.new()
	root.add_child(frigate)
	frigate.configure(_frigate_definition(), &"test_resolute", &"friendly", Color(0.2, 0.48, 0.68))
	frigate.set_physics_process(false)
	var target := CombatShip.new()
	root.add_child(target)
	target.configure(_target_definition(), &"test_target", &"hostile", Color(0.72, 0.24, 0.12))
	target.global_position = Vector3(0.0, 80.0, -2400.0)
	target.set_physics_process(false)

	_test_modeled_complement(frigate)
	_test_vertical_missile_salvo(frigate, target)
	_clear_projectiles()
	_test_flak_coverage(frigate)

	frigate.free()
	target.free()
	_clear_projectiles()
	await process_frame
	if failures.is_empty():
		print("PASS: missile frigate VLS salvo, vertical clearance, and three-zone flak coverage")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d missile-frigate assertion(s)" % failures.size())
		quit(1)

func _test_modeled_complement(frigate: CombatShip) -> void:
	_assert_true(frigate.missile_launch_points.size() == 6, "Resolute exposes six functional missile compartment launch points")
	_assert_true(frigate.flak_battery_mounts.size() == 3, "Resolute exposes exactly three functional flak battery mounts")
	_assert_true(frigate.definition.weapons.size() == 2 and frigate.resolute_flak_weapon != null, "Resolute configures missiles as its main weapon and flak as its secondary battery")
	_assert_true(frigate.find_child("ResoluteDorsalFlakBattery00", true, false) != null and frigate.find_child("ResoluteDorsalFlakBattery01", true, false) != null, "two flak batteries are modeled on the dorsal hull")
	_assert_true(frigate.find_child("ResoluteVentralFlakBattery", true, false) != null, "one flak battery is modeled on the ventral hull")

func _test_vertical_missile_salvo(frigate: CombatShip, target: CombatShip) -> void:
	frigate.weapon_cooldown = 0.0
	frigate._try_fire_at(target)
	for _launch in 5:
		frigate._process_pending_missile_salvo(CombatShip.RESOLUTE_SALVO_INTERVAL_SECONDS)
	var missiles: Array[SidebayProjectile] = []
	for projectile in get_nodes_in_group("projectiles"):
		if projectile is SidebayProjectile and projectile.source_entity_id == frigate.stable_entity_id and projectile.projectile_role == "missile":
			missiles.append(projectile)
			projectile.set_physics_process(false)
	_assert_true(missiles.size() == 6 and frigate.pending_missile_salvo.is_empty(), "one attack order ripples six missiles from the six VLS compartments")
	var launch_origins: Dictionary = {}
	var total_damage := 0.0
	for missile in missiles:
		launch_origins[Vector3(snappedf(missile.global_position.x, 0.01), snappedf(missile.global_position.y, 0.01), snappedf(missile.global_position.z, 0.01))] = true
		total_damage += missile.damage
		_assert_true(missile.direction.dot(frigate.global_transform.basis.y) > 0.98 and missile.is_clearing_launcher(), "each VLS missile initially climbs ship-up with guidance held for hull clearance")
	_assert_true(launch_origins.size() == 6, "all six missiles originate at distinct compartment hatches")
	_assert_true(is_equal_approx(total_damage, frigate.definition.weapons[0].damage * 6.0 * CombatShip.RESOLUTE_SALVO_DAMAGE_SCALE), "six-round salvo damage uses the authored anti-spike scaling")
	if not missiles.is_empty():
		var test_missile := missiles[0]
		var boost_direction := test_missile.direction
		test_missile._physics_process((CombatShip.RESOLUTE_VERTICAL_CLEARANCE_M - 1.0) / test_missile.speed_mps)
		_assert_true(test_missile.direction.is_equal_approx(boost_direction), "missile does not turn toward its target before clearing the launcher")
		test_missile._physics_process(2.0 / test_missile.speed_mps)
		test_missile._physics_process(0.1)
		_assert_true(not test_missile.direction.is_equal_approx(boost_direction), "missile begins its target turn after the vertical clearance phase")

func _test_flak_coverage(frigate: CombatShip) -> void:
	var upper_port := _hostile_missile(frigate.global_position + Vector3(-420.0, 260.0, -380.0), frigate)
	var upper_starboard := _hostile_missile(frigate.global_position + Vector3(420.0, 260.0, -420.0), frigate)
	var lower := _hostile_missile(frigate.global_position + Vector3(0.0, -300.0, -520.0), frigate)
	for index in frigate.flak_battery_cooldowns.size():
		frigate.flak_battery_cooldowns[index] = 0.0
	frigate._process_resolute_flak(0.0)
	_assert_true(frigate.flak_battery_fire_counts == [1, 1, 1], "both dorsal batteries and the ventral battery independently fire into their assigned coverage")
	_assert_true(frigate._resolute_flak_can_engage(0, upper_port.global_position) and not frigate._resolute_flak_can_engage(0, lower.global_position), "port dorsal flak accepts upper threats and rejects lower threats")
	_assert_true(frigate._resolute_flak_can_engage(1, upper_starboard.global_position) and not frigate._resolute_flak_can_engage(1, lower.global_position), "starboard dorsal flak accepts upper threats and rejects lower threats")
	_assert_true(frigate._resolute_flak_can_engage(2, lower.global_position) and not frigate._resolute_flak_can_engage(2, upper_port.global_position), "ventral flak accepts lower threats and rejects upper threats")
	var flak_round_count := 0
	var flak_rounds: Array[SidebayProjectile] = []
	for projectile in get_nodes_in_group("projectiles"):
		if projectile is SidebayProjectile and projectile.source_entity_id == frigate.stable_entity_id and projectile.projectile_role == "flak":
			flak_round_count += 1
			flak_rounds.append(projectile)
			projectile.set_physics_process(false)
	_assert_true(flak_round_count == 3, "three eligible batteries produce three predicted flak airbursts")
	var threats: Array[SidebayProjectile] = [upper_port, upper_starboard, lower]
	for _step in 100:
		for threat in threats:
			if not threat.expired:
				threat._physics_process(0.02)
		for flak_round in flak_rounds:
			if not flak_round.expired:
				flak_round._physics_process(0.02)
		if threats.all(func(threat: SidebayProjectile) -> bool: return threat.expired):
			break
	_assert_true(threats.all(func(threat: SidebayProjectile) -> bool: return threat.expired), "predicted upper and lower flak airbursts intercept all three inbound missiles")

func _hostile_missile(position_value: Vector3, target: CombatShip) -> SidebayProjectile:
	var missile := SidebayProjectile.new()
	root.add_child(missile)
	missile.configure(&"hostile", &"test_hostile_missile", position_value, position_value.direction_to(target.global_position), 480.0, 20.0, 2600.0, target, 0.0, true, "missile")
	missile.set_physics_process(false)
	return missile

func _frigate_definition() -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"iss_resolute"
	definition.display_name = "ISS Resolute"
	definition.role = "frigate"
	definition.dimensions_m = Vector3(24.0, 12.0, 65.0)
	definition.damage_layers = _damage_layers()
	var missile := WeaponDefinition.new()
	missile.weapon_id = &"resolute_missile"
	missile.display_name = "Resolute Strike Missile"
	missile.role = "missile"
	missile.range_m = 4400.0
	missile.cooldown_seconds = 4.0
	missile.damage = 68.0
	missile.projectile_speed_mps = 570.0
	missile.tracks_target = true
	definition.weapons = [missile]
	return definition

func _target_definition() -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"frigate_target"
	definition.display_name = "Target"
	definition.role = "frigate"
	definition.dimensions_m = Vector3(24.0, 12.0, 65.0)
	definition.damage_layers = _damage_layers()
	return definition

func _damage_layers() -> DamageLayerDefinition:
	var layers := DamageLayerDefinition.new()
	layers.max_shields = 1000.0
	layers.max_armor = 1000.0
	layers.max_hull = 1000.0
	return layers

func _clear_projectiles() -> void:
	for projectile in get_nodes_in_group("projectiles"):
		projectile.free()

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
