class_name FleetCommandState
extends RefCounted

signal order_status_changed(order: FleetOrder)
signal doctrine_changed(stance: StringName, formation: StringName, spacing: StringName)

const MAX_QUEUED_ORDERS := 8
const VALID_STANCES: Array[StringName] = [&"aggressive", &"balanced", &"defensive", &"evade_return"]
const VALID_FORMATIONS: Array[StringName] = [&"wedge", &"line", &"screen", &"column"]
const VALID_SPACING: Array[StringName] = [&"tight", &"standard", &"wide"]

var current_order: FleetOrder
var order_queue: Array[FleetOrder] = []
var transmitting_orders: Array[FleetOrder] = []
var stance: StringName = &"balanced"
var formation_name: StringName = &"wedge"
var formation_spacing: StringName = &"standard"
var formation_leader_id: StringName = &""

func submit(order: FleetOrder, command_link: CommandLinkState, now_seconds: float) -> bool:
	if order == null:
		return false
	if order.requires_command_link and not command_link.can_accept_order():
		_reject(order, "COMMAND LINK LOST")
		return false
	if order.queued and _queued_count() >= MAX_QUEUED_ORDERS:
		_reject(order, "ORDER QUEUE FULL (%d)" % MAX_QUEUED_ORDERS)
		return false
	order.stance = stance
	if not order.queued:
		_cancel_transmissions("SUPERSEDED")
	var delay := command_link.latency_seconds if order.requires_command_link else 0.0
	if is_finite(delay) and delay > 0.01:
		order.status = FleetOrder.Status.TRANSMITTING
		order.activation_time_seconds = now_seconds + delay
		transmitting_orders.append(order)
		order_status_changed.emit(order)
		return true
	_activate(order, now_seconds)
	return true

func tick(now_seconds: float) -> void:
	if transmitting_orders.is_empty():
		return
	var ready: Array[FleetOrder] = []
	for order in transmitting_orders:
		if now_seconds >= order.activation_time_seconds:
			ready.append(order)
	for order in ready:
		transmitting_orders.erase(order)
		_activate(order, now_seconds)

func complete_current(now_seconds: float) -> FleetOrder:
	var completed := current_order
	if completed != null:
		completed.status = FleetOrder.Status.COMPLETED
		completed.completed_time_seconds = now_seconds
		order_status_changed.emit(completed)
	current_order = null
	_activate_next(now_seconds)
	return completed

func cancel_all(reason: String = "CANCELLED") -> void:
	if current_order != null:
		_cancel(current_order, reason)
		current_order = null
	for order in order_queue:
		_cancel(order, reason)
	order_queue.clear()
	_cancel_transmissions(reason)

func set_stance(value: StringName) -> bool:
	if not VALID_STANCES.has(value):
		return false
	stance = value
	if current_order != null:
		current_order.stance = value
	doctrine_changed.emit(stance, formation_name, formation_spacing)
	return true

func set_formation(value: StringName, spacing: StringName = &"") -> bool:
	if not VALID_FORMATIONS.has(value):
		return false
	formation_name = value
	if not spacing.is_empty():
		if not VALID_SPACING.has(spacing):
			return false
		formation_spacing = spacing
	doctrine_changed.emit(stance, formation_name, formation_spacing)
	return true

func set_spacing(value: StringName) -> bool:
	if not VALID_SPACING.has(value):
		return false
	formation_spacing = value
	doctrine_changed.emit(stance, formation_name, formation_spacing)
	return true

func spacing_multiplier() -> float:
	match formation_spacing:
		&"tight":
			return 0.75
		&"wide":
			return 1.5
		_:
			return 1.0

func seconds_until_activation(now_seconds: float) -> float:
	if transmitting_orders.is_empty():
		return 0.0
	var earliest := INF
	for order in transmitting_orders:
		earliest = minf(earliest, order.activation_time_seconds)
	return maxf(0.0, earliest - now_seconds)

func all_orders() -> Array[FleetOrder]:
	var result: Array[FleetOrder] = []
	if current_order != null:
		result.append(current_order)
	result.append_array(order_queue)
	result.append_array(transmitting_orders)
	return result

func snapshot(now_seconds: float) -> Dictionary:
	var queue_data: Array[Dictionary] = []
	for order in order_queue:
		queue_data.append(order.to_dictionary())
	var transmission_data: Array[Dictionary] = []
	for order in transmitting_orders:
		var data := order.to_dictionary()
		data["seconds_remaining"] = maxf(0.0, order.activation_time_seconds - now_seconds)
		transmission_data.append(data)
	return {
		"current_order": current_order.to_dictionary() if current_order != null else {},
		"queue": queue_data,
		"transmitting": transmission_data,
		"stance": String(stance),
		"formation": String(formation_name),
		"spacing": String(formation_spacing),
		"leader_id": String(formation_leader_id)
	}

func _activate(order: FleetOrder, now_seconds: float) -> void:
	order.activation_time_seconds = now_seconds
	if order.queued and current_order != null:
		order.status = FleetOrder.Status.QUEUED
		order_queue.append(order)
		order_status_changed.emit(order)
		return
	if not order.queued:
		if current_order != null:
			_cancel(current_order, "SUPERSEDED")
		for queued_order in order_queue:
			_cancel(queued_order, "QUEUE CLEARED")
		order_queue.clear()
	current_order = order
	order.status = FleetOrder.Status.ACTIVE
	order_status_changed.emit(order)

func _activate_next(now_seconds: float) -> void:
	if order_queue.is_empty():
		return
	current_order = order_queue.pop_front()
	current_order.status = FleetOrder.Status.ACTIVE
	current_order.activation_time_seconds = now_seconds
	order_status_changed.emit(current_order)

func _queued_count() -> int:
	var pending_queued := 0
	for order in transmitting_orders:
		if order.queued:
			pending_queued += 1
	return order_queue.size() + pending_queued

func _reject(order: FleetOrder, reason: String) -> void:
	order.status = FleetOrder.Status.REJECTED
	order.rejection_reason = reason
	order_status_changed.emit(order)

func _cancel(order: FleetOrder, reason: String) -> void:
	order.status = FleetOrder.Status.CANCELLED
	order.rejection_reason = reason
	order_status_changed.emit(order)

func _cancel_transmissions(reason: String) -> void:
	for order in transmitting_orders:
		_cancel(order, reason)
	transmitting_orders.clear()
