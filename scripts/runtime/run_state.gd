class_name SidebayRunState
extends RefCounted

const SAVE_VERSION := 9
const MAX_INTERCEPTOR_CRAFT := 4
const MAX_SCOUT_CRAFT := 3
const BASE_INTERCEPTOR_AMMO := 112
const BASE_SCOUT_AMMO := 54

var run_id: String = ""
var seed: int = 0
var sector_index: int = 0
var current_node_id: StringName = &""
var supplies: int = 100
var fuel: int = 10
var intel: int = 2
var requisition: int = 1
var completed_node_ids: Array[StringName] = []
var revealed_node_ids: Array[StringName] = []
var battles_won: int = 0
var withdrawals: int = 0
var objectives_completed: int = 0
var objectives_failed: int = 0
var personnel_rescued: int = 0
var personnel_lost: int = 0
var straggler_craft_recovered: int = 0
var salvage_recovered: int = 0
var salvage_stock: int = 0
var logistics_posture_id: StringName = &"balanced_stores"
var run_completed: bool = false
var run_failed: bool = false
var carrier_shields: float = 1.0
var carrier_armor: float = 1.0
var carrier_hull: float = 1.0
var interceptor_craft_count: int = MAX_INTERCEPTOR_CRAFT
var interceptor_ammunition: int = BASE_INTERCEPTOR_AMMO
var scout_craft_count: int = MAX_SCOUT_CRAFT
var scout_ammunition: int = BASE_SCOUT_AMMO
var active_carrier_id: StringName = &"cvn_sidebay"
var acquired_carrier_ids: Array[StringName] = [&"cvn_sidebay"]
var active_hangar_complement_id: StringName = &"balanced_wings"
var acquired_hangar_complement_ids: Array[StringName] = [&"balanced_wings"]
var escort_active: bool = true
var active_escort_id: StringName = &"iss_resolute"
var acquired_escort_ids: Array[StringName] = [&"iss_resolute"]
var lost_escort_ids: Array[StringName] = []
var unlocked_module_ids: Array[StringName] = [
	&"siege_missile_cell",
	&"aegis_relay",
	&"longwatch_array",
	&"fleet_repair_drones",
	&"rapid_turnaround_deck"
]
var installed_modules: Dictionary = {
	"weapon": "siege_missile_cell",
	"defense": "aegis_relay",
	"sensor": "longwatch_array",
	"support": "fleet_repair_drones",
	"hangar": "rapid_turnaround_deck"
}
var personnel_roster: Array[SidebayPersonnelRecord] = []
var department_assignments: Dictionary = {}
var personnel_event_log: Array[String] = []
var recruitment_pool: Array[SidebayPersonnelRecord] = []
var pending_operational_event: Dictionary = {}
var resolved_operational_event_ids: Array[StringName] = []

static func departments() -> Array[StringName]:
	return [&"Command", &"Flight", &"Gunnery", &"Engineering", &"Sensors", &"Medical"]

static func module_catalog() -> Array[Dictionary]:
	return [
		{"id": &"siege_missile_cell", "slot": "weapon", "name": "Siege Missile Cell", "effect": "+20% carrier missile damage"},
		{"id": &"flak_director", "slot": "weapon", "name": "Aegis Flak Director", "effect": "+25% flak range"},
		{"id": &"aegis_relay", "slot": "defense", "name": "Aegis Shield Relay", "effect": "+20% carrier shields"},
		{"id": &"ablative_citadel", "slot": "defense", "name": "Ablative Citadel", "effect": "+20% carrier armor"},
		{"id": &"longwatch_array", "slot": "sensor", "name": "Longwatch Array", "effect": "+20% passive and active sensor range"},
		{"id": &"command_uplink", "slot": "sensor", "name": "Command Uplink", "effect": "+25% command-link range"},
		{"id": &"fleet_repair_drones", "slot": "support", "name": "Fleet Repair Drones", "effect": "-20% fleet service cost"},
		{"id": &"field_fabricator", "slot": "support", "name": "Field Fabricator", "effect": "+15% carrier hull"},
		{"id": &"rapid_turnaround_deck", "slot": "hangar", "name": "Rapid Turnaround Deck", "effect": "-25% wing service time"},
		{"id": &"expanded_magazines", "slot": "hangar", "name": "Expanded Magazines", "effect": "+25% wing ammunition"}
	]

static func module_data(module_id: StringName) -> Dictionary:
	for module in module_catalog():
		if module.id == module_id:
			return module
	return {}

static func carrier_catalog() -> Array[Dictionary]:
	return [
		{
			"id": &"cvn_sidebay", "name": "CVN Sidebay", "class_name": "Command Carrier",
			"summary": "Balanced command hull with standard mobility, protection, and strike power.",
			"requisition_cost": 0, "required_sector": 0,
			"width": 42.0, "height": 20.0, "length": 120.0,
			"acceleration": 1.0, "speed": 1.0, "rotation": 1.0, "signature": 1.0,
			"shields": 1.0, "armor": 1.0, "hull": 1.0, "shield_regen": 1.0, "armor_mitigation": 1.0,
			"sensors": 1.0, "command": 1.0, "weapon_damage": 1.0
		},
		{
			"id": &"cvn_vanguard", "name": "CVN Vanguard", "class_name": "Assault Carrier",
			"summary": "Fast attack frame with stronger weapons but lighter protection and command reach.",
			"requisition_cost": 3, "required_sector": 1,
			"width": 40.0, "height": 18.0, "length": 112.0,
			"acceleration": 1.18, "speed": 1.15, "rotation": 1.12, "signature": 1.10,
			"shields": 0.85, "armor": 0.95, "hull": 0.90, "shield_regen": 0.90, "armor_mitigation": 0.95,
			"sensors": 0.90, "command": 0.90, "weapon_damage": 1.18
		},
		{
			"id": &"cvn_citadel", "name": "CVN Citadel", "class_name": "Fleet Carrier",
			"summary": "Slow armored command frame with exceptional durability and fleet-control reach.",
			"requisition_cost": 4, "required_sector": 2,
			"width": 48.0, "height": 24.0, "length": 132.0,
			"acceleration": 0.78, "speed": 0.80, "rotation": 0.82, "signature": 1.15,
			"shields": 1.25, "armor": 1.30, "hull": 1.35, "shield_regen": 1.20, "armor_mitigation": 1.12,
			"sensors": 1.05, "command": 1.20, "weapon_damage": 0.90
		}
	]

static func carrier_data(carrier_id: StringName) -> Dictionary:
	for carrier_definition in carrier_catalog():
		if carrier_definition.id == carrier_id:
			return carrier_definition
	return {}

