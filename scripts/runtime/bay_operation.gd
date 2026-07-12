class_name BayOperation
extends RefCounted

enum State { QUEUED, LAUNCHING, DEPLOYED, RETURNING, APPROACH, DOCKING, SERVICING, READY }

var state: State = State.READY
var state_elapsed_seconds: float = 0.0

func transition(next_state: State) -> bool:
	if not is_valid_transition(state, next_state):
		return false
	state = next_state
	state_elapsed_seconds = 0.0
	return true

func tick(delta: float) -> void:
	state_elapsed_seconds += delta

func label() -> String:
	return State.keys()[state].capitalize()

static func is_valid_transition(from_state: State, to_state: State) -> bool:
	match from_state:
		State.READY:
			return to_state == State.QUEUED
		State.QUEUED:
			return to_state == State.LAUNCHING or to_state == State.READY
		State.LAUNCHING:
			return to_state == State.DEPLOYED or to_state == State.RETURNING
		State.DEPLOYED:
			return to_state == State.RETURNING
		State.RETURNING:
			return to_state == State.APPROACH
		State.APPROACH:
			return to_state == State.DOCKING
		State.DOCKING:
			return to_state == State.SERVICING
		State.SERVICING:
			return to_state == State.READY
	return false

