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
@export var hull_texture_path: String = "res://assets/textures/navy_refit_hull.svg"
@export var accent_color: Color = Color(0.58, 0.78, 0.9)
@export var bridge_color: Color = Color(0.12, 0.72, 1.0)
@export var marking_color: Color = Color(0.86, 0.93, 0.94)
@export var faction_style: StringName = &"navy"
@export var armor_rib_count: int = 4
@export var turret_count: int = 2
@export var fin_scale: float = 0.0
@export_range(0.0, 1.0) var surface_metallic: float = 0.52
@export_range(0.0, 1.0) var surface_roughness: float = 0.44
@export_range(0.0, 0.6) var albedo_lift: float = 0.46
@export var texture_scale: float = 3.2
@export_range(0.0, 1.0) var wear_level: float = 0.24
@export_range(0.3, 1.0) var core_fore_taper: float = 0.68
@export_range(0.3, 1.0) var core_aft_taper: float = 0.94
@export_range(0.3, 1.0) var dorsal_fore_taper: float = 0.52
@export_range(0.3, 1.0) var dorsal_aft_taper: float = 0.86
@export_range(0.0, 1.0) var rim_strength: float = 0.18
@export_file("*.tres", "*.res") var visual_asset_path: String = ""

func resolved_visual_asset_path() -> String:
	if not visual_asset_path.is_empty():
		return visual_asset_path
	return "res://assets/ships/%s/%s_visual_asset.tres" % [String(faction_style), String(faction_style)]

func load_visual_asset() -> ShipVisualAsset:
	var path := resolved_visual_asset_path()
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as ShipVisualAsset

