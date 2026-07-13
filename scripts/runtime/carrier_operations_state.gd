class_name CarrierOperationsState
extends RefCounted

signal changed(reason: StringName)
signal incident_started(incident: Dictionary)
signal incident_resolved(incident: Dictionary)
signal store_rejected(store_id: StringName, message: String)
signal team_assignment_changed(team_index: int, target_subsystem: StringName)

const MAX_CREW := 240
const BASE_DAMAGE_CONTROL_SPARES := 60
const TEAM_COUNT := 2
const TEAM_TRANSIT_SECONDS := 4.0
const OFFICER_RESCUE_SECONDS := 10.0

const SUBSYSTEMS: Array[StringName] = [
	&"reactor", &"propulsion", &"shield_grid", &"fire_control",
	&"sensors", &"command_cic", &"port_deck", &"starboard_deck"
]
const POWER_CHANNELS: Array[StringName] = [&"propulsion", &"defense", &"weapons", &"flight"]
const STORE_IDS: Array[StringName] = [&"flak_rounds", &"guided_missiles", &"nuclear_torpedoes", &"aviation_ordnance", &"craft_refuel"]
const POWER_PRESETS := {
	"balanced": {"propulsion": 2, "defense": 2, "weapons": 2, "flight": 2},
	"strike": {"propulsion": 1, "defense": 2, "weapons": 4, "flight": 1},
	"evasive": {"propulsion": 4, "defense": 2, "weapons": 1, "flight": 1},
	"recovery": {"propulsion": 1, "defense": 2, "weapons": 1, "flight": 4}
}
const SUBSYSTEM_TO_CHANNEL := {
	"reactor": "defense",
	"propulsion": "propulsion",
	"shield_grid": "defense",
	"fire_control": "weapons",
	"sensors": "weapons",
	"command_cic": "defense",
	"port_deck": "flight",
	"starboard_deck": "flight"
}
const SUBSYSTEM_DEPARTMENTS := {
	"reactor": "Engineering",
	"propulsion": "Engineering",
	"shield_grid": "Engineering",
	"fire_control": "Gunnery",
	"sensors": "Sensors",
	"command_cic": "Command",
	"port_deck": "Flight",
	"starboard_deck": "Flight"
}
const DEFAULT_DEPARTMENT_LEADS := {
	"Engineering": {"personnel_id": "nia_okafor", "display_name": "Nia Okafor", "status": "active"},
	"Gunnery": {"personnel_id": "ada_kessler", "display_name": "Ada Kessler", "status": "active"},
	"Sensors": {"personnel_id": "yara_sen", "display_name": "Yara Sen", "status": "active"},
	"Command": {"personnel_id": "mara_voss", "display_name": "Mara Voss", "status": "active"},
	"Flight": {"personnel_id": "sora_vale", "display_name": "Sora Vale", "status": "active"}
}
const HAZARD_ADJACENCY := {
	"reactor": ["propulsion", "shield_grid"],
	"propulsion": ["reactor", "port_deck", "starboard_deck"],
	"shield_grid": ["reactor", "command_cic"],
	"fire_control": ["sensors", "command_cic"],
	"sensors": ["fire_control", "command_cic"],
	"command_cic": ["shield_grid", "fire_control", "sensors"],
	"port_deck": ["propulsion", "fire_control"],
	"starboard_deck": ["propulsion", "sensors"]
}

var subsystem_condition: Dictionary = {}
var power_allocations: Dictionary = {}
var current_power_preset: StringName = &"balanced"
var hazards: Dictionary = {}
var damage_control_teams: Array[Dictionary] = []
var crew_current: int = MAX_CREW
var stores: Dictionary = {}
var store_capacities: Dictionary = {}
var damage_control_spares: int = BASE_DAMAGE_CONTROL_SPARES
var damage_control_spares_capacity: int = BASE_DAMAGE_CONTROL_SPARES
var wing_loadouts: Dictionary = {"interceptor": "raptor_multirole", "scout": "watcher_recon"}
var air_group_craft_counts: Dictionary = {"interceptor": 4, "scout": 3}
var service_priority: StringName = &"balanced"
var officer_incidents: Array[Dictionary] = []
var department_leads: Dictionary = DEFAULT_DEPARTMENT_LEADS.duplicate(true)
var last_store_message: String = ""

