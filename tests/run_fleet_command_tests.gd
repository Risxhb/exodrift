extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_order_lifecycle_and_queue()
	_test_command_link_delivery()
	_test_objectives_doctrine_and_lead()
	await _test_context_wheel()
	_test_fixed_group_bindings()
	if failures.is_empty():
		print("PASS: fleet command lifecycle, doctrine, objectives, wheel, bindings, and lead solutions")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d fleet-command assertion(s)" % failures.size())
		quit(1)


func _test_order_lifecycle_and_queue() -> void:
	var state := FleetCommandState.new()
	var link := CommandLinkState.new()
	var statuses: Array[int] = []
	state.order_status_changed.connect(func(order: FleetOrder) -> void: statuses.append(order.status))
	var active := FleetOrder.at_position(FleetOrder.OrderType.MOVE, Vector3(100.0, 0.0, 0.0), 0.0)
	_assert_true(state.submit(active, link, 0.0) and state.current_order == active and active.status == FleetOrder.Status.ACTIVE, "an unqueued order activates immediately on a linked group")
	var queued_orders: Array[FleetOrder] = []
	for index in FleetCommandState.MAX_QUEUED_ORDERS:
		var queued := FleetOrder.at_position(FleetOrder.OrderType.MOVE, Vector3(200.0 + index * 100.0, 0.0, 0.0), 0.0, true)
		queued_orders.append(queued)
		_assert_true(state.submit(queued, link, 0.0), "queue accepts entry %d of eight" % (index + 1))
	_assert_true(state.order_queue.size() == 8 and state.order_queue[0].status == FleetOrder.Status.QUEUED, "Shift-style orders form an eight-entry FIFO queue")
	var overflow := FleetOrder.at_position(FleetOrder.OrderType.MOVE, Vector3(1200.0, 0.0, 0.0), 0.0, true)
	_assert_true(not state.submit(overflow, link, 0.0) and overflow.status == FleetOrder.Status.REJECTED and overflow.rejection_reason.contains("FULL"), "a ninth queued entry is rejected with an explicit reason")
	state.complete_current(1.0)
	_assert_true(active.status == FleetOrder.Status.COMPLETED and state.current_order == queued_orders[0] and state.order_queue.size() == 7, "completion activates the next numbered leg")
	var replacement := FleetOrder.at_position(FleetOrder.OrderType.HOLD, Vector3.ZERO, 2.0)
	_assert_true(state.submit(replacement, link, 2.0) and state.current_order == replacement and state.order_queue.is_empty(), "an unmodified order replaces the active leg and clears its queue")
	_assert_true(queued_orders[0].status == FleetOrder.Status.CANCELLED and queued_orders[1].status == FleetOrder.Status.CANCELLED, "replacement publishes cancellation for active and queued legs")
	state.cancel_all("PLAYER CANCELLED")
	_assert_true(state.current_order == null and replacement.status == FleetOrder.Status.CANCELLED and statuses.has(FleetOrder.Status.COMPLETED), "explicit cancellation clears the retained command and lifecycle signals include completion")


func _test_command_link_delivery() -> void:
	var state := FleetCommandState.new()
	var link := CommandLinkState.new()
	var hold := FleetOrder.at_position(FleetOrder.OrderType.HOLD, Vector3.ZERO, 0.0)
	state.submit(hold, link, 0.0)
	link.state = CommandLinkState.LinkState.DELAYED
	link.latency_seconds = 1.25
	var delayed := FleetOrder.at_position(FleetOrder.OrderType.MOVE, Vector3(500.0, 0.0, 0.0), 3.0)
	_assert_true(state.submit(delayed, link, 3.0) and delayed.status == FleetOrder.Status.TRANSMITTING and state.current_order == hold, "a delayed link retains the last confirmed order during transmission")
	_assert_true(is_equal_approx(state.seconds_until_activation(3.0), 1.25) and is_equal_approx(float(state.snapshot(3.0).transmitting[0].seconds_remaining), 1.25), "the command snapshot exposes the live activation countdown")
	state.tick(4.0)
	_assert_true(state.current_order == hold, "a delayed order does not activate early")
	state.tick(4.25)
	_assert_true(state.current_order == delayed and delayed.status == FleetOrder.Status.ACTIVE and hold.status == FleetOrder.Status.CANCELLED, "delivery activates at the authored latency and supersedes the old command")
	link.state = CommandLinkState.LinkState.DISCONNECTED
	link.latency_seconds = INF
	var rejected := FleetOrder.at_position(FleetOrder.OrderType.WITHDRAW, Vector3(2000.0, 0.0, 0.0), 5.0)
	_assert_true(not state.submit(rejected, link, 5.0) and rejected.status == FleetOrder.Status.REJECTED and rejected.rejection_reason == "COMMAND LINK LOST", "a disconnected group rejects new commands and explains why")
	_assert_true(state.current_order == delayed, "disconnect rejection retains the last confirmed active order")