static func hangar_complement_catalog() -> Array[Dictionary]:
	return [
		{
			"id": &"balanced_wings", "name": "Balanced Air Group",
			"summary": "Four Raptor interceptors and three Watcher scouts.",
			"requisition_cost": 0, "required_sector": 0,
			"interceptor_craft": 4, "scout_craft": 3,
			"interceptor_ammo_per_craft": 28, "scout_ammo_per_craft": 18,
			"interceptor_endurance": 1.0, "scout_endurance": 1.0, "service_time": 1.0
		},
		{
			"id": &"strike_group", "name": "Raptor Strike Group",
			"summary": "Five heavy interceptors and two scouts; ammunition-heavy offensive posture.",
			"requisition_cost": 2, "required_sector": 0,
			"interceptor_craft": 5, "scout_craft": 2,
			"interceptor_ammo_per_craft": 32, "scout_ammo_per_craft": 18,
			"interceptor_endurance": 0.90, "scout_endurance": 0.90, "service_time": 1.10
		},
		{
			"id": &"recon_group", "name": "Watcher Recon Group",
			"summary": "Three interceptors and four long-endurance scouts for contact control.",
			"requisition_cost": 2, "required_sector": 1,
			"interceptor_craft": 3, "scout_craft": 4,
			"interceptor_ammo_per_craft": 28, "scout_ammo_per_craft": 22,
			"interceptor_endurance": 1.0, "scout_endurance": 1.20, "service_time": 0.95
		}
	]

static func hangar_complement_data(complement_id: StringName) -> Dictionary:
	for complement in hangar_complement_catalog():
		if complement.id == complement_id:
			return complement
	return {}

static func logistics_posture_catalog() -> Array[Dictionary]:
	return [
		{
			"id": &"balanced_stores", "name": "Balanced Stores",
			"summary": "Base fuel cost. No jump surcharge. Standard salvage yield.",
			"fuel_adjustment": 0, "supplies_per_jump": 0, "salvage_multiplier": 1.0
		},
		{
			"id": &"lean_burn", "name": "Lean Burn",
			"summary": "Fuel cost -1 (minimum 1). Jump surcharge: 6 supplies.",
			"fuel_adjustment": -1, "supplies_per_jump": 6, "salvage_multiplier": 1.0
		},
		{
			"id": &"recovery_rig", "name": "Recovery Rig",
			"summary": "Fuel cost +1. Salvage recovery +50%.",
			"fuel_adjustment": 1, "supplies_per_jump": 0, "salvage_multiplier": 1.5
		}
	]

static func logistics_posture_data(posture_id: StringName) -> Dictionary:
	for posture in logistics_posture_catalog():
		if posture.id == posture_id:
			return posture
	return {}

static func salvage_allocation_catalog() -> Array[Dictionary]:
	return [
		{"id": &"supplies", "name": "Fabricate Stores", "salvage_cost": 4, "yield": 10, "summary": "Convert 4 salvage into 10 supplies."},
		{"id": &"fuel", "name": "Refine Drive Fuel", "salvage_cost": 6, "yield": 1, "summary": "Convert 6 salvage into 1 fuel."},
		{"id": &"requisition", "name": "Fleet Claims", "salvage_cost": 10, "yield": 1, "summary": "Convert 10 salvage into 1 requisition."}
	]

static func salvage_allocation_data(allocation_id: StringName) -> Dictionary:
	for allocation in salvage_allocation_catalog():
		if allocation.id == allocation_id:
			return allocation
	return {}

static func escort_catalog() -> Array[Dictionary]:
	return [
		{
			"id": &"iss_resolute", "name": "ISS Resolute", "class_name": "Missile Frigate",
			"summary": "Long-range strike escort; balanced protection and missile reach.",
			"requisition_cost": 0, "required_sector": 0, "role": "frigate",
			"length": 65.0, "width": 24.0, "height": 12.0,
			"acceleration": 42.0, "speed": 220.0, "rotation": 0.9, "signature": 1.05,
			"shields": 260.0, "armor": 300.0, "hull": 340.0, "shield_regen": 5.0, "armor_mitigation": 0.22,
			"weapon_id": &"resolute_missile", "weapon_name": "Resolute Strike Missile", "weapon_role": "missile",
			"weapon_range": 4400.0, "weapon_cooldown": 4.0, "weapon_damage": 68.0, "projectile_speed": 570.0,
			"weapon_tracks": true, "weapon_intercepts": false
		},
		{
			"id": &"iss_harrier", "name": "ISS Harrier", "class_name": "Screen Corvette",
			"summary": "Fast close screen; trades endurance and range for interception pressure.",
			"requisition_cost": 2, "required_sector": 0, "role": "corvette",
			"length": 42.0, "width": 16.0, "height": 8.0,
			"acceleration": 64.0, "speed": 330.0, "rotation": 1.3, "signature": 0.82,
			"shields": 175.0, "armor": 180.0, "hull": 220.0, "shield_regen": 7.0, "armor_mitigation": 0.16,
			"weapon_id": &"harrier_cannon", "weapon_name": "Harrier Screen Cannon", "weapon_role": "cannon",
			"weapon_range": 2200.0, "weapon_cooldown": 0.7, "weapon_damage": 24.0, "projectile_speed": 1050.0,
			"weapon_tracks": false, "weapon_intercepts": true
		},
		{
			"id": &"iss_bulwark", "name": "ISS Bulwark", "class_name": "Line Frigate",
			"summary": "Armored fleet anchor; slower, shorter-ranged, and difficult to dislodge.",
			"requisition_cost": 3, "required_sector": 1, "role": "frigate",
			"length": 70.0, "width": 28.0, "height": 15.0,
			"acceleration": 32.0, "speed": 180.0, "rotation": 0.7, "signature": 1.18,
			"shields": 360.0, "armor": 430.0, "hull": 500.0, "shield_regen": 8.0, "armor_mitigation": 0.30,
			"weapon_id": &"bulwark_missile", "weapon_name": "Bulwark Guard Missile", "weapon_role": "missile",
			"weapon_range": 3600.0, "weapon_cooldown": 3.2, "weapon_damage": 56.0, "projectile_speed": 540.0,
			"weapon_tracks": true, "weapon_intercepts": false
		}
	]

static func escort_data(escort_id: StringName) -> Dictionary:
	for escort_definition in escort_catalog():
		if escort_definition.id == escort_id:
			return escort_definition
	return {}

static func create_new(run_seed: int = 0) -> SidebayRunState:
	var state := SidebayRunState.new()
	state.seed = run_seed if run_seed != 0 else int(Time.get_unix_time_from_system())
	state.run_id = "%s-%s" % [state.seed, Time.get_ticks_msec()]
	state._initialize_authored_personnel()
	state._initialize_recruitment_pool()
	return state