var _installed_modules: Dictionary = {}
var _damage_sequence: int = 0
var _incident_sequence: int = 0
var _battle_casualties: int = 0
var _battle_store_usage: Dictionary = {}
var _battle_incident_outcomes: Array[Dictionary] = []
var _casualty_progress: float = 0.0
var _hazard_spread_progress: Dictionary = {}


func _init() -> void:
	_initialize_defaults()


func _initialize_defaults() -> void:
	subsystem_condition.clear()
	for subsystem_id in SUBSYSTEMS:
		subsystem_condition[String(subsystem_id)] = 1.0
	wing_loadouts = {"interceptor": "raptor_multirole", "scout": "watcher_recon"}
	air_group_craft_counts = {"interceptor": 4, "scout": 3}
	store_capacities = _base_store_capacities()
	stores = store_capacities.duplicate(true)
	damage_control_spares_capacity = BASE_DAMAGE_CONTROL_SPARES
	damage_control_spares = damage_control_spares_capacity
	department_leads = DEFAULT_DEPARTMENT_LEADS.duplicate(true)
	reset_for_battle()


func configure_modules(installed_modules: Dictionary, fill_added_capacity: bool = false) -> void:
	var previous_spare_capacity := damage_control_spares_capacity
	_installed_modules = installed_modules.duplicate(true)
	_recalculate_store_capacities(fill_added_capacity)
	damage_control_spares_capacity = BASE_DAMAGE_CONTROL_SPARES + (20 if _has_module(&"fleet_repair_drones") else 0)
	if fill_added_capacity and damage_control_spares_capacity > previous_spare_capacity:
		damage_control_spares += damage_control_spares_capacity - previous_spare_capacity
	damage_control_spares = clampi(damage_control_spares, 0, damage_control_spares_capacity)
	changed.emit(&"modules")


func configure_air_group(interceptor_count: int, scout_count: int, fill_added_capacity: bool = false) -> void:
	air_group_craft_counts = {
		"interceptor": maxi(0, interceptor_count),
		"scout": maxi(0, scout_count),
	}
	_recalculate_store_capacities(fill_added_capacity)
	changed.emit(&"air_group")


func _recalculate_store_capacities(fill_added_capacity: bool) -> void:
	var previous_capacities := store_capacities.duplicate(true)
	store_capacities = _base_store_capacities()
	if _has_module(&"siege_missile_cell"):
		store_capacities["guided_missiles"] = int(store_capacities.guided_missiles) + 8
	if _has_module(&"expanded_magazines"):
		store_capacities["flak_rounds"] = roundi(float(store_capacities.flak_rounds) * 1.25)
		store_capacities["aviation_ordnance"] = roundi(float(store_capacities.aviation_ordnance) * 1.25)
	for store_id in STORE_IDS:
		var key := String(store_id)
		var old_capacity := int(previous_capacities.get(key, store_capacities.get(key, 0)))
		var new_capacity := int(store_capacities.get(key, 0))
		var current := int(stores.get(key, new_capacity))
		if fill_added_capacity and new_capacity > old_capacity:
			current += new_capacity - old_capacity
		stores[key] = clampi(current, 0, new_capacity)


func set_department_leads(leads: Dictionary) -> void:
	if leads.is_empty():
		department_leads = DEFAULT_DEPARTMENT_LEADS.duplicate(true)
		changed.emit(&"department_leads")
		return
	department_leads.clear()
	for department in DEFAULT_DEPARTMENT_LEADS:
		var value: Variant = leads.get(department, {})
		if value is Dictionary:
			var record := (value as Dictionary).duplicate(true)
			if record.is_empty():
				record = {"personnel_id": "", "display_name": "UNASSIGNED", "status": "unavailable"}
			department_leads[String(department)] = record
		else:
			department_leads[String(department)] = {
				"personnel_id": String(value), "display_name": String(value), "status": "active"
			}
	changed.emit(&"department_leads")


