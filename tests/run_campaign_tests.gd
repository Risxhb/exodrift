extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_run_state_roundtrip()
	_test_carrier_and_hangar_economy()
	_test_salvage_and_route_logistics()
	_test_personnel_consequences()
	_test_personnel_progression_and_events()
	_test_campaign_graph()
	await _test_application_flow()
	if failures.is_empty():
		print("PASS: Sidebay campaign foundation checks")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d campaign assertion(s)" % failures.size())
		quit(1)

func _test_run_state_roundtrip() -> void:
	var state := SidebayRunState.create_new(424242)
	_assert_true(state.spend_fuel(2) and state.fuel == 8, "run state spends fuel atomically")
	state.supplies = 137
	state.intel = 5
	state.withdrawals = 2
	state.objectives_completed = 3
	state.objectives_failed = 1
	state.personnel_rescued = 7
	state.personnel_lost = 2
	state.straggler_craft_recovered = 2
	state.salvage_recovered = 18
	state.requisition = 4
	var initial_command_lead := state.assigned_person(&"Command")
	var next_command_lead := state.cycle_department_assignment(&"Command")
	state.get_personnel(&"sora_vale").injure("Test injury", 2)
	state.mark_completed(&"s1_entry_a", 0)
	state.reveal(&"s1_boss")
	state.apply_battle_report({
		"carrier_shields": 0.4,
		"carrier_armor": 0.7,
		"carrier_hull": 0.9,
		"interceptor_craft_count": 3,
		"interceptor_ammunition": 51,
		"scout_craft_count": 2,
		"scout_ammunition": 21,
		"escort_active": false
	})
	_assert_true(not state.escort_active and state.lost_escort_ids.has(&"iss_resolute"), "destroyed authored escorts become unique persistent losses")
	var acquisition_message := state.acquire_escort(&"iss_harrier")
	_assert_true(state.escort_active and state.active_escort_id == &"iss_harrier" and state.requisition == 2, "requisition acquires an available authored replacement hull")
	_assert_true(acquisition_message.contains("ISS Harrier"), "escort acquisition reports the fixed hull identity")
	var unlocked := state.unlock_next_module()
	var restored := SidebayRunState.from_dictionary(state.to_dictionary())
	_assert_true(restored != null, "current save version restores")
	_assert_true(restored.seed == 424242 and restored.fuel == 8 and restored.supplies == 137 and restored.intel == 5, "resource values survive serialization")
	_assert_true(restored.withdrawals == 2, "partial-victory withdrawal count survives serialization")
	_assert_true(restored.objectives_completed == 3 and restored.objectives_failed == 1, "objective outcomes survive save migration")
	_assert_true(restored.personnel_rescued == 7 and restored.personnel_lost == 2 and restored.straggler_craft_recovered == 2 and restored.salvage_recovered == 18, "rescue and salvage consequences survive serialization")
	_assert_true(restored.personnel_roster.size() == 12 and restored.assigned_person(&"Command").personnel_id == next_command_lead.personnel_id and restored.assigned_person(&"Command") != initial_command_lead, "authored roster and department assignments survive serialization")
	_assert_true(restored.requisition == 2 and restored.recruitment_pool.size() == 4, "requisition and authored recruitment pool survive serialization")
	_assert_true(restored.get_personnel(&"sora_vale").status == SidebayPersonnelRecord.Status.INJURED and restored.get_personnel(&"sora_vale").injury_severity == 2, "personnel injuries survive serialization")
	_assert_true(restored.completed_node_ids.has(&"s1_entry_a") and restored.revealed_node_ids.has(&"s1_boss"), "stable node IDs survive serialization")
	_assert_true(is_equal_approx(restored.carrier_hull, 0.9) and restored.interceptor_craft_count == 3 and restored.interceptor_ammunition == 51, "fleet damage and wing stores survive serialization")
	_assert_true(restored.escort_active and restored.active_escort_id == &"iss_harrier" and restored.lost_escort_ids.has(&"iss_resolute") and restored.unlocked_module_ids.has(unlocked), "escort acquisition, unique losses, and authored unlocks survive version-7 serialization")
	var service_cost := restored.service_cost()
	_assert_true(service_cost > 0 and restored.service_fleet(), "supplies can service persistent fleet losses")
	_assert_true(restored.supplies == 137 - service_cost and restored.interceptor_craft_count == 4 and restored.active_escort_id == &"iss_harrier", "service restores carrier and wing losses without replacing the selected escort")
	var supplier_state := SidebayRunState.create_new(51515)
	supplier_state.requisition = 3
	_assert_true(supplier_state.acquire_escort(&"iss_bulwark").contains("sector 2"), "limited suppliers gate advanced authored hulls by route sector")
	supplier_state.sector_index = 1
	_assert_true(supplier_state.acquire_escort(&"iss_bulwark").contains("acquired") and supplier_state.requisition == 0, "route progress unlocks the quoted Bulwark supplier offer")
	supplier_state.cycle_escort()
	_assert_true(supplier_state.active_escort_id == &"iss_bulwark" and SidebayRunState.escort_data(&"iss_bulwark").class_name == "Line Frigate", "fleet selection deploys a fixed tactical escort identity")
	var legacy_data := state.to_dictionary()
	legacy_data.save_version = 4
	legacy_data.erase("personnel_roster")
	legacy_data.erase("department_assignments")
	legacy_data.erase("personnel_event_log")
	var migrated := SidebayRunState.from_dictionary(legacy_data)
	_assert_true(migrated != null and migrated.personnel_roster.size() == 12 and migrated.assigned_person(&"Medical") != null, "version-4 saves migrate into the authored personnel roster")
	_assert_true(migrated.recruitment_pool.size() == 4 and migrated.next_recruit_candidate().personnel_id == &"rui_mercer", "pre-M12 saves migrate into the authored recruitment pool")

