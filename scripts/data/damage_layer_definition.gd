class_name DamageLayerDefinition
extends Resource

@export var max_shields: float = 100.0
@export var max_armor: float = 100.0
@export var max_hull: float = 100.0
@export var shield_regeneration_per_second: float = 2.0
@export_range(0.0, 0.95) var armor_mitigation: float = 0.2

func duplicate_definition() -> DamageLayerDefinition:
	var copy := DamageLayerDefinition.new()
	copy.max_shields = max_shields
	copy.max_armor = max_armor
	copy.max_hull = max_hull
	copy.shield_regeneration_per_second = shield_regeneration_per_second
	copy.armor_mitigation = armor_mitigation
	return copy

