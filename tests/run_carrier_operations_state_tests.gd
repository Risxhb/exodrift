extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_power_and_subsystems()
	_test_damage_hazards_and_teams()
	_test_stores_modules_and_loadouts()
	_test_crew_and_officer_incidents()
	_test_persistence_and_battle_reset()
	_test_run_state_version_ten_and_service()
	if failures.is_empty():
		print("PASS: M19 carrier operations state checks")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d carrier-operations assertion(s)" % failures.size())
		quit(1)


func _test_power_and_subsystems() -> void:
	var state := CarrierOperationsState.new()
	_assert_true(state.available_power_points() == 8, "healthy reactor supplies eight power points")
	_assert_true(state.set_power_preset(&"strike"), "strike power preset is accepted")
	_assert_true(state.power_allocations == {"propulsion": 1, "defense": 2, "weapons": 4, "flight": 1}, "strike preset applies its fixed allocation")
	_assert_close(state.power_multiplier(&"weapons"), 1.4, "four weapon points apply the allocation-only multiplier")
	state.subsystem_condition["fire_control"] = 0.5
	_assert_close(state.power_multiplier(&"weapons"), 1.4, "power multiplier remains independent from subsystem condition")
	_assert_close(state.subsystem_multiplier(&"fire_control"), 0.5, "subsystem multiplier exposes condition independently")
	state.subsystem_condition["reactor"] = 0.20
	state.set_power_preset(&"evasive")
	_assert_true(state.available_power_points() == 5 and _allocation_total(state) == 5, "critical reactor sheds allocations to five available points")
	_assert_true(state.power_allocations == {"propulsion": 1, "defense": 2, "weapons": 1, "flight": 1}, "power shedding follows the documented largest-allocation tie order")
	_assert_true(not state.set_power_allocation(&"flight", 4), "manual allocation reports when reactor shedding cannot retain the request")
	_assert_true(not state.set_power_allocation(&"unknown", 2), "unknown manual power channels are rejected")


func _test_damage_hazards_and_teams() -> void:
	var state := CarrierOperationsState.new()
	var mapped := state.subsystem_for_impact(Vector3(-18.0, 0.0, 0.0), "missile")
	_assert_true(mapped == &"port_deck" and state.subsystem_for_impact(Vector3(-18.0, 0.0, 0.0), "missile") == mapped, "impact mapping is deterministic and location based")
	var result := state.apply_hull_impact({"hull": 48.0}, {"position": Vector3(18.0, 0.0, 0.0), "weapon_role": "missile"})
	_assert_true(result.subsystem == "starboard_deck" and float(result.condition_damage) > 0.0, "hull penetration resolves subsystem condition damage")
	_assert_true(state.hazard_severity(&"starboard_deck", &"fire") > 0.0 and state.hazard_severity(&"starboard_deck", &"breach") > 0.0, "missile penetration creates fire and breach hazards")
	state.subsystem_condition["starboard_deck"] = 0.0
	_assert_close(state.subsystem_multiplier(&"starboard_deck"), 0.0, "failed subsystem has no unassisted functionality")
	_assert_true(state.assign_damage_control_team(0, &"starboard_deck"), "damage-control team accepts a valid assignment")
	state.tick(3.9)
	_assert_close(state.subsystem_multiplier(&"starboard_deck"), 0.0, "team provides no emergency function while in transit")
	state.tick(0.2)
	_assert_close(state.subsystem_multiplier(&"starboard_deck"), 0.25, "arrived team restores emergency functionality to a failed subsystem")
	var spares_before := state.damage_control_spares
	state.tick(20.0)
	_assert_true(state.hazard_severity(&"starboard_deck") <= 0.0001, "damage control extinguishes fire before sealing the breach")
	state.tick(1.0)
	_assert_true(state.damage_control_spares < spares_before and float(state.subsystem_condition.starboard_deck) > 0.0, "contained team spends persistent spares to restore condition")
	state.damage_control_spares = 0
	var condition_before := float(state.subsystem_condition.starboard_deck)
	state.tick(10.0)
	_assert_close(float(state.subsystem_condition.starboard_deck), condition_before, "teams without spares contain hazards but cannot repair condition")