func _test_carrier_and_hangar_economy() -> void:
	var state := SidebayRunState.create_new(61616)
	state.requisition = 7
	_assert_true(state.acquire_carrier(&"cvn_vanguard").contains("sector 2"), "carrier yards gate authored frames by route sector")
	_assert_true(state.acquire_hangar_complement(&"strike_group").contains("Raptor Strike Group") and state.requisition == 5, "requisition unlocks a fixed authored air-group complement")
	var refit_cost := state.hangar_refit_cost(&"strike_group")
	var supplies_before := state.supplies
	var refit_message := state.select_hangar_complement(&"strike_group")
	_assert_true(refit_message.contains("deck refit") and state.supplies == supplies_before - refit_cost, "changing hangar complements spends the exact quoted supply refit cost")
	_assert_true(state.maximum_interceptor_craft() == 5 and state.maximum_scout_craft() == 2 and state.interceptor_ammunition == 160 and state.scout_ammunition == 36, "strike complement deploys its fixed craft and ammunition allocation")
	state.sector_index = 1
	_assert_true(state.acquire_carrier(&"cvn_vanguard").contains("acquired") and state.requisition == 2, "route progress unlocks the authored Vanguard carrier frame")
	state.cycle_carrier()
	_assert_true(state.active_carrier_id == &"cvn_vanguard" and SidebayRunState.carrier_data(state.active_carrier_id).weapon_damage > 1.0, "carrier selection deploys a fixed offensive sidegrade")
	var restored := SidebayRunState.from_dictionary(state.to_dictionary())
	_assert_true(restored != null and restored.active_carrier_id == &"cvn_vanguard" and restored.acquired_carrier_ids.has(&"cvn_vanguard"), "selected and acquired carrier frames survive version-8 persistence")
	_assert_true(restored.active_hangar_complement_id == &"strike_group" and restored.acquired_hangar_complement_ids.has(&"strike_group") and restored.maximum_interceptor_craft() == 5, "selected hangar complement and dynamic capacity survive version-8 persistence")
	var legacy := state.to_dictionary()
	legacy.save_version = 7
	var legacy_fleet: Dictionary = legacy.fleet
	legacy_fleet.erase("active_carrier_id")
	legacy_fleet.erase("acquired_carrier_ids")
	legacy_fleet.erase("active_hangar_complement_id")
	legacy_fleet.erase("acquired_hangar_complement_ids")
	legacy.fleet = legacy_fleet
	var migrated := SidebayRunState.from_dictionary(legacy)
	_assert_true(migrated != null and migrated.active_carrier_id == &"cvn_sidebay" and migrated.active_hangar_complement_id == &"balanced_wings", "version-7 saves migrate to the canonical carrier and balanced air group")

