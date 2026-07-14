extends SceneTree

const TrainingTrialController := preload("res://scripts/systems/training_trial_controller.gd")

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

	_assert_true(is_instance_valid(game.training_controller), "training battle creates the guided combat-trial controller")
	_assert_true(game.training_trial and not game.hosted_campaign and game.encounter == null, "training battle is isolated from campaign and encounter progression")
	_assert_true(is_instance_valid(game.hostile_command) and game.hostile_command.stable_entity_id == &"training_target_dummy", "training arena contains the dedicated target dummy")
	_assert_true(game.hostile_command.definition.weapons.is_empty() and not game.hostile_command.ai_enabled and is_zero_approx(game.hostile_command.incoming_damage_multiplier), "target dummy is inert and protected until the live-fire step")
	_assert_true(not is_instance_valid(game.hostile_corvette) and not is_instance_valid(game.hostile_fighters), "training arena excludes live hostile reinforcements")
	_assert_true(is_instance_valid(game.training_navigation_gate) and game.hostile_command.find_child("TargetDummyMarker", true, false) != null, "training arena visibly marks its navigation gate and target")
	_assert_true(game.hud.objective_label.text.contains("COMBAT TRIAL"), "combat HUD identifies the safe trial objective")

	var guide: ExodriftTrainingTrialController = game.training_controller
	guide.set_process(false)
	_assert_step(guide, TrainingTrialController.Step.WELCOME, "trial begins with a safe-range briefing")
	guide._process(2.5)
	_assert_step(guide, TrainingTrialController.Step.HELM, "briefing advances to direct carrier movement")
	game.carrier.velocity = Vector3(35.0, 0.0, 0.0)
	guide._process(0.8)
	_assert_step(guide, TrainingTrialController.Step.TACTICAL, "carrier movement unlocks tactical command training")
	_assert_true(not game.training_navigation_gate.visible, "navigation gate clears from the firing lane after helm movement is credited")
	game.tactical.set_enabled(true)
	guide._process(0.8)
	_assert_step(guide, TrainingTrialController.Step.ESCORT_MOVE, "opening the map advances to escort movement")
	var move_order := FleetOrder.at_position(FleetOrder.OrderType.MOVE, game.escort.global_position + Vector3(600.0, 0.0, -400.0), 0.0)
	game.escort.issue_order(move_order)
	guide._process(0.8)
	_assert_step(guide, TrainingTrialController.Step.QUEUE_WAYPOINT, "a confirmed escort move advances to waypoint queuing")
	var queued_order := FleetOrder.at_position(FleetOrder.OrderType.MOVE, game.escort.global_position + Vector3(900.0, 0.0, 300.0), 0.0)
	queued_order.queued = true
	game.escort.issue_order(queued_order)
	guide._process(0.8)
	_assert_step(guide, TrainingTrialController.Step.DOCTRINE, "a Shift-style queued order advances to doctrine training")
	game.escort.set_formation_spacing(&"wide")
	guide._process(0.8)
	_assert_step(guide, TrainingTrialController.Step.SENSOR, "a visible doctrine or spacing change advances to sensor identification")
	game.sensors.emit_active_ping()
	guide._process(0.8)
	_assert_step(guide, TrainingTrialController.Step.FLIGHT, "active ping identifies and locks the training target")
	_assert_true(game.manual_target_lock_id == &"training_target_dummy" and game.target_lock == game.hostile_command, "trial computer establishes a usable dummy target lock")
	game.interceptor.operation.state = BayOperation.State.QUEUED
	guide._process(0.8)
	_assert_step(guide, TrainingTrialController.Step.ENGAGE, "wing launch advances to the live-fire exercise")
	_assert_true(is_equal_approx(game.hostile_command.incoming_damage_multiplier, 1.0), "live-fire step makes the target dummy damageable")

	game.hostile_command.receive_damage(1000.0, &"training_test")
	_assert_step(guide, TrainingTrialController.Step.COMPLETE, "destroying the target completes the trial")
	_assert_true(game.battle_finished and game.battle_outcome == "training" and paused, "completed trial pauses safely with its dedicated outcome")
	_assert_true(game.hud.result_label.text.contains("COMBAT TRIAL COMPLETE") and not guide.panel.visible, "completion presents a clear return-to-title result")

	var completion_result := {"emitted": false, "completed": false}
	game.training_trial_finished.connect(func(completed: bool) -> void:
		completion_result.emitted = true
		completion_result.completed = completed
	)
	game._restart_encounter()
	_assert_true(bool(completion_result.emitted) and bool(completion_result.completed) and not paused, "Enter returns a completed trial to the title flow")

	game.queue_free()
	await process_frame

	var app := (load("res://scenes/app.tscn") as PackedScene).instantiate()
	root.add_child(app)
	for _frame in 6:
		await process_frame
	app.main_menu.tutorial_trial_requested.emit()
	for _frame in 60:
		if is_instance_valid(app.active_battle) and app.active_battle.training_trial:
			break
		await process_frame
	_assert_true(is_instance_valid(app.active_battle) and app.active_battle.training_trial and app.run_state == null, "title tutorial launches the trial without creating a campaign run")
	if is_instance_valid(app.active_battle):
		app.active_battle._exit_training_trial(false)
	for _frame in 12:
		if is_instance_valid(app.main_menu) and not is_instance_valid(app.active_battle):
			break
		await process_frame
	_assert_true(is_instance_valid(app.main_menu) and not is_instance_valid(app.active_battle) and app.main_menu.status_label.text.contains("TRAINING RECORD DISCARDED"), "early trial exit returns cleanly to the title with no retained battle")
	app.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: safe combat trial progresses through movement, command, launch, and target engagement")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d combat-trial assertion(s)" % failures.size())
		quit(1)


func _assert_step(guide: ExodriftTrainingTrialController, expected: int, message: String) -> void:
	_assert_true(guide.current_step == expected, "%s (expected %s, got %s)" % [
		message,
		TrainingTrialController.Step.keys()[expected],
		TrainingTrialController.Step.keys()[guide.current_step]
	])


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