func _initialize_authored_personnel() -> void:
	personnel_roster = [
		SidebayPersonnelRecord.create(&"mara_voss", "Mara Voss", "Commander", &"Command", "Commanding Officer", 5, ["Resolute", "Measured"], [&"ilya_chen"]),
		SidebayPersonnelRecord.create(&"ilya_chen", "Ilya Chen", "Lieutenant", &"Command", "Tactical Coordinator", 4, ["Decisive", "Protective"], [&"mara_voss"]),
		SidebayPersonnelRecord.create(&"sora_vale", "Sora Vale", "Lt. Commander", &"Flight", "Carrier Air Group", 5, ["Ace", "Demanding"], [&"tomas_rook"]),
		SidebayPersonnelRecord.create(&"tomas_rook", "Tomas Rook", "Chief", &"Flight", "Flight Deck Chief", 4, ["Deckwise", "Loyal"], [&"sora_vale"]),
		SidebayPersonnelRecord.create(&"ada_kessler", "Ada Kessler", "Lieutenant", &"Gunnery", "Weapons Officer", 5, ["Precise", "Competitive"], [&"malik_torres"]),
		SidebayPersonnelRecord.create(&"malik_torres", "Malik Torres", "Petty Officer", &"Gunnery", "Fire-Control Chief", 4, ["Calm", "Improviser"], [&"ada_kessler"]),
		SidebayPersonnelRecord.create(&"nia_okafor", "Nia Okafor", "Lt. Commander", &"Engineering", "Chief Engineer", 5, ["Inventive", "Unflappable"], [&"bram_holt"]),
		SidebayPersonnelRecord.create(&"bram_holt", "Bram Holt", "Chief", &"Engineering", "Damage-Control Chief", 4, ["Stubborn", "Dependable"], [&"nia_okafor"]),
		SidebayPersonnelRecord.create(&"yara_sen", "Yara Sen", "Lieutenant", &"Sensors", "Sensor Officer", 5, ["Watchful", "Reserved"], [&"keon_aras"]),
		SidebayPersonnelRecord.create(&"keon_aras", "Keon Aras", "Specialist", &"Sensors", "Electronic Warfare", 4, ["Curious", "Signal Savant"], [&"yara_sen"]),
		SidebayPersonnelRecord.create(&"elian_ward", "Elian Ward", "Doctor", &"Medical", "Chief Medical Officer", 5, ["Steady", "Compassionate"], [&"june_park"]),
		SidebayPersonnelRecord.create(&"june_park", "June Park", "Corpsman", &"Medical", "Flight Medic", 4, ["Brave", "Pragmatic"], [&"elian_ward"])
	]
	department_assignments.clear()
	for department in departments():
		var members := department_members(department)
		department_assignments[String(department)] = String(members[0].personnel_id) if not members.is_empty() else ""

func _initialize_recruitment_pool() -> void:
	recruitment_pool.clear()
	var rui := SidebayPersonnelRecord.create(&"rui_mercer", "Rui Mercer", "Ensign", &"Flight", "Reserve Pilot", 3, ["Eager", "Quick Study"], [])
	rui.recruitment_cost = 1
	var samira := SidebayPersonnelRecord.create(&"samira_dax", "Samira Dax", "Chief", &"Engineering", "Salvage Engineer", 4, ["Resourceful", "Outsider"], [])
	samira.recruitment_cost = 2
	var imani := SidebayPersonnelRecord.create(&"imani_thorne", "Imani Thorne", "Doctor", &"Medical", "Trauma Surgeon", 4, ["Clinical", "Fearless"], [])
	imani.recruitment_cost = 2
	var edda := SidebayPersonnelRecord.create(&"edda_kaine", "Edda Kaine", "Captain", &"Command", "Fleet Liaison", 5, ["Legendary", "Politically Connected"], [])
	edda.recruitment_cost = 3
	edda.rare_recruit = true
	edda.recruitment_unlocked = false
	recruitment_pool = [rui, samira, imani, edda]

func next_recruit_candidate() -> SidebayPersonnelRecord:
	for candidate in recruitment_pool:
		if candidate.recruitment_unlocked:
			return candidate
	return null

func recruit_next_candidate() -> String:
	var candidate := next_recruit_candidate()
	if candidate == null:
		return "No unlocked officer is currently available."
	if requisition < candidate.recruitment_cost:
		return "Recruitment rejected: %d requisition required." % candidate.recruitment_cost
	requisition -= candidate.recruitment_cost
	recruitment_pool.erase(candidate)
	personnel_roster.append(candidate)
	personnel_event_log.append("%s joined the %s department." % [candidate.display_name, String(candidate.department)])
	return "%s recruited into %s." % [candidate.display_name, String(candidate.department)]

func next_injured_person() -> SidebayPersonnelRecord:
	for person in personnel_roster:
		if person.status == SidebayPersonnelRecord.Status.INJURED:
			return person
	return null

func treatment_cost(person: SidebayPersonnelRecord) -> int:
	if person == null or person.status != SidebayPersonnelRecord.Status.INJURED:
		return 0
	var base_cost := person.injury_severity * 8
	var medical := assigned_person(&"Medical")
	return ceili(base_cost * (0.8 if medical != null and medical.effective_skill() >= 4 else 1.0))

func treat_next_injury() -> String:
	var person := next_injured_person()
	if person == null:
		return "No injured personnel require treatment."
	var cost := treatment_cost(person)
	if not spend_supplies(cost):
		return "Treatment rejected: %d supplies required." % cost
	var recovered := person.recover_step()
	var message := "%s returned to active duty after treatment." % person.display_name if recovered else "%s treatment reduced injury severity to %d." % [person.display_name, person.injury_severity]
	personnel_event_log.append(message)
	_repair_department_assignments()
	return message

func next_promotion_candidate() -> SidebayPersonnelRecord:
	for person in personnel_roster:
		if person.is_available() and person.skill < 5 and person.missions >= 3:
			return person
	return null

func promote_next_candidate() -> String:
	var person := next_promotion_candidate()
	if person == null:
		return "No officer currently meets promotion requirements."
	var cost := 20
	if not spend_supplies(cost):
		return "Promotion package requires %d supplies." % cost
	person.skill += 1
	person.promotion_count += 1
	person.rank = _promoted_rank(person.rank)
	if not person.traits.has("Proven"):
		person.traits.append("Proven")
	var message := "%s promoted to %s; skill increased to %d." % [person.display_name, person.rank, person.skill]
	personnel_event_log.append(message)
	return message

func _promoted_rank(current_rank: String) -> String:
	match current_rank:
		"Ensign": return "Lieutenant"
		"Lieutenant": return "Lt. Commander"
		"Petty Officer": return "Chief"
		"Chief": return "Senior Chief"
		"Specialist": return "Senior Specialist"
		"Corpsman": return "Chief Corpsman"
		_: return "Senior %s" % current_rank

