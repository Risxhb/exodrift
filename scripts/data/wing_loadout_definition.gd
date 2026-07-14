class_name WingLoadoutDefinition
extends Resource

@export var loadout_id: StringName = &"wing_loadout"
@export var display_name: String = "Wing Loadout"
@export_enum("interceptor", "scout") var wing_role: String = "interceptor"
@export_multiline var description: String = ""
@export_range(0, 64, 1) var ammunition_per_craft: int = 0
@export_range(0.1, 3.0, 0.05) var damage_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.05) var cycle_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.05) var range_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.05) var identification_gain_multiplier: float = 1.0
@export_range(0.1, 1.0, 0.05) var uncertainty_multiplier: float = 1.0
@export var can_intercept_missiles: bool = false
@export_range(0.1, 3.0, 0.05) var defensive_cycle_multiplier: float = 1.0
@export_range(0.0, 1000.0, 25.0) var escape_pod_recovery_range_m: float = 0.0


static func catalog() -> Array[WingLoadoutDefinition]:
	return [
		_create(
			&"raptor_cap", "Raptor CAP", "interceptor", 36,
			{"damage": 0.75, "cycle": 0.8, "range": 0.9, "intercept": true},
			"Dense defensive ammunition load for combat air patrol and missile interception."
		),
		_create(
			&"raptor_multirole", "Raptor Multirole", "interceptor", 28,
			{}, "Baseline package for flexible strike and fleet-defense work."
		),
		_create(
			&"raptor_strike", "Raptor Strike", "interceptor", 12,
			{"damage": 1.9, "cycle": 1.35, "range": 1.25},
			"Low-capacity heavy ordnance package for deliberate long-range attacks."
		),
		_create(
			&"watcher_recon", "Watcher Recon", "scout", 12,
			{"identification": 1.45, "uncertainty": 0.75},
			"Long-watch sensor package that identifies contacts faster and more precisely."
		),
		_create(
			&"watcher_screen", "Watcher Screen", "scout", 24,
			{"defensive_cycle": 0.75, "intercept": true},
			"Fleet-screen package with rapid defensive fire and missile interception."
		),
		_create(
			&"watcher_rescue", "Watcher Rescue", "scout", 6,
			{"rescue_range": 350.0},
			"Search-and-rescue package that lets deployed Watchers recover nearby escape pods."
		)
	]


static func definition(loadout_id_value: StringName) -> WingLoadoutDefinition:
	for candidate in catalog():
		if candidate.loadout_id == loadout_id_value:
			return candidate
	return null


static func for_role(role_value: String) -> Array[WingLoadoutDefinition]:
	var result: Array[WingLoadoutDefinition] = []
	for candidate in catalog():
		if candidate.wing_role == role_value:
			result.append(candidate)
	return result


static func is_valid_for_role(loadout_id_value: StringName, role_value: String) -> bool:
	var candidate := definition(loadout_id_value)
	return candidate != null and candidate.wing_role == role_value


static func _create(
	id: StringName,
	name_value: String,
	role_value: String,
	ammunition: int,
	values: Dictionary,
	description_value: String
) -> WingLoadoutDefinition:
	var definition_value := WingLoadoutDefinition.new()
	definition_value.loadout_id = id
	definition_value.display_name = name_value
	definition_value.wing_role = role_value
	definition_value.description = description_value
	definition_value.ammunition_per_craft = ammunition
	definition_value.damage_multiplier = float(values.get("damage", 1.0))
	definition_value.cycle_multiplier = float(values.get("cycle", 1.0))
	definition_value.range_multiplier = float(values.get("range", 1.0))
	definition_value.identification_gain_multiplier = float(values.get("identification", 1.0))
	definition_value.uncertainty_multiplier = float(values.get("uncertainty", 1.0))
	definition_value.can_intercept_missiles = bool(values.get("intercept", false))
	definition_value.defensive_cycle_multiplier = float(values.get("defensive_cycle", 1.0))
	definition_value.escape_pod_recovery_range_m = float(values.get("rescue_range", 0.0))
	return definition_value