func _test_salvage_and_route_logistics() -> void:
	var state := SidebayRunState.create_new(71717)
	var starting_supplies := state.supplies
	var starting_fuel := state.fuel
	_assert_true(state.recover_salvage(10) == 10 and state.salvage_stock == 10 and state.salvage_recovered == 10, "recovered wreckage enters persistent unallocated salvage stock")
	_assert_true(state.allocate_salvage(&"supplies").contains("Fabricate Stores") and state.salvage_stock == 6 and state.supplies == starting_supplies + 10, "fixed salvage recipe converts four stock into ten supplies")
	_assert_true(state.allocate_salvage(&"fuel").contains("Refine Drive Fuel") and state.salvage_stock == 0 and state.fuel == starting_fuel + 1, "fixed salvage recipe converts six stock into one fuel")
	_assert_true(not state.can_allocate_salvage(&"requisition") and state.allocate_salvage(&"requisition").contains("10 salvage required"), "unaffordable salvage allocations are rejected atomically")
	state.select_logistics_posture(&"recovery_rig")
	_assert_true(state.route_fuel_cost(2) == 3 and state.adjusted_salvage_yield(10) == 15, "Recovery Rig trades one route fuel for fifty-percent salvage yield")
	state.recover_salvage(10)
	var requisition_before := state.requisition
	state.allocate_salvage(&"requisition")
	_assert_true(state.salvage_stock == 5 and state.requisition == requisition_before + 1, "salvage stock converts into requisition through a fixed fleet claim")
	state.select_logistics_posture(&"lean_burn")
	var fuel_before_route := state.fuel
	var supplies_before_route := state.supplies
	_assert_true(state.spend_route_cost(2) and state.fuel == fuel_before_route - 1 and state.supplies == supplies_before_route - 6, "Lean Burn atomically trades six supplies for one reduced route fuel cost")
	var restored := SidebayRunState.from_dictionary(state.to_dictionary())
	_assert_true(restored != null and restored.salvage_stock == 5 and restored.logistics_posture_id == &"lean_burn", "salvage stock and route posture survive version-9 persistence")
	var legacy := state.to_dictionary()
	legacy.save_version = 8
	legacy.erase("salvage_stock")
	legacy.erase("logistics_posture_id")
	var migrated := SidebayRunState.from_dictionary(legacy)
	_assert_true(migrated != null and migrated.salvage_stock == 0 and migrated.logistics_posture_id == &"balanced_stores", "version-8 saves migrate to empty salvage stock and balanced logistics")

func _test_personnel_consequences() -> void:
	var rescued_state := SidebayRunState.create_new(9191)
	var risk_report := {"rescued_sources": ["scout_wing_01"], "adrift_sources": ["interceptor_wing_01"]}
	_assert_true(rescued_state.personnel_risk_summary(risk_report).contains("Yara Sen RECOVERED") and rescued_state.personnel_risk_summary(risk_report).contains("Sora Vale ADRIFT"), "after-action preview identifies named personnel before the recovery decision")
	var events := rescued_state.resolve_personnel_consequences({
		"outcome": "withdrawal",
		"rescued_sources": ["scout_wing_01"],
		"adrift_sources": ["interceptor_wing_01"]
	}, &"rescue")
	_assert_true(events.size() == 2 and rescued_state.get_personnel(&"yara_sen").status == SidebayPersonnelRecord.Status.INJURED, "rescued sensor personnel receive persistent injuries")
	_assert_true(rescued_state.get_personnel(&"sora_vale").status == SidebayPersonnelRecord.Status.INJURED and rescued_state.get_personnel(&"sora_vale").injury_severity == 1, "medical department reduces rescue injury severity")
	rescued_state.advance_personnel_recovery()
	_assert_true(rescued_state.get_personnel(&"sora_vale").is_available(), "injured personnel recover across completed nodes")
	var lost_state := SidebayRunState.create_new(9292)
	lost_state.resolve_personnel_consequences({"outcome": "withdrawal", "adrift_sources": ["interceptor_wing_01"]}, &"immediate")
	_assert_true(not lost_state.get_personnel(&"sora_vale").is_alive(), "abandoned named personnel are permanently killed")
	_assert_true(lost_state.get_personnel(&"tomas_rook").traits.has("Grieving") and lost_state.assigned_person(&"Flight") == lost_state.get_personnel(&"tomas_rook"), "bonds and department succession react to permanent loss")

