extends Node

const LogisticsScreen := preload("res://scripts/ui/logistics_screen.gd")
const PlaytestReport := preload("res://scripts/ui/playtest_report.gd")
const SaveManager := preload("res://scripts/systems/save_manager.gd")

var run_state: SidebayRunState
var generator := SidebayCampaignGenerator.new()
var campaign_map: SidebayCampaignMap
var active_battle: Node
var active_node: SidebayCampaignNode
var fleet_loadout: ExodriftFleetLoadout
var logistics_screen
var personnel_screen: ExodriftPersonnelScreen
var operational_event_screen: ExodriftOperationalEvent
var after_action_report: ExodriftAfterActionReport
var pending_battle_report: Dictionary = {}
var pending_battle_victory: bool = false
var main_menu: ExodriftMainMenu
var playtest_report: ExodriftPlaytestReport
var save_manager := SaveManager.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_show_main_menu()

func _show_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(campaign_map):
		campaign_map.visible = false
	if is_instance_valid(fleet_loadout):
		fleet_loadout.queue_free()
		fleet_loadout = null
	if is_instance_valid(logistics_screen):
		logistics_screen.queue_free()
		logistics_screen = null
	if is_instance_valid(personnel_screen):
		personnel_screen.queue_free()
		personnel_screen = null
	if is_instance_valid(operational_event_screen):
		operational_event_screen.queue_free()
		operational_event_screen = null
	if is_instance_valid(playtest_report):
		playtest_report.queue_free()
		playtest_report = null
	if is_instance_valid(main_menu):
		main_menu.queue_free()
	main_menu = ExodriftMainMenu.new()
	add_child(main_menu)
	main_menu.configure(run_state != null or save_manager.has_any_save())
	main_menu.new_run_requested.connect(_on_menu_new_run)
	main_menu.continue_requested.connect(_on_menu_continue)
	main_menu.quit_requested.connect(func() -> void: get_tree().quit())

func _on_menu_new_run() -> void:
	await _close_main_menu()
	_start_new_run()

func _on_menu_continue() -> void:
	var next_state := run_state
	if next_state == null:
		next_state = _read_saved_state()
	if next_state == null:
		main_menu.set_status(save_manager.last_message.to_upper())
		return
	await _close_main_menu()
	run_state = next_state
	generator = SidebayCampaignGenerator.new()
	generator.generate(run_state.seed)
	_open_campaign("Operation restored. Choose a reachable node.")

func _close_main_menu() -> void:
	if not is_instance_valid(main_menu):
		return
	await main_menu.fade_out()
	main_menu.queue_free()
	main_menu = null

func _start_new_run() -> void:
	if is_instance_valid(main_menu):
		main_menu.queue_free()
		main_menu = null
	if is_instance_valid(active_battle):
		active_battle.queue_free()
	if is_instance_valid(after_action_report):
		after_action_report.queue_free()
	after_action_report = null
	pending_battle_report.clear()
	active_node = null
	get_tree().paused = false
	run_state = SidebayRunState.create_new()
	save_manager.write_state(run_state, "initial")
	var recorder := _playtest_recorder()
	if recorder != null:
		recorder.begin_run(run_state.run_id)
	generator = SidebayCampaignGenerator.new()
	generator.generate(run_state.seed)
	_open_campaign("Choose a reachable node. Nearby type and threat forecasts are confirmed.")

func _open_campaign(status: String) -> void:
	if campaign_map == null:
		campaign_map = SidebayCampaignMap.new()
		add_child(campaign_map)
		campaign_map.node_selected.connect(_on_node_selected)
		campaign_map.new_run_requested.connect(_start_new_run)
		campaign_map.save_requested.connect(_save_run)
		campaign_map.load_requested.connect(_load_run)
		campaign_map.forecast_requested.connect(_reveal_forecast)
		campaign_map.fleet_requested.connect(_open_fleet_loadout)
		campaign_map.logistics_requested.connect(_open_logistics_screen)
		campaign_map.personnel_requested.connect(_open_personnel_screen)
		campaign_map.playtest_requested.connect(_open_playtest_report)
		campaign_map.title_requested.connect(_show_main_menu)
		campaign_map.configure(run_state, generator)
	else:
		campaign_map.visible = true
		campaign_map.replace_state(run_state, generator)
	campaign_map.set_status(status)
	if not run_state.pending_operational_event.is_empty():
		call_deferred("_show_operational_event")