func reset_for_battle() -> void:
	current_power_preset = &"balanced"
	power_allocations = POWER_PRESETS.balanced.duplicate(true)
	_shed_excess_power()
	hazards.clear()
	_hazard_spread_progress.clear()
	damage_control_teams.clear()
	for team_index in TEAM_COUNT:
		damage_control_teams.append(_default_team(team_index))
	officer_incidents.clear()
	_damage_sequence = 0
	_incident_sequence = 0
	_battle_casualties = 0
	_battle_store_usage.clear()
	_battle_incident_outcomes.clear()
	_casualty_progress = 0.0
	last_store_message = ""
	changed.emit(&"battle_reset")


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	var remaining := delta
	while remaining > 0.0:
		var step := minf(remaining, 0.25)
		_update_team_transit(step)
		_update_damage_control(step)
		_update_uncontained_hazards(step)
		_update_officer_incidents(step)
		remaining -= step


func apply_hull_impact(layer_result: Dictionary, impact_context: Dictionary = {}) -> Dictionary:
	var hull_damage := maxf(0.0, float(layer_result.get("hull", layer_result.get("hull_damage", 0.0))))
	if hull_damage <= 0.0:
		return {"subsystem": "", "condition_damage": 0.0, "hazards": []}
	var position_value: Variant = impact_context.get("position", impact_context.get("local_position", Vector3.ZERO))
	var impact_position := position_value as Vector3 if position_value is Vector3 else Vector3.ZERO
	var weapon_role := str(impact_context.get("weapon_role", impact_context.get("role", ""))).to_lower()
	var raw_damage := float(impact_context.get("raw_damage", impact_context.get("projectile_damage", hull_damage)))
	if weapon_role == "cannon" and raw_damage >= 40.0:
		weapon_role = "heavy"
	var subsystem_id := subsystem_for_impact(impact_position, weapon_role)
	var role_multiplier := 1.0
	if weapon_role == "missile" or weapon_role == "heavy":
		role_multiplier = 1.35
	elif weapon_role == "nuclear":
		role_multiplier = 2.75
	var normalized_damage := clampf(hull_damage / 240.0 * role_multiplier, 0.01, 0.75)
	_damage_sequence += 1
	return apply_subsystem_damage(subsystem_id, normalized_damage, weapon_role)


func apply_subsystem_damage(subsystem_id: StringName, normalized_damage: float, weapon_role: String = "") -> Dictionary:
	if not SUBSYSTEMS.has(subsystem_id):
		return {"subsystem": "", "condition_damage": 0.0, "hazards": []}
	var key := String(subsystem_id)
	var previous := float(subsystem_condition.get(key, 1.0))
	var applied := minf(previous, maxf(0.0, normalized_damage))
	subsystem_condition[key] = clampf(previous - applied, 0.0, 1.0)
	var created_hazards: Array[String] = []
	match weapon_role.to_lower():
		"heavy":
			create_hazard(subsystem_id, &"breach", clampf(0.25 + applied, 0.0, 1.0))
			created_hazards.append("breach")
		"missile":
			create_hazard(subsystem_id, &"fire", clampf(0.30 + applied, 0.0, 1.0))
			create_hazard(subsystem_id, &"breach", clampf(0.20 + applied * 0.5, 0.0, 1.0))
			created_hazards.assign(["fire", "breach"])
		"nuclear":
			create_hazard(subsystem_id, &"fire", 1.0)
			create_hazard(subsystem_id, &"breach", 1.0)
			created_hazards.assign(["fire", "breach"])
	_shed_excess_power()
	_check_officer_incident(subsystem_id)
	changed.emit(&"subsystem_damage")
	return {
		"subsystem": key,
		"condition_damage": applied,
		"condition": float(subsystem_condition[key]),
		"hazards": created_hazards
	}


func subsystem_for_impact(local_position: Vector3, weapon_role: String = "") -> StringName:
	var role := weapon_role.to_lower()
	if role == "nuclear":
		return &"reactor"
	if absf(local_position.x) >= 11.0:
		return &"port_deck" if local_position.x < 0.0 else &"starboard_deck"
	if local_position.z >= 32.0:
		return &"propulsion"
	if local_position.z <= -32.0:
		return &"fire_control" if local_position.x <= 0.0 else &"sensors"
	if local_position.y >= 5.0:
		return &"shield_grid"
	if local_position.y <= -5.0:
		return &"reactor"
	var central: Array[StringName] = [&"reactor", &"shield_grid", &"command_cic", &"sensors"]
	var deterministic_index := posmod(roundi(local_position.x * 3.0 + local_position.y * 5.0 + local_position.z * 7.0) + role.hash(), central.size())
	return central[deterministic_index]