func _test_personnel_progression_and_events() -> void:
	var state := SidebayRunState.create_new(30303)
	var injured := state.get_personnel(&"ilya_chen")
	injured.injure("Plasma burns", 2)
	var treatment_cost := state.treatment_cost(injured)
	var supplies_before := state.supplies
	state.treat_next_injury()
	_assert_true(injured.injury_severity == 1 and state.supplies == supplies_before - treatment_cost, "medical treatment spends quoted supplies and reduces injury severity")
	state.treat_next_injury()
	_assert_true(injured.is_available(), "repeated treatment returns an injured officer to active duty")
	injured.missions = 3
	var promotion_supplies := state.supplies
	state.promote_next_candidate()
	_assert_true(injured.skill == 5 and injured.promotion_count == 1 and injured.rank == "Lt. Commander" and state.supplies == promotion_supplies - 20, "eligible officers promote with a persistent rank and skill increase")
	var roster_before := state.personnel_roster.size()
	state.requisition = 1
	var recruitment_message := state.recruit_next_candidate()
	_assert_true(state.personnel_roster.size() == roster_before + 1 and state.get_personnel(&"rui_mercer") != null and state.requisition == 0, "requisition recruits the next authored officer into the persistent roster")
	_assert_true(recruitment_message.contains("Rui Mercer"), "recruitment reports the authored officer outcome")
	var event_state := SidebayRunState.create_new(40404)
	_assert_true(event_state.prepare_operational_event(SidebayCampaignNode.NodeType.INTEL, &"event_test"), "noncombat progression prepares an authored operational event")
	_assert_true(StringName(event_state.pending_operational_event.get("event_id", "")) == &"fractured_watch", "event selection is deterministic from unresolved authored events")
	var event_intel := event_state.intel
	var event_message := event_state.resolve_operational_event(&"share_burden")
	_assert_true(event_state.get_personnel(&"yara_sen").bonds.has(&"mara_voss") and event_state.intel == event_intel + 1, "relationship choice creates a mutual bond and applies its resource outcome")
	_assert_true(event_message.contains("watch") and event_state.resolved_operational_event_ids.has(&"fractured_watch"), "operational outcome is logged and cannot repeat")
	var rare_event := SidebayRunState.operational_event_catalog()[3].duplicate(true)
	event_state.pending_operational_event = rare_event
	event_state.supplies = 20
	event_state.resolve_operational_event(&"take_aboard")
	var rare_unlocked := false
	for candidate in event_state.recruitment_pool:
		if candidate.personnel_id == &"edda_kaine":
			rare_unlocked = candidate.recruitment_unlocked
	_assert_true(rare_unlocked and event_state.supplies == 5, "authored salvage event unlocks a rare officer at its stated cost")
	event_state.pending_operational_event = SidebayRunState.operational_event_catalog()[2].duplicate(true)
	event_state.supplies = 0
	_assert_true(not event_state.can_resolve_event_choice(&"open_reserves") and event_state.can_resolve_event_choice(&"ration_stores"), "operational UI contract disables unaffordable choices without blocking a valid alternative")
	event_state.pending_operational_event.clear()
	event_state.prepare_operational_event(SidebayCampaignNode.NodeType.SALVAGE, &"pending_save")
	var pending_restored := SidebayRunState.from_dictionary(event_state.to_dictionary())
	_assert_true(pending_restored != null and not pending_restored.pending_operational_event.is_empty(), "pending operational decisions survive version-6 serialization")