func _test_stores_modules_and_loadouts() -> void:
	var state := CarrierOperationsState.new()
	_assert_true(state.store_capacity(&"flak_rounds") == 2100 and state.store_capacity(&"guided_missiles") == 24, "carrier begins with baseline flak and missile capacities")
	_assert_true(state.consume_store(&"guided_missiles", 24) and not state.consume_store(&"guided_missiles", 1), "magazine consumption is atomic and rejects empty fire")
	_assert_true(state.last_store_message.contains("depleted"), "empty magazine exposes a clear rejection reason")
	state.stores["craft_refuel"] = 2
	_assert_true(state.consume_store_partial(&"craft_refuel", 5) == 2 and int(state.stores.craft_refuel) == 0, "partial deck service consumes the available refuel stores")
	state.configure_modules({"weapon": "siege_missile_cell", "hangar": "expanded_magazines", "support": "fleet_repair_drones"}, true)
	_assert_true(state.store_capacity(&"guided_missiles") == 32 and state.store_capacity(&"flak_rounds") == 2625, "modules expand guided-missile and flak capacities")
	_assert_true(state.store_capacity(&"aviation_ordnance") == 185 and state.damage_control_spares_capacity == 80, "expanded magazines and repair drones expand their persistent stores")
	_assert_true(state.set_wing_loadout(&"interceptor", &"raptor_strike") and not state.set_wing_loadout(&"scout", &"raptor_cap"), "wing packages validate their compatible role")
	var strike := state.wing_loadout(&"interceptor")
	_assert_true(strike != null and strike.ammunition_per_craft == 12, "selected loadout resolves through the data-driven catalog")
	_assert_close(strike.damage_multiplier, 1.9, "Raptor Strike exposes its authored damage multiplier")
	var rescue := WingLoadoutDefinition.definition(&"watcher_rescue")
	_assert_true(rescue != null and rescue.escape_pod_recovery_range_m == 350.0, "Watcher Rescue exposes its authored recovery radius")
	var capacity_state := CarrierOperationsState.new()
	capacity_state.set_wing_loadout(&"interceptor", &"raptor_cap")
	capacity_state.set_wing_loadout(&"scout", &"watcher_screen")
	_assert_true(capacity_state.store_capacity(&"aviation_ordnance") == 216, "aviation stores hold one complete reload for the selected four-plus-three packages")
	capacity_state.configure_air_group(5, 2)
	_assert_true(capacity_state.store_capacity(&"aviation_ordnance") == 228, "aviation capacity follows a refitted air-group complement")
	capacity_state.configure_modules({"hangar": "expanded_magazines"}, true)
	_assert_true(capacity_state.store_capacity(&"aviation_ordnance") == 285, "Expanded Magazines adds twenty-five percent to the selected air-group reload")
	state.set_service_priority(&"rapid_turn")
	_assert_close(state.deck_armor_recovery_fraction(), 0.0, "Rapid Turn skips armor repair")
	state.set_service_priority(&"repair_first")
	_assert_close(state.deck_armor_recovery_fraction(), 0.60, "Repair First restores sixty percent armor")


func _test_crew_and_officer_incidents() -> void:
	var rescued_state := CarrierOperationsState.new()
	rescued_state.apply_crew_casualties(61, "test")
	_assert_close(rescued_state.crew_efficiency_multiplier(&"damage_control"), 0.85, "crew below seventy-five percent incurs the first operations penalty")
	rescued_state.apply_crew_casualties(60, "test")
	_assert_close(rescued_state.crew_efficiency_multiplier(&"damage_control"), 0.65, "crew below fifty percent incurs the second operations penalty")
	_assert_true(rescued_state.restore_crew_at_repair_node(99) == 24, "repair node restores no more than twenty-four generic crew")
	rescued_state.apply_subsystem_damage(&"reactor", 0.85, "nuclear")
	var incident := rescued_state.active_officer_incident(&"reactor")
	_assert_true(not incident.is_empty() and incident.personnel_id == "nia_okafor" and incident.injury_severity == 3, "severe engineering catastrophe traps the assigned lead with severity-three injury")
	rescued_state.assign_damage_control_team(0, &"reactor")
	_assert_true(rescued_state.active_officer_incident(&"reactor").is_empty(), "assigning damage control rescues a trapped officer")
	_assert_true(str(rescued_state.battle_report().officer_incident_outcomes[0].outcome) == "rescued", "battle report carries rescued officer outcome")

	var killed_state := CarrierOperationsState.new()
	killed_state.apply_subsystem_damage(&"command_cic", 0.85, "nuclear")
	killed_state.tick(10.1)
	var killed_outcomes: Array = killed_state.battle_report().officer_incident_outcomes
	_assert_true(not killed_outcomes.is_empty() and str(killed_outcomes[0].outcome) == "killed", "unresolved rescue countdown deterministically kills the trapped lead")

	var withdrawn_state := CarrierOperationsState.new()
	withdrawn_state.apply_subsystem_damage(&"reactor", 0.85, "nuclear")
	var withdrawn_outcomes: Array = withdrawn_state.battle_report().officer_incident_outcomes
	_assert_true(not withdrawn_outcomes.is_empty() and str(withdrawn_outcomes[0].outcome) == "rescued", "ending a battle resolves and persists an active officer incident through emergency recovery")

	var successor_state := CarrierOperationsState.new()
	successor_state.set_department_leads({"Command": CarrierOperationsState.DEFAULT_DEPARTMENT_LEADS.Command})
	successor_state.apply_subsystem_damage(&"reactor", 0.85, "nuclear")
	_assert_true(successor_state.active_officer_incident(&"reactor").is_empty(), "an unassigned department cannot resurrect and retrap its deceased authored default lead")


