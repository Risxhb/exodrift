class_name DamageState
extends RefCounted

signal destroyed

var definition: DamageLayerDefinition
var shields: float
var armor: float
var hull: float
var shield_regen_delay: float = 0.0

func _init(source: DamageLayerDefinition = null) -> void:
	definition = source if source != null else DamageLayerDefinition.new()
	shields = definition.max_shields
	armor = definition.max_armor
	hull = definition.max_hull

func apply_damage(amount: float) -> Dictionary:
	var remaining := maxf(0.0, amount)
	var result := {"shields": 0.0, "armor": 0.0, "hull": 0.0}
	shield_regen_delay = 4.0
	if shields > 0.0:
		var absorbed := minf(shields, remaining)
		shields -= absorbed
		remaining -= absorbed
		result.shields = absorbed
	if remaining > 0.0 and armor > 0.0:
		var mitigated := remaining * definition.armor_mitigation
		remaining -= mitigated
		var absorbed := minf(armor, remaining)
		armor -= absorbed
		remaining -= absorbed
		result.armor = absorbed
	if remaining > 0.0:
		var absorbed := minf(hull, remaining)
		hull -= absorbed
		result.hull = absorbed
		if hull <= 0.0:
			destroyed.emit()
	return result

func tick(delta: float) -> void:
	shield_regen_delay = maxf(0.0, shield_regen_delay - delta)
	if shield_regen_delay <= 0.0 and shields < definition.max_shields:
		shields = minf(definition.max_shields, shields + definition.shield_regeneration_per_second * delta)

func normalized_layers() -> Vector3:
	return Vector3(
		shields / maxf(1.0, definition.max_shields),
		armor / maxf(1.0, definition.max_armor),
		hull / maxf(1.0, definition.max_hull)
	)