func _test_campaign_graph() -> void:
	var generator := SidebayCampaignGenerator.new()
	generator.generate(12345)
	var state := SidebayRunState.create_new(12345)
	_assert_true(generator.nodes.size() == 18, "three sectors contain six nodes each")
	_assert_true(generator.get_node(&"s1_entry_a").objective_type == SidebayCampaignNode.ObjectiveType.INTERCEPTION, "contact-line battles use interception objectives")
	_assert_true(generator.get_node(&"s1_mid_b").objective_type == SidebayCampaignNode.ObjectiveType.EXTRACTION, "fleet-screen battles use extraction objectives")
	_assert_true(generator.get_node(&"s2_entry_a").objective_type == SidebayCampaignNode.ObjectiveType.DEFENSE, "second-sector contact line uses defense objectives")
	_assert_true(generator.get_node(&"s3_entry_a").objective_type == SidebayCampaignNode.ObjectiveType.ESCORT, "third-sector contact line uses escort objectives")
	_assert_true(generator.get_node(&"s2_entry_b").objective_type == SidebayCampaignNode.ObjectiveType.CAPTURE, "contested-sector alternate route uses capture objectives")
	_assert_true(generator.get_node(&"s3_mid_b").objective_type == SidebayCampaignNode.ObjectiveType.CAPTURE, "command-zone fleet screen uses capture objectives")
	_assert_true(generator.get_node(&"s1_boss").objective_type == SidebayCampaignNode.ObjectiveType.COMMAND_STRIKE, "boss battles retain command-strike objectives")
	_assert_true(generator.reachable_node_ids(state) == [&"s1_entry_a", &"s1_entry_b"], "new run exposes two opening routes")
	var expected_path: Array[StringName] = [&"s1_entry_a", &"s1_mid_a", &"s1_boss", &"s2_entry_a", &"s2_mid_a", &"s2_boss", &"s3_entry_a", &"s3_mid_a", &"s3_boss"]
	for node_id in expected_path:
		_assert_true(generator.reachable_node_ids(state).has(node_id), "route reaches %s" % node_id)
		var node := generator.get_node(node_id)
		state.mark_completed(node_id, node.sector)
	_assert_true(generator.get_node(&"s3_boss").node_type == SidebayCampaignNode.NodeType.BOSS, "route terminates at strategic command")
	var before_intel := state.intel
	var revealed := generator.reveal_forecast(state)
	_assert_true(revealed.is_empty(), "completed terminal route has no downstream forecast")
	_assert_true(state.intel == before_intel, "generator does not spend resources implicitly")

