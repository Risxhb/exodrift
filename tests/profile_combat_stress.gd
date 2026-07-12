extends SceneTree

const SAMPLE_FRAMES := 900
const WARMUP_FRAMES := 240

func _initialize() -> void:
	call_deferred("_profile")

func _profile() -> void:
	root.size = Vector2i(1920, 1080)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in 8:
		await process_frame
	for hostile in get_nodes_in_group("team_hostile"):
		if hostile is CombatShip:
			hostile.ai_enabled = false
			hostile.damage_state.shields = 100000.0
			hostile.damage_state.armor = 100000.0
			hostile.damage_state.hull = 100000.0
	scene.carrier.damage_state.shields = 100000.0
	scene.carrier.damage_state.armor = 100000.0
	scene.carrier.damage_state.hull = 100000.0
	await scene.interceptor.start_deployed(scene.carrier.global_position + Vector3(-260.0, 40.0, -320.0))
	await scene.scout.start_deployed(scene.carrier.global_position + Vector3(260.0, -40.0, -360.0))
	scene.sensors.emit_active_ping()
	var frame_times_ms: Array[float] = []
	var maximum_nodes := 0
	var warm_node_count := 0
	var warm_projectile_count := 0
	var registry := root.get_node("CombatRegistry")
	var started_usec := Time.get_ticks_usec()
	var previous_usec := started_usec
	for frame in SAMPLE_FRAMES:
		if frame % 12 == 0:
			scene.carrier.flak_cooldown = 0.0
			scene.carrier.fire_flak()
		if frame % 90 == 0:
			scene.carrier.missile_cooldown = 0.0
			scene.carrier.fire_missile(scene.hostile_command)
		if frame % 75 == 0 and is_instance_valid(scene.hostile_command):
			var hostile_weapon: WeaponDefinition = scene.hostile_command.definition.weapons[0]
			scene.hostile_command.spawn_projectile(hostile_weapon, scene.hostile_command.global_position, scene.hostile_command.global_position.direction_to(scene.carrier.global_position), scene.carrier)
		await process_frame
		var now_usec := Time.get_ticks_usec()
		if frame >= WARMUP_FRAMES:
			frame_times_ms.append(float(now_usec - previous_usec) / 1000.0)
		var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		maximum_nodes = maxi(maximum_nodes, node_count)
		if frame == WARMUP_FRAMES:
			warm_node_count = node_count
			warm_projectile_count = registry.counts().y
		previous_usec = now_usec
	frame_times_ms.sort()
	var p95 := _percentile(frame_times_ms, 0.95)
	var p99 := _percentile(frame_times_ms, 0.99)
	var elapsed_seconds := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var effective_fps := float(SAMPLE_FRAMES) / maxf(0.001, elapsed_seconds)
	var final_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var vfx := root.get_node("CombatVFX")
	var final_registry_counts: Vector2i = registry.counts()
	var expected_projectile_growth := maxi(0, final_registry_counts.y - warm_projectile_count) * 4
	print("STRESS_PERF: resolution=%dx%d effective=%.1f p95=%.2fms p99=%.2fms nodes_warm=%d nodes_final=%d nodes_max=%d projectiles_warm=%d projectiles_final=%d registry=%s vfx_active=%d vfx_dropped=%d" % [root.size.x, root.size.y, effective_fps, p95, p99, warm_node_count, final_nodes, maximum_nodes, warm_projectile_count, final_registry_counts.y, final_registry_counts, vfx.active_effect_count(), vfx.dropped_effects])
	var stable_nodes := final_nodes <= warm_node_count + expected_projectile_growth + 60
	var passed := effective_fps >= 60.0 and p95 <= 16.7 and p99 <= 25.0 and stable_nodes
	scene.queue_free()
	await process_frame
	quit(0 if passed else 1)

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(ceili(float(values.size()) * fraction) - 1, 0, values.size() - 1)
	return values[index]
