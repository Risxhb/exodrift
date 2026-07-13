class_name SidebaySquadron
extends Node3D

signal status_changed(squadron_id: StringName, message: String)
signal squadron_destroyed(squadron_id: StringName)
signal service_task_changed(squadron_id: StringName, task: StringName)
signal loadout_changed(squadron_id: StringName, loadout_id: StringName)

enum ServicePriority { RAPID_TURN, BALANCED, REPAIR_FIRST }

const STORE_AVIATION_ORDNANCE := &"aviation_ordnance"
const STORE_CRAFT_REFUEL := &"craft_refuel"
const DISABLED_DECK_RECOVERY_SPEED := 0.35

var stable_entity_id: StringName = &"squadron"
var display_name: String = "Squadron"
var team: StringName = &"friendly"
var definition: SquadronDefinition
var home_carrier: PlayerCarrier
var bay_side: StringName = &"port"
var operation := BayOperation.new()
var command_link := CommandLinkState.new()
var current_order: FleetOrder
var order_queue: Array[FleetOrder] = []
var stance: StringName = &"balanced"
var formation_name: StringName = &"wedge"
var crafts: Array[FighterCraft] = []
var launch_index: int = 0
var docking_count: int = 0
var cycle_timer: float = 0.0
var formation_spacing_m: float = 55.0
var is_hostile_air_group: bool = false
var redeploy_requested: bool = false
var service_priority: ServicePriority = ServicePriority.BALANCED
var current_loadout_profile: Dictionary = {}
var store_consumer: Callable
var deck_operational_provider: Callable
var deck_task_speed_multiplier: float = 1.0

func configure(
	squadron_definition: SquadronDefinition,
	entity_id: StringName,
	faction: StringName,
	carrier: PlayerCarrier,
	side: StringName,
	color: Color
) -> void:
	definition = squadron_definition
	stable_entity_id = entity_id
	display_name = definition.display_name
	team = faction
	home_carrier = carrier
	bay_side = side
	stance = StringName(definition.default_stance)
	add_to_group("commandables")
	add_to_group("squadrons")
	add_to_group("team_%s" % team)
	var scene_owner: Node = get_parent() if get_parent() != null else get_tree().root
	for index in definition.craft_count:
		var craft := FighterCraft.new()
		scene_owner.call_deferred("add_child", craft)
		craft.call_deferred(
			"configure_craft",
			definition.craft_definition,
			StringName("%s_%02d" % [stable_entity_id, index + 1]),
			team,
			color,
			self,
			definition.ammunition_per_craft,
			definition.endurance_seconds
		)
		if not current_loadout_profile.is_empty():
			craft.call_deferred("apply_loadout_profile", current_loadout_profile, false)
		crafts.append(craft)

func configure_deck_logistics(
	consume_store_callback: Callable = Callable(),
	task_speed_multiplier: float = 1.0,
	deck_available_callback: Callable = Callable()
) -> void:
	store_consumer = consume_store_callback
	deck_task_speed_multiplier = maxf(0.05, task_speed_multiplier)
	deck_operational_provider = deck_available_callback

func set_deck_task_speed_multiplier(multiplier: float) -> void:
	deck_task_speed_multiplier = maxf(0.05, multiplier)

func set_service_priority(priority_value: Variant) -> bool:
	var resolved := ServicePriority.BALANCED
	if priority_value is int:
		resolved = clampi(int(priority_value), ServicePriority.RAPID_TURN, ServicePriority.REPAIR_FIRST) as ServicePriority
	else:
		match String(priority_value).to_lower().replace(" ", "_"):
			"rapid", "rapid_turn":
				resolved = ServicePriority.RAPID_TURN
			"repair", "repair_first":
				resolved = ServicePriority.REPAIR_FIRST
			"balanced":
				resolved = ServicePriority.BALANCED
			_:
				return false
	service_priority = resolved
	status_changed.emit(stable_entity_id, "%s deck priority: %s" % [display_name, service_priority_label()])
	return true

func service_priority_label() -> String:
	match service_priority:
		ServicePriority.RAPID_TURN:
			return "Rapid Turn"
		ServicePriority.REPAIR_FIRST:
			return "Repair First"
	return "Balanced"

func can_change_loadout() -> bool:
	return all_craft_aboard() and operation.state in [
		BayOperation.State.READY,
		BayOperation.State.SERVICING,
		BayOperation.State.REPAIRING,
		BayOperation.State.REFUELING,
	]