func _on_node_selected(node_id: StringName) -> void:
	if run_state.run_completed or run_state.run_failed:
		return
	if not generator.reachable_node_ids(run_state).has(node_id):
		campaign_map.set_status("Route rejected: node is not connected to the current position.")
		return
	var node := generator.get_node(node_id)
	if node == null:
		return
	if not run_state.spend_route_cost(node.fuel_cost):
		campaign_map.set_status("Route rejected: requires %d fuel and %d supplies under %s." % [run_state.route_fuel_cost(node.fuel_cost), run_state.route_supply_cost(), run_state.active_logistics_posture_data().get("name", "current logistics")])
		campaign_map.refresh()
		return
	active_node = node
	var recorder := _playtest_recorder()
	if recorder != null:
		recorder.record_event(&"route_selected", {"node_id": String(node.node_id), "sector": node.sector, "objective": node.objective_type})
	if node.is_battle():
		_launch_battle(node)
	else:
		_resolve_noncombat_node(node)

func _resolve_noncombat_node(node: SidebayCampaignNode) -> void:
	var message := ""
	match node.node_type:
		SidebayCampaignNode.NodeType.SALVAGE:
			var recovered := run_state.recover_salvage(node.reward_supplies)
			run_state.requisition += 1
			message = "Salvage secured: +%d salvage stock, +1 requisition." % recovered
		SidebayCampaignNode.NodeType.REPAIR:
			run_state.supplies += node.reward_supplies
			message = "Fleet support completed: +%d reserve supplies." % node.reward_supplies
		SidebayCampaignNode.NodeType.INTEL:
			run_state.intel += node.reward_intel
			message = "Signals decoded: +%d intel." % node.reward_intel
	_complete_node(node)
	campaign_map.refresh()
	campaign_map.set_status(message)
	active_node = null
	if run_state.prepare_operational_event(node.node_type, node.node_id):
		_show_operational_event()

func _launch_battle(node: SidebayCampaignNode) -> void:
	campaign_map.visible = false
	active_battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	active_battle.hosted_campaign = true
	active_battle.campaign_node_id = node.node_id
	active_battle.campaign_sector_index = node.sector
	active_battle.guided_onboarding = node.sector == 0 and run_state.battles_won == 0 and run_state.objectives_failed == 0 and run_state.withdrawals == 0
	active_battle.campaign_threat_multiplier = 1.0 + maxf(0.0, float(node.threat - 1)) * 0.08
	active_battle.campaign_objective_type = node.objective_type
	active_battle.campaign_fleet_snapshot = run_state.fleet_snapshot()
	active_battle.return_to_campaign.connect(_on_battle_returned)
	add_child(active_battle)

func _on_battle_returned(victory: bool, battle_report: Dictionary = {}) -> void:
	get_tree().paused = false
	pending_battle_victory = victory
	pending_battle_report = battle_report.duplicate(true)
	run_state.apply_battle_report(battle_report)
	if is_instance_valid(active_battle):
		active_battle.queue_free()
	active_battle = null
	campaign_map.visible = true
	after_action_report = ExodriftAfterActionReport.new()
	add_child(after_action_report)
	after_action_report.configure(run_state, active_node, pending_battle_report)
	after_action_report.decision_selected.connect(_resolve_after_action)

