extends SceneTree

const CarrierOperationsConsole := preload("res://scripts/ui/carrier_operations_console.gd")

class MockOperationsState extends RefCounted:
	signal changed

	var current_power_preset := "balanced"
	var available_power := 8
	var power_allocations := {"propulsion": 2, "defense": 2, "weapons": 2, "flight": 2}
	var subsystem_conditions := {
		"reactor": 0.9, "propulsion": 1.0, "shield_grid": 1.0, "fire_control": 1.0,
		"sensors": 1.0, "command_cic": 1.0, "port_deck": 1.0, "starboard_deck": 1.0,
	}
	var hazards := {"reactor": {"fire": true}}
	var damage_control_teams := [{"assignment": "reactor"}, {"assignment": ""}]
	var surviving_crew := 216
	var damage_control_spares := 42
	var stores := {"flak_rounds": 1840, "guided_missiles": 17, "nuclear_torpedoes": 1, "aviation_ordnance": 0.75, "craft_refuel": 9}
	var store_capacities := {"aviation_ordnance": 1}
	var deck_states := {"port": {"state": "repairing", "task": "armor"}, "starboard": {"state": "ready", "task": "idle"}}
	var officer_incidents: Array[Dictionary] = []
	var service_priority := &"balanced"
	var wing_loadouts := {"interceptor": "raptor_multirole", "scout": "watcher_recon"}
	var last_team := -1
	var last_assignment := StringName()

	func apply_power_preset(preset: StringName) -> void:
		current_power_preset = String(preset)

	func adjust_power(channel: StringName, delta: int) -> void:
		power_allocations[channel] = clampi(int(power_allocations.get(channel, 2)) + delta, 1, 4)

	func assign_damage_control_team(team_index: int, subsystem: StringName) -> void:
		last_team = team_index
		last_assignment = subsystem

	func clear_damage_control_team(team_index: int) -> void:
		last_team = team_index
		last_assignment = &""

	func set_service_priority(priority: StringName) -> void:
		service_priority = priority

	func set_wing_loadout(role: StringName, loadout: StringName) -> void:
		wing_loadouts[String(role)] = String(loadout)


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ExodriftInputSettings.ensure_actions()
	_assert_true(ExodriftInputSettings.DEFAULT_KEYS.get("carrier_operations") == KEY_C, "carrier operations defaults to C")
	_assert_true(InputMap.has_action("carrier_operations"), "carrier operations is registered as a remappable action")

	var state := MockOperationsState.new()
	var console := CarrierOperationsConsole.new()
	root.add_child(console)
	console.configure(state)
	await process_frame
	_assert_true(not console.visible and not console.is_open(), "console configures closed")
	_assert_true(console.process_mode == Node.PROCESS_MODE_ALWAYS, "console keeps processing without pausing combat")
	_assert_true(console.frame.size == Vector2(1220.0, 680.0), "console fits the 720p logical safe area used at 1440p and Web sizes")
	console.root.size = Vector2(960.0, 540.0)
	console._fit_to_viewport()
	_assert_true(console.frame.scale.x < 1.0 and console.frame.size.x * console.frame.scale.x <= 936.0 and console.frame.size.y * console.frame.scale.y <= 516.0, "console responsively scales inside lower-resolution and Web safe margins")
	_assert_true(console.power_labels.size() == 4 and console.subsystem_labels.size() == 8, "console exposes all power channels and subsystems")
	_assert_true(console.team_options.size() == 2, "console exposes both damage-control teams")
	_assert_true(console.deck_priority_options.size() == 2 and console.loadout_options.size() == 2, "console exposes both deck priorities and wing packages")
	_assert_true(console.incident_label.text.contains("1 ACTIVE"), "console renders active hazard warnings")
	_assert_true(console.crew_label.text.contains("216 / 240") and console.stores_label.text.contains("1,840"), "console renders crew and finite stores")
	state.officer_incidents.append({"display_name": "Nia Okafor", "subsystem": "reactor", "time_remaining": 8.4, "outcome": "trapped"})
	console.refresh()
	_assert_true(console.incident_label.text.contains("NIA OKAFOR") and console.incident_label.text.contains("8.4 SEC"), "console visibly renders the active officer rescue countdown")

	console.open_console()
	_assert_true(console.visible and not paused, "opening the console does not pause the scene tree")
	console._on_preset_pressed(&"strike")
	_assert_true(state.current_power_preset == "strike", "preset controls call the bound operations state")
	console._on_power_adjustment(&"weapons", 1)
	_assert_true(int(state.power_allocations.weapons) == 3, "manual power controls call the bound operations state")
	console._on_team_assignment(1, 0)
	_assert_true(state.last_team == 0 and state.last_assignment == &"reactor", "damage-control selector calls the bound operations state")
	console._on_team_assignment(0, 1)
	_assert_true(state.last_team == 1 and state.last_assignment == &"", "automatic damage control clears a fixed assignment")
	console._on_priority_selected(2, &"port")
	_assert_true(state.service_priority == &"repair_first", "deck priority uses the global carrier-state contract without a wrong-arity call")
	console._on_loadout_selected(0, &"interceptor")
	_assert_true(state.wing_loadouts.interceptor == "raptor_cap", "loadout selection uses interceptor/scout role identifiers")
	console.wing_loadout_requested.connect(func(_wing: StringName, _loadout: StringName) -> void: pass)
	console._on_loadout_selected(1, &"interceptor")
	_assert_true(state.wing_loadouts.interceptor == "raptor_cap", "delegated loadout selection cannot bypass a live wing rejection")
	_assert_true(console.consume_escape() and not console.visible, "Escape-close API closes an open console")
	_assert_true(not console.consume_escape(), "Escape-close API leaves an already closed console untouched")

	var hud := SidebayHUD.new()
	_assert_true(SidebayHUD.HUD_SCALE == 0.75, "compact operations HUD retains the 75 percent density scale")
	_assert_true(hud.has_method("bind_carrier_operations"), "HUD exposes the carrier-operations binding API")
	ExodriftInputSettings.rebind("carrier_operations", KEY_O)
	_assert_true(hud._operations_key_label() == "O" and hud._operations_key_tag() == "[O]", "carrier operations HUD resolves the player's live remapped binding")
	ExodriftInputSettings.rebind("carrier_operations", KEY_C)
	hud.free()

	console.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: carrier operations console, remappable input, compact HUD, and Escape-close API")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d carrier-operations UI assertion(s)" % failures.size())
		quit(1)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
