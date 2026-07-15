extends SceneTree

const FIXTURE_PATH := "res://tests/fixtures/ship_assets/test_authored_ship_visual_asset.tres"
const SIDEBAY_PATH := "res://assets/ships/cvn_sidebay/cvn_sidebay_visual_asset.tres"
const NAVY_MATERIAL_PATH := "res://assets/ships/materials/navy/navy_gunmetal_pbr.tres"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var asset := load(FIXTURE_PATH) as ShipVisualAsset
	_assert_true(asset != null, "fixture manifest loads as ShipVisualAsset")
	if asset == null:
		_finish()
		return
	_assert_true(asset.manifest_errors(&"test_authored_ship", Vector3(42.0, 20.0, 120.0)).is_empty(), "valid manifest matches runtime identity and dimensions")
	_assert_true(not asset.manifest_errors(&"wrong_ship", Vector3(42.0, 20.0, 120.0)).is_empty(), "identity mismatch is rejected")
	_assert_true(not asset.manifest_errors(&"test_authored_ship", Vector3(20.0, 10.0, 60.0)).is_empty(), "dimension mismatch is rejected")

	var model := asset.instantiate_model()
	_assert_true(model != null, "authored scene instantiates as Node3D")
	if model != null:
		var instance_errors := asset.instance_errors(model, {"socket_engine_": 1, "socket_weapon_primary_": 1})
		_assert_true(instance_errors.is_empty(), "required runtime sockets and budgets validate")
		var sockets := asset.collect_sockets(model)
		_assert_true(sockets.has(&"socket_engine_01") and sockets.has(&"socket_weapon_primary_01"), "socket discovery uses stable lowercase names")
		var metrics := asset.model_metrics(model)
		_assert_true(int(metrics.get("triangles", 0)) == 12 and int(metrics.get("material_slots", 0)) == 1, "mesh metrics report fixture triangles and material slots")
		asset.apply_material_contract(model)
		var hull := model.get_node("HullLOD0") as MeshInstance3D
		var applied := hull.get_surface_override_material(0) as StandardMaterial3D
		_assert_true(applied != null and applied.normal_enabled and applied.ao_enabled, "PBR material contract reaches imported mesh surfaces")
		model.free()

	var profile := ShipVisualProfile.new()
	profile.visual_asset_path = FIXTURE_PATH
	_assert_true(profile.load_visual_asset() == asset, "visual profile resolves an authored manifest")
	var ship := CombatShip.new()
	root.add_child(ship)
	ship.definition = _definition()
	ship.visual_profile = profile
	_assert_true(ship._try_build_authored_visual(), "CombatShip accepts a valid authored model")
	_assert_true(ship.authored_visual_root != null and ship.authored_sockets.has(&"socket_engine_01"), "CombatShip retains authored root and sockets")
	ship._add_default_collision()
	_assert_true(ship.get_node_or_null("GameplayCollision") is CollisionShape3D, "gameplay collision remains independent from authored geometry")
	ship.free()

	var broken := asset.duplicate(true) as ShipVisualAsset
	broken.model_scene = null
	_assert_true(not broken.manifest_errors().is_empty(), "missing model scene is rejected before integration")

	var navy_material := load(NAVY_MATERIAL_PATH) as ShipPbrMaterial
	_assert_true(navy_material != null and navy_material.validation_errors().is_empty(), "reference Navy PBR pack contains base color, normal, and packed ORM textures")
	var sidebay := load(SIDEBAY_PATH) as ShipVisualAsset
	_assert_true(sidebay != null and sidebay.enabled, "Sidebay reference-sheet asset is enabled as the production carrier visual")
	if sidebay != null:
		_assert_true(sidebay.manifest_errors(&"cvn_sidebay", Vector3(76.0, 32.0, 220.0)).is_empty(), "Sidebay production manifest matches runtime identity and dimensions")
		var sidebay_model := sidebay.instantiate_model()
		var sidebay_errors := sidebay.instance_errors(sidebay_model, {
			"socket_flak_": 10,
			"socket_engine_": 6,
			"socket_bay_port_": 3,
			"socket_bay_starboard_": 3,
			"socket_bay_scout_": 1,
		})
		_assert_true(sidebay_errors.is_empty(), "Sidebay GLB passes geometry, material, bounds, and carrier socket contracts")
		if sidebay_model != null:
			var sidebay_metrics := sidebay.model_metrics(sidebay_model)
			_assert_true(int(sidebay_metrics.get("triangles", 0)) == 99016 and int(sidebay_metrics.get("material_slots", 0)) == 50, "Sidebay source exports the recorded 99,016-triangle reference model with ten linked PDWs, six armored drives, and twelve blast-door halves")
			sidebay_model.free()
		var authored_carrier := PlayerCarrier.new()
		root.add_child(authored_carrier)
		authored_carrier.configure(_sidebay_definition(), &"test_authored_sidebay", &"friendly", Color(0.35, 0.55, 0.7))
		_assert_true(authored_carrier.authored_visual_root != null, "review-approved manifest can replace the PlayerCarrier visual root")
		_assert_true(authored_carrier.flak_mounts.size() == 10 and authored_carrier.engine_trails.size() == 6, "authored Sidebay binds all flak and engine sockets")
		var shared_pdw_mesh: Mesh
		var all_pdw_models_bound := true
		var all_pdw_models_linked := true
		for flak_mount in authored_carrier.flak_mounts:
			var pdw_models := flak_mount.find_children("PDW_FlakCannon_*", "MeshInstance3D", true, false)
			if pdw_models.size() != 1:
				all_pdw_models_bound = false
				continue
			var pdw_model := pdw_models[0] as MeshInstance3D
			if shared_pdw_mesh == null:
				shared_pdw_mesh = pdw_model.mesh
			elif pdw_model.mesh != shared_pdw_mesh:
				all_pdw_models_linked = false
		_assert_true(all_pdw_models_bound and all_pdw_models_linked, "all ten flak sockets own visible instances of one shared PDW cannon mesh")
		_assert_true(authored_carrier.port_bay_markers.size() == 3 and authored_carrier.starboard_bay_markers.size() == 3 and authored_carrier.scout_bay_marker != null, "authored Sidebay binds all launch-bay sockets")
		_assert_true(authored_carrier.bay_assemblies.size() == 6, "authored Sidebay binds six animated armored blast-door assemblies")
		var authored_door := authored_carrier.bay_assemblies[0].door_a as Node3D if not authored_carrier.bay_assemblies.is_empty() else null
		var authored_door_open_position := authored_door.position if authored_door != null else Vector3.ZERO
		authored_carrier.notify_flight_launch_started(&"test_port_launch")
		authored_carrier.notify_flight_launch_started(&"test_starboard_launch")
		authored_carrier.notify_flight_launch_finished(&"test_port_launch")
		_assert_true(is_equal_approx(authored_carrier.bay_target_closure, 0.0), "blast doors remain open while another flight is still launching")
		authored_carrier.notify_flight_launch_finished(&"test_starboard_launch")
		authored_carrier._update_bay_retraction(authored_carrier.bay_transition_seconds)
		_assert_true(authored_carrier.are_bays_closed() and authored_door != null and not authored_door.position.is_equal_approx(authored_door_open_position), "the final completed launch automatically closes the authored hangar blast doors")
		authored_carrier.notify_flight_recovery_started(&"test_recovery")
		authored_carrier.notify_flight_launch_started(&"test_concurrent_launch")
		authored_carrier.notify_flight_launch_finished(&"test_concurrent_launch")
		_assert_true(is_equal_approx(authored_carrier.bay_target_closure, 0.0), "a completed launch cannot close blast doors across an active recovery lane")
		authored_carrier.notify_flight_recovery_finished(&"test_recovery")
		_assert_true(is_equal_approx(authored_carrier.bay_target_closure, 1.0), "blast doors seal after launch and recovery traffic are both clear")
		_assert_true(authored_carrier.get_node_or_null("GameplayCollision") is CollisionShape3D and authored_carrier.chase_camera != null, "authored visuals preserve gameplay collision and chase camera")
		authored_carrier.free()
	_finish()

func _definition() -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"test_authored_ship"
	definition.display_name = "Authored Test Ship"
	definition.role = "frigate"
	definition.dimensions_m = Vector3(42.0, 20.0, 120.0)
	definition.damage_layers = DamageLayerDefinition.new()
	return definition

func _sidebay_definition() -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"cvn_sidebay"
	definition.display_name = "CVN Sidebay"
	definition.role = "carrier"
	definition.dimensions_m = Vector3(76.0, 32.0, 220.0)
	definition.damage_layers = DamageLayerDefinition.new()
	return definition

func _finish() -> void:
	if failures.is_empty():
		print("PASS: authored ship asset contract, sockets, materials, budgets, and fallback seam")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
