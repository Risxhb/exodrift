class_name WeaponDefinition
extends Resource

@export var weapon_id: StringName = &"weapon"
@export var display_name: String = "Weapon"
@export_enum("flak", "missile", "cannon") var role: String = "cannon"
@export var range_m: float = 1500.0
@export var cooldown_seconds: float = 1.0
@export var damage: float = 10.0
@export var projectile_speed_mps: float = 500.0
@export var requires_identified_lock: bool = false
@export var tracks_target: bool = false
@export var can_intercept_projectiles: bool = false

