extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.training_trial = true
	root.add_child(game)
	for _frame in 30:
		if is_instance_valid(game.training_controller):
			break
		await process_frame
	var escort: CombatShip = game.escort
	escort.ai_enabled = true
	_test_order_behaviors(escort, game.hostile_command)
	_test_stances_and_boundaries(escort, game.hostile_command)
	_test_squadron_leadership_and_passes(game.interceptor, game.hostile_command)
	_test_point_defense_priority(game)
	_test_carrier_navigation_snapshot(game.carrier)
	_test_tactical_carrier_origin(game)
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: fleet order behaviors, stance thresholds, formations, attack passes, recovery, and point defense")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d fleet-behavior assertion(s)" % failures.size())
		quit(1)


func _test_order_behaviors(escort: CombatShip, target: CombatShip) -> void:
	var move := FleetOrder.at_position(FleetOrder.OrderType.MOVE, escort.global_position, 0.0)
	escort.velocity = Vector3.ZERO
	escort.issue_order(move)
	escort._process_ai(0.1)
	_assert_true(move.status == FleetOrder.Status.COMPLETED and escort.current_order.order_type == FleetOrder.OrderType.HOLD, "Move arrives, brakes, completes, and transitions to Hold")
	var hold := FleetOrder.at_position(FleetOrder.OrderType.HOLD, escort.global_position, 0.0)
	hold.target_facing = Vector3.RIGHT
	escort.rotation.y = 0.0
	escort.issue_order(hold)
	escort._process_ai(0.5)
	_assert_true(absf(escort.rotation.y) > 0.01 and escort.current_order == hold, "Hold preserves its position and actively restores its confirmed facing")
	escort.target_state_provider = func(_id: StringName) -> Dictionary:
		return {"visible": false, "destroyed": false, "position": escort.global_position + Vector3(500.0, 0.0, 0.0), "velocity": Vector3.ZERO}
	var lost_attack := FleetOrder.at_entity(FleetOrder.OrderType.ATTACK, target.stable_entity_id, 0.0)
	lost_attack.target_position = escort.global_position + Vector3(500.0, 0.0, 0.0)
	escort.issue_order(lost_attack)
	escort._process_ai(0.1)
	_assert_true(escort.current_order == lost_attack and escort.current_target == null and escort._track_lost_order_id == lost_attack.order_id, "Attack stops tracking hidden entities and proceeds only to the last confirmed position")
	escort.target_state_provider = func(_id: StringName) -> Dictionary:
		return {"visible": false, "destroyed": true, "position": target.global_position, "velocity": Vector3.ZERO, "node": target}
	escort._process_ai(0.1)
	_assert_true(lost_attack.status == FleetOrder.Status.COMPLETED and escort.current_order.order_type == FleetOrder.OrderType.HOLD, "Attack completes when the designated target is confirmed destroyed")
	escort.target_state_provider = Callable()
	var interact := FleetOrder.interaction(&"test_objective", "Defend", escort.global_position, 180.0, 0.0)
	escort.issue_order(interact)
	escort._process_ai(0.1)
	_assert_true(escort.current_order == interact and escort.velocity.length() < escort.definition.maximum_speed_mps, "Interact approaches the authored radius and holds until mission resolution")


func _test_stances_and_boundaries(escort: CombatShip, neighbor: CombatShip) -> void:
	for doctrine in [{"stance": &"aggressive", "range": 0.70, "leash": 1.5}, {"stance": &"balanced", "range": 0.82, "leash": 1.0}, {"stance": &"defensive", "range": 0.95, "leash": 0.6}, {"stance": &"evade_return", "range": 1.1, "leash": 0.0}]:
		escort.set_stance(doctrine.stance)
		_assert_true(is_equal_approx(escort._stance_range_ratio(), float(doctrine.range)) and is_equal_approx(escort._stance_pursuit_multiplier(), float(doctrine.leash)), "%s stance exposes its authored range and pursuit behavior" % String(doctrine.stance).capitalize())
	var old_position := escort.global_position
	escort.global_position = Vector3(0.0, CombatShip.VERTICAL_BATTLESPACE_LIMIT_M + 500.0, 0.0)
	escort.velocity = Vector3(0.0, 100.0, 0.0)
	escort._enforce_battlespace_bounds()
	_assert_true(is_equal_approx(escort.global_position.y, CombatShip.VERTICAL_BATTLESPACE_LIMIT_M) and is_zero_approx(escort.velocity.y), "boundary recovery clamps an escaping ship and cancels outward velocity")
	escort.global_position = old_position
	neighbor.global_position = escort.global_position + Vector3(10.0, 0.0, 0.0)
	_assert_true(escort._separation_velocity().length_squared() > 0.0, "collision separation produces an avoidance vector inside combined safety radii")


