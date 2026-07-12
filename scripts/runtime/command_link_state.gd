class_name CommandLinkState
extends RefCounted

enum LinkState { LINKED, DELAYED, DISCONNECTED }

var state: LinkState = LinkState.LINKED
var last_confirmed_order: FleetOrder
var latency_seconds: float = 0.0

func update_for_distance(distance_m: float, command_range_m: float) -> void:
	if distance_m <= command_range_m:
		state = LinkState.LINKED
		latency_seconds = 0.0
	elif distance_m <= command_range_m * 1.25:
		state = LinkState.DELAYED
		latency_seconds = remap(distance_m, command_range_m, command_range_m * 1.25, 0.2, 1.5)
	else:
		state = LinkState.DISCONNECTED
		latency_seconds = INF

func can_accept_order() -> bool:
	return state != LinkState.DISCONNECTED

func label() -> String:
	return LinkState.keys()[state].capitalize()