func set_power_preset(preset_id: StringName) -> bool:
	var key := String(preset_id).to_lower()
	if not POWER_PRESETS.has(key):
		return false
	current_power_preset = StringName(key)
	power_allocations = (POWER_PRESETS[key] as Dictionary).duplicate(true)
	_shed_excess_power()
	changed.emit(&"power")
	return true


func set_power_allocation(channel: StringName, points: int) -> bool:
	if not POWER_CHANNELS.has(channel) or points < 1 or points > 4:
		return false
	current_power_preset = &"manual"
	power_allocations[String(channel)] = points
	_shed_excess_power()
	changed.emit(&"power")
	return int(power_allocations.get(String(channel), 1)) == points


func available_power_points() -> int:
	var condition := float(subsystem_condition.get("reactor", 1.0))
	if condition >= 0.75:
		return 8
	if condition >= 0.50:
		return 7
	if condition >= 0.25:
		return 6
	return 5


func power_multiplier(channel: StringName) -> float:
	if not POWER_CHANNELS.has(channel):
		return 1.0
	var points := int(power_allocations.get(String(channel), 1))
	var allocation_multiplier: float = float([0.0, 0.65, 1.0, 1.2, 1.4][clampi(points, 1, 4)])
	return allocation_multiplier


func subsystem_multiplier(subsystem_id: StringName) -> float:
	if not SUBSYSTEMS.has(subsystem_id):
		return 1.0
	var condition := clampf(float(subsystem_condition.get(String(subsystem_id), 1.0)), 0.0, 1.0)
	if condition < 0.1 and _has_active_team_at(subsystem_id):
		return 0.25
	return condition


func assign_damage_control_team(team_index: int, subsystem_id: StringName) -> bool:
	if team_index < 0 or team_index >= damage_control_teams.size() or not SUBSYSTEMS.has(subsystem_id):
		return false
	var team: Dictionary = damage_control_teams[team_index]
	team.target_subsystem = String(subsystem_id)
	team.state = "transit"
	team.transit_remaining = TEAM_TRANSIT_SECONDS
	team.repair_progress = 0.0
	damage_control_teams[team_index] = team
	_resolve_incident_for_subsystem(subsystem_id, "rescued")
	team_assignment_changed.emit(team_index, subsystem_id)
	changed.emit(&"damage_control")
	return true


func clear_damage_control_team(team_index: int) -> bool:
	if team_index < 0 or team_index >= damage_control_teams.size():
		return false
	damage_control_teams[team_index] = _default_team(team_index)
	team_assignment_changed.emit(team_index, &"")
	changed.emit(&"damage_control")
	return true


func create_hazard(subsystem_id: StringName, hazard_type: StringName, severity: float) -> void:
	if not SUBSYSTEMS.has(subsystem_id) or not [&"fire", &"breach"].has(hazard_type):
		return
	var subsystem_key := String(subsystem_id)
	var subsystem_hazards: Dictionary = hazards.get(subsystem_key, {})
	subsystem_hazards[String(hazard_type)] = maxf(float(subsystem_hazards.get(String(hazard_type), 0.0)), clampf(severity, 0.0, 1.0))
	hazards[subsystem_key] = subsystem_hazards
	_check_officer_incident(subsystem_id)
	changed.emit(&"hazard")


func hazard_severity(subsystem_id: StringName, hazard_type: StringName = &"") -> float:
	var subsystem_hazards: Dictionary = hazards.get(String(subsystem_id), {})
	if hazard_type != &"":
		return float(subsystem_hazards.get(String(hazard_type), 0.0))
	var maximum := 0.0
	for value in subsystem_hazards.values():
		maximum = maxf(maximum, float(value))
	return maximum


func consume_store(store_id: StringName, amount: int = 1) -> bool:
	return bool(request_store_consumption(store_id, amount, false).ok)


func consume_store_partial(store_id: StringName, amount: int) -> int:
	return int(request_store_consumption(store_id, amount, true).consumed)


