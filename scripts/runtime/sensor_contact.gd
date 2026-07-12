class_name SensorContact
extends RefCounted

enum IdentificationState { UNKNOWN, CLASSIFIED, IDENTIFIED }

var contact_id: StringName = &""
var tracked_entity_id: StringName = &""
var classification: StringName = &"unknown"
var estimated_position: Vector3 = Vector3.ZERO
var estimated_velocity: Vector3 = Vector3.ZERO
var confidence: float = 0.0
var uncertainty_radius_m: float = 1000.0
var identification_state: IdentificationState = IdentificationState.UNKNOWN
var last_update_seconds: float = 0.0

func is_targetable() -> bool:
	return identification_state == IdentificationState.IDENTIFIED and confidence >= 0.8

func update_identification() -> void:
	if confidence >= 0.8:
		identification_state = IdentificationState.IDENTIFIED
	elif confidence >= 0.4:
		identification_state = IdentificationState.CLASSIFIED
	else:
		identification_state = IdentificationState.UNKNOWN

func age_track(delta: float, confidence_decay_per_second: float = 0.035) -> void:
	estimated_position += estimated_velocity * delta
	confidence = maxf(0.0, confidence - confidence_decay_per_second * delta)
	uncertainty_radius_m += (30.0 + estimated_velocity.length() * 0.02) * delta
	update_identification()