static func operational_event_catalog() -> Array[Dictionary]:
	return [
		{
			"event_id": &"fractured_watch",
			"title": "FRACTURED WATCH",
			"body": "Yara Sen has been carrying the sensor watch alone since the last contact. Commander Voss can share the burden, or formal discipline can keep the department moving.",
			"radio": "VOSS: No one carries a watch alone on my ship.",
			"choices": [
				{"id": &"share_burden", "label": "SHARE THE BURDEN", "summary": "Voss and Sen form a bond; gain 1 intel."},
				{"id": &"maintain_discipline", "label": "MAINTAIN DISCIPLINE", "summary": "Sensors lead gains Disciplined; gain 1 requisition."}
			]
		},
		{
			"event_id": &"deck_rivalry",
			"title": "THE DECK AND THE GUN LINE",
			"body": "Sora Vale and Ada Kessler are blaming each other for a near miss during recovery. A joint drill could build trust, or command can turn the rivalry into useful pressure.",
			"radio": "KESSLER: Tell Flight to stop crossing my firing solutions.",
			"choices": [
				{"id": &"joint_drill", "label": "ORDER A JOINT DRILL", "summary": "Vale and Kessler form a bond and gain Cross-trained."},
				{"id": &"competitive_edge", "label": "USE THE RIVALRY", "summary": "Both gain Competitive; gain 1 requisition."}
			]
		},
		{
			"event_id": &"triage_shortage",
			"title": "TRIAGE SHORTAGE",
			"body": "Medical stores are running thin. Ward can open protected reserves for immediate treatment, or ration them and accept an exhausted department.",
			"radio": "WARD: Supplies are numbers until someone is bleeding.",
			"choices": [
				{"id": &"open_reserves", "label": "OPEN MEDICAL RESERVES", "summary": "Spend 12 supplies; reduce every injury by one step.", "supplies": 12},
				{"id": &"ration_stores", "label": "RATION THE STORES", "summary": "Gain 1 fuel; Medical lead gains Exhausted."}
			]
		},
		{
			"event_id": &"salvage_survivor",
			"title": "THE ADMIRAL IN THE WRECK",
			"body": "A sealed command capsule contains Captain Edda Kaine, a politically connected fleet liaison presumed dead. Bringing her aboard costs stores and attention.",
			"radio": "KAINE: Open this capsule and I can still win you a war.",
			"choices": [
				{"id": &"take_aboard", "label": "BRING KAINE ABOARD", "summary": "Spend 15 supplies; unlock a rare Command recruit.", "supplies": 15},
				{"id": &"secure_archive", "label": "SECURE THE ARCHIVE", "summary": "Leave the capsule with rescue services; gain 2 intel."}
			]
		}
	]

func prepare_operational_event(_node_type: int, _node_id: StringName) -> bool:
	if not pending_operational_event.is_empty():
		return true
	var available: Array[Dictionary] = []
	for event in operational_event_catalog():
		if not resolved_operational_event_ids.has(event.event_id):
			available.append(event)
	if available.is_empty():
		return false
	var index := completed_node_ids.size() % available.size()
	pending_operational_event = available[index].duplicate(true)
	return true

func can_resolve_event_choice(choice_id: StringName) -> bool:
	for choice in pending_operational_event.get("choices", []):
		if StringName(choice.get("id", "")) == choice_id:
			return supplies >= int(choice.get("supplies", 0))
	return false

func resolve_operational_event(choice_id: StringName) -> String:
	if pending_operational_event.is_empty() or not can_resolve_event_choice(choice_id):
		return "Operational decision unavailable."
	var event_id := StringName(pending_operational_event.get("event_id", ""))
	var message := "Operational decision recorded."
	match event_id:
		&"fractured_watch":
			if choice_id == &"share_burden":
				_add_mutual_bond(&"yara_sen", &"mara_voss")
				intel += 1
				message = "Voss joined the watch. Sen gained a trusted bond; +1 intel."
			else:
				_add_trait(assigned_person(&"Sensors"), "Disciplined")
				requisition += 1
				message = "The watch held formation; +1 requisition."
		&"deck_rivalry":
			if choice_id == &"joint_drill":
				_add_mutual_bond(&"sora_vale", &"ada_kessler")
				_add_trait(get_personnel(&"sora_vale"), "Cross-trained")
				_add_trait(get_personnel(&"ada_kessler"), "Cross-trained")
				message = "The joint drill forged a new Flight-Gunnery bond."
			else:
				_add_trait(get_personnel(&"sora_vale"), "Competitive")
				_add_trait(get_personnel(&"ada_kessler"), "Competitive")
				requisition += 1
				message = "Command weaponized the rivalry; +1 requisition."
		&"triage_shortage":
			if choice_id == &"open_reserves":
				supplies -= 12
				for person in personnel_roster:
					person.recover_step()
				_repair_department_assignments()
				message = "Medical reserves opened; all injuries improved."
			else:
				fuel += 1
				_add_trait(assigned_person(&"Medical"), "Exhausted")
				message = "Stores rationed; +1 fuel, Medical is exhausted."
		&"salvage_survivor":
			if choice_id == &"take_aboard":
				supplies -= 15
				_unlock_recruit(&"edda_kaine")
				message = "Captain Edda Kaine entered the recruitment pool."
			else:
				intel += 2
				message = "The command archive yielded +2 intel."
	resolved_operational_event_ids.append(event_id)
	pending_operational_event.clear()
	personnel_event_log.append(message)
	return message

func _add_mutual_bond(first_id: StringName, second_id: StringName) -> void:
	var first := get_personnel(first_id)
	var second := get_personnel(second_id)
	if first != null and not first.bonds.has(second_id):
		first.bonds.append(second_id)
	if second != null and not second.bonds.has(first_id):
		second.bonds.append(first_id)

func _add_trait(person: SidebayPersonnelRecord, trait_name: String) -> void:
	if person != null and not person.traits.has(trait_name):
		person.traits.append(trait_name)

func _unlock_recruit(personnel_id: StringName) -> void:
	for candidate in recruitment_pool:
		if candidate.personnel_id == personnel_id:
			candidate.recruitment_unlocked = true
			return

func get_personnel(personnel_id: StringName) -> SidebayPersonnelRecord:
	for person in personnel_roster:
		if person.personnel_id == personnel_id:
			return person
	return null

func department_members(department: StringName) -> Array[SidebayPersonnelRecord]:
	var result: Array[SidebayPersonnelRecord] = []
	for person in personnel_roster:
		if person.department == department:
			result.append(person)
	return result

func assigned_person(department: StringName) -> SidebayPersonnelRecord:
	return get_personnel(StringName(department_assignments.get(String(department), "")))

func cycle_department_assignment(department: StringName) -> SidebayPersonnelRecord:
	var available: Array[SidebayPersonnelRecord] = []
	for person in department_members(department):
		if person.is_available():
			available.append(person)
	if available.is_empty():
		department_assignments[String(department)] = ""
		return null
	var current := assigned_person(department)
	var index := available.find(current)
	var next_person := available[(index + 1) % available.size()]
	department_assignments[String(department)] = String(next_person.personnel_id)
	return next_person

func personnel_bonuses() -> Dictionary:
	var result := {}
	for department in departments():
		var person := assigned_person(department)
		result[String(department).to_lower()] = person.effective_skill() if person != null else 0
	return result

func advance_personnel_recovery() -> Array[String]:
	var events: Array[String] = []
	for person in personnel_roster:
		if person.is_alive():
			person.missions += 1
		if person.recover_step():
			events.append("%s returned to active duty." % person.display_name)
	_append_personnel_events(events)
	return events

