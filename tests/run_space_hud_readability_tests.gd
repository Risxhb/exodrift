extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in 6:
		await process_frame
	var world := scene.get_node_or_null("ExodriftSkyEnvironment") as WorldEnvironment
	_assert_true(world != null and world.environment != null, "battle creates a named sky environment")
	if world != null and world.environment != null:
		_assert_true(world.environment.background_mode == Environment.BG_SKY, "battlefield uses a panoramic sky instead of a flat clear color")
		var sky_material := world.environment.sky.sky_material if world.environment.sky != null else null
		_assert_true(sky_material is ShaderMaterial and (sky_material as ShaderMaterial).shader.code.contains("galaxy_noise"), "sky uses a resolution-independent deep-space shader with stars, dust lanes, and galactic structure")
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
	_assert_true(hud.collapsible_panels.size() >= 5 and hud.overview_rows.size() == 5, "carrier telemetry, air group, fire control, target solution, and tactical overview are collapsible command surfaces")
	_assert_true(hud.target_reticle is ExodriftTargetLockReticle and hud.target_panel.find_children("*", "Panel", true, false).is_empty(), "target solution uses projected lock graphics and no placeholder ship portrait panel")
	var collapse_button := hud.telemetry_panel.find_children("*Collapse", "Button", true, false).front() as Button if not hud.telemetry_panel.find_children("*Collapse", "Button", true, false).is_empty() else null
	_assert_true(collapse_button != null, "carrier telemetry exposes an interactive collapse header")
	if collapse_button != null:
		collapse_button.button_pressed = false
		await process_frame
		_assert_true(hud.telemetry_panel.size.y <= 26.0 and not hud.status_label.visible, "collapse header hides telemetry content while retaining the command rail")
		collapse_button.button_pressed = true
		await process_frame
	scene.carrier.begin_flak_placement(scene.get_viewport().get_visible_rect().size * 0.5)
	await process_frame
	_assert_true(hud.crosshair_label.visible and hud.weapon_label.text.contains("PLACEMENT"), "flak placement exposes the director and fuse state")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: M18 deep-space sky, collapsible command HUD, overview, and lock-director readability")
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
