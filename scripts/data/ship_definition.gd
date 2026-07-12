class_name ShipDefinition
extends Resource

@export var ship_id: StringName = &"ship"
@export var display_name: String = "Ship"
@export_enum("carrier", "frigate", "corvette", "fighter", "drone") var role: String = "frigate"
@export var dimensions_m: Vector3 = Vector3(20.0, 10.0, 60.0)
@export var acceleration_mps2: float = 35.0
@export var maximum_speed_mps: float = 250.0
@export var rotation_speed_radians: float = 0.8
@export var signature: float = 1.0
@export var passive_sensor_range_m: float = 8000.0
@export var active_sensor_range_m: float = 12000.0
@export var command_range_m: float = 7000.0
@export var damage_layers: DamageLayerDefinition
@export var weapons: Array[WeaponDefinition] = []