func resolve_personnel_consequences(report: Dictionary, decision: StringName) -> Array[String]:
	var events: Array[String] = []
	var used: Array[StringName] = []
	if str(report.get("outcome", "")) == "carrier_lost":
		for person in personnel_roster:
			if person.is_alive():
				person.mark_deceased()
		if not personnel_roster.is_empty():
			events.append("The carrier crew was lost with the flagship.")
		_repair_department_assignments()
		_append_personnel_events(events)
		return events
	for source in report.get("rescued_sources", []):
		var rescued_person := _person_for_escape_source(str(source), used)
		if rescued_person != null:
			used.append(rescued_person.personnel_id)
			rescued_person.injure("Recovery trauma", 1)
			events.append("%s was rescued with minor injuries." % rescued_person.display_name)
	var medical := assigned_person(&"Medical")
	var rescue_severity := 1 if medical != null and medical.effective_skill() >= 4 else 2
	for source in report.get("adrift_sources", []):
		var adrift_person := _person_for_escape_source(str(source), used)
		if adrift_person == null:
			continue
		used.append(adrift_person.personnel_id)
		if decision == &"rescue":
			adrift_person.injure("Severe exposure", rescue_severity)
			events.append("%s was recovered from an escape pod." % adrift_person.display_name)
		else:
			adrift_person.mark_deceased()
			events.append("%s was lost during withdrawal." % adrift_person.display_name)
	_apply_bond_consequences()
	_repair_department_assignments()
	_append_personnel_events(events)
	return events

func personnel_risk_summary(report: Dictionary) -> String:
	var used: Array[StringName] = []
	var entries: Array[String] = []
	for source in report.get("rescued_sources", []):
		var rescued_person := _person_for_escape_source(str(source), used)
		if rescued_person != null:
			used.append(rescued_person.personnel_id)
			entries.append("%s RECOVERED" % rescued_person.display_name)
	for source in report.get("adrift_sources", []):
		var adrift_person := _person_for_escape_source(str(source), used)
		if adrift_person != null:
			used.append(adrift_person.personnel_id)
			entries.append("%s ADRIFT" % adrift_person.display_name)
	return "NONE" if entries.is_empty() else " / ".join(entries)

func _person_for_escape_source(source: String, used: Array[StringName]) -> SidebayPersonnelRecord:
	var department := &"Command"
	if "interceptor" in source or "fighter" in source:
		department = &"Flight"
	elif "scout" in source or "relay" in source:
		department = &"Sensors"
	elif "frigate" in source:
		department = &"Gunnery"
	elif "convoy" in source:
		department = &"Engineering"
	var assigned := assigned_person(department)
	if assigned != null and assigned.is_available() and not used.has(assigned.personnel_id):
		return assigned
	for person in department_members(department):
		if person.is_available() and not used.has(person.personnel_id):
			return person
	return null

func _apply_bond_consequences() -> void:
	for person in personnel_roster:
		if not person.is_alive() or person.traits.has("Grieving"):
			continue
		for bond_id in person.bonds:
			var bonded := get_personnel(bond_id)
			if bonded != null and not bonded.is_alive():
				person.traits.append("Grieving")
				break

func _repair_department_assignments() -> void:
	for department in departments():
		var assigned := assigned_person(department)
		if assigned != null and assigned.is_available():
			continue
		department_assignments[String(department)] = ""
		for person in department_members(department):
			if person.is_available():
				department_assignments[String(department)] = String(person.personnel_id)
				break

func _append_personnel_events(events: Array[String]) -> void:
	for event in events:
		personnel_event_log.append(event)
	while personnel_event_log.size() > 24:
		personnel_event_log.pop_front()

func can_afford_fuel(amount: int) -> bool:
	return fuel >= amount

func spend_fuel(amount: int) -> bool:
	if not can_afford_fuel(amount):
		return false
	fuel -= amount
	return true

func spend_supplies(amount: int) -> bool:
	if supplies < amount:
		return false
	supplies -= amount
	return true

func spend_intel(amount: int) -> bool:
	if intel < amount:
		return false
	intel -= amount
	return true

func active_logistics_posture_data() -> Dictionary:
	var posture := logistics_posture_data(logistics_posture_id)
	return posture if not posture.is_empty() else logistics_posture_data(&"balanced_stores")

func select_logistics_posture(posture_id: StringName) -> String:
	var posture := logistics_posture_data(posture_id)
	if posture.is_empty():
		return "Logistics order rejected: unknown route posture."
	logistics_posture_id = posture_id
	return "%s selected. %s" % [posture.name, posture.summary]

func route_fuel_cost(base_cost: int) -> int:
	return maxi(1, base_cost + int(active_logistics_posture_data().get("fuel_adjustment", 0)))

func route_supply_cost() -> int:
	return int(active_logistics_posture_data().get("supplies_per_jump", 0))

func can_afford_route(base_fuel_cost: int) -> bool:
	return fuel >= route_fuel_cost(base_fuel_cost) and supplies >= route_supply_cost()

func spend_route_cost(base_fuel_cost: int) -> bool:
	var fuel_cost := route_fuel_cost(base_fuel_cost)
	var supply_cost := route_supply_cost()
	if fuel < fuel_cost or supplies < supply_cost:
		return false
	fuel -= fuel_cost
	supplies -= supply_cost
	return true

func adjusted_salvage_yield(base_value: int) -> int:
	return maxi(0, ceili(base_value * float(active_logistics_posture_data().get("salvage_multiplier", 1.0))))

func recover_salvage(base_value: int) -> int:
	var recovered := adjusted_salvage_yield(base_value)
	salvage_stock += recovered
	salvage_recovered += recovered
	return recovered

func can_allocate_salvage(allocation_id: StringName) -> bool:
	var allocation := salvage_allocation_data(allocation_id)
	return not allocation.is_empty() and salvage_stock >= int(allocation.salvage_cost)

func allocate_salvage(allocation_id: StringName) -> String:
	var allocation := salvage_allocation_data(allocation_id)
	if allocation.is_empty():
		return "Salvage allocation rejected: unknown fabrication order."
	var cost := int(allocation.salvage_cost)
	if salvage_stock < cost:
		return "Salvage allocation rejected: %d salvage required." % cost
	salvage_stock -= cost
	var amount := int(allocation.yield)
	match allocation_id:
		&"supplies":
			supplies += amount
		&"fuel":
			fuel += amount
		&"requisition":
			requisition += amount
	return "%s completed: %d salvage converted into %d %s." % [allocation.name, cost, amount, String(allocation_id)]

func active_carrier_data() -> Dictionary:
	return carrier_data(active_carrier_id)

func next_carrier_offer() -> Dictionary:
	for carrier_definition in carrier_catalog():
		var carrier_id := StringName(carrier_definition.id)
		if int(carrier_definition.required_sector) <= sector_index and not acquired_carrier_ids.has(carrier_id):
			return carrier_definition
	return {}