func set_loadout(loadout_definition: Variant) -> bool:
	if not can_change_loadout():
		status_changed.emit(stable_entity_id, "%s loadout locked until the wing is aboard and clear of rearming" % display_name)
		return false
	var profile := _loadout_to_dictionary(loadout_definition)
	var next_id := StringName(profile.get("loadout_id", profile.get("id", &"")))
	if next_id == &"":
		return false
	var required_role := String(profile.get("squadron_role", profile.get("wing_role", "")))
	if not required_role.is_empty() and definition != null and required_role != definition.role:
		status_changed.emit(stable_entity_id, "%s loadout rejected: incompatible package" % display_name)
		return false
	var previous_id := current_loadout_id()
	var package_changed := previous_id != &"" and previous_id != next_id
	current_loadout_profile = profile.duplicate(true)
	for craft in crafts:
		if is_instance_valid(craft):
			craft.apply_loadout_profile(current_loadout_profile, package_changed)
	if package_changed and operation.state == BayOperation.State.READY:
		operation.transition(BayOperation.State.REARMING)
		service_task_changed.emit(stable_entity_id, &"rearming")
	loadout_changed.emit(stable_entity_id, next_id)
	status_changed.emit(stable_entity_id, "%s package selected: %s" % [display_name, String(profile.get("display_name", next_id))])
	return true

func current_loadout_id() -> StringName:
	return StringName(current_loadout_profile.get("loadout_id", current_loadout_profile.get("id", &"")))

func ammunition_capacity_per_craft() -> int:
	if not current_loadout_profile.is_empty():
		return maxi(0, int(current_loadout_profile.get("ammunition_per_craft", current_loadout_profile.get("ammo_per_craft", definition.ammunition_per_craft))))
	return definition.ammunition_per_craft if definition != null else 0

func identification_gain_multiplier() -> float:
	return maxf(0.0, float(current_loadout_profile.get("identification_gain_multiplier", 1.0)))

func uncertainty_multiplier() -> float:
	return maxf(0.0, float(current_loadout_profile.get("uncertainty_multiplier", 1.0)))

func escape_pod_recovery_range_m() -> float:
	return maxf(0.0, float(current_loadout_profile.get("escape_pod_recovery_range_m", 0.0)))

func deck_queue_snapshot() -> Dictionary:
	var duration := service_task_duration(operation.state) if operation.is_service_state() else 0.0
	var operation_state := String(operation.label()).to_lower().replace(" ", "_")
	return {
		"bay": bay_side,
		"state": operation_state,
		"task": operation_state if operation.is_service_state() else "idle",
		"progress": clampf(operation.state_elapsed_seconds / maxf(0.001, duration), 0.0, 1.0) if duration > 0.0 else 0.0,
		"priority": service_priority_label(),
		"loadout_id": current_loadout_id(),
		"craft_aboard": living_craft_count() - deployed_craft_count(),
		"craft_total": living_craft_count(),
	}

func _loadout_to_dictionary(loadout_definition: Variant) -> Dictionary:
	if loadout_definition is Dictionary:
		return (loadout_definition as Dictionary).duplicate(true)
	if loadout_definition is Object:
		var source := loadout_definition as Object
		if source.has_method("to_dictionary"):
			var serialized: Variant = source.call("to_dictionary")
			if serialized is Dictionary:
				return (serialized as Dictionary).duplicate(true)
		var profile: Dictionary = {}
		var supported := [
			"loadout_id", "id", "display_name", "squadron_role", "wing_role",
			"ammunition_per_craft", "ammo_per_craft", "damage_multiplier", "cycle_multiplier",
			"range_multiplier", "identification_gain_multiplier", "uncertainty_multiplier",
			"missile_interception", "can_intercept_missiles", "missile_intercept_range_m",
			"defensive_cycle_multiplier", "escape_pod_recovery_range_m",
		]
		for property_data in source.get_property_list():
			var property_name := String(property_data.get("name", ""))
			if supported.has(property_name):
				profile[property_name] = source.get(property_name)
		return profile
	return {}

func start_deployed(center: Vector3) -> void:
	is_hostile_air_group = home_carrier == null
	operation.state = BayOperation.State.DEPLOYED
	await get_tree().process_frame
	for index in crafts.size():
		var craft := crafts[index]
		if is_instance_valid(craft):
			craft.deploy(center + _formation_offset(index), Vector3.ZERO)
	status_changed.emit(stable_entity_id, "%s deployed" % display_name)