func request_store_consumption(store_id: StringName, amount: int, allow_partial: bool = false) -> Dictionary:
	if not STORE_IDS.has(store_id) or amount <= 0:
		last_store_message = "Unknown carrier store request."
		store_rejected.emit(store_id, last_store_message)
		return {"ok": false, "consumed": 0, "remaining": 0, "message": last_store_message}
	var key := String(store_id)
	var available := int(stores.get(key, 0))
	var consumed := mini(available, amount) if allow_partial else (amount if available >= amount else 0)
	if consumed <= 0:
		last_store_message = "%s depleted: %d required, %d available." % [_store_display_name(store_id), amount, available]
		store_rejected.emit(store_id, last_store_message)
		return {"ok": false, "consumed": 0, "remaining": available, "message": last_store_message}
	stores[key] = available - consumed
	_battle_store_usage[key] = int(_battle_store_usage.get(key, 0)) + consumed
	last_store_message = ""
	changed.emit(&"stores")
	return {"ok": consumed == amount, "consumed": consumed, "remaining": int(stores[key]), "message": ""}


func store_capacity(store_id: StringName) -> int:
	return int(store_capacities.get(String(store_id), 0))


func refill_store(store_id: StringName, amount: int = -1) -> int:
	if not STORE_IDS.has(store_id):
		return 0
	var key := String(store_id)
	var missing := store_capacity(store_id) - int(stores.get(key, 0))
	var restored := missing if amount < 0 else mini(missing, maxi(0, amount))
	stores[key] = int(stores.get(key, 0)) + restored
	if restored > 0:
		changed.emit(&"stores")
	return restored


func set_wing_loadout(wing_role: StringName, loadout_id: StringName) -> bool:
	var role := String(wing_role)
	if not WingLoadoutDefinition.is_valid_for_role(loadout_id, role):
		return false
	wing_loadouts[role] = String(loadout_id)
	_recalculate_store_capacities(false)
	changed.emit(&"loadout")
	return true


func wing_loadout(wing_role: StringName) -> WingLoadoutDefinition:
	return WingLoadoutDefinition.definition(StringName(wing_loadouts.get(String(wing_role), "")))


func set_service_priority(priority_id: StringName) -> bool:
	if not [&"rapid_turn", &"balanced", &"repair_first"].has(priority_id):
		return false
	service_priority = priority_id
	changed.emit(&"deck_priority")
	return true


func deck_service_time_multiplier() -> float:
	var priority_multiplier := 0.75 if service_priority == &"rapid_turn" else (1.35 if service_priority == &"repair_first" else 1.0)
	var module_multiplier := 0.75 if _has_module(&"rapid_turnaround_deck") else 1.0
	var deck_condition := (subsystem_multiplier(&"port_deck") + subsystem_multiplier(&"starboard_deck")) * 0.5
	return priority_multiplier * module_multiplier / maxf(0.1, power_multiplier(&"flight") * deck_condition * crew_efficiency_multiplier(&"deck"))


func deck_armor_recovery_fraction() -> float:
	if service_priority == &"rapid_turn":
		return 0.0
	return 0.60 if service_priority == &"repair_first" else 0.35


func crew_efficiency_multiplier(area: StringName = &"general") -> float:
	var ratio := float(crew_current) / float(MAX_CREW)
	var value := 1.0
	if ratio < 0.25:
		value = 0.40
	elif ratio < 0.50:
		value = 0.65
	elif ratio < 0.75:
		value = 0.85
	if area == &"damage_control":
		return value
	if area == &"deck":
		return lerpf(0.25, 1.0, value)
	return value


func apply_crew_casualties(count: int, cause: String = "internal damage") -> int:
	var lost := mini(crew_current, maxi(0, count))
	if lost <= 0:
		return 0
	crew_current -= lost
	_battle_casualties += lost
	changed.emit(&"crew")
	return lost


func restore_crew_at_repair_node(maximum_replacements: int = 24) -> int:
	var restored := mini(MAX_CREW - crew_current, clampi(maximum_replacements, 0, 24))
	crew_current += restored
	if restored > 0:
		changed.emit(&"crew")
	return restored


func repair_all_subsystems() -> void:
	for subsystem_id in SUBSYSTEMS:
		subsystem_condition[String(subsystem_id)] = 1.0
	changed.emit(&"subsystem_repair")


func replenish_damage_control_spares() -> int:
	var restored := damage_control_spares_capacity - damage_control_spares
	damage_control_spares = damage_control_spares_capacity
	if restored > 0:
		changed.emit(&"spares")
	return restored


func to_dictionary() -> Dictionary:
	return {
		"subsystem_condition": subsystem_condition.duplicate(true),
		"crew_current": crew_current,
		"stores": stores.duplicate(true),
		"damage_control_spares": damage_control_spares,
		"wing_loadouts": wing_loadouts.duplicate(true),
		"air_group_craft_counts": air_group_craft_counts.duplicate(true),
		"department_leads": department_leads.duplicate(true)
	}


