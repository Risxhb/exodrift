extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var tutorial := ExodriftTutorialScreen.new()
	root.add_child(tutorial)
	tutorial.configure()
	await process_frame
	_assert_true(tutorial.LESSON_TITLES.size() == 9, "tutorial contains all nine lessons")
	_assert_true(tutorial.full_text.contains("CVN Sidebay"), "orientation opens with the authored command-link briefing")
	_assert_true(tutorial.dialogue_label.visible_characters == 0, "typewriter begins with hidden text")
	tutorial._process(0.1)
	_assert_true(tutorial.dialogue_label.visible_characters > 0 and tutorial.dialogue_label.visible_characters < tutorial.full_text.length(), "typewriter reveals text at a bounded rate")
	_assert_true(tutorial.mouth_open, "mouth animation toggles while the transmission is typing")
	var speaking_base := tutorial.portrait.texture as AtlasTexture
	_assert_true(speaking_base != null and is_zero_approx(speaking_base.region.position.x), "speaking keeps the pose's base portrait fixed")
	_assert_true(tutorial.mouth_overlay.visible and not tutorial.eye_overlay.visible, "speaking reveals only the registered mouth overlay")
	tutorial._advance()
	_assert_true(tutorial.dialogue_label.visible_characters == -1 and not tutorial.mouth_open, "first advance completes the current transmission and closes the mouth")
	_assert_true(not tutorial.mouth_overlay.visible, "completing transmission hides the mouth overlay")
	tutorial._advance()
	_assert_true(tutorial.lesson_index == 1 and tutorial.full_text.contains(ExodriftInputSettings.key_label("accelerate")), "next lesson resolves live helm bindings")
	tutorial._show_lesson(3)
	var instruction_frame := tutorial.portrait.texture as AtlasTexture
	_assert_true(instruction_frame != null and is_equal_approx(instruction_frame.region.position.y, 400.0), "fire-control lesson selects the instruction pose")
	tutorial._show_lesson(6)
	_assert_true(tutorial.full_text.contains(ExodriftInputSettings.key_label("carrier_operations")), "carrier-operations lesson resolves its live binding")
	_assert_true(tutorial.full_text.contains("damage-control") and tutorial.full_text.contains("rescue countdown"), "carrier-operations lesson covers triage and officer rescue")
	tutorial._show_lesson(7)
	var alert_frame := tutorial.portrait.texture as AtlasTexture
	_assert_true(alert_frame != null and is_equal_approx(alert_frame.region.position.y, 800.0), "campaign lesson selects the alert encouragement pose")
	tutorial.next_blink = 0.0
	tutorial._process_blink(0.01)
	_assert_true(tutorial.blink_closed, "portrait enters its closed-eye blink state")
	var blinking_base := tutorial.portrait.texture as AtlasTexture
	_assert_true(blinking_base != null and is_zero_approx(blinking_base.region.position.x), "blinking does not replace or reframe the base portrait")
	_assert_true(tutorial.eye_overlay.visible, "blink reveals only the registered eye overlay")
	tutorial._process_blink(0.13)
	_assert_true(not tutorial.blink_closed and tutorial.next_blink >= 2.5 and tutorial.next_blink <= 4.5, "blink returns to open eyes and schedules the next randomized interval")
	_assert_true(not tutorial.eye_overlay.visible, "completed blink hides the eye overlay")
	tutorial.close()
	await process_frame
	var reopened := ExodriftTutorialScreen.new()
	root.add_child(reopened)
	reopened.configure()
	await process_frame
	_assert_true(reopened.lesson_index == 0 and reopened.revealed_characters < reopened.full_text.length() and not reopened.blink_closed, "repeated tutorial entry starts without stale page or animation state")
	reopened.close()
	await process_frame
	var trial_entry := ExodriftTutorialScreen.new()
	root.add_child(trial_entry)
	trial_entry.configure()
	var trial_result := {"requested": false}
	trial_entry.trial_requested.connect(func() -> void: trial_result.requested = true)
	trial_entry._show_lesson(trial_entry.LESSON_TITLES.size() - 1)
	trial_entry._advance()
	trial_entry._advance()
	_assert_true(bool(trial_result.requested), "final briefing action launches the playable combat trial")
	await process_frame
	if failures.is_empty():
		print("PASS: tutorial lessons, live bindings, portrait states, combat-trial launch, and clean re-entry")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d tutorial assertion(s)" % failures.size())
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