func request_launch() -> bool:
	if operation.state != BayOperation.State.READY or home_carrier == null:
		status_changed.emit(stable_entity_id, "%s is %s" % [display_name, operation.label()])
		return false
	if not is_deck_operational():
		status_changed.emit(stable_entity_id, "%s launch rejected: %s deck disabled" % [display_name, String(bay_side)])
		return false
	if not home_carrier.are_bays_open():
		status_changed.emit(stable_entity_id, "%s launch rejected: %s bay is %s" % [display_name, String(bay_side), home_carrier.bay_status()])
		return false
	operation.transition(BayOperation.State.QUEUED)
	launch_index = 0
	cycle_timer = 0.0
	status_changed.emit(stable_entity_id, "%s queued in %s bay" % [display_name, String(bay_side)])
	return true

func request_recall() -> bool:
	if operation.state == BayOperation.State.QUEUED:
		operation.transition(BayOperation.State.READY)
		status_changed.emit(stable_entity_id, "%s launch cancelled for jump preparation" % display_name)
		return true
	if operation.state not in [BayOperation.State.DEPLOYED, BayOperation.State.LAUNCHING]:
		return false
	operation.transition(BayOperation.State.RETURNING)
	cycle_timer = 0.0
	status_changed.emit(stable_entity_id, "%s returning to %s bay" % [display_name, String(bay_side)])
	return true

func request_redeploy() -> bool:
	if home_carrier == null:
		return false
	if operation.state == BayOperation.State.READY:
		return request_launch()
	if not operation.is_service_state():
		status_changed.emit(stable_entity_id, "%s redeploy rejected: flight deck is %s" % [display_name, operation.label()])
		return false
	redeploy_requested = true
	status_changed.emit(stable_entity_id, "%s redeploy queued after service" % display_name)
	return true

func prepare_for_jump() -> bool:
	match operation.state:
		BayOperation.State.QUEUED, BayOperation.State.LAUNCHING, BayOperation.State.DEPLOYED:
			request_recall()
	return all_craft_aboard()

func all_craft_aboard() -> bool:
	return deployed_craft_count() == 0 and (operation.state == BayOperation.State.READY or operation.is_service_state())

func _process(delta: float) -> void:
	operation.tick(delta)
	cycle_timer += delta
	_cleanup_destroyed_crafts()
	if living_craft_count() == 0:
		squadron_destroyed.emit(stable_entity_id)
		set_process(false)
		return
	if home_carrier != null and is_instance_valid(home_carrier):
		command_link.update_for_distance(representative_position().distance_to(home_carrier.global_position), home_carrier.effective_command_range_m())
	match operation.state:
		BayOperation.State.QUEUED:
			if operation.state_elapsed_seconds >= 0.25:
				operation.transition(BayOperation.State.LAUNCHING)
				cycle_timer = launch_interval_seconds()
		BayOperation.State.LAUNCHING:
			_process_launch_cycle()
		BayOperation.State.DEPLOYED:
			_process_deployed(delta)
		BayOperation.State.RETURNING:
			operation.transition(BayOperation.State.APPROACH)
		BayOperation.State.APPROACH:
			_process_approach()
		BayOperation.State.DOCKING:
			_process_docking()
		BayOperation.State.SERVICING:
			# Old snapshots and tests can still resume the former aggregate service state.
			if operation.state_elapsed_seconds >= definition.service_seconds:
				for craft in crafts:
					if is_instance_valid(craft):
						craft.service(definition.ammunition_per_craft, definition.endurance_seconds)
				_finish_service_cycle()
		BayOperation.State.REPAIRING, BayOperation.State.REFUELING, BayOperation.State.REARMING:
			_process_service_task()
		BayOperation.State.READY:
			if redeploy_requested and is_deck_operational():
				redeploy_requested = false
				request_launch()

func _process_launch_cycle() -> void:
	if cycle_timer < launch_interval_seconds():
		return
	cycle_timer = 0.0
	while launch_index < crafts.size() and not is_instance_valid(crafts[launch_index]):
		launch_index += 1
	if launch_index >= crafts.size():
		operation.transition(BayOperation.State.DEPLOYED)
		status_changed.emit(stable_entity_id, "%s launch complete" % display_name)
		return
	var craft := crafts[launch_index]
	var marker := home_carrier.get_bay_marker(bay_side)
	var outward := -home_carrier.global_transform.basis.x if bay_side == &"port" else home_carrier.global_transform.basis.x
	craft.deploy(marker.global_position + outward * 12.0, home_carrier.velocity + outward * 180.0)
	craft.command_move(marker.global_position + outward * (350.0 + launch_index * 45.0) - home_carrier.global_transform.basis.z * 100.0)
	launch_index += 1