func _test_objectives_doctrine_and_lead() -> void:
	var objective := TacticalObjectiveDescriptor.create(&"relay_alpha", "Relay Alpha", "Secure", TacticalObjectiveDescriptor.InteractionKind.SECURE, Vector3(300.0, 0.0, -500.0), 180.0)
	var order := objective.to_order(2.0, true)
	_assert_true(order.order_type == FleetOrder.OrderType.INTERACT and order.interaction_id == &"relay_alpha" and order.interaction_verb == "Secure" and is_equal_approx(order.interaction_radius_m, 180.0) and order.queued, "objective descriptors author a contextual Interact order with ID, verb, radius, and queue state")
	var state := FleetCommandState.new()
	_assert_true(state.set_stance(&"aggressive") and state.set_formation(&"screen", &"wide"), "valid doctrine choices update stance, formation, and spacing")
	_assert_true(is_equal_approx(state.spacing_multiplier(), 1.5) and not state.set_spacing(&"invalid"), "wide spacing is 1.5x and invalid doctrine is rejected")
	state.set_spacing(&"tight")
	_assert_true(is_equal_approx(state.spacing_multiplier(), 0.75), "tight spacing is 0.75x")
	var lead := CombatShip.intercept_direction(Vector3.ZERO, Vector3(1000.0, 0.0, 0.0), Vector3(0.0, 0.0, 100.0), 500.0)
	_assert_true(lead.z > 0.05 and is_equal_approx(lead.length(), 1.0), "unguided firing computes a normalized projectile-leading solution")


func _test_context_wheel() -> void:
	var wheel := TacticalContextWheel.new()
	root.add_child(wheel)
	await process_frame
	var result := {"action": &"", "queued": false, "cancels": 0}
	wheel.action_selected.connect(func(action: StringName, queued: bool) -> void:
		result.action = action
		result.queued = queued
	)
	wheel.cancelled.connect(func() -> void: result.cancels = int(result.cancels) + 1)
	var choices: Array[Dictionary] = [{"id": &"move", "label": "Move"}, {"id": &"hold", "label": "Hold"}]
	wheel.open_at(Vector2(300.0, 300.0), choices, false)
	var center := wheel.wheel_center
	_assert_true(wheel.release_flick(center + Vector2(0.0, 12.0), false) and wheel.active and StringName(result.action).is_empty(), "releasing inside the dead zone leaves the wheel open for precise clicking")
	wheel.click(center + Vector2(0.0, -80.0), true)
	_assert_true(result.action == &"move" and bool(result.queued) and not wheel.active, "precise wheel clicking executes the highlighted action with Shift queue state")
	result.action = &""
	wheel.open_at(Vector2(300.0, 300.0), choices, false)
	wheel.release_flick(wheel.wheel_center + Vector2(0.0, -90.0), false)
	_assert_true(result.action == &"move" and not wheel.active, "dragging beyond the dead zone and releasing executes a quick flick")
	wheel.open_at(Vector2(300.0, 300.0), choices, false)
	wheel.click(wheel.wheel_center, false)
	_assert_true(int(result.cancels) == 1 and not wheel.active, "clicking outside a command wedge cancels the wheel")
	wheel.queue_free()
	await process_frame


func _test_fixed_group_bindings() -> void:
	_assert_true(ExodriftInputSettings.action_key("fleet_group_1") == KEY_F1, "F1 is the fixed Carrier group slot")
	_assert_true(ExodriftInputSettings.action_key("fleet_group_2") == KEY_F2, "F2 is the fixed Escort group slot")
	_assert_true(ExodriftInputSettings.action_key("fleet_group_3") == KEY_F3, "F3 is the fixed Interceptors group slot")
	_assert_true(ExodriftInputSettings.action_key("fleet_group_4") == KEY_F4, "F4 is the fixed Scouts group slot")
	_assert_true(ExodriftInputSettings.action_key("tactical_center_carrier") == KEY_HOME, "Home is the remappable tactical camera recenter action")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