func acquire_carrier(carrier_id: StringName) -> String:
	var carrier_definition := carrier_data(carrier_id)
	if carrier_definition.is_empty():
		return "Acquisition rejected: unknown carrier frame."
	if acquired_carrier_ids.has(carrier_id):
		return "%s is already available to the operation." % carrier_definition.name
	if int(carrier_definition.required_sector) > sector_index:
		return "Carrier yard unavailable until sector %d." % (int(carrier_definition.required_sector) + 1)
	var cost := int(carrier_definition.requisition_cost)
	if requisition < cost:
		return "Acquisition rejected: %d requisition required for %s." % [cost, carrier_definition.name]
	requisition -= cost
	acquired_carrier_ids.append(carrier_id)
	return "%s frame acquired for %d requisition." % [carrier_definition.name, cost]

func acquire_next_carrier() -> String:
	var offer := next_carrier_offer()
	if offer.is_empty():
		return "No authored carrier frame is available from this sector's yards."
	return acquire_carrier(StringName(offer.id))

func cycle_carrier() -> String:
	var available: Array[StringName] = []
	for carrier_definition in carrier_catalog():
		var carrier_id := StringName(carrier_definition.id)
		if acquired_carrier_ids.has(carrier_id):
			available.append(carrier_id)
	if available.is_empty():
		return "No carrier frame is available."
	var index := available.find(active_carrier_id)
	active_carrier_id = available[(index + 1) % available.size()]
	return "%s assigned as the operation's carrier frame." % active_carrier_data().get("name", "Carrier")

func active_hangar_complement_data() -> Dictionary:
	return hangar_complement_data(active_hangar_complement_id)

func next_hangar_complement_offer() -> Dictionary:
	for complement in hangar_complement_catalog():
		var complement_id := StringName(complement.id)
		if int(complement.required_sector) <= sector_index and not acquired_hangar_complement_ids.has(complement_id):
			return complement
	return {}

func acquire_hangar_complement(complement_id: StringName) -> String:
	var complement := hangar_complement_data(complement_id)
	if complement.is_empty():
		return "Acquisition rejected: unknown hangar complement."
	if acquired_hangar_complement_ids.has(complement_id):
		return "%s is already available." % complement.name
	if int(complement.required_sector) > sector_index:
		return "Flight-group supplier unavailable until sector %d." % (int(complement.required_sector) + 1)
	var cost := int(complement.requisition_cost)
	if requisition < cost:
		return "Acquisition rejected: %d requisition required for %s." % [cost, complement.name]
	requisition -= cost
	acquired_hangar_complement_ids.append(complement_id)
	return "%s acquired for %d requisition; select it to begin the deck refit." % [complement.name, cost]

func acquire_next_hangar_complement() -> String:
	var offer := next_hangar_complement_offer()
	if offer.is_empty():
		return "No authored air-group complement is available from this sector's suppliers."
	return acquire_hangar_complement(StringName(offer.id))

func hangar_refit_cost(complement_id: StringName) -> int:
	if complement_id == active_hangar_complement_id:
		return 0
	var craft_deficit := maximum_interceptor_craft() - interceptor_craft_count + maximum_scout_craft() - scout_craft_count
	var ammo_deficit := maximum_interceptor_ammunition() - interceptor_ammunition + maximum_scout_ammunition() - scout_ammunition
	var total := 12 + maxi(0, craft_deficit) * 12 + ceili(float(maxi(0, ammo_deficit)) / 18.0)
	if installed_modules.get("support", "") == "fleet_repair_drones":
		total = ceili(total * 0.8)
	return total

func select_hangar_complement(complement_id: StringName) -> String:
	if not acquired_hangar_complement_ids.has(complement_id):
		return "Deck refit rejected: air-group complement is not available."
	if complement_id == active_hangar_complement_id:
		return "%s is already deployed." % active_hangar_complement_data().get("name", "Air group")
	var cost := hangar_refit_cost(complement_id)
	if not spend_supplies(cost):
		return "Deck refit rejected: %d supplies required." % cost
	active_hangar_complement_id = complement_id
	interceptor_craft_count = maximum_interceptor_craft()
	scout_craft_count = maximum_scout_craft()
	interceptor_ammunition = maximum_interceptor_ammunition()
	scout_ammunition = maximum_scout_ammunition()
	return "%s deployed after a %d-supply deck refit." % [active_hangar_complement_data().get("name", "Air group"), cost]

func cycle_hangar_complement() -> String:
	var available: Array[StringName] = []
	for complement in hangar_complement_catalog():
		var complement_id := StringName(complement.id)
		if acquired_hangar_complement_ids.has(complement_id):
			available.append(complement_id)
	if available.is_empty():
		return "No air-group complement is available."
	var index := available.find(active_hangar_complement_id)
	return select_hangar_complement(available[(index + 1) % available.size()])

func active_escort_data() -> Dictionary:
	return escort_data(active_escort_id) if escort_active else {}

func next_escort_offer() -> Dictionary:
	for escort_definition in escort_catalog():
		var escort_id := StringName(escort_definition.id)
		if int(escort_definition.required_sector) <= sector_index and not acquired_escort_ids.has(escort_id) and not lost_escort_ids.has(escort_id):
			return escort_definition
	return {}

func acquire_escort(escort_id: StringName) -> String:
	var escort_definition := escort_data(escort_id)
	if escort_definition.is_empty():
		return "Acquisition rejected: unknown escort hull."
	if acquired_escort_ids.has(escort_id):
		return "%s is already attached to the task force." % escort_definition.name
	if lost_escort_ids.has(escort_id):
		return "%s was lost and cannot be replaced by a duplicate hull." % escort_definition.name
	if int(escort_definition.required_sector) > sector_index:
		return "Supplier unavailable until sector %d." % (int(escort_definition.required_sector) + 1)
	var cost := int(escort_definition.requisition_cost)
	if requisition < cost:
		return "Acquisition rejected: %d requisition required for %s." % [cost, escort_definition.name]
	requisition -= cost
	acquired_escort_ids.append(escort_id)
	if active_escort_id == &"" or not escort_active:
		active_escort_id = escort_id
		escort_active = true
	return "%s acquired for %d requisition." % [escort_definition.name, cost]

func acquire_next_escort() -> String:
	var offer := next_escort_offer()
	if offer.is_empty():
		return "No authored escort hulls are available from this sector's suppliers."
	return acquire_escort(StringName(offer.id))

func deploy_escort(escort_id: StringName) -> String:
	if not acquired_escort_ids.has(escort_id) or lost_escort_ids.has(escort_id):
		return "Deployment rejected: escort is not available."
	active_escort_id = escort_id
	escort_active = true
	return "%s assigned as the active escort." % escort_data(escort_id).get("name", "Escort")

func cycle_escort() -> String:
	var available: Array[StringName] = []
	for escort_definition in escort_catalog():
		var escort_id := StringName(escort_definition.id)
		if acquired_escort_ids.has(escort_id) and not lost_escort_ids.has(escort_id):
			available.append(escort_id)
	if available.is_empty():
		return "No operational escort hull is available."
	var index := available.find(active_escort_id)
	return deploy_escort(available[(index + 1) % available.size()])

