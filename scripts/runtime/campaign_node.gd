class_name SidebayCampaignNode
extends RefCounted

enum NodeType { COMBAT, SALVAGE, REPAIR, INTEL, BOSS }
enum ObjectiveType { COMMAND_STRIKE, INTERCEPTION, EXTRACTION, DEFENSE, ESCORT, CAPTURE }

var node_id: StringName
var display_name: String
var sector: int
var column: int
var row: int
var node_type: NodeType
var threat: int
var fuel_cost: int = 1
var reward_supplies: int = 0
var reward_intel: int = 0
var connections: Array[StringName] = []
var objective_type: ObjectiveType = ObjectiveType.COMMAND_STRIKE

static func create(
	id: StringName,
	name_value: String,
	sector_value: int,
	column_value: int,
	row_value: int,
	type_value: NodeType,
	threat_value: int,
	objective_value: ObjectiveType = ObjectiveType.COMMAND_STRIKE
) -> SidebayCampaignNode:
	var node := SidebayCampaignNode.new()
	node.node_id = id
	node.display_name = name_value
	node.sector = sector_value
	node.column = column_value
	node.row = row_value
	node.node_type = type_value
	node.threat = threat_value
	node.objective_type = objective_value
	return node

func type_label() -> String:
	return NodeType.keys()[node_type].capitalize()

func is_battle() -> bool:
	return node_type in [NodeType.COMBAT, NodeType.BOSS]

func objective_label() -> String:
	match objective_type:
		ObjectiveType.INTERCEPTION:
			return "Interception"
		ObjectiveType.EXTRACTION:
			return "Extraction"
		ObjectiveType.DEFENSE:
			return "Defense"
		ObjectiveType.ESCORT:
			return "Escort"
		ObjectiveType.CAPTURE:
			return "Capture"
		_:
			return "Command Strike"
