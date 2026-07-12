extends Node

signal quality_changed(profile_name: StringName)
signal reduced_flashes_changed(enabled: bool)

const SETTINGS_PATH := "user://exodrift_settings.cfg"
const PROFILE_ORDER: Array[StringName] = [&"low", &"medium", &"high"]
const PROFILES := {
	&"low": {
		"label": "LOW",
		"effect_density": 0.5,
		"impact_budget": 24,
		"trail_scale": 0.55,
		"backdrop_layers": 1,
		"secondary_debris": false
	},
	&"medium": {
		"label": "MEDIUM",
		"effect_density": 0.75,
		"impact_budget": 48,
		"trail_scale": 0.78,
		"backdrop_layers": 2,
		"secondary_debris": false
	},
	&"high": {
		"label": "HIGH",
		"effect_density": 1.0,
		"impact_budget": 80,
		"trail_scale": 1.0,
		"backdrop_layers": 3,
		"secondary_debris": true
	}
}

var current_quality: StringName = &"medium"
var reduced_flashes: bool = false

func _ready() -> void:
	load_settings()

func default_quality() -> StringName:
	return &"medium" if OS.has_feature("web") else &"high"

func load_settings() -> void:
	var config := ConfigFile.new()
	var fallback := default_quality()
	if config.load(SETTINGS_PATH) == OK:
		var stored := StringName(str(config.get_value("display", "graphics_quality", String(fallback))).to_lower())
		current_quality = stored if PROFILES.has(stored) else fallback
		reduced_flashes = bool(config.get_value("accessibility", "reduced_flashes", false))
	else:
		current_quality = fallback

func set_quality(profile_name: StringName, persist: bool = true) -> void:
	var normalized := StringName(String(profile_name).to_lower())
	if not PROFILES.has(normalized):
		return
	var changed := current_quality != normalized
	current_quality = normalized
	if persist:
		_save_values()
	if changed:
		quality_changed.emit(current_quality)

func set_reduced_flashes(enabled: bool, persist: bool = true) -> void:
	var changed := reduced_flashes != enabled
	reduced_flashes = enabled
	if persist:
		_save_values()
	if changed:
		reduced_flashes_changed.emit(reduced_flashes)

func profile() -> Dictionary:
	return PROFILES[current_quality]

func profile_label() -> String:
	return str(profile().get("label", "MEDIUM"))

func profile_index() -> int:
	return maxi(0, PROFILE_ORDER.find(current_quality))

func _save_values() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("display", "graphics_quality", String(current_quality))
	config.set_value("accessibility", "reduced_flashes", reduced_flashes)
	config.save(SETTINGS_PATH)