func load_dictionary(data: Dictionary) -> void:
	var saved_conditions: Dictionary = data.get("subsystem_condition", {})
	for subsystem_id in SUBSYSTEMS:
		var key := String(subsystem_id)
		subsystem_condition[key] = clampf(float(saved_conditions.get(key, 1.0)), 0.0, 1.0)
	var saved_craft_counts: Dictionary = data.get("air_group_craft_counts", {"interceptor": 4, "scout": 3})
	air_group_craft_counts = {
		"interceptor": maxi(0, int(saved_craft_counts.get("interceptor", 4))),
		"scout": maxi(0, int(saved_craft_counts.get("scout", 3))),
	}
	var saved_loadouts: Dictionary = data.get("wing_loadouts", {})
	wing_loadouts = {"interceptor": "raptor_multirole", "scout": "watcher_recon"}
	set_wing_loadout(&"interceptor", StringName(saved_loadouts.get("interceptor", "raptor_multirole")))
	set_wing_loadout(&"scout", StringName(saved_loadouts.get("scout", "watcher_recon")))
	crew_current = clampi(int(data.get("crew_current", MAX_CREW)), 0, MAX_CREW)
	var saved_stores: Dictionary = data.get("stores", {})
	for store_id in STORE_IDS:
		var key := String(store_id)
		stores[key] = clampi(int(saved_stores.get(key, store_capacity(store_id))), 0, store_capacity(store_id))
	damage_control_spares = clampi(int(data.get("damage_control_spares", damage_control_spares_capacity)), 0, damage_control_spares_capacity)
	set_department_leads(data.get("department_leads", DEFAULT_DEPARTMENT_LEADS))
	reset_for_battle()


static func from_dictionary(data: Dictionary, installed_modules: Dictionary = {}) -> CarrierOperationsState:
	var state := CarrierOperationsState.new()
	state.configure_modules(installed_modules, false)
	state.load_dictionary(data)
	return state


func battle_report() -> Dictionary:
	_finalize_unresolved_incidents()
	return {
		"persistent": to_dictionary(),
		"crew_casualties": _battle_casualties,
		"stores_expended": _battle_store_usage.duplicate(true),
		"officer_incidents": officer_incidents.duplicate(true),
		"officer_incident_outcomes": _battle_incident_outcomes.duplicate(true),
		"final_hazards": hazards.duplicate(true),
		"final_power_preset": String(current_power_preset)
	}


func apply_battle_report(report: Dictionary) -> void:
	var payload: Dictionary = report.get("persistent", report)
	load_dictionary(payload)


func active_officer_incident(subsystem_id: StringName = &"") -> Dictionary:
	for incident in officer_incidents:
		if str(incident.get("outcome", "")) == "trapped" and (subsystem_id == &"" or str(incident.get("subsystem", "")) == String(subsystem_id)):
			return incident
	return {}


func _base_store_capacities() -> Dictionary:
	return {
		"flak_rounds": 2100,
		"guided_missiles": 24,
		"nuclear_torpedoes": 1,
		"aviation_ordnance": _aviation_reload_capacity(),
		"craft_refuel": 14
	}


func _aviation_reload_capacity() -> int:
	var total := 0
	for role in [&"interceptor", &"scout"]:
		var loadout := wing_loadout(role)
		var ammunition_per_craft := loadout.ammunition_per_craft if loadout != null else 0
		total += int(air_group_craft_counts.get(String(role), 0)) * ammunition_per_craft
	return total


func _has_module(module_id: StringName) -> bool:
	for value in _installed_modules.values():
		if StringName(value) == module_id:
			return true
	return false


func _default_team(team_index: int) -> Dictionary:
	return {
		"team_index": team_index,
		"target_subsystem": "",
		"state": "idle",
		"transit_remaining": 0.0,
		"repair_progress": 0.0
	}


func _shed_excess_power() -> void:
	for channel in POWER_CHANNELS:
		power_allocations[String(channel)] = clampi(int(power_allocations.get(String(channel), 1)), 1, 4)
	var tie_order: Array[StringName] = [&"flight", &"weapons", &"propulsion", &"defense"]
	while _allocated_power_total() > available_power_points():
		var selected := &""
		var largest := 1
		for channel in tie_order:
			var allocation := int(power_allocations.get(String(channel), 1))
			if allocation > largest:
				largest = allocation
				selected = channel
		if selected == &"":
			break
		power_allocations[String(selected)] = largest - 1


