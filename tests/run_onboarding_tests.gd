extends SceneTree

const OnboardingController = preload("res://scripts/systems/onboarding_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Node3D.new()
	fixture.name = "OnboardingTestFixture"
	root.add_child(fixture)

	var carrier := PlayerCarrier.new()
	var interceptor := SidebaySquadron.new()
	var scout := SidebaySquadron.new()
	var sensors := SidebaySensorSystem.new()
	var tactical := TacticalController.new()
	for dependency in [carrier, interceptor, scout, sensors, tactical]:
		dependency.set_process(false)
		dependency.set_physics_process(false)
		fixture.add_child(dependency)

	carrier.global_position = Vector3(120.0, 10.0, -80.0)
	var onboarding := OnboardingController.new()
	onboarding.set_process(false)
	fixture.add_child(onboarding)
	onboarding.configure(carrier, interceptor, scout, sensors, tactical)

	_assert_step(onboarding, OnboardingController.Step.WELCOME, "configure starts at welcome")
	_assert_true(onboarding.panel != null and onboarding.panel.visible, "configure builds and shows the onboarding overlay")
	_assert_true(onboarding.progress_label.text == "ORIENTATION   [F3] HIDE", "welcome is labeled separately from the six guided milestones")

	onboarding._process(2.99)
	_assert_step(onboarding, OnboardingController.Step.WELCOME, "welcome remains visible for its full duration")
	onboarding._process(0.01)
	_assert_step(onboarding, OnboardingController.Step.HELM, "welcome advances to helm after three seconds")
	_assert_progress(onboarding, 1, "helm reports the first guided milestone")

	carrier.velocity = Vector3(30.0, 0.0, 0.0)
	onboarding._process(1.24)
	_assert_step(onboarding, OnboardingController.Step.HELM, "helm remains readable briefly after movement begins")
	onboarding._process(0.01)
	_assert_step(onboarding, OnboardingController.Step.SENSOR, "helm advances when carrier movement is observed")
	_assert_progress(onboarding, 2, "sensor reports the second guided milestone")

	sensors.active_ping_emitted.emit(carrier.global_position, 12000.0)
	_assert_true(onboarding.active_ping_observed, "sensor signal is observed by onboarding")
	onboarding._process(1.24)
	_assert_step(onboarding, OnboardingController.Step.SENSOR, "sensor remains readable briefly after an active ping")
	onboarding._process(0.01)
	_assert_step(onboarding, OnboardingController.Step.FLIGHT, "sensor advances after an active ping")
	_assert_progress(onboarding, 3, "flight reports the third guided milestone")

	interceptor.operation.state = BayOperation.State.QUEUED
	onboarding._process(1.24)
	_assert_step(onboarding, OnboardingController.Step.FLIGHT, "flight remains readable briefly after a launch begins")
	onboarding._process(0.01)
	_assert_step(onboarding, OnboardingController.Step.COMMAND, "flight advances when either wing leaves ready state")
	_assert_progress(onboarding, 4, "command reports the fourth guided milestone")

	tactical.enabled = true
	onboarding._process(1.24)
	_assert_step(onboarding, OnboardingController.Step.COMMAND, "command remains readable briefly after tactical mode opens")
	onboarding._process(0.01)
	_assert_step(onboarding, OnboardingController.Step.ORDERS, "command advances when the tactical map is enabled")
	_assert_progress(onboarding, 5, "orders report the fifth guided milestone")

	carrier.autopilot_active = true
	onboarding._process(1.24)
	_assert_step(onboarding, OnboardingController.Step.ORDERS, "orders remains readable briefly after an order is issued")
	onboarding._process(0.01)
	_assert_step(onboarding, OnboardingController.Step.COMPLETE, "orders advance when a player order is observed")
	_assert_progress(onboarding, 6, "completion reports all six guided milestones")
	_assert_true(not onboarding.dismissed and onboarding.panel.visible, "completion remains visible before its dismissal delay")

	onboarding._process(6.99)
	_assert_true(not onboarding.dismissed, "completion remains visible for its full duration")
	onboarding._process(0.01)
	_assert_true(onboarding.dismissed and not onboarding.panel.visible, "completion dismisses the overlay after seven seconds")

	fixture.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: guided onboarding progresses deterministically through all six milestones")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d onboarding assertion(s)" % failures.size())
		quit(1)


func _assert_step(onboarding: CanvasLayer, expected: int, message: String) -> void:
	_assert_true(onboarding.current_step == expected, "%s (expected %s, got %s)" % [
		message,
		OnboardingController.Step.keys()[expected],
		OnboardingController.Step.keys()[onboarding.current_step]
	])


func _assert_progress(onboarding: CanvasLayer, expected: int, message: String) -> void:
	_assert_true(onboarding.progress_label.text == "%d / 6   [F3] HIDE" % expected, "%s (got %s)" % [message, onboarding.progress_label.text])


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