func _test_squadron_leadership_and_passes(wing: SidebaySquadron, target: CombatShip) -> void:
	wing.operation.state = BayOperation.State.DEPLOYED
	for index in 2:
		var craft: FighterCraft = wing.crafts[index]
		craft.deploy(wing.home_carrier.global_position + Vector3(index * 40.0, 0.0, -200.0), Vector3.ZERO)
		craft.set_physics_process(false)
	wing._update_formation_leader()
	var first_leader := wing.fleet_command.formation_leader_id
	wing.crafts[0].is_destroyed = true
	wing._update_formation_leader()
	_assert_true(not first_leader.is_empty() and wing.fleet_command.formation_leader_id == wing.crafts[1].stable_entity_id, "the first surviving deployed craft automatically inherits formation leadership")
	for formation in FleetCommandState.VALID_FORMATIONS:
		for spacing in FleetCommandState.VALID_SPACING:
			wing.set_formation(formation, spacing)
			var offset := wing._formation_offset(1)
			_assert_true(offset.is_finite(), "%s/%s formation produces a finite leader-local slot" % [String(formation), String(spacing)])
	var craft: FighterCraft = wing.crafts[1]
	craft.global_position = target.global_position + Vector3(0.0, 0.0, 80.0)
	craft.velocity = Vector3(0.0, 0.0, -300.0)
	craft.command_attack(target)
	craft.attack_phase = FighterCraft.AttackPhase.FIRING_RUN
	craft.attack_phase_elapsed = 0.0
	craft._process_attack_maneuver()
	_assert_true(craft.attack_phase == FighterCraft.AttackPhase.BREAKAWAY, "fighters leave a close firing run through a committed breakaway state")
	craft.global_position = target.global_position + Vector3(0.0, 0.0, craft._preferred_weapon_range() * 1.3)
	craft._process_attack_maneuver()
	_assert_true(craft.attack_phase == FighterCraft.AttackPhase.REFORM, "a completed breakaway transitions to an explicit reform state")
	craft.attack_phase_elapsed = 3.0
	craft._process_attack_maneuver()
	_assert_true(craft.attack_phase == FighterCraft.AttackPhase.APPROACH, "reformed fighters begin a new predictive approach pass")
	wing.set_stance(&"aggressive")
	craft.ammunition = 1
	craft.endurance_seconds = 11.0
	_assert_true(not wing._craft_should_return(craft), "aggressive wings remain committed above their hard ammunition, hull, and endurance limits")
	wing.set_stance(&"defensive")
	craft.endurance_seconds = 24.0
	_assert_true(wing._craft_should_return(craft), "defensive wings recall at the authored 25-second endurance threshold")


func _test_point_defense_priority(game: Node) -> void:
	var carrier: PlayerCarrier = game.carrier
	var far_round := SidebayProjectile.new()
	game.add_child(far_round)
	far_round.configure(&"hostile", &"pd_far", carrier.global_position + Vector3(800.0, 0.0, 0.0), Vector3.LEFT, 200.0, 10.0, 2000.0, null, 0.0, true, "missile")
	far_round.set_physics_process(false)
	var imminent := SidebayProjectile.new()
	game.add_child(imminent)
	imminent.configure(&"hostile", &"pd_imminent", carrier.global_position + Vector3(700.0, 0.0, 0.0), Vector3.LEFT, 1000.0, 10.0, 2000.0, carrier, 0.0, true, "nuclear")
	imminent.radial_warhead = true
	imminent.set_physics_process(false)
	carrier.point_defense_cooldown = 0.0
	carrier._process_point_defense()
	_assert_true(carrier.point_defense_target == imminent and carrier.point_defense_last_tti < 1.0, "point defense prioritizes time-to-impact and protected-unit risk instead of registry order")
	far_round.queue_free()
	imminent.queue_free()


func _test_carrier_navigation_snapshot(carrier: PlayerCarrier) -> void:
	var destination := carrier.global_position + Vector3(800.0, 0.0, -1200.0)
	carrier.set_autopilot(destination)
	var snapshot := carrier.command_snapshot()
	_assert_true(String(snapshot.current_order.type) == "Set Course" and snapshot.current_order.target_position == destination and String(snapshot.link) == "Local", "carrier tactical movement drives autopilot and appears in the common command snapshot")


func _test_tactical_carrier_origin(game: Node) -> void:
	var tactical: TacticalController = game.tactical
	tactical.camera_focus_position = game.carrier.global_position + Vector3(2500.0, 0.0, 1800.0)
	tactical.follow_carrier_focus = false
	tactical.center_camera_on_carrier(false)
	var grid_bounds := tactical.grid_instance.get_aabb()
	_assert_true(tactical.follow_carrier_focus and tactical.camera_focus_position == game.carrier.global_position, "tactical recenter restores the carrier as the followed camera origin")
	_assert_true(grid_bounds.size.x >= TacticalController.GRID_EXTENT_M * 2.0 and grid_bounds.size.z >= TacticalController.GRID_EXTENT_M * 2.0, "carrier-origin grid covers the full tactical battlespace instead of a local patch")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
