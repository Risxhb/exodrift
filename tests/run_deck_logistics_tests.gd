extends SceneTree

var failures: Array[String] = []
var test_stores: Dictionary = {}

func _initialize() -> void:
	_test_explicit_service_states()
	_test_priorities_and_partial_stores()
	_test_loadout_rules_and_stats()
	_test_disabled_deck_recovery()
	if failures.is_empty():
		print("PASS: carrier flight-deck logistics, priorities, stores, and loadouts")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d deck-logistics assertion(s)" % failures.size())
		quit(1)

func _test_explicit_service_states() -> void:
	var bay := BayOperation.new()
	bay.state = BayOperation.State.DOCKING
	_assert_true(bay.transition(BayOperation.State.REPAIRING), "docking enters explicit repairing")
	_assert_true(bay.is_service_state(), "repairing is a service state")
	_assert_true(bay.transition(BayOperation.State.REFUELING), "repairing advances to refueling")
	_assert_true(bay.transition(BayOperation.State.REARMING), "refueling advances to rearming")
	_assert_true(bay.transition(BayOperation.State.READY), "rearming completes ready")
	bay.state = BayOperation.State.SERVICING
	_assert_true(bay.is_service_state() and bay.transition(BayOperation.State.READY), "legacy servicing remains resumable")

func _test_priorities_and_partial_stores() -> void:
	test_stores = {&"craft_refuel": 1, &"aviation_ordnance": 3}
	var wing := _make_wing(2, 1, 0.0, 0.0)
	wing.configure_deck_logistics(Callable(self, "_consume_test_store"))
	wing.operation.state = BayOperation.State.DOCKING
	wing._begin_service_cycle()
	_assert_true(wing.operation.state == BayOperation.State.REPAIRING, "balanced service begins with repair")
	_assert_true(str(wing.deck_queue_snapshot().task) == "repairing", "deck queue snapshot exposes the current explicit service task")
	wing.operation.state_elapsed_seconds = wing.service_task_duration(BayOperation.State.REPAIRING)
	wing._process_service_task()
	_assert_near(wing.crafts[0].damage_state.armor, 35.0, "balanced service restores 35 percent armor")
	_assert_true(wing.operation.state == BayOperation.State.REFUELING, "repair advances to refuel")
	wing.operation.state_elapsed_seconds = wing.service_task_duration(BayOperation.State.REFUELING)
	wing._process_service_task()
	_assert_true(wing.crafts[0].endurance_seconds == 100.0 and wing.crafts[1].endurance_seconds == 0.0, "one refuel unit services one craft and leaves a valid partial result")
	_assert_true(wing.operation.state == BayOperation.State.REARMING, "refuel advances to rearm")
	wing.operation.state_elapsed_seconds = wing.service_task_duration(BayOperation.State.REARMING)
	wing._process_service_task()
	_assert_true(wing.operation.state == BayOperation.State.READY and wing.total_ammunition() == 5, "finite aviation rounds are distributed without inventing stores")

	var repair_first := _make_wing(1, 4, 100.0, 0.0)
	repair_first.set_service_priority(&"repair_first")
	repair_first._complete_repairs()
	_assert_near(repair_first.crafts[0].damage_state.armor, 60.0, "repair-first restores 60 percent armor")
	var balanced_duration := repair_first.definition.service_seconds * 0.25
	_assert_true(repair_first.service_task_duration(BayOperation.State.REFUELING) > balanced_duration, "repair-first tasks run 35 percent slower")

	var rapid := _make_wing(1, 0, 0.0, 0.0)
	rapid.set_service_priority(&"rapid_turn")
	rapid.operation.state = BayOperation.State.DOCKING
	rapid._begin_service_cycle()
	_assert_true(rapid.operation.state == BayOperation.State.REFUELING and rapid.crafts[0].damage_state.armor == 0.0, "rapid turn skips armor repair")
	_assert_near(rapid.service_task_duration(BayOperation.State.REFUELING), rapid.definition.service_seconds * 0.25 * 0.75, "rapid-turn tasks use the 0.75 time multiplier")
	_free_wing(wing)
	_free_wing(repair_first)
	_free_wing(rapid)

