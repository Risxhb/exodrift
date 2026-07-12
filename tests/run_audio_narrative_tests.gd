extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog := SidebayRunState.operational_event_catalog()
	var event_ids: Dictionary = {}
	for event in catalog:
		event_ids[String(event.event_id)] = true
		_assert_true(str(event.get("body", "")).length() > 80, "%s has authored narrative body copy" % event.event_id)
		_assert_true((event.get("choices", []) as Array).size() == 2, "%s offers two command decisions" % event.event_id)
	_assert_true(catalog.size() >= 10 and event_ids.size() == catalog.size(), "campaign has at least ten unique operational events")

	var state := SidebayRunState.create_new(1616)
	state.pending_operational_event = _event(catalog, &"reactor_hymn")
	state.carrier_armor = 0.5
	var result := state.resolve_operational_event(&"cold_shutdown")
	_assert_true(is_equal_approx(state.carrier_armor, 0.65) and state.supplies == 90, "reactor narrative choice applies its stated armor and supply consequences")
	_assert_true(result.contains("repaired") and state.resolved_operational_event_ids.has(&"reactor_hymn"), "resolved narrative is logged and cannot repeat")

	var audio := SidebayAudio.new()
	root.add_child(audio)
	audio.configure_sector(2, true)
	audio.play_radio("BASTION: Core exposure window open.", 0.9)
	audio.set_intensity(0.8)
	_assert_true(audio.sector_index == 2 and is_equal_approx(audio.target_intensity, 0.8), "adaptive score tracks sector identity and combat pressure")
	_assert_true(audio.last_radio_message.contains("Core exposure") and audio.radio_history.size() == 1, "radio callouts retain authored encounter context")
	audio.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: M15 adaptive audio and expanded operational narrative")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d audio/narrative assertion(s)" % failures.size())
		quit(1)

func _event(catalog: Array[Dictionary], event_id: StringName) -> Dictionary:
	for event in catalog:
		if event.event_id == event_id:
			return event.duplicate(true)
	return {}

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
