class_name TacticalObjectiveDescriptor
extends RefCounted

enum InteractionKind { SECURE, DEFEND, ESCORT, WITHDRAW }

var objective_id: StringName = &"objective"
var label: String = "OBJECTIVE"
var verb: String = "INTERACT"
var interaction_kind: InteractionKind = InteractionKind.SECURE
var target_entity_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var radius_m: float = 250.0
var completed: bool = false

static func create(
	id: StringName,
	caption: String,
	action_verb: String,
	kind: InteractionKind,
	world_position: Vector3,
	radius: float,
	target_id: StringName = &""
) -> TacticalObjectiveDescriptor:
	var descriptor := TacticalObjectiveDescriptor.new()
	descriptor.objective_id = id
	descriptor.label = caption
	descriptor.verb = action_verb
	descriptor.interaction_kind = kind
	descriptor.position = world_position
	descriptor.radius_m = maxf(25.0, radius)
	descriptor.target_entity_id = target_id
	return descriptor

func to_order(time_seconds: float, queued: bool = false) -> FleetOrder:
	match interaction_kind:
		InteractionKind.ESCORT:
			return FleetOrder.at_entity(FleetOrder.OrderType.ESCORT, target_entity_id, time_seconds, queued)
		InteractionKind.WITHDRAW:
			return FleetOrder.at_position(FleetOrder.OrderType.WITHDRAW, position, time_seconds, queued)
		_:
			return FleetOrder.interaction(objective_id, verb, position, radius_m, time_seconds, queued, target_entity_id)
