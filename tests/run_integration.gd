extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var carrier: PlayerCarrier = game.carrier
	var interceptor: SidebaySquadron = game.interceptor
	var scout: SidebaySquadron = game.scout
	var tactical: TacticalController = game.tactical
	var sensors: SidebaySensorSystem = game.sensors
	_assert_true(is_instance_valid(carrier), "main scene creates carrier")
	_assert_true(interceptor.crafts.size() == 4 and scout.crafts.size() == 3, "friendly force has exact wing counts")
	var initial_chase_zoom := carrier.chase_target_distance_m
	carrier.adjust_chase_zoom(1.0)
	_assert_true(carrier.chase_target_distance_m < initial_chase_zoom, "combat camera wheel zoom moves the chase camera inward")
	var steering_yaw := carrier.look_yaw
	var steering_pitch := carrier.look_pitch
	carrier.set_camera_orbiting(true)
	carrier.apply_camera_orbit(Vector2(90.0, -40.0))
	carrier._update_camera()
	_assert_true(absf(carrier.camera_orbit_yaw) > 0.1 and absf(carrier.camera_orbit_pitch) > 0.05, "middle-drag combat camera orbit rotates independently around the carrier")
	_assert_true(is_equal_approx(carrier.look_yaw, steering_yaw) and is_equal_approx(carrier.look_pitch, steering_pitch), "camera orbit does not alter the carrier steering heading")
	var camera_to_carrier := carrier.chase_camera.global_position.direction_to(carrier.global_position + carrier.global_transform.basis.y * 3.0)
	_assert_true(camera_to_carrier.dot(-carrier.chase_camera.global_transform.basis.z) > 0.98 and carrier.aim_direction.dot(camera_to_carrier) > 0.99 and carrier.aim_direction.dot(-carrier.global_transform.basis.z) < 0.98, "chase camera centers the carrier while its independent view directs flak away from the hull-forward axis")
	var orbit_before_mouse_look := Vector2(carrier.camera_orbit_yaw, carrier.camera_orbit_pitch)
	carrier.apply_mouse_look(Vector2(35.0, 12.0))
	_assert_true(Vector2(carrier.camera_orbit_yaw, carrier.camera_orbit_pitch) != orbit_before_mouse_look and is_equal_approx(carrier.look_yaw, steering_yaw), "normal mouse look moves the combat camera without rotating the carrier")
	var centered_aim := carrier.aim_direction
	var viewport_size := game.get_viewport().get_visible_rect().size
	carrier.set_web_cursor_steering(Vector2(viewport_size.x * 0.75, viewport_size.y * 0.5), viewport_size)
	carrier._update_camera()
	_assert_true(carrier.aim_direction.dot(centered_aim) < 0.995 and is_equal_approx(carrier.look_yaw, steering_yaw), "Web cursor position offsets the flak director without steering the hull")
	_assert_true(not carrier.flak_mounts.is_empty() and (-carrier.flak_mounts[0].global_transform.basis.z).dot(carrier.aim_direction) > 0.99, "visible flak mounts track the mouse director")
	carrier.flak_aim_uses_pointer = false
	carrier.web_cursor_steer = Vector2.ZERO
	carrier._update_camera()
	_assert_true(not game.hud.crosshair_label.visible and game.get_node_or_null("DeepStarfield") != null and game.get_node_or_null("NebulaStarBand") != null, "combat view removes the center crosshair and builds the layered deep-space backdrop")
	_assert_true(ResourceLoader.exists("res://scripts/ui/ui_style.gd") and game.hud.target_panel is Panel and game.hud.telemetry_panel.visible and game.hud.controls_panel.visible, "combat HUD uses the shared polished panel system with grouped telemetry and controls")
	var graphics := root.get_node_or_null("GraphicsQualityManager")
	var vfx := root.get_node_or_null("CombatVFX")
	var registry := root.get_node_or_null("CombatRegistry")
	_assert_true(graphics != null and vfx != null and registry != null, "graphics quality, pooled combat VFX, and combat registry services are available")
	var initial_quality: StringName = graphics.current_quality
	graphics.set_quality(&"low", false)
	await process_frame
	_assert_true(vfx.active_impact_budget == 24 and not game.get_node("ParallaxDust").visible, "low graphics profile applies its bounded VFX budget and hides tertiary backdrop layers immediately")
	graphics.set_quality(&"high", false)
	await process_frame
	_assert_true(vfx.active_impact_budget == 80 and game.get_node("ParallaxDust").visible, "high graphics profile restores the full pooled VFX budget and parallax backdrop")
	graphics.set_quality(initial_quality, false)
	_assert_true(registry.counts().x >= 6, "maintained combat registry tracks the active capital ships and craft without scene-wide projectile queries")
	_assert_true(ResourceLoader.exists("res://assets/textures/armor_panels.svg") and ResourceLoader.exists("res://assets/textures/nebula_card.svg"), "original GL-compatible armor and nebula textures are packaged as project resources")
	var radar_phase: float = game.hud.radar.pulse_phase
	for _frame in 3:
		await process_frame
	_assert_true(game.hud.radar.pulse_phase != radar_phase, "tactical radar pulse animates continuously around the carrier")
	carrier.set_camera_orbiting(false)
	carrier.global_position.y = CombatShip.VERTICAL_BATTLESPACE_LIMIT_M + 500.0
	carrier.velocity.y = 120.0
	carrier._enforce_battlespace_bounds()
	_assert_true(is_equal_approx(carrier.global_position.y, CombatShip.VERTICAL_BATTLESPACE_LIMIT_M) and is_zero_approx(carrier.velocity.y), "combat ships cannot climb above the vertical battlespace cap")
	for hostile in get_nodes_in_group("team_hostile"):
		if hostile is CombatShip:
			hostile.ai_enabled = false
	_assert_true(carrier.are_bays_open() and carrier.bay_assemblies.size() == 2, "carrier begins combat with two extended flight-ready hangar assemblies")
	carrier.flak_cooldown = 0.0
	var flak_before := _source_projectile_count(carrier.stable_entity_id)
	_assert_true(carrier.fire_flak(), "manual flak barrage fires when its cycle is ready")
	_assert_true(_source_projectile_count(carrier.stable_entity_id) - flak_before == carrier.flak_burst_count, "manual flak creates the full seven-round defensive burst")
	var flak_visuals: Array[SidebayProjectile] = []
	for candidate in get_nodes_in_group("projectiles"):
		if candidate is SidebayProjectile and candidate.source_entity_id == carrier.stable_entity_id:
			flak_visuals.append(candidate)
	_assert_true(flak_visuals.size() >= 2 and flak_visuals[0].get_child_count() > 0 and flak_visuals[1].get_child_count() > 0, "flak simulation nodes receive reusable shared-resource tracer visuals")
	if not flak_visuals.is_empty():
		_assert_true(flak_visuals[0].direction.dot(carrier.aim_direction) > 0.995, "manual flak follows the independent mouse director")
	if flak_visuals.size() >= 2:
		var first_core := flak_visuals[0].get_child(0).get_child(0) as MeshInstance3D
		var second_core := flak_visuals[1].get_child(0).get_child(0) as MeshInstance3D
		_assert_true(first_core.mesh == second_core.mesh and first_core.material_override == second_core.material_override, "flak shots share mesh and material resources instead of allocating per shot")
	_clear_source_projectiles(carrier.stable_entity_id)
	await process_frame
	carrier.missile_cooldown = 0.0
	var missile_before := _source_projectile_count(carrier.stable_entity_id)
	_assert_true(carrier.fire_missile(game.hostile_command), "long-range carrier salvo accepts a tracked target beyond the former five-kilometer limit")
	_assert_true(carrier.missile_weapon.range_m == 8500.0 and _source_projectile_count(carrier.stable_entity_id) - missile_before == carrier.missile_salvo_count, "carrier launches four independently tracked long-range missiles")
	_clear_source_projectiles(carrier.stable_entity_id)
	await process_frame
	_assert_true(game.hud.weapon_label.text.contains("FLAK CURTAIN") and game.hud.weapon_label.text.contains("MISSILE SALVO") and game.hud.weapon_label.text.contains("RELOAD"), "combat HUD exposes flak cycle, salvo reload, weapon counts, and missile range")
	# Tactical mode is live and preserves the carrier's current velocity.
	carrier.velocity = Vector3(0.0, 0.0, -140.0)
	var before := carrier.global_position
	tactical.set_enabled(true)
	await process_frame
	_assert_true(game.hud.map_info_panel.visible and game.hud.mode_panel.visible and not game.hud.telemetry_panel.visible, "tactical mode swaps combat telemetry for the polished command-link presentation")
	var initial_map_zoom := tactical.zoom_factor
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_event.pressed = true
	_assert_true(tactical.handle_input(wheel_event) and tactical.zoom_factor < initial_map_zoom, "tactical map wheel zoom changes persistent framing scale")
	for _frame in 12:
		await physics_frame
	_assert_true(carrier.global_position.distance_to(before) > 10.0, "carrier keeps moving while tactical map is open")
	_assert_true(not carrier.control_enabled, "tactical map transfers helm to maintained orders")
	tactical.set_enabled(false)
	# Command loss rejects new instructions but retains the last confirmed order.
	var confirmed := FleetOrder.at_position(FleetOrder.OrderType.HOLD, interceptor.representative_position(), 1.0)
	interceptor.command_link.last_confirmed_order = confirmed
	interceptor.command_link.update_for_distance(9000.0, 7000.0)
	var rejected := interceptor.issue_order(FleetOrder.at_position(FleetOrder.OrderType.MOVE, Vector3.ONE * 50.0, 2.0))
	_assert_true(not rejected, "disconnected squadron rejects a new order")
	_assert_true(interceptor.command_link.last_confirmed_order == confirmed, "disconnected squadron retains last confirmed order")
	interceptor.command_link.update_for_distance(0.0, 7000.0)
	# Active ping makes the command target eligible for a missile lock.
	sensors.emit_active_ping()
	var command_contact := sensors.get_contact(&"hostile_command")
	_assert_true(command_contact != null and command_contact.is_targetable(), "active ping identifies hostile command ship")
	game.hud.update_target(command_contact, game.hostile_command.display_name, game.hostile_command)
	game.hud._process(0.016)
	_assert_true(game.hud.locked_target == game.hostile_command and game.hud.target_label.text.contains("LOCKED"), "target lock exposes directional and layered ship-status presentation")
	# Speed up only the test flight-deck timings; production values remain unchanged.
	for wing in [interceptor, scout]:
		wing.definition.launch_interval_seconds = 0.02
		wing.definition.recovery_interval_seconds = 0.02
		wing.definition.service_seconds = 0.05
		for craft in wing.crafts:
			craft.definition.maximum_speed_mps = 2600.0
			craft.definition.acceleration_mps2 = 4000.0
		wing.request_launch()
	await _wait_for_wing_state(interceptor, BayOperation.State.DEPLOYED, 360)
	await _wait_for_wing_state(scout, BayOperation.State.DEPLOYED, 360)
	_assert_true(interceptor.deployed_craft_count() == 4, "port interceptor wing launches all craft")
	_assert_true(scout.deployed_craft_count() == 3, "starboard scout wing launches all craft")
	var interceptor_ids := _craft_ids(interceptor)
	var scout_ids := _craft_ids(scout)
	interceptor.request_recall()
	scout.request_recall()
	await _wait_for_wing_state(interceptor, BayOperation.State.READY, 900)
	await _wait_for_wing_state(scout, BayOperation.State.READY, 900)
	_assert_true(interceptor.operation.state == BayOperation.State.READY, "interceptor wing recovers, services, and becomes ready")
	_assert_true(scout.operation.state == BayOperation.State.READY, "scout wing recovers, services, and becomes ready")
	_assert_true(_craft_ids(interceptor) == interceptor_ids and _craft_ids(scout) == scout_ids, "bay cycle preserves stable craft identities without duplication")
	interceptor.request_launch()
	await _wait_for_wing_state(interceptor, BayOperation.State.DEPLOYED, 360)
	game.request_withdrawal()
	_assert_true(game.extraction_requested and is_instance_valid(game.extraction_beacon), "jump preparation creates a visible extraction objective and recalls deployed wings")
	interceptor.crafts[0].definition.maximum_speed_mps = 100.0
	interceptor.crafts[0].deploy(game.extraction_position + Vector3(5000.0, 0.0, 0.0), Vector3.ZERO)
	game._spawn_escape_pod(&"test_lost_craft", game.extraction_position + Vector3(900.0, 0.0, 0.0), 2)
	carrier.global_position = game.extraction_position
	game._process_objective(0.016)
	_assert_true(not game.battle_finished and not carrier.are_bays_closed(), "reaching the jump corridor cannot resolve withdrawal while hangar bays remain open")
	game.request_withdrawal()
	_assert_true(game.emergency_bay_seal and not scout.request_launch(), "second withdrawal command seals the bays and locks new flight operations")
	await _wait_for_bays_closed_or_battle(game, 420)
	carrier.global_position = game.extraction_position
	carrier.velocity = Vector3.ZERO
	game._process_objective(0.016)
	_assert_true(game.pursuit_spawned and is_instance_valid(game.pursuit_ship), "bay retraction keeps the task force exposed long enough for withdrawal pursuit")
	_assert_true(game.battle_finished and game.battle_outcome == "withdrawal" and carrier.are_bays_closed(), "jump completes only after both retractable bays report sealed (finished=%s outcome=%s closure=%.2f target=%.2f state=%s)" % [game.battle_finished, game.battle_outcome, carrier.bay_closure, carrier.bay_target_closure, carrier.bay_status()])
	var withdrawal_report: Dictionary = game._create_battle_report()
	_assert_true(int(withdrawal_report.get("interceptor_stragglers", 0)) >= 1 and int(withdrawal_report.get("survivors_adrift", 0)) == 2, "emergency bay seal reports separated craft and unrecovered escape pods (craft=%d survivors=%d)" % [int(withdrawal_report.get("interceptor_stragglers", 0)), int(withdrawal_report.get("survivors_adrift", 0))])
	paused = false
	game.queue_free()
	await process_frame
	await _test_mission_variety(packed)
	if failures.is_empty():
		print("PASS: Sidebay integrated first-playable checks")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d integration assertion(s)" % failures.size())
		quit(1)