func _process_deployed(_delta: float) -> void:
	var emergency := false
	for index in crafts.size():
		var craft := crafts[index]
		if not is_instance_valid(craft) or not craft.deployed:
			continue
		if craft.endurance_seconds <= 10.0 or craft.ammunition <= 0 or craft.layer_percentages().z <= 0.25:
			emergency = true
		_apply_order_to_craft(craft, index)
	if emergency and home_carrier != null:
		request_recall()

func _apply_order_to_craft(craft: FighterCraft, index: int) -> void:
	if current_order == null:
		return
	match current_order.order_type:
		FleetOrder.OrderType.MOVE, FleetOrder.OrderType.HOLD, FleetOrder.OrderType.WITHDRAW:
			craft.command_move(current_order.target_position + _formation_offset(index))
		FleetOrder.OrderType.ATTACK, FleetOrder.OrderType.INTERCEPT:
			var target_node := resolve_command_target(current_order.target_entity_id)
			if is_instance_valid(target_node):
				craft.command_attack(target_node)
		FleetOrder.OrderType.ESCORT:
			var escort := resolve_command_target(current_order.target_entity_id)
			if is_instance_valid(escort):
				craft.command_move(escort.global_position + _formation_offset(index) + Vector3(0.0, 40.0, 120.0))
		FleetOrder.OrderType.RECALL:
			request_recall()

func _process_approach() -> void:
	var marker := home_carrier.get_bay_marker(bay_side)
	var outward := -home_carrier.global_transform.basis.x if bay_side == &"port" else home_carrier.global_transform.basis.x
	var approach_point := marker.global_position + outward * 260.0 + home_carrier.global_transform.basis.z * 40.0
	var all_in_approach := true
	for index in crafts.size():
		var craft := crafts[index]
		if not is_instance_valid(craft) or not craft.deployed:
			continue
		craft.command_move(approach_point + _formation_offset(index) * 0.3)
		if craft.global_position.distance_to(approach_point) > 120.0:
			all_in_approach = false
	if all_in_approach:
		operation.transition(BayOperation.State.DOCKING)
		docking_count = 0
		cycle_timer = 0.0

func _process_docking() -> void:
	if cycle_timer < recovery_interval_seconds():
		return
	cycle_timer = 0.0
	var marker := home_carrier.get_bay_marker(bay_side)
	for craft in crafts:
		if not is_instance_valid(craft) or not craft.deployed:
			continue
		craft.command_move(marker.global_position)
		if craft.global_position.distance_to(marker.global_position) <= 35.0:
			craft.dock()
			docking_count += 1
			break
	if deployed_craft_count() == 0:
		_begin_service_cycle()

func _begin_service_cycle() -> void:
	if service_priority != ServicePriority.RAPID_TURN and _needs_repair():
		_transition_service_task(BayOperation.State.REPAIRING)
	elif _needs_refuel():
		_transition_service_task(BayOperation.State.REFUELING)
	elif _needs_rearm():
		_transition_service_task(BayOperation.State.REARMING)
	else:
		_finish_service_cycle()

func _process_service_task() -> void:
	if operation.state_elapsed_seconds < service_task_duration(operation.state):
		return
	match operation.state:
		BayOperation.State.REPAIRING:
			_complete_repairs()
			if _needs_refuel():
				_transition_service_task(BayOperation.State.REFUELING)
			elif _needs_rearm():
				_transition_service_task(BayOperation.State.REARMING)
			else:
				_finish_service_cycle()
		BayOperation.State.REFUELING:
			_complete_refueling()
			if _needs_rearm():
				_transition_service_task(BayOperation.State.REARMING)
			else:
				_finish_service_cycle()
		BayOperation.State.REARMING:
			_complete_rearming()
			_finish_service_cycle()

func _transition_service_task(next_state: BayOperation.State) -> void:
	if not operation.transition(next_state):
		return
	var task := StringName(BayOperation.State.keys()[next_state].to_lower())
	service_task_changed.emit(stable_entity_id, task)
	status_changed.emit(stable_entity_id, "%s %s" % [display_name, operation.label().to_lower()])

