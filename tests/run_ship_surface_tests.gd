extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sidebay := _spawn_ship(&"cvn_sidebay", "carrier", &"friendly", Vector3(76.0, 32.0, 220.0), Color(0.35, 0.55, 0.7))
	var resolute := _spawn_ship(&"iss_resolute", "frigate", &"friendly", Vector3(24.0, 12.0, 65.0), Color(0.34, 0.56, 0.7))
	var harrier := _spawn_ship(&"iss_harrier", "corvette", &"friendly", Vector3(16.0, 8.0, 42.0), Color(0.32, 0.54, 0.68))
	var bulwark := _spawn_ship(&"iss_bulwark", "frigate", &"friendly", Vector3(28.0, 15.0, 70.0), Color(0.38, 0.55, 0.66))
	var acheron := _spawn_ship(&"acheron_command_frigate", "command", &"hostile", Vector3(28.0, 14.0, 72.0), Color(0.58, 0.24, 0.1))
	var vesper := _spawn_ship(&"vesper_lance_cruiser", "cruiser", &"hostile", Vector3(36.0, 17.0, 94.0), Color(0.48, 0.18, 0.68))
	var crucible := _spawn_ship(&"crucible_war_regent", "cruiser", &"hostile", Vector3(42.0, 22.0, 108.0), Color(0.34, 0.2, 0.46))

	var authored_sidebay := sidebay.authored_visual_root != null
	var sidebay_has_carrier_surface := (
		authored_sidebay
		and sidebay.find_child("Hull_LOD0", true, false) != null
		and sidebay.find_child("blastdoor_port_01_upper", true, false) != null
	) or (
		sidebay.find_child("SidebayFlightDeck", true, false) != null
		and sidebay.find_child("SidebayHangarMouth", true, false) != null
	)
	_assert_true(sidebay_has_carrier_surface, "CVN Sidebay has an enclosed armored hull and functional sidebay apertures")
	var resolute_compartment_count := 0
	for compartment_index in CombatShip.RESOLUTE_VLS_COMPARTMENT_COUNT:
		if resolute.find_child("ResoluteMissileCompartment%02d" % compartment_index, true, false) != null:
			resolute_compartment_count += 1
	_assert_true(resolute_compartment_count == 6 and resolute.missile_launch_points.size() == 6, "ISS Resolute has six modeled and functional dorsal missile compartments")
	_assert_true(resolute.find_child("ResoluteDorsalFlakBattery00", true, false) != null and resolute.find_child("ResoluteDorsalFlakBattery01", true, false) != null and resolute.find_child("ResoluteVentralFlakBattery", true, false) != null, "ISS Resolute has two dorsal and one ventral flak batteries")
	_assert_true(resolute.find_child("ResoluteRangefinder", true, false) != null, "ISS Resolute has a dedicated missile rangefinder")
	_assert_true(harrier.find_child("HarrierScreenCannon", true, false) != null and harrier.find_child("HarrierCockpit", true, false) != null, "ISS Harrier has screen cannons and a forward cockpit")
	_assert_true(bulwark.find_child("BulwarkArmorCourse", true, false) != null and bulwark.find_child("BulwarkCommandBastion", true, false) != null, "ISS Bulwark has layered armor courses and a command bastion")
	_assert_true(acheron.find_child("AcheronJawPlate", true, false) != null, "Acheron hulls use welded jaw armor")
	_assert_true(vesper.find_child("VesperPhaseRail", true, false) != null and vesper.find_child("VesperCrescent", true, false) != null, "Vesper hulls use phase rails and crescent geometry")
	_assert_true(crucible.find_child("CrucibleCarapacePlate", true, false) != null and crucible.find_child("CrucibleLatticeMark", true, false) != null, "Crucible hulls use basalt carapace plates and lattice marks")

	var profiles := [sidebay.visual_profile, acheron.visual_profile, vesper.visual_profile, crucible.visual_profile]
	var texture_paths: Dictionary = {}
	for profile: ShipVisualProfile in profiles:
		texture_paths[profile.hull_texture_path] = true
		_assert_true(ResourceLoader.exists(profile.hull_texture_path), "surface atlas exists: %s" % profile.hull_texture_path)
	_assert_true(texture_paths.size() == 4, "Navy, Acheron, Vesper, and Crucible use four distinct surface atlases")
	_assert_true(acheron.visual_profile.surface_roughness > vesper.visual_profile.surface_roughness + 0.3, "worn Acheron plate and polished Vesper phase hulls have distinct material response")
	var hull_material: StandardMaterial3D
	if authored_sidebay:
		var authored_hull := sidebay.find_child("Hull_LOD0", true, false) as MeshInstance3D
		if authored_hull != null:
			hull_material = authored_hull.get_surface_override_material(0) as StandardMaterial3D
	else:
		hull_material = sidebay.get_node("Hull").material_override as StandardMaterial3D
	var expected_hull_roughness := sidebay.visual_asset.hull_material.fallback_roughness if authored_sidebay and sidebay.visual_asset != null else sidebay.visual_profile.surface_roughness
	_assert_true(
		hull_material != null
		and hull_material.albedo_texture != null
		and hull_material.normal_enabled
		and hull_material.ao_enabled
		and is_equal_approx(hull_material.roughness, expected_hull_roughness),
		"production hull texture, normal/ORM data, and authored roughness reach the rendered carrier material",
	)
	for ship: CombatShip in [sidebay, resolute, harrier, bulwark, acheron, vesper, crucible]:
		_assert_true(ship.get_child_count() <= 80, "%s stays within the 80-node capital surface budget" % ship.definition.ship_id)

	var navy_fighter := _spawn_fighter(&"raptor_interceptor", &"friendly", Color(0.32, 0.58, 0.74))
	var vesper_fighter := _spawn_fighter(&"vesper_lance_fighter", &"hostile", Color(0.58, 0.22, 0.76))
	var crucible_fighter := _spawn_fighter(&"crucible_talon_fighter", &"hostile", Color(0.4, 0.24, 0.52))
	_assert_true(navy_fighter.find_child("InterceptorLeadingEdge", true, false) != null and navy_fighter.find_child("CanopyOrSensorShroud", true, false) != null, "Raptor craft carry readable leading-edge marks and a canopy")
	_assert_true(vesper_fighter.find_child("VesperPhaseVein", true, false) != null and crucible_fighter.find_child("CrucibleWingFacet", true, false) != null, "small craft inherit faction-specific surface language")
	for fighter: FighterCraft in [navy_fighter, vesper_fighter, crucible_fighter]:
		_assert_true(fighter.get_child_count() <= 24, "%s stays within the 24-node fighter surface budget" % fighter.definition.ship_id)

	for child in root.get_children():
		if child is CombatShip:
			child.free()
	await process_frame
	if failures.is_empty():
		print("PASS: faction surface atlases, material response, named hull modeling, and node budgets")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d ship-surface assertion(s)" % failures.size())
		quit(1)

func _spawn_ship(ship_id: StringName, role: String, faction: StringName, dimensions: Vector3, color: Color) -> CombatShip:
	var ship := CombatShip.new()
	root.add_child(ship)
	ship.configure(_definition(ship_id, role, dimensions), StringName("test_%s" % ship_id), faction, color)
	return ship

func _spawn_fighter(ship_id: StringName, faction: StringName, color: Color) -> FighterCraft:
	var fighter := FighterCraft.new()
	root.add_child(fighter)
	fighter.configure(_definition(ship_id, "fighter", Vector3(10.0, 3.0, 18.0)), StringName("test_%s" % ship_id), faction, color)
	return fighter

func _definition(ship_id: StringName, role: String, dimensions: Vector3) -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = ship_id
	definition.display_name = String(ship_id).capitalize()
	definition.role = role
	definition.dimensions_m = dimensions
	definition.damage_layers = DamageLayerDefinition.new()
	return definition

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
