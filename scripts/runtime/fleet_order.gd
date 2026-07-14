class_name FleetOrder
extends RefCounted

enum OrderType { MOVE, ATTACK, INTERCEPT, ESCORT, HOLD, RECALL, WITHDRAW, INTERACT }
enum Status { TRANSMITTING, QUEUED, ACTIVE, COMPLETED, REJECTED, CANCELLED }

static var _next_order_sequence: int = 1

var order_type: OrderType = OrderType.HOLD
var order_id: StringName
var target_entity_id: StringName = &""
var target_position: Vector3 = Vector3.ZERO
var target_velocity: Vector3 = Vector3.ZERO
var target_facing: Vector3 = Vector3.ZERO
var origin_position: Vector3 = Vector3.ZERO
var issued_time_seconds: float = 0.0
var activation_time_seconds: float = 0.0
var completed_time_seconds: float = 0.0
var queued: bool = false
var stance: StringName = &"balanced"
var requires_command_link: bool = true
var status: Status = Status.QUEUED
var rejection_reason: String = ""
var interaction_id: StringName = &""
var interaction_radius_m: float = 0.0
var interaction_verb: String = ""

func _init() -> void:
	order_id = StringName("order_%06d" % _next_order_sequence)
	_next_order_sequence += 1

static func at_position(type: OrderType, position: Vector3, time_seconds: float, should_queue: bool = false) -> FleetOrder:
	var order := FleetOrder.new()
	order.order_type = type
	order.target_position = position
	order.issued_time_seconds = time_seconds
	order.activation_time_seconds = time_seconds
	order.queued = should_queue
	return order

static func at_entity(type: OrderType, entity_id: StringName, time_seconds: float, should_queue: bool = false) -> FleetOrder:
	var order := FleetOrder.new()
	order.order_type = type
	order.target_entity_id = entity_id
	order.issued_time_seconds = time_seconds
	order.activation_time_seconds = time_seconds
	order.queued = should_queue
	return order

static func interaction(
	interaction: StringName,
	verb: String,
	position: Vector3,
	radius_m: float,
	time_seconds: float,
	should_queue: bool = false,
	target_id: StringName = &""
) -> FleetOrder:
	var order := at_position(OrderType.INTERACT, position, time_seconds, should_queue)
	order.target_entity_id = target_id
	order.interaction_id = interaction
	order.interaction_verb = verb
	order.interaction_radius_m = maxf(25.0, radius_m)
	return order

func type_label() -> String:
	if order_type == OrderType.INTERACT and not interaction_verb.is_empty():
		return interaction_verb
	return OrderType.keys()[order_type].capitalize()

func status_label() -> String:
	return Status.keys()[status].capitalize()

func target_label() -> String:
	if not target_entity_id.is_empty():
		return String(target_entity_id)
	return "%.0f / %.0f / %.0f" % [target_position.x, target_position.y, target_position.z]

func to_dictionary() -> Dictionary:
	return {
		"order_id": String(order_id),
		"type": type_label(),
		"status": status_label(),
		"target_entity_id": String(target_entity_id),
		"target_position": target_position,
		"target_velocity": target_velocity,
		"target_facing": target_facing,
		"issued_time_seconds": issued_time_seconds,
		"activation_time_seconds": activation_time_seconds,
		"queued": queued,
		"stance": String(stance),
		"rejection_reason": rejection_reason,
		"interaction_id": String(interaction_id),
		"interaction_radius_m": interaction_radius_m
	}
