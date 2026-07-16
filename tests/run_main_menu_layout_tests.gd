extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(2560, 1440)
	var menu := ExodriftMainMenu.new()
	root.add_child(menu)
	menu.configure(false)
	await process_frame
	_assert_true(menu.main_panel.size.y <= 110.0, "primary menu is a compact command bar")
	_assert_true(is_equal_approx(menu.main_panel.anchor_top, 1.0) and menu.main_panel.offset_top < 0.0, "primary menu is bottom anchored")
	var menu_rect := menu.main_panel.get_global_rect()
	_assert_true(menu_rect.position.x >= 18.0 and menu_rect.end.x <= root.size.x - 18.0 and menu_rect.position.y >= 18.0 and menu_rect.end.y <= root.size.y - 18.0, "1440p command bar remains inside safe margins")
	var command_buttons: Array[Button] = []
	for child in menu.main_panel.get_children():
		if child is Button:
			command_buttons.append(child)
	_assert_true(command_buttons.size() == 6, "command bar exposes new, continue, tutorial, settings, credits, and quit actions")
	_assert_true(menu.primary_action_button != null and menu.primary_action_button.text == "NEW OPERATION" and menu.primary_action_button.size.y > menu.continue_button.size.y, "new operation owns the primary title action when no checkpoint is available")
	_assert_true(command_buttons.filter(func(button: Button) -> bool: return button != menu.primary_action_button).all(func(button: Button) -> bool: return button.size.y <= 40.0), "tutorial and system actions remain visually secondary to the primary operation command")
	var branding_copy := " ".join(menu.main_panel.get_children().filter(func(child: Node) -> bool: return child is Label).map(func(child: Node) -> String: return (child as Label).text))
	_assert_true(not branding_copy.contains("M19") and branding_copy.contains("CARRIER COMMAND"), "title branding presents the game identity without development milestone copy")
	_assert_true(menu.settings_panel.size == Vector2(440.0, 552.0) and menu.controls_panel.size == Vector2(440.0, 552.0), "secondary settings and controls remain focused overlays")
	_assert_true(menu.ships.size() == 20, "background battle contains two capital formations, six Raptor leaders, one Watcher, and six hostile attack craft")
	var capital_models := menu.ships.filter(func(ship_data: Dictionary) -> bool: return not bool(ship_data.fighter))
	var fighter_models := menu.ships.filter(func(ship_data: Dictionary) -> bool: return bool(ship_data.fighter))
	_assert_true(capital_models.all(func(ship_data: Dictionary) -> bool: return ship_data.node is CombatShip and not ship_data.node is FighterCraft), "menu capital formation uses the current CombatShip model builder")
	_assert_true(fighter_models.all(func(ship_data: Dictionary) -> bool: return ship_data.node is FighterCraft), "menu wings use the current FighterCraft model builder")
	var sidebay := capital_models[0].node as CombatShip
	_assert_true(sidebay is PlayerCarrier, "menu flagship instantiates the exact playable carrier model")
	var authored_hull := sidebay.find_child("Hull_LOD0", true, false) as MeshInstance3D
	var gallery_door_names := ["blastdoor_port_01_upper", "blastdoor_port_02_upper", "blastdoor_port_03_upper", "blastdoor_starboard_01_upper", "blastdoor_starboard_02_upper", "blastdoor_starboard_03_upper"]
	_assert_true(sidebay.authored_visual_root != null and authored_hull != null and gallery_door_names.all(func(node_name: String) -> bool: return sidebay.find_child(node_name, true, false) != null) and sidebay.scout_bay_marker != null, "menu flagship carries the production armored hull, six functional gallery door sectors, and Watcher EW socket")
	var sidebay_material := authored_hull.get_surface_override_material(0) as StandardMaterial3D if authored_hull != null else null
	_assert_true(sidebay_material != null and sidebay_material.albedo_texture != null, "menu flagship renders the current textured hull surface")
	var sidebay_metrics := sidebay.visual_asset.model_metrics(sidebay.authored_visual_root) if sidebay.visual_asset != null else {}
	_assert_true(int(sidebay_metrics.get("triangles", 0)) >= 61000 and sidebay.find_child("CarrierEngineCorePlume", true, false) != null, "menu flagship uses the runtime-refined reference-sheet armor model and layered engine plume")
	var friendly_air_group := fighter_models.filter(func(ship_data: Dictionary) -> bool: return bool(ship_data.friendly))
	_assert_true(friendly_air_group.size() == 7 and friendly_air_group.filter(func(ship_data: Dictionary) -> bool: return ship_data.model_id == &"raptor_interceptor").size() == 6 and friendly_air_group.filter(func(ship_data: Dictionary) -> bool: return ship_data.model_id == &"watcher_drone").size() == 1, "menu air group presents six Raptor squadron leaders and the dedicated Watcher EW wing")
	_assert_true(get_nodes_in_group("menu_missile_trail").size() == 12 and get_nodes_in_group("menu_flak_tracer").size() == 28 and get_nodes_in_group("menu_flak_airburst").size() == 14, "menu battle layers reciprocal six-weapon salvos, three seven-round friendly flak curtains, return fire, and a dense airburst wall")
	_assert_true(menu.tracers.filter(func(tracer_data: Dictionary) -> bool: return bool(tracer_data.missile) and bool(tracer_data.friendly)).size() == 6 and menu.tracers.filter(func(tracer_data: Dictionary) -> bool: return bool(tracer_data.missile) and not bool(tracer_data.friendly)).size() == 6, "friendly frigates and hostile secondary ships each contribute a readable missile salvo")
	_assert_true(menu.tracers.filter(func(tracer_data: Dictionary) -> bool: return not bool(tracer_data.missile) and bool(tracer_data.friendly)).size() == 21, "title-screen flak uses three automatic seven-round friendly curtains")
	var hostile_capitals := capital_models.filter(func(ship_data: Dictionary) -> bool: return not bool(ship_data.friendly))
	_assert_true(hostile_capitals.all(func(ship_data: Dictionary) -> bool: return Vector3(ship_data.base).distance_to(Vector3(capital_models[0].base)) > 1200.0), "hostile menu formation arrives on a distinctly deeper plane than the friendly carrier")
	_assert_true(get_nodes_in_group("menu_warp_effect").size() == 3 and get_nodes_in_group("menu_launch_flare").size() == 4, "title battle authors three hostile warp rifts plus friendly and hostile launch flashes")
	menu.elapsed = 0.2
	menu._update_battle(0.0)
	_assert_true(hostile_capitals.all(func(ship_data: Dictionary) -> bool: return not (ship_data.node as Node3D).visible), "enemy capital ships remain absent before the warp arrival")
	menu.elapsed = 1.15
	menu._update_battle(0.0)
	_assert_true(menu.warp_effects.any(func(effect_data: Dictionary) -> bool: return (effect_data.node as Node3D).visible), "enemy warp rifts open before the hostile formation resolves")
	menu.elapsed = 2.6
	menu._update_battle(0.0)
	_assert_true(fighter_models.any(func(ship_data: Dictionary) -> bool: return not bool(ship_data.friendly) and (ship_data.node as Node3D).visible) and fighter_models.all(func(ship_data: Dictionary) -> bool: return not bool(ship_data.friendly) or not (ship_data.node as Node3D).visible), "hostile strike craft launch before Sidebay commits its air group")
	menu.elapsed = 4.0
	menu._update_battle(0.0)
	_assert_true(menu.tracers.any(func(tracer_data: Dictionary) -> bool: return not bool(tracer_data.missile) and bool(tracer_data.friendly) and (tracer_data.node as Node3D).visible) and fighter_models.any(func(ship_data: Dictionary) -> bool: return bool(ship_data.friendly) and (ship_data.node as Node3D).visible), "Sidebay raises the automatic flak screen while launching friendly strike craft")
	menu.elapsed = 5.1
	menu._update_battle(0.0)
	_assert_true(menu.tracers.any(func(tracer_data: Dictionary) -> bool: return bool(tracer_data.missile) and bool(tracer_data.friendly) and (tracer_data.node as Node3D).visible), "friendly frigates answer with their salvos after the carrier screen and air-group launch")
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
	_assert_true(is_instance_valid(menu.tutorial_screen) and menu.tutorial_screen.LESSON_TITLES.size() == 9, "main-menu tutorial opens a nine-lesson communications sequence")
	if is_instance_valid(menu.tutorial_screen):
		var tutorial := menu.tutorial_screen
		var communications_frame := tutorial.root.find_child("CommunicationsFrame", true, false) as Control
		_assert_true(communications_frame != null and communications_frame.get_global_rect().position.x >= 18.0 and communications_frame.get_global_rect().end.x <= root.size.x - 18.0 and communications_frame.get_global_rect().position.y >= 18.0 and communications_frame.get_global_rect().end.y <= root.size.y - 18.0, "tutorial communications frame stays within 1440p safe margins")
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
		print("PASS: hierarchical title command menu and readable fleet engagement layout")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d main-menu layout assertion(s)" % failures.size())
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
