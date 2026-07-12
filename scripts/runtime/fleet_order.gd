class_name FleetOrder
extends RefCounted

enum OrderType { MOVE, ATTACK, INTERCEPT, ESCORT, HOLD, RECALL, WITHDRAW }

var order_type: OrderType = OrderType.HOLD
var target_entity_id: StringName = &""
var target_position: Vector3 = Vector3.ZERO
var issued_time_seconds: float = 0.0
var queued: bool = false
var stance: StringName = &"balanced"
var requires_command_link: bool = true

static func at_position(type: OrderType, position: Vector3, time_seconds: float, should_queue: bool = false) -> FleetOrder:
	var order := FleetOrder.new()
	order.order_type = type
	order.target_position = position
	order.issued_time_seconds = time_seconds
	order.queued = should_queue
	return order

static func at_entity(type: OrderType, entity_id: StringName, time_seconds: float, should_queue: bool = false) -> FleetOrder:
	var order := FleetOrder.new()
	order.order_type = type
	order.target_entity_id = entity_id
	order.issued_time_seconds = time_seconds
	order.queued = should_queue
	return order