func _test_application_flow() -> void:
	var app := (load("res://scenes/app.tscn") as PackedScene).instantiate()
	root.add_child(app)
	for _frame in 4:
		await process_frame
	_assert_true(is_instance_valid(app.main_menu) and app.run_state == null, "application starts on the presentation shell before creating a run")
	_assert_true(is_instance_valid(app.main_menu.world_root) and app.main_menu.ships.size() >= 8 and app.main_menu.tracers.size() >= 12, "main menu contains a continuously simulated fleet battle")
	var menu_ship_position: Vector3 = app.main_menu.ships[8].node.position
	for _frame in 6:
		await process_frame
	_assert_true(app.main_menu.ships[8].node.position.distance_to(menu_ship_position) > 1.0, "background fighters continue moving above the compact bottom command row")
	app.main_menu._show_settings()
	app.main_menu.flash_toggle.set_pressed_no_signal(true)
	app.main_menu._on_flash_toggled(true)
	_assert_true(app.main_menu.settings_panel.visible and app.main_menu.reduced_flashes, "settings panel applies and persists reduced-flash accessibility")
	app.main_menu.new_run_requested.emit()
	for _frame in 180:
		if app.run_state != null:
			break
		await process_frame
	_assert_true(app.run_state != null and app.campaign_map.visible and not is_instance_valid(app.main_menu), "new operation transitions from title into the sector map")
	var command_lead_before: StringName = app.run_state.assigned_person(&"Command").personnel_id
	app._open_personnel_screen()
	_assert_true(is_instance_valid(app.personnel_screen) and app.personnel_screen.department_buttons.size() == 6, "sector map opens all six department command cards")
	app.personnel_screen._cycle_department(&"Command")
	_assert_true(app.run_state.assigned_person(&"Command").personnel_id != command_lead_before, "personnel screen changes the assigned department lead")
	app.personnel_screen._recruit_next()
	_assert_true(app.run_state.get_personnel(&"rui_mercer") != null and app.run_state.requisition == 0, "personnel screen recruits an available authored officer")
	app._close_personnel_screen()
	app.run_state.requisition = 7
	app.run_state.sector_index = 1
	app._open_fleet_loadout()
	_assert_true(is_instance_valid(app.fleet_loadout) and not app.fleet_loadout.carrier_acquire_button.disabled and not app.fleet_loadout.hangar_acquire_button.disabled and not app.fleet_loadout.acquire_button.disabled, "fleet screen exposes affordable carrier, air-group, and escort offers")
	app.fleet_loadout._acquire_carrier()
	app.fleet_loadout._cycle_carrier()
	app.fleet_loadout._acquire_hangar()
	app.fleet_loadout._cycle_hangar()
	app.fleet_loadout._acquire_escort()
	app.fleet_loadout._cycle_escort()
	_assert_true(app.run_state.active_carrier_id == &"cvn_vanguard" and app.run_state.active_hangar_complement_id == &"strike_group" and app.run_state.active_escort_id == &"iss_harrier" and app.run_state.requisition == 0, "fleet screen acquires and selects all three authored fleet sidegrade categories")
	app._close_fleet_loadout()
	app.run_state.salvage_stock = 10
	app._open_logistics_screen()
	_assert_true(is_instance_valid(app.logistics_screen) and app.logistics_screen.posture_buttons.size() == 3 and app.logistics_screen.allocation_buttons.size() == 3, "sector map opens all authored route postures and salvage allocations")
	var supplies_before_allocation: int = app.run_state.supplies
	app.logistics_screen._allocate_salvage(&"supplies")
	app.logistics_screen._select_posture(&"lean_burn")
	_assert_true(app.run_state.salvage_stock == 6 and app.run_state.supplies == supplies_before_allocation + 10 and app.run_state.logistics_posture_id == &"lean_burn", "logistics screen allocates salvage and selects a route posture")
	app._close_logistics_screen()
	var starting_fuel: int = app.run_state.fuel
	var starting_route_supplies: int = app.run_state.supplies
	_assert_true(app.campaign_map.node_buttons[&"s1_entry_b"].text.contains("S6"), "campaign nodes quote the active posture's supply overhead")
	app._on_node_selected(&"s1_entry_b")
	_assert_true(app.run_state.current_node_id == &"s1_entry_b", "noncombat node resolves immediately")
	_assert_true(app.run_state.fuel == starting_fuel - 1 and app.run_state.supplies == starting_route_supplies - 6 and app.run_state.intel >= 5, "route executor spends the active posture's quoted fuel and supply costs")
	_assert_true(is_instance_valid(app.operational_event_screen) and not app.run_state.pending_operational_event.is_empty(), "noncombat nodes open a blocking authored operational decision")
	var first_choice: Dictionary = app.run_state.pending_operational_event.get("choices", [])[0]
	app._on_operational_event_choice(StringName(first_choice.get("id", "")))
	_assert_true(not is_instance_valid(app.operational_event_screen) and app.run_state.pending_operational_event.is_empty(), "operational choice applies and returns to the campaign map")
	app._save_run()
	var saved_fuel: int = app.run_state.fuel
	app._show_main_menu()
	app.run_state = null
	_assert_true(not app.main_menu.continue_button.disabled and not app.campaign_map.visible, "saved run enables Continue and title hides the campaign")
	app.main_menu.continue_requested.emit()
	for _frame in 180:
		if app.run_state != null:
			break
		await process_frame
	_assert_true(app.run_state.fuel == saved_fuel and app.campaign_map.visible, "Continue restores the manual save and returns to the campaign")
	app._on_node_selected(&"s1_mid_b")
	for _frame in 6:
		await process_frame
	_assert_true(is_instance_valid(app.active_battle) and not app.campaign_map.visible, "combat node launches existing battle scene")
	_assert_true(app.active_battle.hosted_campaign and app.active_battle.campaign_threat_multiplier > 1.0, "campaign context reaches combat executor")
	_assert_true(app.active_battle.campaign_sector_index == 0 and app.active_battle.guided_onboarding and is_instance_valid(app.active_battle.onboarding), "first sector combat receives campaign identity and the one-run guided orientation")
	var acheron_profile: Dictionary = app.active_battle._sector_encounter_profile()
	app.active_battle.campaign_sector_index = 1
	var vesper_profile: Dictionary = app.active_battle._sector_encounter_profile()
	app.active_battle.campaign_sector_index = 2
	var crucible_profile: Dictionary = app.active_battle._sector_encounter_profile()
	app.active_battle.campaign_sector_index = 0
	_assert_true(acheron_profile.command_name != vesper_profile.command_name and vesper_profile.command_name != crucible_profile.command_name and int(acheron_profile.fighter_count) < int(vesper_profile.fighter_count) and int(vesper_profile.fighter_count) < int(crucible_profile.fighter_count), "sector profiles define distinct hostile fleets with escalating complements")
	_assert_true(app.active_battle.carrier.display_name == "CVN Vanguard" and app.active_battle.carrier.definition.maximum_speed_mps > 290.0, "selected carrier frame identity and mobility profile reach tactical combat")
	_assert_true(app.active_battle.interceptor.crafts.size() == 5 and app.active_battle.scout.crafts.size() == 2 and app.active_battle.interceptor.definition.ammunition_per_craft == 32, "selected hangar complement reaches tactical craft counts and stores")
	_assert_true(app.active_battle.escort.display_name == "ISS Harrier" and app.active_battle.escort.definition.maximum_speed_mps == 330.0 and app.active_battle.escort.definition.weapons[0].can_intercept_projectiles, "selected escort identity and tactical profile reach the combat executor")
	_assert_true(int(app.active_battle.campaign_fleet_snapshot.get("personnel_bonuses", {}).get("command", 0)) > 0, "assigned department skills reach the tactical battle snapshot")
	_assert_true(app.active_battle.carrier.definition.command_range_m > 7000.0 and app.active_battle.carrier.definition.active_sensor_range_m > 12000.0, "department leads apply command and sensor tactical modifiers")
	var victory_report: Dictionary = app.active_battle._create_battle_report()
	victory_report.outcome = "interception"
	app._on_battle_returned(true, victory_report)
	await process_frame
	_assert_true(is_instance_valid(app.after_action_report) and not app.run_state.completed_node_ids.has(&"s1_mid_b"), "battle waits for an after-action decision before advancing")
	var salvage_stock_before: int = app.run_state.salvage_stock
	var supplies_before_salvage: int = app.run_state.supplies
	var victory_reward_supplies: int = app.active_node.reward_supplies
	app._resolve_after_action(&"salvage")
	await process_frame
	_assert_true(app.run_state.completed_node_ids.has(&"s1_mid_b") and app.run_state.battles_won == 1, "victory returns to map and advances run")
	_assert_true(app.run_state.objectives_completed == 1 and app.run_state.salvage_recovered == int(victory_report.get("salvage_value", 0)) and app.run_state.salvage_stock == salvage_stock_before + int(victory_report.get("salvage_value", 0)), "salvage choice persists unallocated stock and lifetime recovery totals")
	_assert_true(app.run_state.supplies == supplies_before_salvage + victory_reward_supplies, "salvage sweep no longer bypasses allocation by granting supplies directly")
	_assert_true(app.run_state.unlocked_module_ids.size() == 6, "victory unlocks one authored module sidegrade")
	_assert_true(app.campaign_map.visible, "campaign map becomes visible after battle")
	app._on_node_selected(&"s1_boss")
	for _frame in 6:
		await process_frame
	_assert_true(is_instance_valid(app.active_battle), "sector command launches after the completed midpoint")
	_assert_true(not app.active_battle.guided_onboarding and not is_instance_valid(app.active_battle.onboarding), "guided orientation does not repeat after the first completed battle")
	var supplies_before_withdrawal: int = app.run_state.supplies
	var fuel_before_rescue: int = app.run_state.fuel
	var withdrawal_report: Dictionary = app.active_battle._create_battle_report()
	withdrawal_report.outcome = "withdrawal"
	withdrawal_report.interceptor_craft_count = 2
	withdrawal_report.interceptor_stragglers = 1
	withdrawal_report.scout_stragglers = 0
	withdrawal_report.escort_straggler = true
	withdrawal_report.escort_active = false
	withdrawal_report.survivors_adrift = 3
	withdrawal_report.adrift_sources = ["interceptor_wing_01"]
	app._on_battle_returned(true, withdrawal_report)
	await process_frame
	_assert_true(not app.after_action_report.rescue_button.disabled, "rescue operation is offered when fuel and recoverable units are available")
	app._resolve_after_action(&"rescue")
	await process_frame
	_assert_true(app.run_state.withdrawals == 1 and app.run_state.battles_won == 1, "partial withdrawal advances without counting as a full battle victory")
	_assert_true(app.run_state.supplies == supplies_before_withdrawal + floori(float(app.generator.get_node(&"s1_boss").reward_supplies) / 4.0), "withdrawal awards only partial supplies")
	_assert_true(app.run_state.fuel == fuel_before_rescue - 1 and app.run_state.interceptor_craft_count == 3 and app.run_state.escort_active, "rescue spends fuel and restores separated ships")
	_assert_true(app.run_state.personnel_rescued == 3 and app.run_state.straggler_craft_recovered == 1, "rescue consequences persist personnel and craft recovery")
	_assert_true(app.run_state.get_personnel(&"sora_vale").status == SidebayPersonnelRecord.Status.INJURED, "after-action rescue links escape-pod sources to named personnel injuries")
	app.queue_free()
	await process_frame

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
