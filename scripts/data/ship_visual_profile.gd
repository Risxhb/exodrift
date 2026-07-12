class_name ShipVisualProfile
extends Resource

@export var core_scale: Vector3 = Vector3(0.82, 0.72, 0.78)
@export var dorsal_scale: Vector3 = Vector3(0.52, 0.28, 0.48)
@export var shoulder_scale: Vector3 = Vector3(0.16, 0.55, 0.58)
@export var keel_scale: Vector3 = Vector3(0.38, 0.24, 0.52)
@export var bow_scale: Vector3 = Vector3(0.72, 0.7, 0.3)
@export var engine_scale: Vector3 = Vector3(0.16, 0.34, 0.16)
@export var engine_color: Color = Color(0.18, 0.62, 0.92)
@export var engine_emission: float = 2.4

static func for_ship(role: StringName, faction: StringName) -> ShipVisualProfile:
	var profile := ShipVisualProfile.new()
	if faction == &"hostile":
		profile.core_scale = Vector3(0.74, 0.66, 0.82)
		profile.dorsal_scale = Vector3(0.42, 0.34, 0.56)
		profile.shoulder_scale = Vector3(0.21, 0.44, 0.66)
		profile.keel_scale = Vector3(0.3, 0.3, 0.6)
		profile.bow_scale = Vector3(0.62, 0.82, 0.34)
		profile.engine_color = Color(1.0, 0.24, 0.055)
		profile.engine_emission = 3.0
	if role == &"corvette":
		profile.core_scale.z = 0.68
		profile.shoulder_scale.x = 0.25
		profile.bow_scale.z = 0.4
	elif role in [&"frigate", &"command"]:
		profile.dorsal_scale.y = 0.36
		profile.keel_scale.z = 0.6
	return profile
