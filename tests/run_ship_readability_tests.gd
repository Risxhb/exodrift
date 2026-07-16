extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	_assert_true(game.get_node_or_null("FleetFillLight") != null, "combat environment provides a texture-readable fill light")
	_assert_true(game.escort.find_child("ResoluteDorsalDeck", true, false) != null and game.escort.find_child("ResoluteMissileCompartment05", true, false) != null, "ISS Resolute exposes a low naval deck and complete six-cell VLS bank")
	_assert_true(game.escort.find_child("ResoluteDorsalFlakBattery01", true, false) != null and game.escort.find_child("ResoluteVentralFlakBattery", true, false) != null, "ISS Resolute's upper and lower flak coverage reads in the combat model")
	var harrier := CombatShip.new()
	game.add_child(harrier)
	harrier.configure(game._friendly_escort_definition(&"iss_harrier"), &"test_harrier", &"friendly", game._friendly_escort_color(&"iss_harrier"))
	_assert_true(harrier.find_child("HarrierInterceptVane", true, false) != null and harrier.find_child("HarrierGunSpine", true, false) != null, "ISS Harrier exposes interceptor vanes and a gun spine")
	var bulwark := CombatShip.new()
	game.add_child(bulwark)
	bulwark.configure(game._friendly_escort_definition(&"iss_bulwark"), &"test_bulwark", &"friendly", game._friendly_escort_color(&"iss_bulwark"))
	_assert_true(bulwark.find_child("BulwarkCitadelPlate", true, false) != null and bulwark.find_child("BulwarkShieldVane", true, false) != null, "ISS Bulwark exposes citadel armor and shield vanes")
	_assert_true(game.carrier.damage_indicator_nodes.size() == 4 and game.carrier.damage_visual_stage == 0, "capital ships build four hidden progressive damage indicators")
	game.carrier.damage_state.shields = 0.0
	game.carrier.damage_state.armor = 0.0
	game.carrier.damage_state.hull = game.carrier.damage_state.definition.max_hull * 0.3
	game.carrier._update_damage_presentation()
	_assert_true(game.carrier.damage_visual_stage == 4 and game.carrier.damage_indicator_nodes.all(func(node: MeshInstance3D) -> bool: return node.visible), "critical hull damage exposes every breach indicator")
	_assert_true(game.interceptor.crafts[0].find_child("SweptWing", true, false) != null and game.scout.crafts[0].find_child("WatcherSensorEye", true, false) != null, "Raptor interceptors and Watcher drones use distinct silhouettes")
	game.campaign_sector_index = 1
	var vesper := FighterCraft.new()
	game.add_child(vesper)
	vesper.configure(game._hostile_squadron_definition().craft_definition, &"test_vesper", &"hostile", Color(0.8, 0.2, 0.9))
	game.campaign_sector_index = 2
	var crucible := FighterCraft.new()
	game.add_child(crucible)
	crucible.configure(game._hostile_squadron_definition().craft_definition, &"test_crucible", &"hostile", Color(0.8, 0.4, 0.1))
	_assert_true(vesper.find_child("VesperNeedleFuselage", true, false) != null and crucible.find_child("CrucibleCarapace", true, false) != null, "Vesper and Crucible fighters have faction-specific silhouettes")
	_assert_true(not vesper.engine_trails.is_empty() and not crucible.engine_trails.is_empty(), "small craft expose faction-colored engine trails")
	var vfx := root.get_node("CombatVFX")
	var navy_visual: Node3D = vfx.create_projectile_visual("missile", true, &"friendly", &"cvn_sidebay")
	var vesper_visual: Node3D = vfx.create_projectile_visual("missile", true, &"hostile", &"vesper_lance_cruiser")
	var crucible_visual: Node3D = vfx.create_projectile_visual("missile", true, &"hostile", &"crucible_war_regent")
	var navy_core := navy_visual.get_child(0) as MeshInstance3D
	var vesper_core := vesper_visual.get_child(0) as MeshInstance3D
	var crucible_core := crucible_visual.get_child(0) as MeshInstance3D
	_assert_true(navy_core.get_meta("palette_key") == "navy" and vesper_core.get_meta("palette_key") == "vesper" and crucible_core.get_meta("palette_key") == "crucible", "navy, Vesper, and Crucible projectiles retain distinct shared palettes")
	_assert_true(navy_core.material_override == null and navy_core.get_surface_override_material(0) != null, "authored projectile surfaces keep separate hull, refractory, and emissive treatments")
	navy_visual.free()
	vesper_visual.free()
	crucible_visual.free()
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS: M15 ship readability, damage presentation, faction VFX, and lighting")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d ship-readability assertion(s)" % failures.size())
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
