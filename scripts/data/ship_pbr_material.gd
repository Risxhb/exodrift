class_name ShipPbrMaterial
extends Resource

## Runtime-friendly PBR texture pack for authored ship surfaces.
## ORM channel convention: red = ambient occlusion, green = roughness,
## blue = metallic. This matches tools/ship_assets/build_pbr_maps.py.

@export var material_name: StringName = &"Hull"
@export var base_color_texture: Texture2D
@export var normal_texture: Texture2D
@export var orm_texture: Texture2D
@export var emission_texture: Texture2D
@export var color_tint: Color = Color.WHITE
@export_range(0.0, 1.0) var fallback_metallic: float = 0.7
@export_range(0.0, 1.0) var fallback_roughness: float = 0.42
@export_range(0.0, 8.0) var normal_scale: float = 1.0
@export var emission_color: Color = Color.WHITE
@export_range(0.0, 16.0) var emission_energy: float = 0.0
@export var uv_scale: Vector3 = Vector3.ONE
@export var use_triplanar_projection: bool = false

var _cached_material: StandardMaterial3D

func validation_errors(require_complete_pack: bool = true) -> PackedStringArray:
	var errors := PackedStringArray()
	if material_name == &"":
		errors.append("material_name is required")
	if base_color_texture == null:
		errors.append("base_color_texture is required")
	if require_complete_pack and normal_texture == null:
		errors.append("normal_texture is required for a production hull material")
	if require_complete_pack and orm_texture == null:
		errors.append("orm_texture is required for a production hull material")
	if uv_scale.x <= 0.0 or uv_scale.y <= 0.0 or uv_scale.z <= 0.0:
		errors.append("uv_scale must be positive")
	return errors

func build_material() -> StandardMaterial3D:
	if _cached_material != null:
		return _cached_material
	var material := StandardMaterial3D.new()
	material.resource_name = String(material_name)
	material.albedo_color = color_tint
	material.albedo_texture = base_color_texture
	material.metallic = fallback_metallic
	material.roughness = fallback_roughness
	material.uv1_scale = uv_scale
	material.uv1_triplanar = use_triplanar_projection
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if normal_texture != null:
		material.normal_enabled = true
		material.normal_texture = normal_texture
		material.normal_scale = normal_scale
	if orm_texture != null:
		material.ao_enabled = true
		material.ao_texture = orm_texture
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.roughness_texture = orm_texture
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.metallic_texture = orm_texture
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	if emission_texture != null or emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_texture = emission_texture
		material.emission_energy_multiplier = emission_energy
	_cached_material = material
	return material

func invalidate_cache() -> void:
	_cached_material = null
