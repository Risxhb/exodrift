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
@export var hull_texture_path: String = "res://assets/textures/navy_hull.svg"
@export var accent_color: Color = Color(0.58, 0.78, 0.9)
@export var bridge_color: Color = Color(0.12, 0.72, 1.0)
@export var faction_style: StringName = &"navy"
@export var armor_rib_count: int = 4
@export var turret_count: int = 2
@export var fin_scale: float = 0.0

static func for_ship(role: StringName, faction: StringName, identity: StringName = &"") -> ShipVisualProfile:
	var profile := ShipVisualProfile.new()
	if faction == &"hostile":
		profile.faction_style = &"raider"
		profile.hull_texture_path = "res://assets/textures/raider_hull.svg"
		profile.core_scale = Vector3(0.74, 0.66, 0.82)
		profile.dorsal_scale = Vector3(0.42, 0.34, 0.56)
		profile.shoulder_scale = Vector3(0.21, 0.44, 0.66)
		profile.keel_scale = Vector3(0.3, 0.3, 0.6)
		profile.bow_scale = Vector3(0.62, 0.82, 0.34)
		profile.engine_color = Color(1.0, 0.24, 0.055)
		profile.engine_emission = 3.0
		profile.accent_color = Color(0.92, 0.34, 0.08)
		profile.bridge_color = Color(1.0, 0.18, 0.04)
		profile.armor_rib_count = 5
		profile.fin_scale = 0.34
	if String(identity).begins_with("vanta_") or String(identity).begins_with("crucible_"):
		profile.faction_style = &"vanta"
		profile.hull_texture_path = "res://assets/textures/vanta_hull.svg"
		profile.core_scale = Vector3(0.68, 0.74, 0.86)
		profile.dorsal_scale = Vector3(0.32, 0.48, 0.62)
		profile.shoulder_scale = Vector3(0.28, 0.32, 0.72)
		profile.keel_scale = Vector3(0.22, 0.4, 0.64)
		profile.bow_scale = Vector3(0.48, 0.92, 0.42)
		profile.engine_color = Color(0.62, 0.18, 1.0)
		profile.engine_emission = 3.4
		profile.accent_color = Color(0.64, 0.28, 0.92)
		profile.bridge_color = Color(0.82, 0.28, 1.0)
		profile.armor_rib_count = 6
		profile.fin_scale = 0.62
	var role_text := String(role)
	if role_text.contains("corvette"):
		profile.core_scale.z = 0.68
		profile.shoulder_scale.x = 0.25
		profile.bow_scale.z = 0.4
		profile.turret_count = 1
	elif role_text in ["frigate", "command"]:
		profile.dorsal_scale.y = 0.36
		profile.keel_scale.z = 0.6
		profile.turret_count = 3 if role == &"command" else 2
	elif role_text.contains("destroyer") or role_text.contains("cruiser"):
		profile.core_scale = Vector3(profile.core_scale.x * 1.05, profile.core_scale.y, profile.core_scale.z)
		profile.dorsal_scale = Vector3(profile.dorsal_scale.x * 1.08, profile.dorsal_scale.y * 1.2, profile.dorsal_scale.z)
		profile.shoulder_scale.x *= 1.18
		profile.turret_count = 4 if role_text.contains("cruiser") else 3
		profile.armor_rib_count += 2
	return profile
