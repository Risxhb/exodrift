class_name ExodriftSpaceSky
extends RefCounted

const SKY_SHADER_SOURCE := """
shader_type sky;
render_mode use_debanding;

uniform vec3 void_color : source_color = vec3(0.0015, 0.0025, 0.006);
uniform vec3 galaxy_color : source_color = vec3(0.20, 0.24, 0.34);
uniform vec3 nebula_color : source_color = vec3(0.20, 0.09, 0.24);
uniform vec3 dust_color : source_color = vec3(0.05, 0.028, 0.024);
uniform vec3 star_color : source_color = vec3(0.82, 0.9, 1.0);
uniform vec3 galaxy_axis = vec3(0.18, 0.86, 0.47);
uniform float galaxy_strength = 0.7;
uniform float star_strength = 1.0;
uniform float sky_seed = 0.0;
uniform sampler2D panorama_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float panorama_strength = 0.28;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32 + sky_seed);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float galaxy_noise(vec2 p) {
	float total = value_noise(p) * 0.56;
	total += value_noise(p * 2.07 + vec2(7.1, 3.7)) * 0.29;
	total += value_noise(p * 4.13 + vec2(2.4, 9.2)) * 0.15;
	return total;
}

float star_layer(vec2 uv, vec2 resolution, float threshold, float radius) {
	vec2 scaled = uv * resolution;
	vec2 cell = floor(scaled);
	vec2 local = fract(scaled) - 0.5;
	float seed = hash21(cell + resolution + sky_seed);
	vec2 offset = vec2(hash21(cell + 17.3), hash21(cell + 61.7)) - 0.5;
	float point = 1.0 - smoothstep(0.0, radius, length(local - offset * 0.56));
	return point * smoothstep(threshold, 1.0, seed);
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	float longitude = atan(direction.z, direction.x) / 6.2831853 + 0.5;
	float latitude = asin(clamp(direction.y, -1.0, 1.0)) / 3.14159265 + 0.5;
	vec2 spherical_uv = vec2(longitude, latitude);
	vec3 panorama = texture(panorama_texture, vec2(fract(longitude + 0.11), latitude)).rgb;

	vec3 axis = normalize(galaxy_axis);
	float band_distance = abs(dot(direction, axis));
	float broad_band = exp(-band_distance * band_distance * 29.0);
	float bright_core = exp(-band_distance * band_distance * 112.0);
	vec2 galaxy_uv = vec2(longitude * 7.0 + direction.y * 0.7, latitude * 13.0);
	float structure = galaxy_noise(galaxy_uv);
	float fine_structure = value_noise(galaxy_uv * 5.3 + vec2(13.0, 2.0));
	float dust_lane = smoothstep(0.42, 0.82, fine_structure) * bright_core;

	vec3 panorama_tint = mix(vec3(0.88, 0.92, 1.0), max(galaxy_color * 2.2, vec3(0.28)), 0.2);
	vec3 color = void_color + panorama * panorama_tint * panorama_strength;
	color += galaxy_color * broad_band * (0.13 + structure * 0.42) * galaxy_strength;
	color += nebula_color * bright_core * pow(structure, 2.2) * 0.62 * galaxy_strength;
	color -= dust_color * dust_lane * (0.35 + structure * 0.45);

	float small_stars = star_layer(spherical_uv, vec2(720.0, 360.0), 0.985, 0.22);
	float medium_stars = star_layer(spherical_uv + vec2(0.137, 0.071), vec2(310.0, 155.0), 0.991, 0.19);
	float hero_stars = star_layer(spherical_uv + vec2(0.371, 0.193), vec2(128.0, 64.0), 0.996, 0.15);
	float band_stars = star_layer(spherical_uv + vec2(0.019, 0.117), vec2(520.0, 260.0), 0.979, 0.2) * broad_band;
	float stars = small_stars * 0.72 + medium_stars * 1.25 + hero_stars * 2.6 + band_stars * 0.68;
	vec3 temperature = mix(star_color, vec3(1.0, 0.74, 0.48), hash21(floor(spherical_uv * vec2(310.0, 155.0))));
	color += temperature * stars * star_strength;
	COLOR = max(color, vec3(0.0));
}
"""

static func apply_to_environment(environment: Environment, preset: StringName = &"menu") -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SKY_SHADER_SOURCE
	var material := ShaderMaterial.new()
	material.shader = shader
	var palette := _palette(preset)
	for parameter in palette:
		material.set_shader_parameter(parameter, palette[parameter])
	var panorama := load("res://assets/textures/galaxy_arm_panorama.png") as Texture2D
	if panorama != null:
		material.set_shader_parameter("panorama_texture", panorama)
	material.set_shader_parameter("panorama_strength", 0.42 if preset == &"menu" else 0.26)
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.sky_material = material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.background_energy_multiplier = 0.92
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.16, 0.2, 0.28)
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.04
	return material

static func sector_preset(sector_index: int) -> StringName:
	return [&"acheron", &"vesper", &"crucible"][clampi(sector_index, 0, 2)]

static func _palette(preset: StringName) -> Dictionary:
	match preset:
		&"acheron":
			return {
				"void_color": Color(0.0018, 0.0022, 0.0048),
				"galaxy_color": Color(0.19, 0.22, 0.31),
				"nebula_color": Color(0.28, 0.075, 0.035),
				"dust_color": Color(0.075, 0.026, 0.012),
				"star_color": Color(0.78, 0.87, 1.0),
				"galaxy_axis": Vector3(0.18, 0.86, 0.47),
				"galaxy_strength": 0.72,
				"star_strength": 1.05,
				"sky_seed": 2.3,
			}
		&"vesper":
			return {
				"void_color": Color(0.0015, 0.0015, 0.0055),
				"galaxy_color": Color(0.22, 0.2, 0.34),
				"nebula_color": Color(0.2, 0.055, 0.3),
				"dust_color": Color(0.045, 0.018, 0.07),
				"star_color": Color(0.84, 0.9, 1.0),
				"galaxy_axis": Vector3(-0.28, 0.8, 0.53),
				"galaxy_strength": 0.78,
				"star_strength": 1.08,
				"sky_seed": 11.7,
			}
		&"crucible":
			return {
				"void_color": Color(0.002, 0.0016, 0.0045),
				"galaxy_color": Color(0.23, 0.21, 0.28),
				"nebula_color": Color(0.24, 0.11, 0.025),
				"dust_color": Color(0.08, 0.035, 0.012),
				"star_color": Color(0.94, 0.87, 0.72),
				"galaxy_axis": Vector3(0.42, 0.78, -0.46),
				"galaxy_strength": 0.76,
				"star_strength": 1.0,
				"sky_seed": 23.4,
			}
		_:
			return {
				"void_color": Color(0.0014, 0.0022, 0.0052),
				"galaxy_color": Color(0.32, 0.29, 0.31),
				"nebula_color": Color(0.26, 0.065, 0.09),
				"dust_color": Color(0.08, 0.035, 0.02),
				"star_color": Color(0.82, 0.9, 1.0),
				"galaxy_axis": Vector3(0.24, 0.96, -0.1),
				"galaxy_strength": 1.45,
				"star_strength": 1.02,
				"sky_seed": 5.9,
			}
