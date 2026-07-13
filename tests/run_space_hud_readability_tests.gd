extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(2560, 1440)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in 6:
		await process_frame
	var world := scene.get_node_or_null("ExodriftSkyEnvironment") as WorldEnvironment
	_assert_true(world != null and world.environment != null, "battle creates a named sky environment")
	if world != null and world.environment != null:
		_assert_true(world.environment.background_mode == Environment.BG_SKY, "battlefield uses a panoramic sky instead of a flat clear color")
		var sky_material := world.environment.sky.sky_material if world.environment.sky != null else null
		_assert_true(sky_material is ShaderMaterial and (sky_material as ShaderMaterial).shader.code.contains("galaxy_noise") and (sky_material as ShaderMaterial).get_shader_parameter("panorama_texture") != null, "sky blends a generated galaxy arm with resolution-independent stars and dust lanes")
	var stars := scene.get_node_or_null("DeepStarfield") as MultiMeshInstance3D
	_assert_true(stars != null and stars.multimesh.instance_count == 360, "bounded procedural parallax stars layer over the panorama")
	var hud := scene.hud as SidebayHUD
	_assert_true(hud != null and hud.mode_panel.visible, "command view and throttle remain continuously readable")
	_assert_true(hud.mode_label.text.contains("COMMAND VIEW") and hud.mode_label.text.contains("THROTTLE"), "HUD identifies the unified command view and throttle")
	var military_frames := 0
	for candidate in hud.get_children():
		military_frames += _count_military_frames(candidate)
	_assert_true(military_frames >= 10, "HUD uses the asymmetric military frame language throughout")
	var panel_style := hud.telemetry_panel.get_theme_stylebox("panel") as StyleBoxFlat
	_assert_true(panel_style != null and panel_style.border_width_left > panel_style.border_width_right and panel_style.corner_radius_top_right > panel_style.corner_radius_top_left, "HUD frames use asymmetrical rails instead of uniform boxes")
	_assert_true(hud.collapsible_panels.size() >= 6 and hud.overview_rows.size() == 5, "carrier telemetry, air group, fire control, carrier operations, target solution, and tactical overview are collapsible command surfaces")
	_assert_true(is_equal_approx(hud.telemetry_panel.scale.x, 0.75) and hud.target_context_menu.item_count >= 13, "combat HUD uses the compact 75% layout and shared distance-bearing target menu")
	_assert_true(int(ProjectSettings.get_setting("display/window/size/window_width_override")) == 2560 and int(ProjectSettings.get_setting("display/window/size/window_height_override")) == 1440, "desktop window defaults to 2560×1440")
	_assert_true(hud.target_reticle is ExodriftTargetLockReticle and hud.target_panel.find_children("*", "Panel", true, false).is_empty(), "target solution uses projected lock graphics and no placeholder ship portrait panel")
	var collapse_button := hud.telemetry_panel.find_children("*Collapse", "Button", true, false).front() as Button if not hud.telemetry_panel.find_children("*Collapse", "Button", true, false).is_empty() else null
	_assert_true(collapse_button != null, "carrier telemetry exposes an interactive collapse header")
	if collapse_button != null:
		collapse_button.button_pressed = false
		await process_frame
		_assert_true(hud.telemetry_panel.size.y <= 26.0 and not hud.status_label.visible, "collapse header hides telemetry content while retaining the command rail")
		collapse_button.button_pressed = true
		await process_frame
	var safe_rect := Rect2(Vector2(10.0, 10.0), Vector2(root.size) - Vector2(20.0, 20.0))
	for panel in [hud.objective_panel, hud.telemetry_panel, hud.wing_panel, hud.weapon_panel, hud.carrier_operations_panel, hud.target_panel, hud.overview_panel, hud.radar_panel, hud.mode_panel, hud.controls_panel]:
		_assert_true(safe_rect.encloses(panel.get_global_rect()), "%s remains within the 2560x1440 safe margins" % panel.name)
	_assert_true(not hud.weapon_panel.get_global_rect().intersects(hud.carrier_operations_panel.get_global_rect()), "compact carrier operations panel does not overlap fire control")
	_assert_true(hud.carrier_operations_label.get_theme_font_size("font_size") >= 11 and hud.carrier_operations_label.text.contains("BALANCED"), "compact carrier operations summary remains readable and shows the current preset")

	var console := scene.carrier_operations_console as ExodriftCarrierOperationsConsole
	_assert_true(console != null and not console.is_open(), "carrier operations console starts closed")
	console.open_console()
	await process_frame
	_assert_true(console.is_open() and not paused, "carrier operations console remains live without pausing combat")
	_assert_true(safe_rect.encloses(console.frame.get_global_rect()), "carrier operations console remains inside 1440p safe margins")
	var power_panel := console.frame.get_node("PowerManagement") as Control
	var subsystem_panel := console.frame.get_node("SubsystemStatus") as Control
	var stores_panel := console.frame.get_node("CrewAndStores") as Control
	var deck_panel := console.frame.get_node("FlightDeck") as Control
	_assert_true(not power_panel.get_global_rect().intersects(subsystem_panel.get_global_rect()) and not stores_panel.get_global_rect().intersects(deck_panel.get_global_rect()), "console power, subsystem, stores, and deck regions do not overlap")
	_assert_true(console.preset_label.get_theme_font_size("font_size") >= 14 and console.team_options.size() == 2 and console.loadout_options.size() == 2, "console text and interactive triage/deck controls remain readable")
	var operations := scene.carrier.carrier_operations as CarrierOperationsState
	operations.subsystem_condition.command_cic = 0.15
	operations.create_hazard(&"command_cic", &"fire", 0.9)
	console.refresh()
	hud._update_carrier_operations_summary()
	_assert_true(console.incident_label.text.contains("RESCUE") and console.incident_label.text.contains("SEC"), "operations console visibly presents the officer rescue countdown")
	_assert_true(hud.carrier_operations_label.text.contains("RESCUE") and hud.carrier_operations_label.text.contains("COMMAND CIC"), "compact HUD presents the officer rescue subsystem and countdown")
	console.close_console()

	scene.sensors.emit_active_ping()
	await process_frame
	hud.open_target_context_menu(Vector2(root.size) - Vector2(4.0, 4.0), scene.hostile_command.stable_entity_id)
	await process_frame
	var popup_rect := Rect2(Vector2(hud.target_context_menu.position), Vector2(hud.target_context_menu.size))
	_assert_true(hud.target_context_menu.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(popup_rect), "target context menu clamps inside the viewport near the lower-right edge")
	hud.target_context_menu.hide()
	scene.carrier.begin_flak_placement(scene.get_viewport().get_visible_rect().size * 0.5)
	await process_frame
	_assert_true(hud.crosshair_label.visible and hud.weapon_label.text.contains("PLACEMENT"), "flak placement exposes the director and fuse state")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: 1440p sky, carrier-operations console/HUD, popup placement, and command readability")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d space/HUD assertion(s)" % failures.size())
		quit(1)

func _count_military_frames(node: Node) -> int:
	var total := 1 if bool(node.get_meta("military_hud_frame", false)) else 0
	for child in node.get_children():
		total += _count_military_frames(child)
	return total

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