func _resolve_after_action(decision: StringName) -> void:
	if pending_battle_report.is_empty() or active_node == null:
		return
	var outcome := str(pending_battle_report.get("outcome", "carrier_lost"))
	var rescued_in_battle := int(pending_battle_report.get("survivors_rescued", 0))
	var survivors_adrift := int(pending_battle_report.get("survivors_adrift", 0))
	var interceptor_stragglers := int(pending_battle_report.get("interceptor_stragglers", 0))
	var scout_stragglers := int(pending_battle_report.get("scout_stragglers", 0))
	var escort_straggler := bool(pending_battle_report.get("escort_straggler", false))
	var decision_message := ""
	run_state.personnel_rescued += rescued_in_battle
	if decision == &"rescue" and outcome != "carrier_lost" and run_state.spend_fuel(1):
		run_state.interceptor_craft_count = mini(run_state.maximum_interceptor_craft(), run_state.interceptor_craft_count + interceptor_stragglers)
		run_state.scout_craft_count = mini(run_state.maximum_scout_craft(), run_state.scout_craft_count + scout_stragglers)
		if escort_straggler:
			run_state.escort_active = true
		var recovered_craft := interceptor_stragglers + scout_stragglers
		run_state.straggler_craft_recovered += recovered_craft
		run_state.personnel_rescued += survivors_adrift
		decision_message = " Rescue crews recovered %d craft and %d personnel for 1 fuel." % [recovered_craft + (1 if escort_straggler else 0), survivors_adrift]
	elif decision == &"salvage" and outcome != "carrier_lost":
		if escort_straggler:
			run_state.lose_active_escort()
		var salvage_value := run_state.recover_salvage(int(pending_battle_report.get("salvage_value", 0)))
		run_state.personnel_lost += survivors_adrift
		decision_message = " Salvage crews recovered %d allocation stock; %d personnel remained behind." % [salvage_value, survivors_adrift]
	else:
		if escort_straggler:
			run_state.lose_active_escort()
		run_state.personnel_lost += survivors_adrift
		decision_message = " The fleet departed immediately; %d personnel remained behind." % survivors_adrift

	var status := ""
	if outcome == "carrier_lost" or not pending_battle_victory:
		run_state.run_failed = true
		status = "Carrier destroyed. The run is over; load a manual save or begin anew."
	elif outcome == "withdrawal":
		run_state.withdrawals += 1
		var recovered_supplies := floori(float(active_node.reward_supplies) / 4.0)
		run_state.supplies += recovered_supplies
		_complete_node(active_node)
		status = "Withdrawal from %s: task force survived and recovered %d base supplies.%s" % [active_node.display_name, recovered_supplies, decision_message]
	elif outcome in ["defense_failed", "escort_failed"]:
		run_state.objectives_failed += 1
		_complete_node(active_node)
		status = "Objective failed at %s, but the task force survived.%s" % [active_node.display_name, decision_message]
	else:
		run_state.battles_won += 1
		run_state.objectives_completed += 1
		run_state.requisition += 1
		run_state.supplies += active_node.reward_supplies
		run_state.intel += active_node.reward_intel
		_complete_node(active_node)
		var unlocked := run_state.unlock_next_module()
		var unlock_message := ""
		if unlocked != &"":
			unlock_message = " Module recovered: %s." % SidebayRunState.module_data(unlocked).get("name", "Unknown")
		status = "Victory at %s: +%d supplies, +%d intel.%s%s" % [active_node.display_name, active_node.reward_supplies, active_node.reward_intel, unlock_message, decision_message]
	var personnel_events := run_state.resolve_personnel_consequences(pending_battle_report, decision)
	var recorder := _playtest_recorder()
	if recorder != null:
		recorder.record_event(&"after_action_decision", {"decision": String(decision), "outcome": outcome})
		if run_state.run_completed:
			recorder.increment(&"runs_completed")
	if not personnel_events.is_empty():
		status += " Personnel: %s" % personnel_events[0]
	_autosave("after-action")

	if is_instance_valid(after_action_report):
		after_action_report.queue_free()
	after_action_report = null
	pending_battle_report.clear()
	pending_battle_victory = false
	active_node = null
	campaign_map.refresh()
	campaign_map.set_status(status)

func _open_fleet_loadout() -> void:
	if is_instance_valid(fleet_loadout):
		return
	fleet_loadout = ExodriftFleetLoadout.new()
	add_child(fleet_loadout)
	fleet_loadout.configure(run_state)
	fleet_loadout.closed.connect(_close_fleet_loadout)
	fleet_loadout.fleet_changed.connect(_on_fleet_changed)

func _close_fleet_loadout() -> void:
	if is_instance_valid(fleet_loadout):
		fleet_loadout.queue_free()
	fleet_loadout = null
	campaign_map.refresh()

