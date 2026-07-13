class_name SidebaySquadron
extends Node3D

signal status_changed(squadron_id: StringName, message: String)
signal squadron_destroyed(squadron_id: StringName)

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
		crafts.append(craft)

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
	if operation.state != BayOperation.State.SERVICING:
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
	return deployed_craft_count() == 0 and operation.state in [BayOperation.State.READY, BayOperation.State.SERVICING]

func _process(delta: float) -> void:
	operation.tick(delta)
	cycle_timer += delta
	_cleanup_destroyed_crafts()
	if living_craft_count() == 0:
		squadron_destroyed.emit(stable_entity_id)
		set_process(false)
		return
	if home_carrier != null and is_instance_valid(home_carrier):
		command_link.update_for_distance(representative_position().distance_to(home_carrier.global_position), home_carrier.definition.command_range_m)
	match operation.state:
		BayOperation.State.QUEUED:
			if operation.state_elapsed_seconds >= 0.25:
				operation.transition(BayOperation.State.LAUNCHING)
				cycle_timer = definition.launch_interval_seconds
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
			if operation.state_elapsed_seconds >= definition.service_seconds:
				for craft in crafts:
					if is_instance_valid(craft):
						craft.service(definition.ammunition_per_craft, definition.endurance_seconds)
				operation.transition(BayOperation.State.READY)
				status_changed.emit(stable_entity_id, "%s ready to relaunch" % display_name)
				if redeploy_requested:
					redeploy_requested = false
					request_launch()

func _process_launch_cycle() -> void:
	if cycle_timer < definition.launch_interval_seconds:
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

func _process_docking() -> void:
	if cycle_timer < definition.recovery_interval_seconds:
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
	if docking_count >= living_craft_count():
		operation.transition(BayOperation.State.SERVICING)
		status_changed.emit(stable_entity_id, "%s servicing" % display_name)

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
