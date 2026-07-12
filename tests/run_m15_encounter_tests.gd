extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_authored_layouts()
	await _test_acheron_command_net()
	await _test_vesper_hunt()
	await _test_crucible_citadel()
	if failures.is_empty():
		print("PASS: M15 authored layouts and sector-command phases")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d M15 encounter assertion(s)" % failures.size())
		quit(1)

func _test_authored_layouts() -> void:
	var expected_prefixes := [[&"picket_line", &"crossfire_gap", &"relay_ambush"], [&"high_low_pincer", &"ion_veil", &"needle_trap"], [&"breach_corridor", &"carapace_screen", &"fortress_approach"]]
	for sector in 3:
		var game := await _spawn_battle(sector, StringName("s%d_mid_b" % (sector + 1)))
		_assert_true(game.encounter.layout_id in expected_prefixes[sector], "sector %d chooses one of its three authored layouts" % (sector + 1))
		_assert_true(game.get_meta("encounter_fighter_position", Vector3.ZERO) != Vector3.ZERO, "layout provides explicit fighter geometry")
		await _remove_battle(game)

func _test_acheron_command_net() -> void:
	var game := await _spawn_battle(0, &"s1_boss")
	_assert_true(game.encounter.layout_id == &"acheron_command_net" and is_equal_approx(game.hostile_command.incoming_damage_multiplier, 0.12), "Acheron command net initially screens its command frigate")
	game.hostile_corvette_destroyed = true
	game.hostile_fighters_destroyed = true
	game.encounter._process(0.0)
	_assert_true(game.encounter.boss_phase == 1 and is_equal_approx(game.hostile_command.incoming_damage_multiplier, 1.0), "destroying both Acheron screens exposes the command frigate")
	await _remove_battle(game)

func _test_vesper_hunt() -> void:
	var game := await _spawn_battle(1, &"s2_boss")
	game.hostile_command.damage_state.shields = 0.0
	game.encounter._process(0.0)
	_assert_true(game.encounter.boss_phase == 1 and game.encounter.reinforcement_ships.size() == 1, "Vesper shield break opens phase two and closes the second pincer")
	_assert_true(game.hostile_command.definition.maximum_speed_mps > 205.0 and game.hostile_command.incoming_damage_multiplier == 1.0, "Vesper lance cruiser becomes exposed and more mobile")
	game.hostile_command.damage_state.armor = 0.0
	game.hostile_command.damage_state.hull = game.hostile_command.damage_state.definition.max_hull * 0.45
	game.encounter._process(0.0)
	_assert_true(game.encounter.boss_phase == 2 and game.hostile_command.outgoing_damage_multiplier > 1.0, "damaged Vesper command escalates to its desperate phase")
	await _remove_battle(game)

func _test_crucible_citadel() -> void:
	var game := await _spawn_battle(2, &"s3_boss")
	_assert_true(game.encounter.support_ships.size() == 2 and game.hostile_command.incoming_damage_multiplier == 0.0, "Crucible Regent begins protected by two shield anchors")
	for anchor in game.encounter.support_ships:
		anchor.receive_damage(100000.0, &"test")
	game.encounter._process(0.0)
	_assert_true(game.encounter.boss_phase == 1 and game.hostile_command.incoming_damage_multiplier == 1.0, "destroying both Crucible anchors collapses the shield lattice")
	game.hostile_command.damage_state.shields = 0.0
	game.hostile_command.damage_state.armor = 0.0
	game.hostile_command.damage_state.hull = game.hostile_command.damage_state.definition.max_hull * 0.55
	game.encounter._process(0.0)
	_assert_true(game.encounter.boss_phase == 2 and game.encounter.reinforcement_ships.size() == 1, "Crucible core phase adds its authored Bastion reinforcement")
	game.hostile_command.damage_state.hull = game.hostile_command.damage_state.definition.max_hull * 0.2
	game.encounter._process(0.0)
	_assert_true(game.encounter.boss_phase == 3 and game.hostile_command.incoming_damage_multiplier > 1.0, "Crucible final phase exposes a vulnerable core while increasing pressure")
	await _remove_battle(game)

func _spawn_battle(sector: int, node_id: StringName) -> Node:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.hosted_campaign = true
	game.campaign_sector_index = sector
	game.campaign_node_id = node_id
	game.campaign_objective_type = SidebayCampaignNode.ObjectiveType.COMMAND_STRIKE
	root.add_child(game)
	for _frame in 8:
		await process_frame
	return game

func _remove_battle(game: Node) -> void:
	game.queue_free()
	await process_frame
	await process_frame

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