func _test_loadout_rules_and_stats() -> void:
	var wing := _make_wing(1, 20, 100.0, 100.0)
	var strike := {
		"loadout_id": &"raptor_strike",
		"display_name": "Raptor Strike",
		"squadron_role": "interceptor",
		"ammunition_per_craft": 12,
		"damage_multiplier": 1.9,
		"cycle_multiplier": 1.35,
		"range_multiplier": 1.25,
	}
	_assert_true(wing.set_loadout(strike), "aboard ready wing accepts a loadout")
	var craft := wing.crafts[0]
	_assert_true(craft.loadout_id == &"raptor_strike" and craft.ammunition == 12, "loadout clamps carried ammunition to its package capacity")
	_assert_near(craft.loadout_damage_multiplier, 1.9, "strike damage multiplier reaches craft")
	_assert_near(craft._preferred_weapon_range(), 1250.0, "strike range multiplier reaches weapon behavior")

	var cap := {
		"loadout_id": &"raptor_cap",
		"squadron_role": "interceptor",
		"ammunition_per_craft": 36,
		"damage_multiplier": 0.75,
		"cycle_multiplier": 0.8,
		"range_multiplier": 0.9,
		"missile_interception": true,
	}
	_assert_true(wing.set_loadout(cap), "package can change while aboard before rearming")
	_assert_true(wing.operation.state == BayOperation.State.REARMING and craft.ammunition == 0 and craft.missile_interception_enabled, "package change discards incompatible ordnance and starts rearming")
	_assert_true(not wing.set_loadout(strike), "loadout change is locked once rearming begins")
	wing.operation.state = BayOperation.State.DEPLOYED
	craft.deployed = true
	_assert_true(not wing.set_loadout(strike), "deployed wing rejects loadout changes")
	_free_wing(wing)

	var multirole := _make_wing(1, 30, 100.0, 100.0)
	_assert_true(multirole.set_loadout(WingLoadoutDefinition.definition(&"raptor_multirole")), "data-driven Raptor Multirole package is accepted")
	_assert_true(multirole.ammunition_capacity_per_craft() == 28, "Raptor Multirole exposes its 28-round capacity")
	_free_wing(multirole)

	var watcher_expectations := {
		&"watcher_recon": {"ammo": 12, "identification": 1.45, "uncertainty": 0.75},
		&"watcher_screen": {"ammo": 24, "interception": true, "defensive_cycle": 0.75},
		&"watcher_rescue": {"ammo": 6, "rescue_range": 350.0},
	}
	for loadout_id in watcher_expectations:
		var watcher := _make_wing(1, 24, 100.0, 100.0)
		watcher.definition.role = "scout"
		var expected: Dictionary = watcher_expectations[loadout_id]
		_assert_true(watcher.set_loadout(WingLoadoutDefinition.definition(loadout_id)), "%s resource is accepted" % String(loadout_id))
		var watcher_craft := watcher.crafts[0]
		_assert_true(watcher.ammunition_capacity_per_craft() == int(expected.ammo), "%s capacity reaches the deck queue" % String(loadout_id))
		_assert_near(watcher.identification_gain_multiplier(), float(expected.get("identification", 1.0)), "%s identification modifier reaches sensors" % String(loadout_id))
		_assert_near(watcher.uncertainty_multiplier(), float(expected.get("uncertainty", 1.0)), "%s uncertainty modifier reaches sensors" % String(loadout_id))
		_assert_true(watcher_craft.missile_interception_enabled == bool(expected.get("interception", false)), "%s interception behavior reaches craft" % String(loadout_id))
		_assert_near(watcher_craft.defensive_cycle_multiplier, float(expected.get("defensive_cycle", 1.0)), "%s defensive cycle reaches craft" % String(loadout_id))
		if loadout_id == &"watcher_screen":
			_assert_near(watcher_craft.weapon_cycle_seconds(1.0), 0.75, "Watcher Screen accelerates normal defensive weapon cycling")
		_assert_near(watcher.escape_pod_recovery_range_m(), float(expected.get("rescue_range", 0.0)), "%s rescue range reaches deployed operations" % String(loadout_id))
		_free_wing(watcher)

func _test_disabled_deck_recovery() -> void:
	var wing := _make_wing(1, 0, 0.0, 0.0)
	wing.set_deck_task_speed_multiplier(2.0)
	_assert_near(wing.launch_interval_seconds(), wing.definition.launch_interval_seconds * 0.5, "flight power and crew efficiency accelerate launch cadence")
	_assert_near(wing.recovery_interval_seconds(), wing.definition.recovery_interval_seconds * 0.5, "flight power and crew efficiency accelerate enabled-deck recovery")
	wing.configure_deck_logistics(Callable(), 1.0, Callable(self, "_deck_disabled"))
	_assert_true(wing.recovery_interval_seconds() > wing.definition.recovery_interval_seconds * 2.8, "disabled deck preserves emergency recovery at reduced speed")
	wing.operation.state = BayOperation.State.DOCKING
	wing._begin_service_cycle()
	_assert_true(wing.operation.is_service_state(), "disabled deck still accepts recovered craft into its service queue")
	_free_wing(wing)

func _make_wing(craft_count: int, ammunition: int, endurance: float, armor: float) -> SidebaySquadron:
	var definition := SquadronDefinition.new()
	definition.role = "interceptor"
	definition.craft_count = craft_count
	definition.ammunition_per_craft = 4
	definition.endurance_seconds = 100.0
	definition.recovery_interval_seconds = 1.0
	definition.service_seconds = 8.0
	var weapon := WeaponDefinition.new()
	weapon.range_m = 1000.0
	var ship := ShipDefinition.new()
	ship.role = "fighter"
	ship.weapons = [weapon]
	var layers := DamageLayerDefinition.new()
	layers.max_shields = 100.0
	layers.max_armor = 100.0
	layers.max_hull = 100.0
	ship.damage_layers = layers
	definition.craft_definition = ship
	var wing := SidebaySquadron.new()
	wing.definition = definition
	for _index in craft_count:
		var craft := FighterCraft.new()
		craft.definition = ship
		craft.home_squadron = wing
		craft.damage_state = DamageState.new(layers)
		craft.damage_state.shields = 20.0
		craft.damage_state.armor = armor
		craft.ammunition = ammunition
		craft.endurance_seconds = endurance
		wing.crafts.append(craft)
	return wing

func _consume_test_store(store_id: StringName, requested: int) -> int:
	var available := int(test_stores.get(store_id, 0))
	var consumed := mini(available, requested)
	test_stores[store_id] = available - consumed
	return consumed

func _deck_disabled(_side: StringName) -> bool:
	return false

func _free_wing(wing: SidebaySquadron) -> void:
	for craft in wing.crafts:
		if is_instance_valid(craft):
			craft.free()
	wing.crafts.clear()
	wing.free()

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _assert_near(value: float, expected: float, message: String, tolerance: float = 0.001) -> void:
	if absf(value - expected) > tolerance:
		failures.append("%s (expected %.3f, got %.3f)" % [message, expected, value])