func _allocated_power_total() -> int:
	var total := 0
	for channel in POWER_CHANNELS:
		total += int(power_allocations.get(String(channel), 1))
	return total


func _has_active_team_at(subsystem_id: StringName) -> bool:
	for team in damage_control_teams:
		if str(team.get("state", "")) == "working" and str(team.get("target_subsystem", "")) == String(subsystem_id):
			return true
	return false


func _update_team_transit(delta: float) -> void:
	for index in damage_control_teams.size():
		var team: Dictionary = damage_control_teams[index]
		if str(team.get("state", "")) != "transit":
			continue
		team.transit_remaining = maxf(0.0, float(team.get("transit_remaining", 0.0)) - delta)
		if float(team.transit_remaining) <= 0.0:
			team.state = "working"
		damage_control_teams[index] = team


func _update_damage_control(delta: float) -> void:
	var work_multiplier := crew_efficiency_multiplier(&"damage_control")
	for index in damage_control_teams.size():
		var team: Dictionary = damage_control_teams[index]
		if str(team.get("state", "")) != "working":
			continue
		var subsystem_id := StringName(team.get("target_subsystem", ""))
		if not SUBSYSTEMS.has(subsystem_id):
			continue
		var subsystem_key := String(subsystem_id)
		var subsystem_hazards: Dictionary = hazards.get(subsystem_key, {})
		var work_done := false
		for hazard_type in [&"fire", &"breach"]:
			var hazard_key := String(hazard_type)
			var severity := float(subsystem_hazards.get(hazard_key, 0.0))
			if severity <= 0.0:
				continue
			var rate := 0.16 if hazard_type == &"fire" else 0.12
			severity = maxf(0.0, severity - rate * work_multiplier * delta)
			if severity <= 0.0001:
				subsystem_hazards.erase(hazard_key)
			else:
				subsystem_hazards[hazard_key] = severity
			work_done = true
			break
		if subsystem_hazards.is_empty():
			hazards.erase(subsystem_key)
			_resolve_incident_for_subsystem(subsystem_id, "rescued")
		else:
			hazards[subsystem_key] = subsystem_hazards
		if not work_done and damage_control_spares > 0 and float(subsystem_condition.get(subsystem_key, 1.0)) < 1.0:
			team.repair_progress = float(team.get("repair_progress", 0.0)) + 2.0 * work_multiplier * delta
			var spare_units := mini(damage_control_spares, floori(float(team.repair_progress)))
			if spare_units > 0:
				team.repair_progress = float(team.repair_progress) - spare_units
				damage_control_spares -= spare_units
				subsystem_condition[subsystem_key] = minf(1.0, float(subsystem_condition[subsystem_key]) + float(spare_units) * 0.01)
		damage_control_teams[index] = team


func _update_uncontained_hazards(delta: float) -> void:
	var total_severity := 0.0
	for subsystem_key in hazards.keys():
		var subsystem_id := StringName(subsystem_key)
		var subsystem_hazards: Dictionary = hazards[subsystem_key]
		var contained := _has_active_team_at(subsystem_id)
		for hazard_type in subsystem_hazards.keys():
			var severity := float(subsystem_hazards[hazard_type])
			if contained:
				continue
			total_severity += severity
			if hazard_type == "fire":
				subsystem_hazards[hazard_type] = minf(1.0, severity + 0.01 * delta)
			subsystem_condition[subsystem_key] = maxf(0.0, float(subsystem_condition.get(subsystem_key, 1.0)) - severity * (0.003 if hazard_type == "fire" else 0.002) * delta)
		hazards[subsystem_key] = subsystem_hazards
		_check_officer_incident(subsystem_id)
		if not contained and hazard_severity(subsystem_id) >= 0.85:
			_hazard_spread_progress[subsystem_key] = float(_hazard_spread_progress.get(subsystem_key, 0.0)) + delta
			if float(_hazard_spread_progress[subsystem_key]) >= 12.0:
				_hazard_spread_progress[subsystem_key] = 0.0
				_spread_fire_from(subsystem_id)
	_casualty_progress += total_severity * delta * 0.08
	var casualties := floori(_casualty_progress)
	if casualties > 0:
		_casualty_progress -= casualties
		apply_crew_casualties(casualties, "uncontained carrier hazard")
	_shed_excess_power()


