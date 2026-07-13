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
	_assert_true(InputMap.has_action("accelerate") and InputMap.has_action("decelerate"), "W/S throttle actions are registered")
	_assert_true(InputMap.has_action("flak_screen") and InputMap.has_action("missile_salvo") and InputMap.has_action("nuclear_torpedo"), "1/2/3 ordnance actions are registered")
	_assert_true(not ExodriftInputSettings.ACTION_LABELS.has("move_left") and not ExodriftInputSettings.ACTION_LABELS.has("move_up"), "lateral and vertical strafe bindings are removed from player controls")
	_assert_true(not ExodriftInputSettings.DEFAULT_KEYS.values().has(KEY_C) and not ExodriftInputSettings.DEFAULT_KEYS.values().has(KEY_G), "obsolete camera-mode keys are absent from command bindings")
	_assert_true(ExodriftInputSettings.action_key("flak_screen") == KEY_1 and ExodriftInputSettings.action_key("missile_salvo") == KEY_2 and ExodriftInputSettings.action_key("nuclear_torpedo") == KEY_3, "1/2/3 provide remappable flak, missile, and nuclear controls")

	var observed_throttles: Array[float] = []
	var observed_vectors: Array[Vector3] = []
	carrier.throttle_changed.connect(func(value: float) -> void: observed_throttles.append(value))
	carrier.navigation_commanded.connect(func(direction: Vector3, _full_cruise: bool) -> void: observed_vectors.append(direction))

	carrier.set_throttle(0.4)
	Input.action_press("accelerate")
	carrier._process_throttle_input(0.5)
	Input.action_release("accelerate")
	var accelerated_throttle := carrier.throttle_setting
	Input.action_press("decelerate")
	carrier._process_throttle_input(0.5)
	Input.action_release("decelerate")
	_assert_true(accelerated_throttle > 0.4 and carrier.throttle_setting < accelerated_throttle and not observed_throttles.is_empty(), "W/S changes persistent throttle and emits HUD-ready state")

	var viewport_size := game.get_viewport().get_visible_rect().size
	var empty_screen_point := Vector2(viewport_size.x * 0.12, viewport_size.y * 0.16)
	carrier.set_throttle(0.0)
	_assert_true(carrier.command_flight_from_screen(empty_screen_point, true, true), "double-click flight command accepts an empty-space camera ray")
	_assert_true(carrier.throttle_percent() == 100 and not observed_vectors.is_empty(), "double-click flight command sets full cruise and publishes its world direction")
	var commanded_vector := carrier.commanded_heading
	_assert_true(commanded_vector.dot(carrier.chase_camera.project_ray_normal(empty_screen_point)) > 0.999, "screen command follows the camera ray in three dimensions")

	var blocked_screen_point := Vector2(viewport_size.x * 0.88, viewport_size.y * 0.18)
	var blocked_origin := carrier.chase_camera.project_ray_origin(blocked_screen_point)
	var blocked_direction := carrier.chase_camera.project_ray_normal(blocked_screen_point).normalized()
	var blocker := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 35.0
	blocker_shape.shape = sphere
	blocker.add_child(blocker_shape)
	game.add_child(blocker)
	blocker.global_position = blocked_origin + blocked_direction * 500.0
	await physics_frame
	await physics_frame
	_assert_true(not carrier.command_flight_from_screen(blocked_screen_point, false, true), "Pilot mode rejects a navigation ray that lands on a world collider")
	blocker.queue_free()
	await physics_frame
	carrier.set_throttle(0.0)
	var double_click := InputEventMouseButton.new()
	double_click.button_index = MOUSE_BUTTON_LEFT
	double_click.pressed = true
	double_click.double_click = true
	double_click.position = empty_screen_point
	game._unhandled_input(double_click)
	_assert_true(carrier.throttle_percent() == 100, "battle input routes a command-view double-click to full-cruise navigation")

	carrier.velocity = Vector3.ZERO
	carrier.global_transform.basis = Basis.IDENTITY
	carrier.command_heading(Vector3(1.0, 0.25, -1.0), false)
	carrier.set_throttle(0.7)
	for _frame in 45:
		await physics_frame
	var forward := -carrier.global_transform.basis.z.normalized()
	_assert_true(carrier.velocity.length() > 1.0 and carrier.velocity.normalized().dot(forward) > 0.96, "carrier accelerates along its steered heading without side or vertical translation inputs")

	_assert_true(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the unified command view retains a visible pointer")

	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS: heavy heading, throttle, and unified command-view controls")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d flight-control assertion(s)" % failures.size())
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