func lose_active_escort() -> void:
	if active_escort_id != &"" and not lost_escort_ids.has(active_escort_id):
		lost_escort_ids.append(active_escort_id)
	acquired_escort_ids.erase(active_escort_id)
	active_escort_id = &""
	escort_active = false

func maximum_interceptor_craft() -> int:
	return int(active_hangar_complement_data().get("interceptor_craft", MAX_INTERCEPTOR_CRAFT))

func maximum_scout_craft() -> int:
	return int(active_hangar_complement_data().get("scout_craft", MAX_SCOUT_CRAFT))

func maximum_interceptor_ammunition() -> int:
	var per_craft := int(active_hangar_complement_data().get("interceptor_ammo_per_craft", BASE_INTERCEPTOR_AMMO / MAX_INTERCEPTOR_CRAFT))
	return int(round(maximum_interceptor_craft() * per_craft * (1.25 if installed_modules.get("hangar", "") == "expanded_magazines" else 1.0)))

func maximum_scout_ammunition() -> int:
	var per_craft := int(active_hangar_complement_data().get("scout_ammo_per_craft", BASE_SCOUT_AMMO / MAX_SCOUT_CRAFT))
	return int(round(maximum_scout_craft() * per_craft * (1.25 if installed_modules.get("hangar", "") == "expanded_magazines" else 1.0)))

func fleet_snapshot() -> Dictionary:
	return {
		"carrier_shields": carrier_shields,
		"carrier_armor": carrier_armor,
		"carrier_hull": carrier_hull,
		"interceptor_craft_count": interceptor_craft_count,
		"interceptor_ammunition": interceptor_ammunition,
		"scout_craft_count": scout_craft_count,
		"scout_ammunition": scout_ammunition,
		"active_carrier_id": String(active_carrier_id),
		"acquired_carrier_ids": acquired_carrier_ids.map(func(value: StringName) -> String: return String(value)),
		"active_hangar_complement_id": String(active_hangar_complement_id),
		"acquired_hangar_complement_ids": acquired_hangar_complement_ids.map(func(value: StringName) -> String: return String(value)),
		"escort_active": escort_active,
		"active_escort_id": String(active_escort_id),
		"acquired_escort_ids": acquired_escort_ids.map(func(value: StringName) -> String: return String(value)),
		"lost_escort_ids": lost_escort_ids.map(func(value: StringName) -> String: return String(value)),
		"installed_modules": installed_modules.duplicate(true),
		"personnel_bonuses": personnel_bonuses()
	}

func apply_battle_report(report: Dictionary) -> void:
	carrier_shields = clampf(float(report.get("carrier_shields", carrier_shields)), 0.0, 1.0)
	carrier_armor = clampf(float(report.get("carrier_armor", carrier_armor)), 0.0, 1.0)
	carrier_hull = clampf(float(report.get("carrier_hull", carrier_hull)), 0.0, 1.0)
	interceptor_craft_count = clampi(int(report.get("interceptor_craft_count", interceptor_craft_count)), 0, maximum_interceptor_craft())
	interceptor_ammunition = clampi(int(report.get("interceptor_ammunition", interceptor_ammunition)), 0, maximum_interceptor_ammunition())
	scout_craft_count = clampi(int(report.get("scout_craft_count", scout_craft_count)), 0, maximum_scout_craft())
	scout_ammunition = clampi(int(report.get("scout_ammunition", scout_ammunition)), 0, maximum_scout_ammunition())
	escort_active = bool(report.get("escort_active", escort_active))
	if not escort_active and not bool(report.get("escort_straggler", false)):
		lose_active_escort()

func service_cost() -> int:
	var damage_cost := ceili((1.0 - carrier_shields) * 12.0 + (1.0 - carrier_armor) * 18.0 + (1.0 - carrier_hull) * 30.0)
	var craft_cost := (maximum_interceptor_craft() - interceptor_craft_count + maximum_scout_craft() - scout_craft_count) * 12
	var ammo_missing := maximum_interceptor_ammunition() - interceptor_ammunition + maximum_scout_ammunition() - scout_ammunition
	var ammo_cost := ceili(float(ammo_missing) / 18.0)
	var total := damage_cost + craft_cost + ammo_cost
	if installed_modules.get("support", "") == "fleet_repair_drones":
		total = ceili(total * 0.8)
	return maxi(0, total)

func service_fleet() -> bool:
	var cost := service_cost()
	if cost == 0:
		return true
	if not spend_supplies(cost):
		return false
	carrier_shields = 1.0
	carrier_armor = 1.0
	carrier_hull = 1.0
	interceptor_craft_count = maximum_interceptor_craft()
	interceptor_ammunition = maximum_interceptor_ammunition()
	scout_craft_count = maximum_scout_craft()
	scout_ammunition = maximum_scout_ammunition()
	return true

func cycle_module(slot: String) -> StringName:
	var choices: Array[StringName] = []
	for module in module_catalog():
		if module.slot == slot and unlocked_module_ids.has(module.id):
			choices.append(module.id)
	if choices.is_empty():
		return &""
	var current := StringName(installed_modules.get(slot, ""))
	var index := choices.find(current)
	var next_id := choices[(index + 1) % choices.size()]
	installed_modules[slot] = String(next_id)
	interceptor_ammunition = mini(interceptor_ammunition, maximum_interceptor_ammunition())
	scout_ammunition = mini(scout_ammunition, maximum_scout_ammunition())
	return next_id

func unlock_next_module() -> StringName:
	for module in module_catalog():
		if not unlocked_module_ids.has(module.id):
			unlocked_module_ids.append(module.id)
			return module.id
	return &""

func mark_completed(node_id: StringName, node_sector: int) -> void:
	if not completed_node_ids.has(node_id):
		completed_node_ids.append(node_id)
	current_node_id = node_id
	sector_index = maxi(sector_index, node_sector)

func reveal(node_id: StringName) -> void:
	if not revealed_node_ids.has(node_id):
		revealed_node_ids.append(node_id)

