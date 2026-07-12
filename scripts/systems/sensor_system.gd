class_name SidebaySensorSystem
extends Node

signal contact_updated(contact: SensorContact)
signal active_ping_emitted(position: Vector3, radius_m: float)

var carrier: PlayerCarrier
var contacts: Dictionary = {}
var elapsed_seconds: float = 0.0
var scan_accumulator: float = 0.0
var scan_interval_seconds: float = 0.35

func configure(player_carrier: PlayerCarrier) -> void:
	carrier = player_carrier

func _process(delta: float) -> void:
	elapsed_seconds += delta
	scan_accumulator += delta
	for contact in contacts.values():
		contact.age_track(delta)
	if scan_accumulator >= scan_interval_seconds:
		scan_accumulator = 0.0
		perform_passive_scan()

func perform_passive_scan() -> void:
	if not is_instance_valid(carrier) or carrier.is_destroyed:
		return
	var observers := _observer_positions()
	for target_data in _hostile_targets():
		var target_position: Vector3 = target_data.position
		var best_distance := INF
		for observer in observers:
			best_distance = minf(best_distance, observer.distance_to(target_position))
		var target_signature: float = target_data.signature
		var effective_range := carrier.definition.passive_sensor_range_m * clampf(target_signature, 0.55, 1.5)
		if best_distance <= effective_range:
			var quality := clampf(1.0 - best_distance / effective_range, 0.04, 1.0)
			_update_contact(target_data, 0.08 + quality * 0.16, best_distance <= 1200.0)

func emit_active_ping() -> void:
	if not is_instance_valid(carrier):
		return
	for target_data in _hostile_targets():
		if carrier.global_position.distance_to(target_data.position) <= carrier.definition.active_sensor_range_m:
			_update_contact(target_data, 1.0, true)
	active_ping_emitted.emit(carrier.global_position, carrier.definition.active_sensor_range_m)

func _update_contact(target_data: Dictionary, confidence_gain: float, force_identified: bool) -> void:
	var entity_id: StringName = target_data.entity_id
	var contact: SensorContact = contacts.get(entity_id)
	if contact == null:
		contact = SensorContact.new()
		contact.contact_id = StringName("contact_%s" % entity_id)
		contact.tracked_entity_id = entity_id
		contacts[entity_id] = contact
	contact.classification = target_data.classification
	contact.estimated_velocity = target_data.velocity
	contact.confidence = 1.0 if force_identified else clampf(contact.confidence + confidence_gain, 0.0, 1.0)
	var uncertainty_target := lerpf(900.0, 35.0, contact.confidence)
	contact.uncertainty_radius_m = lerpf(contact.uncertainty_radius_m, uncertainty_target, 0.45)
	var noise_seed := float(String(entity_id).hash() % 997) + elapsed_seconds * 0.2
	var noise := Vector3(sin(noise_seed), sin(noise_seed * 1.71) * 0.35, cos(noise_seed * 0.83)) * contact.uncertainty_radius_m * 0.3
	contact.estimated_position = target_data.position + noise
	contact.last_update_seconds = elapsed_seconds
	contact.update_identification()
	contact_updated.emit(contact)

func _observer_positions() -> Array[Vector3]:
	var observers: Array[Vector3] = [carrier.global_position]
	for group in get_tree().get_nodes_in_group("squadrons"):
		if group is SidebaySquadron and group.team == carrier.team and group.definition.role == "scout":
			if group.operation.state == BayOperation.State.DEPLOYED:
				observers.append(group.representative_position())
	return observers

func _hostile_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var registry := get_node_or_null("/root/CombatRegistry")
	var entities: Array = registry.active_combat_entities() if registry != null else get_tree().get_nodes_in_group("combat_entities")
	for entity in entities:
		if entity is CombatShip and entity.team != carrier.team and not entity.is_destroyed:
			# Squadron craft are represented by their parent group to avoid seven noisy contacts.
			if entity is FighterCraft and entity.home_squadron != null:
				continue
			targets.append({
				"entity_id": entity.stable_entity_id,
				"position": entity.global_position,
				"velocity": entity.velocity,
				"signature": entity.definition.signature,
				"classification": StringName(entity.definition.role)
			})
	for squadron in get_tree().get_nodes_in_group("squadrons"):
		if squadron is SidebaySquadron and squadron.team != carrier.team and squadron.deployed_craft_count() > 0:
			targets.append({
				"entity_id": squadron.stable_entity_id,
				"position": squadron.representative_position(),
				"velocity": squadron.representative_velocity(),
				"signature": 0.75,
				"classification": &"fighter_group"
			})
	return targets

func get_contact(entity_id: StringName) -> SensorContact:
	return contacts.get(entity_id)

func is_targetable(entity_id: StringName) -> bool:
	var contact := get_contact(entity_id)
	return contact != null and contact.is_targetable()

func targetable_contacts() -> Array[SensorContact]:
	var result: Array[SensorContact] = []
	for contact in contacts.values():
		if contact.is_targetable():
			result.append(contact)
	return result

func best_target_in_direction(origin: Vector3, direction: Vector3, maximum_range: float, cone_dot: float = 0.72) -> CombatShip:
	var best: CombatShip
	var best_score := -INF
	for contact in targetable_contacts():
		var entity := resolve_combat_target(contact.tracked_entity_id)
		if not is_instance_valid(entity):
			continue
		var offset := entity.global_position - origin
		if offset.length() > maximum_range:
			continue
		var score := direction.normalized().dot(offset.normalized()) - offset.length() / maximum_range * 0.08
		if score >= cone_dot and score > best_score:
			best = entity
			best_score = score
	return best

func resolve_combat_target(entity_id: StringName) -> CombatShip:
	var registry := get_node_or_null("/root/CombatRegistry")
	var entity: Node = registry.resolve_combat_entity(entity_id) if registry != null else null
	if entity is CombatShip:
		return entity
	for group in get_tree().get_nodes_in_group("squadrons"):
		if group is SidebaySquadron and group.stable_entity_id == entity_id:
			return group.resolve_command_target(entity_id)
	return null
