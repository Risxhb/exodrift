class_name SquadronDefinition
extends Resource

@export var squadron_id: StringName = &"squadron"
@export var display_name: String = "Squadron"
@export_enum("interceptor", "scout", "bomber", "support") var role: String = "interceptor"
@export var craft_count: int = 4
@export var endurance_seconds: float = 120.0
@export var ammunition_per_craft: int = 30
@export var launch_interval_seconds: float = 0.65
@export var recovery_interval_seconds: float = 0.8
@export var service_seconds: float = 6.0
@export_enum("aggressive", "balanced", "defensive", "evade_return") var default_stance: String = "balanced"
@export var craft_definition: ShipDefinition

