extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var recorder := root.get_node_or_null("PlaytestRecorder") as ExodriftPlaytestRecorder
	_assert_true(recorder != null, "playtest recorder is available as a project service")
	recorder.start_session()
	recorder.begin_run("TEST-RUN")
	for counter in [&"onboarding_completed", &"active_pings", &"tactical_opens", &"orders_issued", &"wing_launches", &"wing_recalls", &"flak_barrages", &"missile_salvos", &"runs_completed"]:
		recorder.increment(counter)
	recorder.begin_battle({"node_id": "s2_boss", "sector": 1, "layout": "vesper_hunt", "objective": SidebayCampaignNode.ObjectiveType.COMMAND_STRIKE, "boss": true})
	recorder.active_battle["started_msec"] = Time.get_ticks_msec() - 2500
	recorder.finish_battle({"outcome": "command_strike", "objective_success": true, "carrier_hull": 0.72, "interceptor_craft_count": 3, "scout_craft_count": 2, "survivors_adrift": 0})
	var acceptance := recorder.acceptance_snapshot()
	_assert_true(bool(acceptance.onboarding_completed) and bool(acceptance.used_active_ping) and bool(acceptance.opened_tactical_map) and bool(acceptance.issued_orders), "first-time command acceptance derives from recorded behavior")
	_assert_true(int(acceptance.battle_count) == 1 and bool(acceptance.completed_run), "battle and run completion appear in the acceptance snapshot")
	var summary := recorder.summary_text()
	_assert_true(summary.contains("VESPER_HUNT") or summary.contains("vesper_hunt"), "debrief includes the authored encounter layout")
	_assert_true(summary.contains("What was the first moment") and summary.contains("Missile salvos 1"), "debrief includes external tester prompts and action counters")
	recorder.record_feedback("The sensor lesson was clear; recall timing needs another prompt.")
	_assert_true(FileAccess.file_exists(recorder.report_path()), "playtest snapshot persists to user storage")
	var report := ExodriftPlaytestReport.new()
	root.add_child(report)
	report.configure(recorder)
	_assert_true(report.notes != null and report.status_label.text.contains("exodrift_playtest_report"), "campaign debrief UI exposes notes and the snapshot path")
	report.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: M15 playtest recorder and external debrief")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d playtest assertion(s)" % failures.size())
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
