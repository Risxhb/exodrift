extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_test_damage_transitions()
	_test_sensor_contact_decay_and_lock()
	_test_command_link_transitions()
	_test_bay_state_machine()
	_test_fleet_order_contract()
	_test_ship_visual_profiles()
	if failures.is_empty():
		print("PASS: 6 Sidebay contract suites")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d assertion(s)" % failures.size())
		quit(1)

func _test_damage_transitions() -> void:
	var definition := DamageLayerDefinition.new()
	definition.max_shields = 100.0
	definition.max_armor = 100.0
	definition.max_hull = 100.0
	definition.armor_mitigation = 0.2
	var state := DamageState.new(definition)
	state.apply_damage(150.0)
	_assert_near(state.shields, 0.0, "damage depletes shields first")
	_assert_near(state.armor, 60.0, "armor mitigation applies to overflow")
	_assert_near(state.hull, 100.0, "hull remains protected by armor")
	state.apply_damage(200.0)
	_assert_true(state.hull < 100.0, "overflow reaches hull")

func _test_sensor_contact_decay_and_lock() -> void:
	var contact := SensorContact.new()
	contact.confidence = 0.9
	contact.estimated_position = Vector3.ZERO
	contact.estimated_velocity = Vector3(10.0, 0.0, 0.0)
	contact.uncertainty_radius_m = 100.0
	contact.update_identification()
	_assert_true(contact.is_targetable(), "identified high-confidence contact is targetable")
	contact.age_track(5.0, 0.1)
	_assert_near(contact.estimated_position.x, 50.0, "stale track drifts with estimated velocity")
	_assert_true(contact.uncertainty_radius_m > 100.0, "stale track uncertainty expands")
	_assert_true(not contact.is_targetable(), "decayed contact loses missile eligibility")

func _test_command_link_transitions() -> void:
	var link := CommandLinkState.new()
	link.update_for_distance(6000.0, 7000.0)
	_assert_true(link.state == CommandLinkState.LinkState.LINKED, "inside range is linked")
	link.update_for_distance(8000.0, 7000.0)
	_assert_true(link.state == CommandLinkState.LinkState.DELAYED, "fringe range is delayed")
	link.update_for_distance(9000.0, 7000.0)
	_assert_true(link.state == CommandLinkState.LinkState.DISCONNECTED, "outside fringe is disconnected")
	_assert_true(not link.can_accept_order(), "disconnected group rejects new orders")

func _test_bay_state_machine() -> void:
	var bay := BayOperation.new()
	var sequence := [
		BayOperation.State.QUEUED,
		BayOperation.State.LAUNCHING,
		BayOperation.State.DEPLOYED,
		BayOperation.State.RETURNING,
		BayOperation.State.APPROACH,
		BayOperation.State.DOCKING,
		BayOperation.State.SERVICING,
		BayOperation.State.READY
	]
	for next_state in sequence:
		_assert_true(bay.transition(next_state), "valid bay transition to %s" % BayOperation.State.keys()[next_state])
	_assert_true(not bay.transition(BayOperation.State.DEPLOYED), "ready cannot skip launch states")

func _test_fleet_order_contract() -> void:
	var first := FleetOrder.at_position(FleetOrder.OrderType.MOVE, Vector3(1.0, 2.0, 3.0), 4.0, true)
	_assert_true(first.order_type == FleetOrder.OrderType.MOVE, "position order keeps its type")
	_assert_true(first.target_position == Vector3(1.0, 2.0, 3.0), "position order keeps its target")
	_assert_true(first.queued, "position order keeps queue intent")
	var second := FleetOrder.at_entity(FleetOrder.OrderType.ATTACK, &"hostile_command", 5.0)
	_assert_true(second.target_entity_id == &"hostile_command", "entity order keeps stable target ID")
	var intercept := FleetOrder.at_entity(FleetOrder.OrderType.INTERCEPT, &"hostile_fighter_wing", 6.0)
	var escort := FleetOrder.at_entity(FleetOrder.OrderType.ESCORT, &"player_carrier", 7.0)
	_assert_true(intercept.order_type == FleetOrder.OrderType.INTERCEPT and escort.order_type == FleetOrder.OrderType.ESCORT, "intercept and escort remain first-class order types")

func _test_ship_visual_profiles() -> void:
	var friendly := ShipVisualProfile.for_ship(&"frigate", &"friendly")
	var hostile := ShipVisualProfile.for_ship(&"corvette", &"hostile")
	_assert_true(friendly.engine_color.b > friendly.engine_color.r, "friendly visual profile keeps cool engine identification")
	_assert_true(hostile.engine_color.r > hostile.engine_color.b and hostile.shoulder_scale.x > friendly.shoulder_scale.x, "hostile corvette profile exposes a distinct hot-engine, broad-shoulder silhouette")

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _assert_near(value: float, expected: float, message: String, tolerance: float = 0.001) -> void:
	if absf(value - expected) > tolerance:
		failures.append("%s (expected %.3f, got %.3f)" % [message, expected, value])
