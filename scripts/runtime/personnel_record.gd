class_name SidebayPersonnelRecord
extends RefCounted

enum Status { ACTIVE, INJURED, MISSING, DECEASED }

var personnel_id: StringName = &"personnel"
var display_name: String = "Crew Member"
var rank: String = "Specialist"
var department: StringName = &"Command"
var role: String = "Crew"
var skill: int = 3
var traits: Array[String] = []
var bonds: Array[StringName] = []
var status: Status = Status.ACTIVE
var injury: String = ""
var injury_severity: int = 0
var missions: int = 0
var promotion_count: int = 0
var recruitment_cost: int = 0
var rare_recruit: bool = false
var recruitment_unlocked: bool = true

static func create(
	id: StringName,
	name_value: String,
	rank_value: String,
	department_value: StringName,
	role_value: String,
	skill_value: int,
	trait_values: Array[String],
	bond_values: Array[StringName]
) -> SidebayPersonnelRecord:
	var record := SidebayPersonnelRecord.new()
	record.personnel_id = id
	record.display_name = name_value
	record.rank = rank_value
	record.department = department_value
	record.role = role_value
	record.skill = clampi(skill_value, 1, 5)
	record.traits = trait_values.duplicate()
	record.bonds = bond_values.duplicate()
	return record

func is_available() -> bool:
	return status == Status.ACTIVE

func is_alive() -> bool:
	return status != Status.DECEASED

func effective_skill() -> int:
	var penalty := 1 if traits.has("Grieving") else 0
	return maxi(0, skill - penalty) if is_available() else 0

func injure(description: String, severity: int) -> void:
	if not is_alive():
		return
	status = Status.INJURED
	injury = description
	injury_severity = clampi(severity, 1, 3)

func recover_step() -> bool:
	if status != Status.INJURED:
		return false
	injury_severity = maxi(0, injury_severity - 1)
	if injury_severity == 0:
		status = Status.ACTIVE
		injury = ""
		return true
	return false

func mark_deceased() -> void:
	status = Status.DECEASED
	injury = "Killed in action"
	injury_severity = 0

func status_label() -> String:
	match status:
		Status.INJURED:
			return "INJURED (%d) — %s" % [injury_severity, injury]
		Status.MISSING:
			return "MISSING"
		Status.DECEASED:
			return "KILLED IN ACTION"
		_:
			return "ACTIVE"

func to_dictionary() -> Dictionary:
	return {
		"personnel_id": String(personnel_id),
		"display_name": display_name,
		"rank": rank,
		"department": String(department),
		"role": role,
		"skill": skill,
		"traits": traits.duplicate(),
		"bonds": bonds.map(func(value: StringName) -> String: return String(value)),
		"status": status,
		"injury": injury,
		"injury_severity": injury_severity,
		"missions": missions,
		"promotion_count": promotion_count,
		"recruitment_cost": recruitment_cost,
		"rare_recruit": rare_recruit,
		"recruitment_unlocked": recruitment_unlocked
	}

static func from_dictionary(data: Dictionary) -> SidebayPersonnelRecord:
	var record := SidebayPersonnelRecord.new()
	record.personnel_id = StringName(data.get("personnel_id", "personnel"))
	record.display_name = str(data.get("display_name", "Crew Member"))
	record.rank = str(data.get("rank", "Specialist"))
	record.department = StringName(data.get("department", "Command"))
	record.role = str(data.get("role", "Crew"))
	record.skill = clampi(int(data.get("skill", 3)), 1, 5)
	for value in data.get("traits", []):
		record.traits.append(str(value))
	for value in data.get("bonds", []):
		record.bonds.append(StringName(value))
	record.status = clampi(int(data.get("status", Status.ACTIVE)), Status.ACTIVE, Status.DECEASED) as Status
	record.injury = str(data.get("injury", ""))
	record.injury_severity = clampi(int(data.get("injury_severity", 0)), 0, 3)
	record.missions = maxi(0, int(data.get("missions", 0)))
	record.promotion_count = maxi(0, int(data.get("promotion_count", 0)))
	record.recruitment_cost = maxi(0, int(data.get("recruitment_cost", 0)))
	record.rare_recruit = bool(data.get("rare_recruit", false))
	record.recruitment_unlocked = bool(data.get("recruitment_unlocked", true))
	return record