func _test_persistence_and_battle_reset() -> void:
	var state := CarrierOperationsState.new()
	state.configure_modules({"weapon": "siege_missile_cell"}, true)
	state.subsystem_condition["sensors"] = 0.42
	state.crew_current = 177
	state.stores["flak_rounds"] = 1234
	state.damage_control_spares = 19
	state.set_wing_loadout(&"scout", &"watcher_screen")
	state.set_power_preset(&"strike")
	state.create_hazard(&"sensors", &"fire", 0.5)
	state.assign_damage_control_team(1, &"sensors")
	var restored := CarrierOperationsState.from_dictionary(state.to_dictionary(), {"weapon": "siege_missile_cell"})
	_assert_close(float(restored.subsystem_condition.sensors), 0.42, "subsystem condition survives persistence round trip")
	_assert_true(restored.crew_current == 177 and int(restored.stores.flak_rounds) == 1234 and restored.damage_control_spares == 19, "crew, stores, and spares survive persistence round trip")
	_assert_true(restored.wing_loadouts.scout == "watcher_screen", "selected wing packages survive persistence round trip")
	_assert_true(restored.current_power_preset == &"balanced" and restored.hazards.is_empty(), "power and active hazards reset to safe battle defaults")
	_assert_true(str(restored.damage_control_teams[0].state) == "idle" and str(restored.damage_control_teams[1].state) == "idle", "team assignments do not persist between battles")


func _test_run_state_version_ten_and_service() -> void:
	var run_state := SidebayRunState.create_new(1919)
	_assert_true(SidebayRunState.SAVE_VERSION == 10, "campaign save schema advances to version ten")
	run_state.carrier_operations.subsystem_condition["propulsion"] = 0.3
	run_state.carrier_operations.crew_current = 201
	run_state.carrier_operations.stores["flak_rounds"] = 1800
	run_state.carrier_operations.damage_control_spares = 40
	run_state.carrier_operations.set_wing_loadout(&"interceptor", &"raptor_cap")
	var restored := SidebayRunState.from_dictionary(run_state.to_dictionary())
	_assert_true(restored != null and restored.carrier_operations.crew_current == 201, "version-ten campaign round trip restores carrier crew")
	_assert_close(float(restored.carrier_operations.subsystem_condition.propulsion), 0.3, "version-ten campaign round trip restores subsystem condition")
	_assert_true(restored.carrier_operations.wing_loadouts.interceptor == "raptor_cap", "version-ten campaign round trip restores selected wing loadout")

	var legacy := run_state.to_dictionary()
	legacy.save_version = 9
	(legacy.fleet as Dictionary).erase("carrier_operations")
	var migrated := SidebayRunState.from_dictionary(legacy)
	_assert_true(migrated != null and migrated.carrier_operations.crew_current == 240, "versions one through nine migrate to a full generic crew")
	_assert_true(float(migrated.carrier_operations.subsystem_condition.reactor) == 1.0 and migrated.carrier_operations.wing_loadouts.interceptor == "raptor_multirole", "legacy saves migrate to full condition and default packages")
	_assert_true(int(migrated.carrier_operations.stores.guided_missiles) == 32, "legacy migration applies installed module capacity to full stores")
	_assert_true(migrated.scout_ammunition == 36 and migrated.maximum_scout_ammunition() == 36, "legacy ammunition is capped to the default Watcher Recon package")

	restored.carrier_operations.set_wing_loadout(&"interceptor", &"raptor_cap")
	restored.apply_battle_report({
		"interceptor_ammunition": 120,
		"carrier_operations": restored.carrier_operations.battle_report(),
	})
	_assert_true(restored.maximum_interceptor_ammunition() == 144 and restored.interceptor_ammunition == 120, "battle report applies a changed package before clamping persisted wing ammunition")

	restored.supplies = 999
	var crew_before := restored.carrier_operations.crew_current
	var breakdown := restored.service_cost_breakdown()
	_assert_true(int((breakdown.repair as Dictionary).subtotal) > 0 and int((breakdown.rearm as Dictionary).subtotal) > 0, "fleet service quotes exact repair and rearm subtotals")
	_assert_true(restored.service_fleet(&"full_service"), "full service accepts the quoted supply cost")
	_assert_true(restored.carrier_operations.crew_current == crew_before, "normal fleet service never replaces generic casualties")
	_assert_close(float(restored.carrier_operations.subsystem_condition.propulsion), 1.0, "full service restores persistent subsystem condition")
	_assert_true(int(restored.carrier_operations.stores.flak_rounds) == restored.carrier_operations.store_capacity(&"flak_rounds"), "full service replenishes carrier stores")


func _allocation_total(state: CarrierOperationsState) -> int:
	var total := 0
	for value in state.power_allocations.values():
		total += int(value)
	return total


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_close(actual: float, expected: float, message: String, tolerance: float = 0.001) -> void:
	if not is_equal_approx(actual, expected) and absf(actual - expected) > tolerance:
		failures.append("%s (expected %.3f, got %.3f)" % [message, expected, actual])
