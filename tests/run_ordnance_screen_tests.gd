extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 10:
		await process_frame
	var carrier: PlayerCarrier = game.carrier
	for ship in get_nodes_in_group("combat_entities"):
		if ship is CombatShip:
			ship.ai_enabled = false

	_assert_true(ExodriftInputSettings.action_key("flak_screen") == KEY_1 and ExodriftInputSettings.action_key("missile_salvo") == KEY_2 and ExodriftInputSettings.action_key("nuclear_torpedo") == KEY_3, "ordnance actions use the requested remappable 1/2/3 defaults")
	_assert_true(ExodriftInputSettings.action_key("flak_range_decrease") == KEY_BRACKETLEFT and ExodriftInputSettings.action_key("flak_range_increase") == KEY_BRACKETRIGHT, "brackets provide remappable flak fuse-range adjustment")
	_assert_true(ExodriftInputSettings.action_key("toggle_all_wings") == KEY_B, "B provides the remappable aggregate hangar-wing deployment and retraction control")
	_assert_true(carrier.definition.acceleration_mps2 <= 18.0 and carrier.definition.rotation_speed_radians <= 0.38, "carrier uses capital-ship acceleration and turn-rate limits")
	_assert_true(not carrier.engine_trails.is_empty() and carrier.engine_trails[0].has("outer") and carrier.engine_trails[0].has("inner") and carrier.engine_trails[0].has("core"), "carrier engine banks expose layered propulsion-demand plumes")
	_assert_true(is_equal_approx(carrier.flak_weapon.range_m, 3200.0) and is_equal_approx(carrier.flak_airburst_radius_m, 250.0), "carrier flak uses the 3.2 km battery envelope and 250 m airburst radius")
	_assert_true(carrier.chase_zoom_percent() == 0, "the authored carrier framing is the signed zoom scale's zero point")
	carrier.adjust_chase_zoom(-20.0)
	_assert_true(carrier.chase_zoom_percent() < 0 and carrier.chase_target_distance_m > 260.0, "signed zoom allows substantially farther carrier command framing")
	carrier.chase_target_distance_m = PlayerCarrier.CHASE_DEFAULT_DISTANCE_M
	carrier.chase_distance_m = PlayerCarrier.CHASE_DEFAULT_DISTANCE_M

	var screen_center := game.get_viewport().get_visible_rect().size * 0.5
	_assert_true(carrier.begin_flak_placement(screen_center) and carrier.flak_placement_active, "1-style placement creates a valid world-space fuse preview")
	for _frame in 8:
		carrier._update_camera()
	var camera_to_carrier := carrier.chase_camera.global_position.direction_to(carrier.global_position)
	_assert_true(carrier.flak_camera_blend > 0.7 and carrier.chase_camera.position.z > 0.0 and carrier.chase_camera.position.length() > 800.0 and (-carrier.chase_camera.global_transform.basis.z).dot(camera_to_carrier) > 0.98, "placement zooms out while keeping the carrier centered instead of travelling toward the fuse volume")
	var minimum := carrier.adjust_flak_screen_range(-20)
	var maximum := carrier.adjust_flak_screen_range(20)
	_assert_true(is_equal_approx(minimum, 1000.0) and is_equal_approx(maximum, 3200.0), "flak fuse range clamps to the authored 1.0–3.2 km envelope")
	carrier.adjust_flak_screen_range(-4)
	_assert_true(carrier.confirm_flak_placement() and carrier.flak_screen_active and not carrier.flak_placement_active, "LMB-style confirmation commits sustained flak and exits placement")
	for _frame in 18:
		carrier._update_camera()
	_assert_true(carrier.flak_camera_blend < 0.05 and carrier.chase_camera.position.z > 0.0, "confirmation returns the camera to the carrier command view")
	var committed_local := carrier.flak_screen_local_offset
	carrier.global_position += Vector3(220.0, 35.0, -90.0)
	carrier.global_transform.basis = carrier.global_transform.basis.rotated(Vector3.UP, 0.4)
	carrier._update_flak_indicator(false)
	_assert_true(carrier.flak_screen_world_position().distance_to(carrier.global_transform * committed_local) < 0.01, "committed screen stays fixed in carrier-local space through translation and turn")
	carrier.clear_flak_screen()
	game.tactical.set_enabled(true)
	var tactical_point: Vector3 = game.tactical.flak_placement_world_point(screen_center + Vector2(120.0, 40.0), carrier.flak_screen_range_m)
	_assert_true(carrier.begin_flak_placement_world(tactical_point) and carrier.confirm_flak_placement() and game.tactical.camera.current, "tactical overlay places and confirms the same carrier-relative flak screen without leaving tactical command")
	game.tactical.set_enabled(false)

	carrier.flak_cooldown = 0.0
	var before_flak := _source_projectiles(carrier.stable_entity_id).size()
	carrier._process_flak_screen()
	_assert_true(carrier.pending_flak_shots.size() == carrier.flak_burst_count - 1, "capital batteries stagger the remaining rounds instead of spawning a simultaneous wall")
	carrier._process_flak_salvo_queue(1.0)
	var flak_rounds := _source_projectiles(carrier.stable_entity_id).filter(func(projectile: SidebayProjectile) -> bool: return projectile.projectile_role == "flak")
	_assert_true(flak_rounds.size() >= before_flak + carrier.flak_burst_count, "active screen sustains a staggered seven-round battery barrage")
	var screen_round: SidebayProjectile = flak_rounds.back() if not flak_rounds.is_empty() else null
	_assert_true(screen_round != null and screen_round.airburst_distance_m > 0.0 and is_equal_approx(screen_round.blast_radius_m, carrier.flak_airburst_radius_m), "screen rounds carry a bounded proximity/airburst fuse")
	if screen_round != null:
		var hostile_weapon: WeaponDefinition = game.hostile_command.definition.weapons[0]
		var threat: SidebayProjectile = game.hostile_command.spawn_projectile(hostile_weapon, screen_round.global_position + Vector3(20.0, 0.0, 0.0), Vector3.FORWARD, carrier)
		screen_round.global_position = threat.global_position
		screen_round.detonate()
		_assert_true(threat.expired, "flak airburst intercepts an incoming missile inside its screening radius")
		var active_roles: Array[String] = []
		var combat_vfx := root.get_node_or_null("CombatVFX")
		if combat_vfx != null:
			for slot in combat_vfx.impact_slots:
				if bool(slot.active):
					active_roles.append(String(slot.role))
		_assert_true(active_roles.has("flak_flash") and active_roles.has("flak_smoke") and active_roles.has("flak_pressure"), "airburst layers a flash, dark smoke, and pressure ring from the pooled VFX system")

	_clear_source_projectiles(carrier.stable_entity_id)
	await process_frame
	_assert_true(carrier.fire_nuclear(game.hostile_command), "3 launches the battle's single nuclear torpedo against a valid lock")
	var nuclear_round: SidebayProjectile
	for projectile in _source_projectiles(carrier.stable_entity_id):
		if projectile.projectile_role == "nuclear":
			nuclear_round = projectile
			break
	_assert_true(nuclear_round != null and nuclear_round.radial_warhead and nuclear_round.can_be_intercepted, "nuclear torpedo is an interceptable radial warhead")
	_assert_true(not carrier.fire_nuclear(game.hostile_command) and not carrier.nuclear_available, "nuclear inventory is limited to one launch per battle")
	if nuclear_round != null:
		var visual := nuclear_round.get_node_or_null("NuclearTorpedoVisual")
		_assert_true(visual != null and visual.get_node_or_null("ExhaustTrail") != null and visual.get_node_or_null("IonWake") != null, "nuclear torpedo has a distinctive long two-stage trail")
		var friendly_before := _total_layers(carrier)
		var hostile_before := _total_layers(game.hostile_command)
		nuclear_round.global_position = carrier.global_position + Vector3(110.0, 0.0, 0.0)
		game.hostile_command.global_position = nuclear_round.global_position + Vector3(130.0, 0.0, 0.0)
		nuclear_round.distance_travelled_m = carrier.nuclear_arming_distance_m
		nuclear_round.detonate()
		_assert_true(_total_layers(carrier) < friendly_before and _total_layers(game.hostile_command) < hostile_before, "armed nuclear blast applies radial damage to hostile and friendly hulls")

	var wing: SidebaySquadron = game.interceptor
	wing.operation.state = BayOperation.State.SERVICING
	wing.operation.state_elapsed_seconds = wing.definition.service_seconds
	_assert_true(wing.request_redeploy() and wing.redeploy_requested, "servicing wing accepts an explicit redeploy request")
	wing._process(0.01)
	_assert_true(wing.operation.state == BayOperation.State.QUEUED and not wing.redeploy_requested, "serviced wing automatically enters the physical launch queue")

	var vfx: Node = root.get_node_or_null("CombatVFX")
	_assert_true(vfx != null and vfx.active_effect_count() <= vfx.active_impact_budget, "layered ordnance explosions remain inside the pooled VFX budget")
	var volume_mesh_found := false
	var ring_mesh_found := false
	if vfx != null:
		for slot in vfx.impact_slots:
			var effect_node: MeshInstance3D = slot.node
			volume_mesh_found = volume_mesh_found or effect_node.mesh is SphereMesh
			ring_mesh_found = ring_mesh_found or effect_node.mesh is TorusMesh
	_assert_true(volume_mesh_found and ring_mesh_found, "nuclear core and shockwave use pooled volumetric geometry instead of oversized impact cards")
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS: sustained flak placement, guided ordnance, nuclear risk, trails, and wing redeploy")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d ordnance assertion(s)" % failures.size())
		quit(1)

func _source_projectiles(source_id: StringName) -> Array[SidebayProjectile]:
	var found: Array[SidebayProjectile] = []
	for projectile in get_nodes_in_group("projectiles"):
		if projectile is SidebayProjectile and projectile.source_entity_id == source_id and not projectile.expired:
			found.append(projectile)
	return found

func _clear_source_projectiles(source_id: StringName) -> void:
	for projectile in get_nodes_in_group("projectiles"):
		if projectile is SidebayProjectile and projectile.source_entity_id == source_id:
			projectile.queue_free()

func _total_layers(ship: CombatShip) -> float:
	return ship.damage_state.shields + ship.damage_state.armor + ship.damage_state.hull

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
