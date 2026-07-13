extends SceneTree

const AppScript := preload("res://scripts/app.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_test_exact_service_actions()
	_test_repair_node_crew_recovery()
	_test_after_action_carrier_operations_summary()
	if failures.is_empty():
		print("PASS: carrier service UI, repair-node crew recovery, and operations after-action summary")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d carrier-service assertion(s)" % failures.size())
		quit(1)

func _test_exact_service_actions() -> void:
	for action in [&"repair", &"rearm", &"air_group", &"full_service"]:
		var state := _damaged_run_state()
		var screen := ExodriftLogisticsScreen.new()
		root.add_child(screen)
		screen.configure(state)
		_assert_true(screen.service_buttons.size() == 4, "logistics exposes four carrier service actions")
		var button: Button = screen.service_buttons[action]
		var quoted_cost := state.service_action_cost(action)
		_assert_true(quoted_cost > 0 and button.text.contains("%d SUPPLIES" % quoted_cost), "%s displays its exact quoted supply cost" % String(action))
		match action:
			&"repair":
				_assert_true(button.text.contains("Layers") and button.text.contains("Systems") and button.text.contains("DC spares"), "repair displays every cost component")
			&"rearm":
				_assert_true(button.text.contains("Flak") and button.text.contains("Missiles") and button.text.contains("Nuclear"), "rearm displays every magazine component")
			&"air_group":
				_assert_true(button.text.contains("Craft") and button.text.contains("Wing ammo") and button.text.contains("Ordnance") and button.text.contains("Refuel"), "air-group restoration displays every service component")
			&"full_service":
				_assert_true(button.text.contains("Repair") and button.text.contains("Rearm") and button.text.contains("Air group"), "full service displays all three subtotals")
		var crew_before := state.carrier_operations.crew_current
		var supplies_before := state.supplies
		screen._service_fleet(action)
		_assert_true(state.supplies == supplies_before - quoted_cost, "%s spends exactly its quoted supplies" % String(action))
		_assert_true(state.carrier_operations.crew_current == crew_before, "%s does not replace carrier casualties" % String(action))
		screen.free()

func _test_repair_node_crew_recovery() -> void:
	var state := SidebayRunState.create_new(1919)
	state.supplies = 10
	state.carrier_operations.crew_current = 200
	var app := AppScript.new()
	app.run_state = state
	var node := SidebayCampaignNode.create(&"repair_test", "Repair Test", 1, 0, 0, SidebayCampaignNode.NodeType.REPAIR, 0)
	node.reward_supplies = 7
	var message: String = app._apply_repair_node_support(node)
	_assert_true(state.supplies == 17, "repair node still grants its authored reserve supplies")
	_assert_true(state.carrier_operations.crew_current == 224, "repair node restores at most twenty-four missing crew")
	_assert_true(message.contains("+24 replacement crew") and message.contains("224/240"), "repair-node status reports the exact crew recovery")
	app.free()

func _test_after_action_carrier_operations_summary() -> void:
	var state := SidebayRunState.create_new(8181)
	state.carrier_operations.crew_current = 228
	var node := SidebayCampaignNode.create(&"aar_test", "AAR Test", 1, 0, 0, SidebayCampaignNode.NodeType.COMBAT, 2)
	var report := {
		"outcome": "victory",
		"carrier_shields": 0.8,
		"carrier_armor": 0.7,
		"carrier_hull": 0.9,
		"interceptor_craft_count": 4,
		"scout_craft_count": 2,
		"escort_name": "ISS Harrier",
		"escort_active": true,
		"destroyed_hostile_count": 3,
		"salvage_value": 8,
		"carrier_operations": {
			"persistent": {"crew_current": 228},
			"crew_casualties": 12,
			"stores_expended": {
				"flak_rounds": 49,
				"guided_missiles": 4,
				"aviation_ordnance": 16,
			},
			"officer_incident_outcomes": [
				{"display_name": "Nia Okafor", "outcome": "rescued", "subsystem": "reactor"},
				{"display_name": "Mara Voss", "outcome": "killed", "subsystem": "command_cic"},
			],
		},
	}
	var after_action := ExodriftAfterActionReport.new()
	root.add_child(after_action)
	after_action.configure(state, node, report)
	var text := after_action.summary_label.text
	_assert_true(text.contains("CREW 228/240") and text.contains("CASUALTIES 12"), "after-action report summarizes surviving carrier crew and casualties")
	_assert_true(text.contains("FLAK 49") and text.contains("MISSILES 4") and text.contains("AVIATION 16"), "after-action report summarizes every expended store")
	_assert_true(text.contains("NIA OKAFOR RESCUED") and text.contains("MARA VOSS KILLED"), "after-action report summarizes officer rescue and death outcomes")
	after_action.free()

func _damaged_run_state() -> SidebayRunState:
	var state := SidebayRunState.create_new(4242)
	state.supplies = 999
	state.carrier_shields = 0.45
	state.carrier_armor = 0.55
	state.carrier_hull = 0.65
	state.interceptor_craft_count = maxi(0, state.maximum_interceptor_craft() - 1)
	state.scout_craft_count = maxi(0, state.maximum_scout_craft() - 1)
	state.interceptor_ammunition = maxi(0, state.maximum_interceptor_ammunition() - 14)
	state.scout_ammunition = maxi(0, state.maximum_scout_ammunition() - 8)
	state.carrier_operations.crew_current = 190
	state.carrier_operations.subsystem_condition["propulsion"] = 0.35
	state.carrier_operations.damage_control_spares = 30
	state.carrier_operations.stores["flak_rounds"] = state.carrier_operations.store_capacity(&"flak_rounds") - 280
	state.carrier_operations.stores["guided_missiles"] = state.carrier_operations.store_capacity(&"guided_missiles") - 2
	state.carrier_operations.stores["nuclear_torpedoes"] = 0
	state.carrier_operations.stores["aviation_ordnance"] = state.carrier_operations.store_capacity(&"aviation_ordnance") - 18
	state.carrier_operations.stores["craft_refuel"] = state.carrier_operations.store_capacity(&"craft_refuel") - 2
	return state

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