func _finish_service_cycle() -> void:
	for craft in crafts:
		if is_instance_valid(craft) and craft.damage_state != null and craft.damage_state.definition != null:
			craft.damage_state.shields = craft.damage_state.definition.max_shields
	if operation.state != BayOperation.State.READY:
		operation.transition(BayOperation.State.READY)
	service_task_changed.emit(stable_entity_id, &"ready")
	status_changed.emit(stable_entity_id, "%s ready to relaunch" % display_name)
	if redeploy_requested and is_deck_operational():
		redeploy_requested = false
		request_launch()

func service_task_duration(state_value: BayOperation.State) -> float:
	if definition == null:
		return 0.0
	var task_weight := 1.0
	match state_value:
		BayOperation.State.REPAIRING:
			task_weight = 0.4
		BayOperation.State.REFUELING:
			task_weight = 0.25
		BayOperation.State.REARMING:
			task_weight = 0.35
		BayOperation.State.SERVICING:
			return definition.service_seconds
		_:
			return 0.0
	var priority_time_multiplier := 1.0
	match service_priority:
		ServicePriority.RAPID_TURN:
			priority_time_multiplier = 0.75
		ServicePriority.REPAIR_FIRST:
			priority_time_multiplier = 1.35
	var speed := deck_task_speed_multiplier
	if not is_deck_operational():
		speed *= DISABLED_DECK_RECOVERY_SPEED
	return definition.service_seconds * task_weight * priority_time_multiplier / maxf(0.05, speed)

func recovery_interval_seconds() -> float:
	if definition == null:
		return 0.0
	var speed := deck_task_speed_multiplier
	if not is_deck_operational():
		speed *= DISABLED_DECK_RECOVERY_SPEED
	return definition.recovery_interval_seconds / maxf(0.05, speed)


func launch_interval_seconds() -> float:
	if definition == null:
		return 0.0
	return definition.launch_interval_seconds / maxf(0.05, deck_task_speed_multiplier)

func is_deck_operational() -> bool:
	if deck_operational_provider.is_valid():
		return bool(deck_operational_provider.call(bay_side))
	if home_carrier != null and home_carrier.has_method("is_flight_deck_operational"):
		return bool(home_carrier.call("is_flight_deck_operational", bay_side))
	return true

func _needs_repair() -> bool:
	for craft in crafts:
		if not is_instance_valid(craft) or craft.damage_state == null or craft.damage_state.definition == null:
			continue
		if craft.damage_state.shields < craft.damage_state.definition.max_shields or craft.damage_state.armor < craft.damage_state.definition.max_armor:
			return true
	return false

func _needs_refuel() -> bool:
	if definition == null:
		return false
	for craft in crafts:
		if is_instance_valid(craft) and craft.endurance_seconds < definition.endurance_seconds - 0.001:
			return true
	return false

func _needs_rearm() -> bool:
	var capacity := ammunition_capacity_per_craft()
	for craft in crafts:
		if is_instance_valid(craft) and craft.ammunition < capacity:
			return true
	return false

func _complete_repairs() -> void:
	var recovery := 0.6 if service_priority == ServicePriority.REPAIR_FIRST else 0.35
	for craft in crafts:
		if is_instance_valid(craft):
			craft.service_repair(recovery)

func _complete_refueling() -> void:
	if definition == null:
		return
	var awaiting: Array[FighterCraft] = []
	for craft in crafts:
		if is_instance_valid(craft) and craft.endurance_seconds < definition.endurance_seconds - 0.001:
			awaiting.append(craft)
	var supplied := _consume_store(STORE_CRAFT_REFUEL, awaiting.size())
	for index in mini(supplied, awaiting.size()):
		awaiting[index].service_refuel(definition.endurance_seconds)
	if supplied < awaiting.size():
		status_changed.emit(stable_entity_id, "%s refuel partial: %d/%d craft" % [display_name, supplied, awaiting.size()])

func _complete_rearming() -> void:
	var capacity := ammunition_capacity_per_craft()
	var requested := 0
	for craft in crafts:
		if is_instance_valid(craft):
			requested += maxi(0, capacity - craft.ammunition)
	var supplied := _consume_store(STORE_AVIATION_ORDNANCE, requested)
	var remaining := supplied
	for craft in crafts:
		if not is_instance_valid(craft) or remaining <= 0:
			continue
		remaining -= craft.service_rearm(capacity, remaining)
	if supplied < requested:
		status_changed.emit(stable_entity_id, "%s rearm partial: %d/%d rounds" % [display_name, supplied, requested])