func _wait_for_wing_state(wing: SidebaySquadron, target_state: BayOperation.State, maximum_frames: int) -> void:
	for _frame in maximum_frames:
		if wing.operation.state == target_state:
			return
		await physics_frame

func _wait_for_bays_closed_or_battle(game: Node, maximum_frames: int) -> void:
	for _frame in maximum_frames:
		if game.carrier.are_bays_closed() and game.battle_finished:
			return
		await physics_frame

func _source_projectile_count(source_id: StringName) -> int:
	var count := 0
	for candidate in get_nodes_in_group("projectiles"):
		if candidate is SidebayProjectile and candidate.source_entity_id == source_id:
			count += 1
	return count

func _clear_source_projectiles(source_id: StringName) -> void:
	for candidate in get_nodes_in_group("projectiles"):
		if candidate is SidebayProjectile and candidate.source_entity_id == source_id:
			candidate.queue_free()

func _test_mission_variety(packed: PackedScene) -> void:
	var cases := [
		{"type": SidebayCampaignNode.ObjectiveType.DEFENSE, "outcome": "defense"},
		{"type": SidebayCampaignNode.ObjectiveType.ESCORT, "outcome": "escort"},
		{"type": SidebayCampaignNode.ObjectiveType.CAPTURE, "outcome": "capture"}
	]
	for mission in cases:
		var mission_game := packed.instantiate()
		mission_game.campaign_objective_type = mission.type
		root.add_child(mission_game)
		for _frame in 5:
			await process_frame
		for hostile in get_nodes_in_group("team_hostile"):
			if hostile is CombatShip:
				hostile.ai_enabled = false
		match mission.type:
			SidebayCampaignNode.ObjectiveType.DEFENSE:
				_assert_true(is_instance_valid(mission_game.objective_ship), "defense mission spawns the Longwatch relay")
				mission_game.objective_elapsed = 25.0
				mission_game._process_objective(0.016)
			SidebayCampaignNode.ObjectiveType.ESCORT:
				_assert_true(is_instance_valid(mission_game.objective_ship), "escort mission spawns the Atlas convoy")
				mission_game.objective_ship.global_position = mission_game.objective_destination
				mission_game._process_objective(0.016)
			SidebayCampaignNode.ObjectiveType.CAPTURE:
				mission_game.carrier.global_position = mission_game.objective_destination
				for hostile in get_nodes_in_group("team_hostile"):
					if hostile is CombatShip:
						hostile.global_position = Vector3(9000.0, 9000.0, 9000.0)
				mission_game.capture_progress = 11.9
				mission_game._process_objective(0.2)
		_assert_true(mission_game.battle_finished and mission_game.battle_outcome == mission.outcome, "%s objective resolves through its unique success condition" % mission.outcome)
		paused = false
		mission_game.queue_free()
		await process_frame

func _craft_ids(wing: SidebaySquadron) -> Array[StringName]:
	var result: Array[StringName] = []
	for craft in wing.crafts:
		if is_instance_valid(craft):
			result.append(craft.stable_entity_id)
	return result

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