func _on_fleet_changed(message: String) -> void:
	campaign_map.set_status(message)

func _open_logistics_screen() -> void:
	if is_instance_valid(logistics_screen):
		return
	logistics_screen = LogisticsScreen.new()
	add_child(logistics_screen)
	logistics_screen.configure(run_state)
	logistics_screen.closed.connect(_close_logistics_screen)
	logistics_screen.logistics_changed.connect(_on_logistics_changed)

func _close_logistics_screen() -> void:
	if is_instance_valid(logistics_screen):
		logistics_screen.queue_free()
	logistics_screen = null
	campaign_map.refresh()

func _on_logistics_changed(message: String) -> void:
	campaign_map.refresh()
	campaign_map.set_status(message)

func _open_personnel_screen() -> void:
	if is_instance_valid(personnel_screen):
		return
	personnel_screen = ExodriftPersonnelScreen.new()
	add_child(personnel_screen)
	personnel_screen.configure(run_state)
	personnel_screen.closed.connect(_close_personnel_screen)
	personnel_screen.personnel_changed.connect(_on_personnel_changed)

func _close_personnel_screen() -> void:
	if is_instance_valid(personnel_screen):
		personnel_screen.queue_free()
	personnel_screen = null
	campaign_map.refresh()

func _on_personnel_changed(message: String) -> void:
	campaign_map.set_status(message)

func _open_playtest_report() -> void:
	if is_instance_valid(playtest_report):
		return
	var recorder := _playtest_recorder()
	if recorder == null:
		campaign_map.set_status("Playtest recorder unavailable.")
		return
	playtest_report = PlaytestReport.new()
	add_child(playtest_report)
	playtest_report.configure(recorder)
	playtest_report.closed.connect(_close_playtest_report)

func _close_playtest_report() -> void:
	if is_instance_valid(playtest_report):
		playtest_report.queue_free()
	playtest_report = null

func _playtest_recorder() -> ExodriftPlaytestRecorder:
	return get_node_or_null("/root/PlaytestRecorder") as ExodriftPlaytestRecorder

func _show_operational_event() -> void:
	if run_state == null or run_state.pending_operational_event.is_empty() or is_instance_valid(operational_event_screen):
		return
	operational_event_screen = ExodriftOperationalEvent.new()
	add_child(operational_event_screen)
	operational_event_screen.configure(run_state, run_state.pending_operational_event)
	operational_event_screen.choice_selected.connect(_on_operational_event_choice)

func _on_operational_event_choice(choice_id: StringName) -> void:
	var message := run_state.resolve_operational_event(choice_id)
	_autosave("decision")
	if is_instance_valid(operational_event_screen):
		operational_event_screen.queue_free()
	operational_event_screen = null
	campaign_map.refresh()
	campaign_map.set_status(message)

func _complete_node(node: SidebayCampaignNode) -> void:
	run_state.advance_personnel_recovery()
	run_state.mark_completed(node.node_id, node.sector)
	if node.node_id == &"s3_boss":
		run_state.run_completed = true
	_autosave("node")

func _reveal_forecast() -> void:
	if not run_state.spend_intel(1):
		campaign_map.set_status("Forecast unavailable: insufficient intel.")
		return
	var revealed := generator.reveal_forecast(run_state)
	campaign_map.refresh()
	campaign_map.set_status("Deep forecast resolved %d downstream node(s)." % revealed.size())

func _save_run() -> void:
	var result := save_manager.write_state(run_state, "manual")
	campaign_map.set_status(save_manager.last_message if result == OK else "Save failed: %s" % save_manager.last_message)

func _load_run() -> void:
	var loaded := _read_saved_state()
	if loaded == null:
		campaign_map.set_status(save_manager.last_message)
		return
	run_state = loaded
	generator = SidebayCampaignGenerator.new()
	generator.generate(run_state.seed)
	campaign_map.replace_state(run_state, generator)
	campaign_map.set_status(save_manager.last_message)

func _read_saved_state() -> SidebayRunState:
	return save_manager.read_state()

func _autosave(reason: String) -> void:
	if run_state != null:
		save_manager.write_state(run_state, reason)