func _consume_store(store_id: StringName, requested_amount: int) -> int:
	if requested_amount <= 0:
		return 0
	var result: Variant = requested_amount
	if store_consumer.is_valid():
		result = store_consumer.call(store_id, requested_amount)
	elif home_carrier != null and home_carrier.has_method("consume_carrier_store"):
		result = home_carrier.call("consume_carrier_store", store_id, requested_amount)
	elif home_carrier != null:
		var operations: Variant = home_carrier.get("carrier_operations")
		if operations is Object and (operations as Object).has_method("consume_store_partial"):
			result = (operations as Object).call("consume_store_partial", store_id, requested_amount)
	if result is bool:
		return requested_amount if bool(result) else 0
	if result is Dictionary:
		return clampi(int(result.get("consumed", result.get("amount", 0))), 0, requested_amount)
	return clampi(int(result), 0, requested_amount)

func issue_order(order: FleetOrder) -> bool:
	if order.requires_command_link and not command_link.can_accept_order():
		status_changed.emit(stable_entity_id, "%s: command link lost" % display_name)
		return false
	order.stance = stance
	command_link.last_confirmed_order = order
	if order.queued and current_order != null:
		order_queue.append(order)
	else:
		current_order = order
		order_queue.clear()
	status_changed.emit(stable_entity_id, "%s acknowledges %s" % [display_name, FleetOrder.OrderType.keys()[order.order_type]])
	return true

func set_stance(next_stance: StringName) -> void:
	stance = next_stance
	status_changed.emit(stable_entity_id, "%s stance: %s" % [display_name, String(stance).capitalize()])

func cycle_formation() -> void:
	var formations: Array[StringName] = [&"wedge", &"line", &"screen", &"column"]
	formation_name = formations[(formations.find(formation_name) + 1) % formations.size()]
	status_changed.emit(stable_entity_id, "%s formation: %s" % [display_name, String(formation_name).capitalize()])

func _formation_offset(index: int) -> Vector3:
	match formation_name:
		&"line":
			return Vector3((index - (definition.craft_count - 1) * 0.5) * formation_spacing_m, 0.0, 0.0)
		&"screen":
			var angle := TAU * float(index) / maxf(1.0, float(definition.craft_count))
			return Vector3(cos(angle), sin(angle) * 0.35, sin(angle)) * formation_spacing_m
		&"column":
			return Vector3(0.0, 0.0, index * formation_spacing_m)
		_:
			var side := -1.0 if index % 2 == 0 else 1.0
			var rank := (index + 1) / 2
			return Vector3(side * rank * formation_spacing_m, 0.0, rank * formation_spacing_m)

func representative_position() -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for craft in crafts:
		if is_instance_valid(craft) and craft.deployed:
			total += craft.global_position
			count += 1
	if count > 0:
		return total / float(count)
	if home_carrier != null and is_instance_valid(home_carrier):
		return home_carrier.global_position
	return global_position

func representative_velocity() -> Vector3:
	for craft in crafts:
		if is_instance_valid(craft) and craft.deployed:
			return craft.velocity
	return Vector3.ZERO

func resolve_command_target(entity_id: StringName) -> CombatShip:
	for candidate in get_tree().get_nodes_in_group("combat_entities"):
		if candidate is CombatShip and candidate.stable_entity_id == entity_id:
			return candidate
	for group in get_tree().get_nodes_in_group("squadrons"):
		if group is SidebaySquadron and group.stable_entity_id == entity_id:
			for craft in group.crafts:
				if is_instance_valid(craft) and craft.deployed:
					return craft
	return null

func living_craft_count() -> int:
	var count := 0
	for craft in crafts:
		if is_instance_valid(craft) and not craft.is_destroyed:
			count += 1
	return count

func deployed_craft_count() -> int:
	var count := 0
	for craft in crafts:
		if is_instance_valid(craft) and craft.deployed and not craft.is_destroyed:
			count += 1
	return count

func average_endurance() -> float:
	var total := 0.0
	var count := 0
	for craft in crafts:
		if is_instance_valid(craft):
			total += craft.endurance_seconds
			count += 1
	return total / maxf(1.0, float(count))

func total_ammunition() -> int:
	var total := 0
	for craft in crafts:
		if is_instance_valid(craft):
			total += craft.ammunition
	return total

func _cleanup_destroyed_crafts() -> void:
	# Invalid references remain as empty launch slots so craft identities never shift or duplicate.
	pass
