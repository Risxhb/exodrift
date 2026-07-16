extends SceneTree

var failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for _frame in 3:
		await process_frame
	var node := SidebayCampaignNode.create(&"travel_test", "Vesper Relay", 1, 3, 1, SidebayCampaignNode.NodeType.COMBAT, 3, SidebayCampaignNode.ObjectiveType.INTERCEPTION)
	var state := SidebayRunState.create_new()
	state.active_carrier_id = &"cvn_sidebay"
	var screen = (load("res://scripts/ui/sector_travel_screen.gd") as GDScript).new()
	root.add_child(screen)
	screen.configure(node, state.fleet_snapshot(), 0)

	_assert_true(screen.phase == screen.Phase.DEPARTURE and screen.carrier != null, "sector travel opens on the selected carrier's departure phase")
	_assert_true(screen.warp_ring.mesh == root.get_node("CombatVFX").warp_ring_mesh, "travel transition reuses the authored combat warp aperture")
	_assert_true(screen.loading_bar.get_parent().anchor_top == 1.0 and screen.loading_bar.get_parent().offset_bottom < 0.0, "loading progress is anchored along the bottom frame")
	_assert_true(screen.destination_label.text.contains("VESPER RELAY"), "selected destination identity reaches the travel screen")

	for _frame in 120:
		if screen.loaded_scene != null:
			break
		await process_frame
	_assert_true(screen.loaded_scene != null, "battle scene streams during the travel cinematic")
	screen._enter_phase(screen.Phase.TRANSIT)
	_assert_true(screen.streaks.all(func(streak: MeshInstance3D) -> bool: return streak.visible), "carrier remains staged inside the visible warp-transit field")
	_assert_true(screen.status_label.text.contains("NAVIGATION") or screen.status_label.text.contains("TRANSIT"), "transit reports streaming or navigation readiness")

	screen._enter_phase(screen.Phase.ARRIVAL)
	_assert_true(screen.warp_root.visible and screen.status_label.text.contains("LOAD COMPLETE"), "loaded destination opens the arrival aperture before tactical handoff")
	var emitted_scenes: Array[PackedScene] = []
	screen.battle_scene_ready.connect(func(scene: PackedScene) -> void: emitted_scenes.append(scene))
	screen._request_handoff()
	_assert_true(screen.phase == screen.Phase.HANDOFF and not emitted_scenes.is_empty() and screen.loading_bar.value == 100.0, "arrival reaches 100 percent and releases the loaded battle scene")

	screen.queue_free()
	await process_frame
	await process_frame
	emitted_scenes.clear()
	state = null
	node = null
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("PASS: carrier departure, warp transit loading, arrival, and bottom progress bar")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d sector-travel assertion(s)" % failures.size())
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
