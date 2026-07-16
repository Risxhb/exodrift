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
	_assert_true(ExodriftInputSettings.ACTION_LABELS.get("flak_screen") == "Toggle Auto Flak" and not ExodriftInputSettings.ACTION_LABELS.has("flak_range_decrease"), "1 toggles the automatic flak screen instead of requiring repeated fire commands")
	_assert_true(carrier.automatic_flak_enabled and carrier.automatic_flak_interval_seconds >= 1.0, "automatic flak begins online with a paced curtain interval")
	_assert_true(ExodriftInputSettings.action_key("toggle_all_wings") == KEY_B, "B provides the remappable aggregate hangar-wing deployment and retraction control")
	_assert_true(carrier.definition.acceleration_mps2 <= 18.0 and carrier.definition.rotation_speed_radians <= 0.38, "carrier uses capital-ship acceleration and turn-rate limits")
	_assert_true(not carrier.engine_trails.is_empty() and carrier.engine_trails[0].has("outer") and carrier.engine_trails[0].has("inner") and carrier.engine_trails[0].has("core"), "carrier engine banks expose layered propulsion-demand plumes")
	_assert_true(is_equal_approx(carrier.flak_weapon.range_m, 3200.0) and is_equal_approx(carrier.flak_airburst_radius_m, 250.0), "carrier flak uses the 3.2 km battery envelope and 250 m airburst radius")
	_assert_true(carrier.chase_zoom_percent() == 0, "the authored carrier framing is the signed zoom scale's zero point")
	carrier.adjust_chase_zoom(-20.0)
	_assert_true(carrier.chase_zoom_percent() < 0 and carrier.chase_target_distance_m > 260.0, "signed zoom allows substantially farther carrier command framing")
	carrier.chase_target_distance_m = PlayerCarrier.CHASE_DEFAULT_DISTANCE_M
	carrier.chase_distance_m = PlayerCarrier.CHASE_DEFAULT_DISTANCE_M

	var lock_target: CombatShip = game.hostile_command
	lock_target.global_position = carrier.global_position + Vector3(0.0, 0.0, -1800.0)
	lock_target.velocity = Vector3.ZERO
	carrier.flak_cooldown = 0.0
	var before_flak := _source_projectiles(carrier.stable_entity_id).size()
	_assert_true(not carrier.fire_flak(null), "flak rejects fire without a valid target lock")
	game.target_lock = lock_target
	_assert_true(game._fire_flak_barrage() and game.hud.notification_label.text.contains("FRIENDLIES KEEP CLEAR"), "1-style flak command immediately fires toward an in-range target lock and warns about the hazardous sector")
	_assert_true(carrier.pending_flak_shots.size() == carrier.flak_burst_count - 1, "capital batteries stagger the remaining rounds instead of spawning a simultaneous wall")
	carrier._process_flak_salvo_queue(1.0)
	var flak_rounds := _source_projectiles(carrier.stable_entity_id).filter(func(projectile: SidebayProjectile) -> bool: return projectile.projectile_role == "flak")
	_assert_true(flak_rounds.size() >= before_flak + carrier.flak_burst_count, "lock-directed fire creates a staggered seven-round wall")
	var screen_round: SidebayProjectile = flak_rounds.back() if not flak_rounds.is_empty() else null
	var lock_direction := carrier.global_position.direction_to(lock_target.global_position)
	_assert_true(screen_round != null and screen_round.direction.dot(lock_direction) > 0.99 and screen_round.airburst_distance_m > 0.0 and is_equal_approx(screen_round.blast_radius_m, carrier.flak_airburst_radius_m), "flak rounds follow the target lock and carry a bounded airburst fuse")
	if screen_round != null:
		_assert_true(screen_round.friendly_fire and screen_round.airburst_intercepts_friendlies and is_equal_approx(screen_round.airburst_capital_damage_multiplier, carrier.flak_capital_damage_multiplier), "the flak firing sector is a friendly-fire hazard with reduced capital damage")
		var burst_position := carrier.global_position + lock_direction * 1800.0
		var hostile_weapon: WeaponDefinition = game.hostile_command.definition.weapons[0]
		var threat: SidebayProjectile = game.hostile_command.spawn_projectile(hostile_weapon, burst_position + Vector3(20.0, 0.0, 0.0), Vector3.FORWARD, carrier)
		var friendly_missile: SidebayProjectile = carrier.spawn_projectile(carrier.missile_weapon, burst_position + Vector3(-20.0, 0.0, 0.0), Vector3.FORWARD, lock_target)
		var hostile_craft: CombatShip = game.hostile_fighters.crafts[0]
		var friendly_craft: CombatShip = game.interceptor.crafts[0]
		var path_round: SidebayProjectile = flak_rounds.front()
		friendly_craft.global_position = path_round.global_position
		_assert_true(path_round._check_proximity_hit(), "flak detects allied strikecraft that stray through the firing solution")
		lock_target.global_position = burst_position + Vector3(0.0, 0.0, 25.0)
		game.escort.global_position = burst_position + Vector3(25.0, 0.0, 0.0)
		hostile_craft.global_position = burst_position + Vector3(0.0, 25.0, 0.0)
		friendly_craft.global_position = burst_position + Vector3(0.0, -25.0, 0.0)
		var hostile_capital_before := _total_layers(lock_target)
		var friendly_capital_before := _total_layers(game.escort)
		var hostile_craft_before := _total_layers(hostile_craft)
		var friendly_craft_before := _total_layers(friendly_craft)
		screen_round.global_position = burst_position
		screen_round.detonate()
		_assert_true(threat.expired and friendly_missile.expired, "the flak wall destroys hostile and friendly missiles caught in its firing sector")
		var hostile_capital_damage := hostile_capital_before - _total_layers(lock_target)
		var friendly_capital_damage := friendly_capital_before - _total_layers(game.escort)
		var hostile_craft_damage := hostile_craft_before - _total_layers(hostile_craft)
		var friendly_craft_damage := friendly_craft_before - _total_layers(friendly_craft)
		_assert_true(hostile_craft_damage > 0.0 and friendly_craft_damage > 0.0, "flak heavily damages hostile and friendly strikecraft in the saturated sector")
		_assert_true(hostile_capital_damage > 0.0 and friendly_capital_damage > 0.0 and hostile_capital_damage < hostile_craft_damage * 0.5, "flak applies light damage to hostile and friendly capital ships")
		var active_roles: Array[String] = []
		var combat_vfx := root.get_node_or_null("CombatVFX")
		if combat_vfx != null:
			for slot in combat_vfx.impact_slots:
				if bool(slot.active):
					active_roles.append(String(slot.role))
		_assert_true(active_roles.has("flak_flash") and active_roles.has("flak_smoke") and active_roles.has("flak_pressure"), "airburst layers a flash, dark smoke, and pressure ring from the pooled VFX system")

	carrier.flak_cooldown = 0.0
	carrier.automatic_flak_cycle_seconds = 0.0
	lock_target.global_position = carrier.global_position + lock_direction * 6400.0
	game.target_lock = lock_target
	game._process_automatic_flak()
	carrier._process_flak_salvo_queue(1.0)
	var automatic_rounds := _source_projectiles(carrier.stable_entity_id).filter(func(projectile: SidebayProjectile) -> bool: return projectile.projectile_role == "flak" and not projectile.friendly_fire and not projectile.airburst_intercepts_friendlies)
	_assert_true(carrier.automatic_flak_cycle_seconds > 0.0 and automatic_rounds.size() >= carrier.flak_burst_count, "automatic director refreshes a full deconflicted curtain without a fire-button press")
	if not automatic_rounds.is_empty():
		_assert_true(is_equal_approx(automatic_rounds[0].airburst_distance_m, carrier.flak_weapon.range_m) and automatic_rounds[0].airburst_distance_m < carrier.global_position.distance_to(lock_target.global_position), "distant hostile tracks place the automatic flak screen between the fleets at the battery envelope")

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
			volume_mesh_found = volume_mesh_found or effect_node.mesh == vfx.blast_volume_mesh
			ring_mesh_found = ring_mesh_found or effect_node.mesh == vfx.blast_ring_mesh
	_assert_true(volume_mesh_found and ring_mesh_found, "nuclear core and shockwave use the Blender-authored pooled geometry instead of oversized impact cards")
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS: automatic deconflicted flak screen, guided ordnance, nuclear risk, trails, and wing redeploy")
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
