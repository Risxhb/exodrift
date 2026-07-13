extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var menu := ExodriftMainMenu.new()
	root.add_child(menu)
	menu.configure(false)
	await process_frame
	_assert_true(menu.main_panel.size.y <= 110.0, "primary menu is a compact command bar")
	_assert_true(is_equal_approx(menu.main_panel.anchor_top, 1.0) and menu.main_panel.offset_top < 0.0, "primary menu is bottom anchored")
	var command_buttons: Array[Button] = []
	for child in menu.main_panel.get_children():
		if child is Button:
			command_buttons.append(child)
	_assert_true(command_buttons.size() == 5, "command bar retains new, continue, settings, credits, and quit actions")
	_assert_true(command_buttons.all(func(button: Button) -> bool: return is_equal_approx(button.position.y, command_buttons[0].position.y)), "primary commands share one horizontal row")
	_assert_true(menu.settings_panel.size == Vector2(440.0, 552.0) and menu.controls_panel.size == Vector2(440.0, 552.0), "secondary settings and controls remain focused overlays")
	_assert_true(menu.ships.size() == 19, "background battle contains two capital formations and twelve fighter craft")
	_assert_true(menu.camera.fov <= 51.0 and menu.camera.far >= 30000.0, "battle camera holds the full readable command-view backdrop")
	var environment_node := menu.world_root.get_child(0) as WorldEnvironment
	_assert_true(environment_node.environment.background_mode == Environment.BG_SKY and environment_node.environment.sky.sky_material is ProceduralSkyMaterial, "menu battle uses the crisp resolution-independent space dome")
	var nebula_veils := get_nodes_in_group("menu_nebula_veil").filter(func(node: Node) -> bool: return menu.world_root.is_ancestor_of(node))
	_assert_true(nebula_veils.size() == 2, "menu battle layers two scalable vector nebula veils")
	menu.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: compact bottom command menu and readable fleet engagement layout")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d main-menu layout assertion(s)" % failures.size())
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
