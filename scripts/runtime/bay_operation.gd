class_name BayOperation
extends RefCounted

enum State {
	QUEUED,
	LAUNCHING,
	DEPLOYED,
	RETURNING,
	APPROACH,
	DOCKING,
	SERVICING, # Legacy aggregate state retained for save/test compatibility.
	REPAIRING,
	REFUELING,
	REARMING,
	READY,
}

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

func is_service_state() -> bool:
	return state in [State.SERVICING, State.REPAIRING, State.REFUELING, State.REARMING]

static func is_valid_transition(from_state: State, to_state: State) -> bool:
	match from_state:
		State.READY:
			return to_state in [State.QUEUED, State.REARMING]
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
			return to_state in [State.SERVICING, State.REPAIRING, State.REFUELING, State.REARMING, State.READY]
		State.SERVICING:
			return to_state in [State.REPAIRING, State.REFUELING, State.REARMING, State.READY]
		State.REPAIRING:
			return to_state in [State.REFUELING, State.REARMING, State.READY]
		State.REFUELING:
			return to_state in [State.REARMING, State.READY]
		State.REARMING:
			return to_state == State.READY
	return false
