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
	_assert_true(command_buttons.size() == 6, "command bar exposes new, continue, tutorial, settings, credits, and quit actions")
	_assert_true(command_buttons.all(func(button: Button) -> bool: return is_equal_approx(button.position.y, command_buttons[0].position.y)), "primary commands share one horizontal row")
	_assert_true(menu.settings_panel.size == Vector2(440.0, 552.0) and menu.controls_panel.size == Vector2(440.0, 552.0), "secondary settings and controls remain focused overlays")
	_assert_true(menu.ships.size() == 19, "background battle contains two capital formations and twelve fighter craft")
	var capital_models := menu.ships.filter(func(ship_data: Dictionary) -> bool: return not bool(ship_data.fighter))
	var fighter_models := menu.ships.filter(func(ship_data: Dictionary) -> bool: return bool(ship_data.fighter))
	_assert_true(capital_models.all(func(ship_data: Dictionary) -> bool: return ship_data.node is CombatShip and not ship_data.node is FighterCraft), "menu capital formation uses the current CombatShip model builder")
	_assert_true(fighter_models.all(func(ship_data: Dictionary) -> bool: return ship_data.node is FighterCraft), "menu wings use the current FighterCraft model builder")
	var sidebay := capital_models[0].node as CombatShip
	_assert_true(sidebay is PlayerCarrier, "menu flagship instantiates the exact playable carrier model")
	_assert_true(sidebay.find_child("ArmoredCore", true, false) != null and sidebay.find_child("PortBayAssembly", true, false) != null and sidebay.find_child("StarboardBayAssembly", true, false) != null, "menu flagship carries the playable armored core and mirrored hangar assemblies")
	var armored_core := sidebay.find_child("ArmoredCore", true, false) as MeshInstance3D
	var sidebay_material := armored_core.material_override as StandardMaterial3D if armored_core != null else null
	_assert_true(sidebay_material != null and sidebay_material.albedo_texture != null, "menu flagship renders the current textured hull surface")
	_assert_true(sidebay.find_child("RecessedWaist", true, false) != null and sidebay.find_child("OverlappingArmorRib06", true, false) != null and sidebay.find_child("CarrierEngineCorePlume", true, false) != null, "menu flagship uses the Sidebay-specific recessed hull, armor courses, and layered engine plume")
	_assert_true(get_nodes_in_group("menu_missile_trail").size() >= 5 and get_nodes_in_group("menu_flak_tracer").size() >= 20, "menu battle layers missile plumes and dense flak tracer streaks")
	var layered_impacts := get_nodes_in_group("menu_layered_explosion")
	_assert_true(layered_impacts.size() == 4 and layered_impacts.all(func(effect: Node) -> bool: return effect.find_child("WhiteHotCore", true, false) != null and effect.find_child("ShockwaveRing", true, false) != null and effect.find_child("DirectionalDebris", true, false) != null), "menu ship hits use layered core, shockwave, and debris effects")
	_assert_true(menu.camera.fov <= 51.0 and menu.camera.far >= 30000.0, "battle camera holds the full readable command-view backdrop")
	var environment_node := menu.world_root.get_child(0) as WorldEnvironment
	var sky_material := environment_node.environment.sky.sky_material if environment_node != null and environment_node.environment != null and environment_node.environment.sky != null else null
	_assert_true(environment_node.environment.background_mode == Environment.BG_SKY and sky_material is ShaderMaterial and (sky_material as ShaderMaterial).shader.code.contains("panorama_texture") and (sky_material as ShaderMaterial).get_shader_parameter("panorama_texture") != null, "menu battle blends the generated galaxy panorama with its infinite procedural sky")
	var nebula_veils := get_nodes_in_group("menu_nebula_veil").filter(func(node: Node) -> bool: return menu.world_root.is_ancestor_of(node))
	_assert_true(nebula_veils.size() == 2, "menu battle layers two scalable vector nebula veils")
	menu._show_tutorial()
	await process_frame
	_assert_true(is_instance_valid(menu.tutorial_screen) and menu.tutorial_screen.LESSON_TITLES.size() == 8, "main-menu tutorial opens an eight-lesson communications sequence")
	if is_instance_valid(menu.tutorial_screen):
		var tutorial := menu.tutorial_screen
		_assert_true(tutorial.portrait.texture is AtlasTexture and tutorial.dialogue_label.visible_characters >= 0 and tutorial.dialogue_label.visible_characters < tutorial.full_text.length(), "tutorial starts with the generated portrait atlas and typewriter text")
		tutorial._advance()
		_assert_true(tutorial.dialogue_label.visible_characters == -1 and not tutorial.mouth_open, "first advance completes the current transmission without skipping a lesson")
		tutorial._advance()
		_assert_true(tutorial.lesson_index == 1, "second advance moves to the next control lesson")
		tutorial.close()
		await process_frame
		_assert_true(menu.tutorial_screen == null and menu.main_panel.visible, "tutorial returns cleanly to the command menu")
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