static func for_ship(role: StringName, faction: StringName, identity: StringName = &"") -> ShipVisualProfile:
	var profile := ShipVisualProfile.new()
	if identity != &"":
		profile.visual_asset_path = "res://assets/ships/%s/%s_visual_asset.tres" % [String(identity), String(identity)]
	if faction == &"hostile":
		profile.faction_style = &"acheron"
		profile.hull_texture_path = "res://assets/textures/acheron_forged_hull.svg"
		profile.core_scale = Vector3(0.74, 0.66, 0.82)
		profile.dorsal_scale = Vector3(0.42, 0.34, 0.56)
		profile.shoulder_scale = Vector3(0.21, 0.44, 0.66)
		profile.keel_scale = Vector3(0.3, 0.3, 0.6)
		profile.bow_scale = Vector3(0.62, 0.82, 0.34)
		profile.engine_color = Color(1.0, 0.24, 0.055)
		profile.engine_emission = 3.0
		profile.accent_color = Color(0.92, 0.34, 0.08)
		profile.bridge_color = Color(1.0, 0.18, 0.04)
		profile.marking_color = Color(1.0, 0.62, 0.16)
		profile.armor_rib_count = 5
		profile.fin_scale = 0.34
		profile.surface_metallic = 0.46
		profile.surface_roughness = 0.68
		profile.albedo_lift = 0.36
		profile.texture_scale = 2.55
		profile.wear_level = 0.72
		profile.core_fore_taper = 0.58
		profile.core_aft_taper = 0.96
		profile.dorsal_fore_taper = 0.46
		profile.dorsal_aft_taper = 0.82
		profile.rim_strength = 0.12
	var identity_text := String(identity)
	if identity_text.begins_with("vesper_"):
		profile.faction_style = &"vesper"
		profile.hull_texture_path = "res://assets/textures/vesper_phase_hull.svg"
		profile.core_scale = Vector3(0.64, 0.62, 0.92)
		profile.dorsal_scale = Vector3(0.3, 0.3, 0.68)
		profile.shoulder_scale = Vector3(0.18, 0.36, 0.74)
		profile.keel_scale = Vector3(0.2, 0.27, 0.7)
		profile.bow_scale = Vector3(0.42, 0.76, 0.48)
		profile.engine_color = Color(0.96, 0.18, 1.0)
		profile.engine_emission = 3.6
		profile.accent_color = Color(0.95, 0.24, 1.0)
		profile.bridge_color = Color(1.0, 0.52, 1.0)
		profile.marking_color = Color(0.38, 0.95, 1.0)
		profile.armor_rib_count = 3
		profile.fin_scale = 0.76
		profile.surface_metallic = 0.68
		profile.surface_roughness = 0.3
		profile.albedo_lift = 0.4
		profile.texture_scale = 3.8
		profile.wear_level = 0.08
		profile.core_fore_taper = 0.4
		profile.core_aft_taper = 0.78
		profile.dorsal_fore_taper = 0.34
		profile.dorsal_aft_taper = 0.7
		profile.rim_strength = 0.26
	elif identity_text.begins_with("vanta_") or identity_text.begins_with("crucible_"):
		profile.faction_style = &"crucible"
		profile.hull_texture_path = "res://assets/textures/crucible_basalt_hull.svg"
		profile.core_scale = Vector3(0.68, 0.74, 0.86)
		profile.dorsal_scale = Vector3(0.32, 0.48, 0.62)
		profile.shoulder_scale = Vector3(0.28, 0.32, 0.72)
		profile.keel_scale = Vector3(0.22, 0.4, 0.64)
		profile.bow_scale = Vector3(0.48, 0.92, 0.42)
		profile.engine_color = Color(0.62, 0.18, 1.0)
		profile.engine_emission = 3.4
		profile.accent_color = Color(0.64, 0.28, 0.92)
		profile.bridge_color = Color(0.82, 0.28, 1.0)
		profile.marking_color = Color(0.82, 0.56, 1.0)
		profile.armor_rib_count = 6
		profile.fin_scale = 0.62
		profile.surface_metallic = 0.58
		profile.surface_roughness = 0.52
		profile.albedo_lift = 0.34
		profile.texture_scale = 2.8
		profile.wear_level = 0.38
		profile.core_fore_taper = 0.72
		profile.core_aft_taper = 0.98
		profile.dorsal_fore_taper = 0.56
		profile.dorsal_aft_taper = 0.92
		profile.rim_strength = 0.2
	var role_text := String(role)
	if role_text.contains("corvette"):
		profile.core_scale.z = 0.68
		profile.core_fore_taper *= 0.82
		profile.shoulder_scale.x = 0.25
		profile.bow_scale.z = 0.4
		profile.turret_count = 1
	elif role_text in ["frigate", "command"]:
		profile.dorsal_scale.y = 0.36
		profile.keel_scale.z = 0.6
		profile.core_fore_taper *= 0.9
		profile.turret_count = 3 if role == &"command" else 2
	elif role_text.contains("destroyer") or role_text.contains("cruiser"):
		profile.core_scale = Vector3(profile.core_scale.x * 1.05, profile.core_scale.y, profile.core_scale.z)
		profile.dorsal_scale = Vector3(profile.dorsal_scale.x * 1.08, profile.dorsal_scale.y * 1.2, profile.dorsal_scale.z)
		profile.shoulder_scale.x *= 1.18
		profile.turret_count = 4 if role_text.contains("cruiser") else 3
		profile.armor_rib_count += 2
		profile.core_aft_taper = minf(1.0, profile.core_aft_taper * 1.04)
	match identity:
		&"cvn_sidebay":
			profile.hull_texture_path = "res://assets/textures/sidebay_gunmetal_hull.svg"
			profile.core_scale = Vector3(0.76, 0.72, 0.82)
			profile.dorsal_scale = Vector3(0.54, 0.3, 0.58)
			profile.shoulder_scale = Vector3(0.2, 0.58, 0.62)
			profile.bow_scale = Vector3(0.66, 0.7, 0.34)
			profile.marking_color = Color(0.86, 0.96, 0.98)
			profile.accent_color = Color(0.18, 0.76, 0.9)
			profile.surface_metallic = 0.72
			profile.surface_roughness = 0.36
			profile.albedo_lift = 0.22
			profile.texture_scale = 3.6
			profile.wear_level = 0.32
			profile.rim_strength = 0.22
			profile.armor_rib_count = 8
			profile.turret_count = 4
		&"cvn_vanguard":
			profile.core_scale = Vector3(0.74, 0.64, 0.86)
			profile.bow_scale = Vector3(0.6, 0.58, 0.46)
			profile.accent_color = Color(0.93, 0.44, 0.2)
			profile.marking_color = Color(1.0, 0.78, 0.52)
			profile.surface_roughness = 0.28
			profile.turret_count = 5
		&"cvn_citadel":
			profile.core_scale = Vector3(0.92, 0.82, 0.82)
			profile.shoulder_scale = Vector3(0.24, 0.72, 0.7)
			profile.accent_color = Color(0.5, 0.68, 0.78)
			profile.marking_color = Color(0.84, 0.9, 0.92)
			profile.surface_roughness = 0.48
			profile.armor_rib_count = 8
		&"iss_resolute":
			profile.core_scale = Vector3(0.88, 0.6, 0.88)
			profile.dorsal_scale = Vector3(0.58, 0.24, 0.54)
			profile.shoulder_scale = Vector3(0.18, 0.46, 0.7)
			profile.keel_scale = Vector3(0.34, 0.22, 0.68)
			profile.bow_scale = Vector3(0.76, 0.56, 0.38)
			profile.accent_color = Color(0.2, 0.78, 0.96)
			profile.marking_color = Color(0.9, 0.95, 0.96)
			profile.core_fore_taper = 0.6
			profile.core_aft_taper = 0.98
			profile.dorsal_fore_taper = 0.48
			profile.dorsal_aft_taper = 0.92
			profile.armor_rib_count = 5
			profile.turret_count = 0
		&"iss_harrier":
			profile.core_scale = Vector3(0.66, 0.58, 0.9)
			profile.accent_color = Color(0.98, 0.48, 0.16)
			profile.marking_color = Color(1.0, 0.82, 0.52)
			profile.texture_scale = 4.2
			profile.surface_roughness = 0.28
		&"iss_bulwark":
			profile.core_scale = Vector3(0.9, 0.84, 0.8)
			profile.shoulder_scale = Vector3(0.24, 0.7, 0.68)
			profile.accent_color = Color(0.46, 0.74, 0.86)
			profile.marking_color = Color(0.82, 0.9, 0.92)
			profile.surface_roughness = 0.5
			profile.armor_rib_count = 7
	return profile