func _spread_fire_from(subsystem_id: StringName) -> void:
	var adjacent: Array = HAZARD_ADJACENCY.get(String(subsystem_id), [])
	if adjacent.is_empty():
		return
	var index := posmod(_damage_sequence + String(subsystem_id).hash(), adjacent.size())
	_damage_sequence += 1
	create_hazard(StringName(adjacent[index]), &"fire", 0.25)


func _check_officer_incident(subsystem_id: StringName) -> void:
	if float(subsystem_condition.get(String(subsystem_id), 1.0)) >= 0.20 or hazard_severity(subsystem_id) < 0.75:
		return
	if not active_officer_incident(subsystem_id).is_empty():
		return
	var department := str(SUBSYSTEM_DEPARTMENTS.get(String(subsystem_id), "Command"))
	var lead: Dictionary = department_leads.get(department, {})
	if lead.is_empty() or str(lead.get("personnel_id", "")).is_empty() or str(lead.get("status", "active")) == "deceased":
		return
	_incident_sequence += 1
	var incident := {
		"incident_id": "carrier_incident_%d" % _incident_sequence,
		"subsystem": String(subsystem_id),
		"department": department,
		"personnel_id": str(lead.get("personnel_id", "")),
		"display_name": str(lead.get("display_name", lead.get("personnel_id", "Officer"))),
		"injury_severity": 3,
		"time_remaining": OFFICER_RESCUE_SECONDS,
		"outcome": "trapped"
	}
	officer_incidents.append(incident)
	incident_started.emit(incident.duplicate(true))
	changed.emit(&"officer_incident")


func _update_officer_incidents(delta: float) -> void:
	for index in officer_incidents.size():
		var incident: Dictionary = officer_incidents[index]
		if str(incident.get("outcome", "")) != "trapped":
			continue
		incident.time_remaining = maxf(0.0, float(incident.get("time_remaining", OFFICER_RESCUE_SECONDS)) - delta)
		var subsystem_id := StringName(incident.get("subsystem", ""))
		if hazard_severity(subsystem_id) <= 0.0:
			incident.outcome = "rescued"
		elif float(subsystem_condition.get(String(subsystem_id), 1.0)) <= 0.0 or float(incident.time_remaining) <= 0.0:
			incident.outcome = "killed"
		officer_incidents[index] = incident
		if str(incident.outcome) != "trapped":
			_record_incident_outcome(incident)


func _resolve_incident_for_subsystem(subsystem_id: StringName, outcome: String) -> void:
	for index in officer_incidents.size():
		var incident: Dictionary = officer_incidents[index]
		if str(incident.get("subsystem", "")) != String(subsystem_id) or str(incident.get("outcome", "")) != "trapped":
			continue
		incident.outcome = outcome
		officer_incidents[index] = incident
		_record_incident_outcome(incident)


func _finalize_unresolved_incidents() -> void:
	# Leaving the combat scene triggers an emergency recovery operation. The lead
	# survives, but the severity-three injury still persists through the report.
	for index in officer_incidents.size():
		var incident: Dictionary = officer_incidents[index]
		if str(incident.get("outcome", "")) != "trapped":
			continue
		incident.outcome = "rescued"
		incident["resolution"] = "emergency_battle_end_recovery"
		officer_incidents[index] = incident
		_record_incident_outcome(incident)


func _record_incident_outcome(incident: Dictionary) -> void:
	for existing in _battle_incident_outcomes:
		if str(existing.get("incident_id", "")) == str(incident.get("incident_id", "")):
			return
	_battle_incident_outcomes.append(incident.duplicate(true))
	incident_resolved.emit(incident.duplicate(true))
	changed.emit(&"officer_incident")


func _store_display_name(store_id: StringName) -> String:
	match store_id:
		&"flak_rounds": return "Flak magazine"
		&"guided_missiles": return "Guided missile magazine"
		&"nuclear_torpedoes": return "Nuclear torpedo magazine"
		&"aviation_ordnance": return "Aviation ordnance"
		&"craft_refuel": return "Craft refuel stores"
		_: return "Carrier store"
