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
		_assert_true(world.environment.sky != null and world.environment.sky.sky_material is ProceduralSkyMaterial, "sky uses a resolution-independent procedural dome instead of a stretched bitmap")
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
	scene.carrier.begin_flak_placement(scene.get_viewport().get_visible_rect().size * 0.5)
	await process_frame
	_assert_true(hud.crosshair_label.visible and hud.weapon_label.text.contains("PLACEMENT"), "flak placement exposes the director and fuse state")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: M17 panoramic space, unified command view, and military HUD readability")
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
