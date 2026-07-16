extends SceneTree

var failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for _frame in 3:
		await process_frame
	var vfx := root.get_node_or_null("CombatVFX")
	_assert_true(vfx != null, "CombatVFX autoload is available")
	if vfx == null:
		_finish()
		return

	_assert_true(vfx.missile_mesh != null and vfx.missile_mesh.get_faces().size() / 3 > 100, "guided missile uses the detailed Blender mesh")
	_assert_true(vfx.nuclear_torpedo_mesh != null and vfx.nuclear_torpedo_mesh != vfx.missile_mesh, "nuclear torpedo uses its distinct Blender body")
	_assert_true(vfx.missile_exhaust_mesh != null and vfx.nuclear_exhaust_mesh != null and vfx.missile_exhaust_mesh != vfx.trail_mesh, "missiles use layered authored exhaust instead of box trails")
	_assert_true(vfx.shield_lattice_mesh != null and vfx.shield_lattice_mesh.get_faces().size() / 3 > 100, "shield impacts use the geodesic Blender lattice")
	_assert_true(vfx.armor_shard_mesh != null and vfx.blast_ring_mesh != null and vfx.blast_core_mesh != vfx.blast_volume_mesh, "armor debris, blast core, and shockwave geometry are distinct")
	_assert_true(vfx.warp_ring_mesh != null and vfx.warp_core_mesh != null and vfx.warp_wake_mesh != null, "warp aperture, core, and wake geometry are loaded")

	var before: int = int(vfx.spawned_effects)
	vfx.spawn_burst("shield", Vector3.ZERO, 1.0)
	vfx.spawn_shockwave(Vector3(30.0, 0.0, 0.0), 1.0)
	vfx.spawn_warp_effect(Vector3(60.0, 0.0, 0.0), false, 1.0)
	vfx.spawn_warp_effect(Vector3(90.0, 0.0, 0.0), true, 1.0)
	_assert_true(vfx.spawned_effects == before + 8, "shield, shockwave, warp-in, and warp-out occupy the expected pooled layers")
	var warp_in: Array = vfx.impact_slots.filter(func(slot: Dictionary) -> bool: return slot.role == "warp_in_ring")
	var warp_out: Array = vfx.impact_slots.filter(func(slot: Dictionary) -> bool: return slot.role == "warp_out_ring")
	_assert_true(not warp_in.is_empty() and float(warp_in[0].start_scale) < float(warp_in[0].end_scale), "warp-in aperture expands")
	_assert_true(not warp_out.is_empty() and float(warp_out[0].start_scale) > float(warp_out[0].end_scale), "warp-out aperture collapses")
	vfx.spawn_burst("debris", Vector3.ZERO, 1.0)
	var debris: Array = vfx.impact_slots.filter(func(slot: Dictionary) -> bool: return slot.role == "debris")
	var debris_velocity: Vector3 = debris[0].velocity if not debris.is_empty() else Vector3.ZERO
	var debris_spin: Vector3 = debris[0].angular_velocity if not debris.is_empty() else Vector3.ZERO
	_assert_true(not debris.is_empty() and debris_velocity.length() > 0.0 and debris_spin.length() > 0.0, "armor debris launches outward with spin")

	var raptor := load("res://assets/ships/raptor/raptor_visual_asset.tres") as ShipVisualAsset
	_assert_true(raptor != null and raptor.enabled, "Raptor production manifest is enabled")
	if raptor != null:
		var model := raptor.instantiate_model()
		_assert_true(raptor.manifest_errors(&"raptor", Vector3(6.0, 2.2, 8.0)).is_empty(), "Raptor manifest matches the gameplay definition")
		_assert_true(model != null and raptor.instance_errors(model, {"socket_engine_": 1}).is_empty(), "Raptor bounds, budget, and engine socket validate")
		_assert_true(model != null and model.find_child("SweptWing", true, false) != null and model.find_child("CanopyOrSensorShroud", true, false) != null, "Raptor retains its readable wing and canopy contract")
		if model != null:
			model.free()

	var sky_scene := load("res://assets/vfx/skybox/skybox_accents.glb") as PackedScene
	var sky := sky_scene.instantiate() if sky_scene != null else null
	_assert_true(sky != null and sky.find_child("SkyDistantMoon", true, false) != null, "skybox library contains the ringed moon")
	_assert_true(sky != null and sky.find_child("SkyAsteroidCluster", true, false) != null and sky.find_child("SkyNebulaRibbon", true, false) != null, "skybox library contains asteroid and nebula accents")
	if sky != null:
		sky.free()
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("PASS: Blender-authored combat VFX, Raptor, skybox accents, and bidirectional warp")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d authored-VFX assertion(s)" % failures.size())
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