func to_dictionary() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"run_id": run_id,
		"seed": seed,
		"sector_index": sector_index,
		"current_node_id": String(current_node_id),
		"supplies": supplies,
		"fuel": fuel,
		"intel": intel,
		"requisition": requisition,
		"completed_node_ids": completed_node_ids.map(func(value: StringName) -> String: return String(value)),
		"revealed_node_ids": revealed_node_ids.map(func(value: StringName) -> String: return String(value)),
		"battles_won": battles_won,
		"withdrawals": withdrawals,
		"objectives_completed": objectives_completed,
		"objectives_failed": objectives_failed,
		"personnel_rescued": personnel_rescued,
		"personnel_lost": personnel_lost,
		"straggler_craft_recovered": straggler_craft_recovered,
		"salvage_recovered": salvage_recovered,
		"salvage_stock": salvage_stock,
		"logistics_posture_id": String(logistics_posture_id),
		"run_completed": run_completed,
		"run_failed": run_failed,
		"fleet": fleet_snapshot(),
		"unlocked_module_ids": unlocked_module_ids.map(func(value: StringName) -> String: return String(value)),
		"personnel_roster": personnel_roster.map(func(person: SidebayPersonnelRecord) -> Dictionary: return person.to_dictionary()),
		"department_assignments": department_assignments.duplicate(true),
		"personnel_event_log": personnel_event_log.duplicate(),
		"recruitment_pool": recruitment_pool.map(func(person: SidebayPersonnelRecord) -> Dictionary: return person.to_dictionary()),
		"pending_operational_event": pending_operational_event.duplicate(true),
		"resolved_operational_event_ids": resolved_operational_event_ids.map(func(value: StringName) -> String: return String(value))
	}

static func from_dictionary(data: Dictionary) -> SidebayRunState:
	var version := int(data.get("save_version", -1))
	if version < 1 or version > SAVE_VERSION:
		return null
	var state := SidebayRunState.new()
	state.run_id = str(data.get("run_id", ""))
	state.seed = int(data.get("seed", 0))
	state.sector_index = int(data.get("sector_index", 0))
	state.current_node_id = StringName(data.get("current_node_id", ""))
	state.supplies = int(data.get("supplies", 100))
	state.fuel = int(data.get("fuel", 10))
	state.intel = int(data.get("intel", 2))
	state.requisition = int(data.get("requisition", 1))
	for value in data.get("completed_node_ids", []):
		state.completed_node_ids.append(StringName(value))
	for value in data.get("revealed_node_ids", []):
		state.revealed_node_ids.append(StringName(value))
	state.battles_won = int(data.get("battles_won", 0))
	state.withdrawals = int(data.get("withdrawals", 0))
	state.objectives_completed = int(data.get("objectives_completed", 0))
	state.objectives_failed = int(data.get("objectives_failed", 0))
	state.personnel_rescued = int(data.get("personnel_rescued", 0))
	state.personnel_lost = int(data.get("personnel_lost", 0))
	state.straggler_craft_recovered = int(data.get("straggler_craft_recovered", 0))
	state.salvage_recovered = int(data.get("salvage_recovered", 0))
	if version >= 9:
		state.salvage_stock = maxi(0, int(data.get("salvage_stock", 0)))
		state.logistics_posture_id = StringName(data.get("logistics_posture_id", "balanced_stores"))
		if logistics_posture_data(state.logistics_posture_id).is_empty():
			state.logistics_posture_id = &"balanced_stores"
	state.run_completed = bool(data.get("run_completed", false))
	state.run_failed = bool(data.get("run_failed", false))
	if version >= 2:
		var fleet: Dictionary = data.get("fleet", {})
		if version >= 8:
			state.active_carrier_id = StringName(fleet.get("active_carrier_id", "cvn_sidebay"))
			state.acquired_carrier_ids.clear()
			for carrier_id in fleet.get("acquired_carrier_ids", []):
				state.acquired_carrier_ids.append(StringName(carrier_id))
			if state.acquired_carrier_ids.is_empty():
				state.acquired_carrier_ids.append(&"cvn_sidebay")
			state.active_hangar_complement_id = StringName(fleet.get("active_hangar_complement_id", "balanced_wings"))
			state.acquired_hangar_complement_ids.clear()
			for complement_id in fleet.get("acquired_hangar_complement_ids", []):
				state.acquired_hangar_complement_ids.append(StringName(complement_id))
			if state.acquired_hangar_complement_ids.is_empty():
				state.acquired_hangar_complement_ids.append(&"balanced_wings")
		state.carrier_shields = clampf(float(fleet.get("carrier_shields", 1.0)), 0.0, 1.0)
		state.carrier_armor = clampf(float(fleet.get("carrier_armor", 1.0)), 0.0, 1.0)
		state.carrier_hull = clampf(float(fleet.get("carrier_hull", 1.0)), 0.0, 1.0)
		state.interceptor_craft_count = clampi(int(fleet.get("interceptor_craft_count", state.maximum_interceptor_craft())), 0, state.maximum_interceptor_craft())
		state.scout_craft_count = clampi(int(fleet.get("scout_craft_count", state.maximum_scout_craft())), 0, state.maximum_scout_craft())
		state.escort_active = bool(fleet.get("escort_active", true))
		state.installed_modules = fleet.get("installed_modules", state.installed_modules).duplicate(true)
		state.interceptor_ammunition = clampi(int(fleet.get("interceptor_ammunition", BASE_INTERCEPTOR_AMMO)), 0, state.maximum_interceptor_ammunition())
		state.scout_ammunition = clampi(int(fleet.get("scout_ammunition", BASE_SCOUT_AMMO)), 0, state.maximum_scout_ammunition())
		state.unlocked_module_ids.clear()
		for value in data.get("unlocked_module_ids", []):
			state.unlocked_module_ids.append(StringName(value))
		if state.unlocked_module_ids.is_empty():
			state.unlocked_module_ids = [&"siege_missile_cell", &"aegis_relay", &"longwatch_array", &"fleet_repair_drones", &"rapid_turnaround_deck"]
		if version >= 7:
			state.active_escort_id = StringName(fleet.get("active_escort_id", ""))
			state.acquired_escort_ids.clear()
			for escort_id in fleet.get("acquired_escort_ids", []):
				state.acquired_escort_ids.append(StringName(escort_id))
			state.lost_escort_ids.clear()
			for escort_id in fleet.get("lost_escort_ids", []):
				state.lost_escort_ids.append(StringName(escort_id))
		else:
			state.active_escort_id = &"iss_resolute" if state.escort_active else &""
			state.acquired_escort_ids.clear()
			state.lost_escort_ids.clear()
			if state.escort_active:
				state.acquired_escort_ids.append(&"iss_resolute")
			else:
				state.lost_escort_ids.append(&"iss_resolute")
	if version >= 5:
		for person_data in data.get("personnel_roster", []):
			if person_data is Dictionary:
				state.personnel_roster.append(SidebayPersonnelRecord.from_dictionary(person_data))
		state.department_assignments = data.get("department_assignments", {}).duplicate(true)
		for event in data.get("personnel_event_log", []):
			state.personnel_event_log.append(str(event))
	if state.personnel_roster.is_empty():
		state._initialize_authored_personnel()
	else:
		state._repair_department_assignments()
	if version >= 6:
		for candidate_data in data.get("recruitment_pool", []):
			if candidate_data is Dictionary:
				state.recruitment_pool.append(SidebayPersonnelRecord.from_dictionary(candidate_data))
		state.pending_operational_event = data.get("pending_operational_event", {}).duplicate(true)
		for event_id in data.get("resolved_operational_event_ids", []):
			state.resolved_operational_event_ids.append(StringName(event_id))
	if state.recruitment_pool.is_empty() and version < 6:
		state._initialize_recruitment_pool()
	return state
