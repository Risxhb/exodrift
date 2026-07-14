class_name TacticalController
extends Node

signal mode_changed(enabled: bool)
signal notification_requested(message: String)
signal selection_changed(name: String)
signal target_lock_requested(entity_id: StringName)
signal context_menu_requested(screen_position: Vector2, entity_id: StringName)
signal carrier_navigation_requested(command: StringName, entity_id: StringName, distance_m: float)
signal command_issued(entity_id: StringName, order: FleetOrder)
signal wheel_cancelled

const GRID_EXTENT_M := 60000.0
const GRID_MINOR_STEP_M := 1000.0
const GRID_MAJOR_STEP_M := 5000.0

var enabled: bool = false
var carrier: PlayerCarrier
var sensors: SidebaySensorSystem
var camera: Camera3D
var selected: Node
var commandables: Array[Node] = []
var contact_marker_root: Node3D
var friendly_marker_root: Node3D
var grid_instance: MeshInstance3D
var order_path_root: Node3D
var objective_marker_root: Node3D
var selection_ring: MeshInstance3D
var context_wheel: TacticalContextWheel
var objective_descriptors: Array[TacticalObjectiveDescriptor] = []
var yaw: float = 0.35
var pitch: float = -0.95
var distance_m: float = 4200.0
var zoom_factor: float = 1.0
var middle_dragging: bool = false
var hidden_hostiles: Dictionary = {}
var wheel_world_position: Vector3 = Vector3.ZERO
var wheel_contact_id: StringName = &""
var wheel_friendly_id: StringName = &""
var wheel_objective: TacticalObjectiveDescriptor
var wheel_screen_position: Vector2 = Vector2.ZERO
var marker_refresh_elapsed: float = 0.0
var camera_focus_position: Vector3 = Vector3.ZERO
var follow_carrier_focus: bool = true

func configure(player_carrier: PlayerCarrier, sensor_system: SidebaySensorSystem, friendly_commandables: Array[Node]) -> void:
	carrier = player_carrier
	camera_focus_position = carrier.global_position
	sensors = sensor_system
	commandables = friendly_commandables
	camera = Camera3D.new()
	camera.name = "TacticalCamera"
	camera.fov = 58.0
	camera.near = 5.0
	camera.far = 140000.0
	var scene_owner: Node = carrier.get_parent() if carrier.get_parent() != null else get_tree().root
	scene_owner.add_child(camera)
	contact_marker_root = Node3D.new()
	contact_marker_root.name = "ContactMarkers"
	scene_owner.add_child(contact_marker_root)
	contact_marker_root.visible = false
	friendly_marker_root = Node3D.new()
	friendly_marker_root.name = "FriendlyMarkers"
	scene_owner.add_child(friendly_marker_root)
	friendly_marker_root.visible = false
	grid_instance = _create_grid()
	scene_owner.add_child(grid_instance)
	grid_instance.visible = false
	order_path_root = Node3D.new()
	order_path_root.name = "FleetOrderPaths"
	scene_owner.add_child(order_path_root)
	order_path_root.visible = false
	objective_marker_root = Node3D.new()
	objective_marker_root.name = "TacticalObjectives"
	scene_owner.add_child(objective_marker_root)
	objective_marker_root.visible = false
	selection_ring = _create_selection_ring()
	scene_owner.add_child(selection_ring)
	selection_ring.visible = false
	var wheel_layer := CanvasLayer.new()
	wheel_layer.name = "TacticalContextLayer"
	wheel_layer.layer = 30
	add_child(wheel_layer)
	context_wheel = TacticalContextWheel.new()
	wheel_layer.add_child(context_wheel)
	context_wheel.action_selected.connect(_on_wheel_action_selected)
	context_wheel.cancelled.connect(_on_wheel_cancelled)
	if not commandables.is_empty():
		select_commandable(commandables[0])

func set_objective_descriptors(descriptors: Array[TacticalObjectiveDescriptor]) -> void:
	objective_descriptors = descriptors
	_rebuild_objective_markers()

func set_enabled(value: bool) -> void:
	enabled = value
	carrier.control_enabled = not enabled
	if enabled:
		center_camera_on_carrier(false)
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		contact_marker_root.visible = true
		friendly_marker_root.visible = true
		grid_instance.visible = true
		order_path_root.visible = true
		objective_marker_root.visible = true
		selection_ring.visible = selected != null
		_set_hostile_visibility(false)
	else:
		context_wheel.close(false)
		carrier.chase_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		contact_marker_root.visible = false
		friendly_marker_root.visible = false
		grid_instance.visible = false
		order_path_root.visible = false
		objective_marker_root.visible = false
		selection_ring.visible = false
		_set_hostile_visibility(true)
	mode_changed.emit(enabled)

func _process(delta: float) -> void:
	if not enabled or not is_instance_valid(carrier):
		return
	if follow_carrier_focus:
		camera_focus_position = carrier.global_position
	var framing := _map_framing(camera_focus_position)
	var target: Vector3 = camera_focus_position
	distance_m = lerpf(distance_m, framing.distance * zoom_factor, 0.08)
	var direction := Vector3(cos(pitch) * sin(yaw), sin(-pitch), cos(pitch) * cos(yaw)).normalized()
	camera.global_position = target + direction * distance_m
	camera.look_at(target, Vector3.UP)
	grid_instance.global_position = Vector3(carrier.global_position.x, carrier.global_position.y - 18.0, carrier.global_position.z)
	marker_refresh_elapsed += delta
	if marker_refresh_elapsed >= 0.1:
		marker_refresh_elapsed = 0.0
		_update_contact_markers()
		_update_friendly_markers()
		_update_order_paths()
	_update_selection_ring()

func handle_input(event: InputEvent) -> bool:
	if not enabled:
		return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_open_context_wheel(event.position, event.shift_pressed)
			else:
				context_wheel.release_flick(event.position, event.shift_pressed)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and context_wheel.active:
			return context_wheel.click(event.position, event.shift_pressed)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_factor = maxf(0.35, zoom_factor * 0.86)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_factor = minf(2.5, zoom_factor * 1.16)
			return true
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			middle_dragging = event.pressed
			return true
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _select_near_screen_point(event.position):
				var contact := _contact_near_screen_point(event.position)
				if contact != null:
					if contact.is_targetable():
						target_lock_requested.emit(contact.tracked_entity_id)
					else:
						notification_requested.emit("Lock rejected: contact not identified")
			return true
	if event is InputEventMouseMotion:
		if context_wheel.active:
			context_wheel.update_pointer(event.position, event.shift_pressed)
			return true
		if middle_dragging:
			if event.shift_pressed:
				_pan_camera(event.relative)
			else:
				yaw -= event.relative.x * 0.006
				pitch = clampf(pitch - event.relative.y * 0.005, -1.35, -0.3)
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("tactical_center_carrier"):
			center_camera_on_carrier()
			return true
		for index in 4:
			if event.is_action_pressed("fleet_group_%d" % (index + 1)):
				if index < commandables.size() and is_instance_valid(commandables[index]):
					select_commandable(commandables[index])
				else:
					notification_requested.emit("Fleet group %d unavailable" % (index + 1))
				return true
		if event.is_action_pressed("command_stance"):
			_cycle_stance()
			return true
		if event.is_action_pressed("command_formation"):
			if selected != null and selected.has_method("cycle_formation"):
				selected.cycle_formation()
			return true
		if event.is_action_pressed("command_recall"):
			_issue_recall()
			return true
		if event.is_action_pressed("command_intercept"):
			_issue_best_contact_order(FleetOrder.OrderType.INTERCEPT, event.shift_pressed)
			return true
		if event.is_action_pressed("command_escort"):
			_issue_escort_carrier(event.shift_pressed)
			return true
		if event.is_action_pressed("command_hold"):
			_issue_position_order(FleetOrder.OrderType.HOLD, _selected_position(), event.shift_pressed)
			return true
		if event.is_action_pressed("command_withdraw"):
			_issue_position_order(FleetOrder.OrderType.WITHDRAW, carrier.global_position + carrier.global_transform.basis.z * 5000.0, event.shift_pressed)
			return true
	return false

func consume_escape() -> bool:
	if context_wheel != null and context_wheel.active:
		context_wheel.close(true)
		return true
	return false

func zoom_percent() -> int:
	return int(round(inverse_lerp(2.5, 0.35, zoom_factor) * 100.0))


func center_camera_on_carrier(announce: bool = true) -> void:
	if not is_instance_valid(carrier):
		return
	camera_focus_position = carrier.global_position
	follow_carrier_focus = true
	if announce:
		notification_requested.emit("Tactical camera centered on %s" % carrier.display_name)


func _pan_camera(relative: Vector2) -> void:
	var planar_right := Vector3(camera.global_transform.basis.x.x, 0.0, camera.global_transform.basis.x.z).normalized()
	var planar_up := Vector3(camera.global_transform.basis.y.x, 0.0, camera.global_transform.basis.y.z).normalized()
	if planar_right.length_squared() < 0.5:
		planar_right = Vector3.RIGHT
	if planar_up.length_squared() < 0.5:
		planar_up = Vector3.FORWARD
	var world_units_per_pixel := maxf(1.0, distance_m * 0.00135)
	camera_focus_position += (-planar_right * relative.x + planar_up * relative.y) * world_units_per_pixel
	camera_focus_position.y = carrier.global_position.y
	follow_carrier_focus = false

func select_commandable(node: Node) -> void:
	selected = node
	selection_changed.emit(_selected_name())
	_update_selection_ring()

func _select_near_screen_point(screen_point: Vector2) -> bool:
	var best: Node
	var best_distance := 48.0
	for candidate in commandables:
		if not is_instance_valid(candidate):
			continue
		var projected := camera.unproject_position(_node_position(candidate))
		var distance := projected.distance_to(screen_point)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	if best != null:
		select_commandable(best)
		return true
	return false

func _open_context_wheel(screen_point: Vector2, queued: bool) -> void:
	wheel_screen_position = screen_point
	wheel_world_position = _screen_to_command_plane(screen_point)
	wheel_contact_id = &""
	wheel_friendly_id = &""
	wheel_objective = _objective_near_screen_point(screen_point)
	var choices: Array[Dictionary] = []
	var caption := "COMMAND"
	if wheel_objective != null:
		caption = wheel_objective.label
		choices = [_choice(&"interact", wheel_objective.verb), _choice(&"hold", "Hold"), _choice(&"doctrine", "Doctrine")]
	else:
		var friendly := _commandable_near_screen_point(screen_point, selected)
		var contact := _contact_near_screen_point(screen_point)
		if is_instance_valid(friendly):
			wheel_friendly_id = friendly.stable_entity_id
			caption = friendly.display_name
			choices = [_choice(&"escort", "Escort"), _choice(&"hold", "Hold"), _choice(&"doctrine", "Doctrine")]
		elif contact != null:
			if not contact.is_targetable():
				notification_requested.emit("Command rejected: contact not identified")
				return
			wheel_contact_id = contact.tracked_entity_id
			caption = String(contact.classification).capitalize()
			if selected == carrier:
				choices = [_choice(&"lock", "Lock"), _choice(&"approach", "Approach"), _choice(&"orbit_menu", "Orbit"), _choice(&"keep_menu", "Keep"), _choice(&"doctrine", "Doctrine")]
			else:
				choices = [_choice(&"attack", "Attack"), _choice(&"intercept", "Intercept"), _choice(&"lock", "Lock"), _choice(&"doctrine", "Doctrine")]
		else:
			choices = [_choice(&"set_course" if selected == carrier else &"move", "Set Course" if selected == carrier else "Move"), _choice(&"hold", "Hold"), _choice(&"withdraw", "Withdraw"), _choice(&"doctrine", "Doctrine")]
	context_wheel.open_at(screen_point, choices, queued, caption.to_upper())

func _choice(id: StringName, label: String) -> Dictionary:
	return {"id": id, "label": label}

func _on_wheel_action_selected(action_id: StringName, queued: bool) -> void:
	match action_id:
		&"doctrine":
			context_wheel.open_at(wheel_screen_position, [
				_choice(&"stance_aggressive", "Aggressive"), _choice(&"stance_balanced", "Balanced"),
				_choice(&"stance_defensive", "Defensive"), _choice(&"stance_evade_return", "Evade/Return"),
				_choice(&"formation_menu", "Formation"), _choice(&"spacing_menu", "Spacing")
			], queued, "DOCTRINE")
		&"formation_menu":
			context_wheel.open_at(wheel_screen_position, [
				_choice(&"formation_wedge", "Wedge"), _choice(&"formation_line", "Line"),
				_choice(&"formation_screen", "Screen"), _choice(&"formation_column", "Column")
			], queued, "FORMATION")
		&"spacing_menu":
			context_wheel.open_at(wheel_screen_position, [
				_choice(&"spacing_tight", "Tight"), _choice(&"spacing_standard", "Standard"), _choice(&"spacing_wide", "Wide")
			], queued, "SPACING")
		&"stance_aggressive", &"stance_balanced", &"stance_defensive", &"stance_evade_return":
			if selected != null and selected.has_method("set_stance"):
				selected.set_stance(StringName(String(action_id).trim_prefix("stance_")))
		&"formation_wedge", &"formation_line", &"formation_screen", &"formation_column":
			if selected != null and selected.has_method("set_formation"):
				selected.set_formation(StringName(String(action_id).trim_prefix("formation_")))
		&"spacing_tight", &"spacing_standard", &"spacing_wide":
			if selected != null and selected.has_method("set_formation_spacing"):
				selected.set_formation_spacing(StringName(String(action_id).trim_prefix("spacing_")))
		&"set_course", &"move":
			_issue_position_order(FleetOrder.OrderType.MOVE, wheel_world_position, queued)
		&"hold":
			_issue_position_order(FleetOrder.OrderType.HOLD, _selected_position(), queued)
		&"withdraw":
			_issue_position_order(FleetOrder.OrderType.WITHDRAW, wheel_world_position, queued)
		&"attack":
			_issue_entity_order(FleetOrder.OrderType.ATTACK, wheel_contact_id, queued)
		&"intercept":
			_issue_entity_order(FleetOrder.OrderType.INTERCEPT, wheel_contact_id, queued)
		&"escort":
			var target_id := wheel_friendly_id if not wheel_friendly_id.is_empty() else carrier.stable_entity_id
			_issue_entity_order(FleetOrder.OrderType.ESCORT, target_id, queued)
		&"interact":
			_issue_objective_order(wheel_objective, queued)
		&"lock":
			target_lock_requested.emit(wheel_contact_id)
		&"approach":
			carrier_navigation_requested.emit(&"approach", wheel_contact_id, 500.0)
		&"orbit_menu":
			context_wheel.open_at(wheel_screen_position, [
				_choice(&"orbit_500", "500 M"), _choice(&"orbit_5000", "5 KM"),
				_choice(&"orbit_10000", "10 KM"), _choice(&"orbit_25000", "25 KM")
			], queued, "ORBIT")
		&"keep_menu":
			context_wheel.open_at(wheel_screen_position, [
				_choice(&"keep_500", "500 M"), _choice(&"keep_5000", "5 KM"),
				_choice(&"keep_10000", "10 KM"), _choice(&"keep_25000", "25 KM")
			], queued, "KEEP")
		&"orbit_500", &"orbit_5000", &"orbit_10000", &"orbit_25000":
			carrier_navigation_requested.emit(&"orbit", wheel_contact_id, _distance_from_action(action_id))
		&"keep_500", &"keep_5000", &"keep_10000", &"keep_25000":
			carrier_navigation_requested.emit(&"keep_distance", wheel_contact_id, _distance_from_action(action_id))

func _distance_from_action(action_id: StringName) -> float:
	var token := String(action_id).get_slice("_", 1)
	return float(token)

func _on_wheel_cancelled() -> void:
	wheel_cancelled.emit()

func _issue_objective_order(objective: TacticalObjectiveDescriptor, queued: bool) -> void:
	if objective == null:
		return
	if selected == carrier:
		carrier.set_autopilot(objective.position)
		notification_requested.emit("Carrier course set — %s" % objective.verb.to_upper())
		return
	var order := objective.to_order(_now_seconds(), queued)
	_submit_selected_order(order)

func _issue_context_order(screen_point: Vector2, queued: bool) -> void:
	if selected == null:
		return
	var contact := _contact_near_screen_point(screen_point)
	if contact != null:
		if not contact.is_targetable():
			notification_requested.emit("Attack rejected: contact not identified")
			return
		_issue_entity_order(FleetOrder.OrderType.ATTACK, contact.tracked_entity_id, queued)
		return
	var world_point := _screen_to_command_plane(screen_point)
	_issue_position_order(FleetOrder.OrderType.MOVE, world_point, queued)

func _issue_position_order(order_type: FleetOrder.OrderType, position_value: Vector3, queued: bool) -> void:
	var order := FleetOrder.at_position(order_type, position_value, _now_seconds(), queued)
	if selected is PlayerCarrier:
		if order_type == FleetOrder.OrderType.HOLD:
			selected.clear_target_navigation()
			selected.autopilot_active = false
			selected.set_throttle(0.0)
			notification_requested.emit("Carrier holding position")
		else:
			selected.set_autopilot(position_value)
			notification_requested.emit("Carrier autopilot destination set")
		return
	_submit_selected_order(order)

func _issue_entity_order(order_type: FleetOrder.OrderType, entity_id: StringName, queued: bool) -> void:
	var order := FleetOrder.at_entity(order_type, entity_id, _now_seconds(), queued)
	var contact := sensors.get_contact(entity_id)
	if contact != null:
		order.target_position = contact.estimated_position
		order.target_velocity = contact.estimated_velocity
	_submit_selected_order(order)

func _submit_selected_order(order: FleetOrder) -> void:
	if selected == null or not selected.has_method("issue_order"):
		return
	if bool(selected.issue_order(order)):
		command_issued.emit(StringName(selected.stable_entity_id), order)

func _issue_recall() -> void:
	if selected is SidebaySquadron:
		selected.request_recall()
	else:
		notification_requested.emit("Recall applies to a launched squadron")

func _issue_best_contact_order(order_type: FleetOrder.OrderType, queued: bool) -> void:
	var best: SensorContact
	var best_distance := INF
	for contact in sensors.targetable_contacts():
		var distance := _selected_position().distance_to(contact.estimated_position)
		if distance < best_distance:
			best = contact
			best_distance = distance
	if best == null:
		notification_requested.emit("Intercept rejected: no identified contact")
		return
	_issue_entity_order(order_type, best.tracked_entity_id, queued)

func _issue_escort_carrier(queued: bool) -> void:
	if selected == carrier:
		notification_requested.emit("Carrier cannot escort itself")
		return
	_issue_entity_order(FleetOrder.OrderType.ESCORT, carrier.stable_entity_id, queued)

func _cycle_stance() -> void:
	if selected == null or not selected.has_method("set_stance"):
		return
	var stances: Array[StringName] = [&"aggressive", &"balanced", &"defensive", &"evade_return"]
	var current: StringName = selected.stance
	selected.set_stance(stances[(stances.find(current) + 1) % stances.size()])

func _contact_near_screen_point(screen_point: Vector2) -> SensorContact:
	var best: SensorContact
	var best_distance := 44.0
	for contact in sensors.contacts.values():
		if contact.confidence <= 0.05 or camera.is_position_behind(contact.estimated_position):
			continue
		var distance := camera.unproject_position(contact.estimated_position).distance_to(screen_point)
		if distance < best_distance:
			best = contact
			best_distance = distance
	return best

func _commandable_near_screen_point(screen_point: Vector2, excluded: Node = null) -> Node:
	var best: Node
	var best_distance := 44.0
	for candidate in commandables:
		if not is_instance_valid(candidate) or candidate == excluded or camera.is_position_behind(_node_position(candidate)):
			continue
		var distance := camera.unproject_position(_node_position(candidate)).distance_to(screen_point)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _objective_near_screen_point(screen_point: Vector2) -> TacticalObjectiveDescriptor:
	var best: TacticalObjectiveDescriptor
	var best_distance := 52.0
	for objective in objective_descriptors:
		if objective.completed or camera.is_position_behind(objective.position):
			continue
		var distance := camera.unproject_position(objective.position).distance_to(screen_point)
		if distance < best_distance:
			best = objective
			best_distance = distance
	return best

func _screen_to_command_plane(screen_point: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var plane := Plane(Vector3.UP, carrier.global_position.y)
	var intersection = plane.intersects_ray(origin, direction)
	return intersection if intersection != null else carrier.global_position

func _update_contact_markers() -> void:
	var live_ids: Dictionary = {}
	for contact in sensors.contacts.values():
		if contact.confidence <= 0.02:
			continue
		live_ids[contact.contact_id] = true
		var marker := contact_marker_root.get_node_or_null(String(contact.contact_id)) as MeshInstance3D
		if marker == null:
			marker = _create_contact_marker(contact)
		marker.global_position = contact.estimated_position
		var size := clampf(contact.uncertainty_radius_m / 45.0, 6.0, 48.0)
		marker.scale = Vector3.ONE * size
		var silhouette := marker.get_node_or_null("ClassSilhouette") as MeshInstance3D
		if silhouette != null:
			silhouette.scale = Vector3.ONE / size * (2.0 if contact.classification == &"fighter_group" else 3.2)
		var label := marker.get_node_or_null("ContactLabel") as Label3D
		if label != null:
			label.scale = Vector3.ONE / size
			label.text = "%s  %d%%  ±%.0fM" % [String(contact.classification).to_upper(), contact.confidence * 100.0, contact.uncertainty_radius_m]
			label.modulate = Color(1.0, 0.56, 0.15) if contact.is_targetable() else Color(0.65, 0.38, 0.2)
	for child in contact_marker_root.get_children():
		if not live_ids.has(StringName(child.name)):
			child.queue_free()

func _create_contact_marker(contact: SensorContact) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = String(contact.contact_id)
	var mesh := SphereMesh.new()
	mesh.radius = 10.0
	mesh.height = 20.0
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.2, 0.1, 0.2 if contact.is_targetable() else 0.1)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.1, 0.05)
	marker.material_override = material
	var silhouette := MeshInstance3D.new()
	silhouette.name = "ClassSilhouette"
	if contact.classification == &"fighter_group":
		var fighter_mesh := PrismMesh.new()
		fighter_mesh.size = Vector3(20.0, 5.0, 28.0)
		silhouette.mesh = fighter_mesh
	elif String(contact.classification).contains("command") or String(contact.classification).contains("carrier"):
		var command_mesh := BoxMesh.new()
		command_mesh.size = Vector3(18.0, 8.0, 42.0)
		silhouette.mesh = command_mesh
	else:
		var escort_mesh := CylinderMesh.new()
		escort_mesh.top_radius = 7.0
		escort_mesh.bottom_radius = 11.0
		escort_mesh.height = 28.0
		silhouette.mesh = escort_mesh
	var silhouette_material := StandardMaterial3D.new()
	silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silhouette_material.albedo_color = Color(1.0, 0.24, 0.12, 0.95)
	silhouette_material.emission_enabled = true
	silhouette_material.emission = Color(1.0, 0.08, 0.03) * 1.8
	silhouette.material_override = silhouette_material
	marker.add_child(silhouette)
	var label := Label3D.new()
	label.name = "ContactLabel"
	label.position = Vector3(0.0, 18.0, 0.0)
	label.font_size = 20
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	marker.add_child(label)
	contact_marker_root.add_child(marker)
	return marker

func _update_friendly_markers() -> void:
	for candidate in commandables:
		if not is_instance_valid(candidate):
			continue
		var marker_name := "friendly_%s" % String(candidate.stable_entity_id)
		var marker := friendly_marker_root.get_node_or_null(marker_name) as MeshInstance3D
		if marker == null:
			marker = MeshInstance3D.new()
			marker.name = marker_name
			var mesh := CylinderMesh.new()
			mesh.top_radius = 14.0
			mesh.bottom_radius = 14.0
			mesh.height = 5.0
			marker.mesh = mesh
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color(0.1, 0.75, 1.0)
			material.emission_enabled = true
			material.emission = Color(0.05, 0.55, 1.0) * 2.5
			marker.material_override = material
			friendly_marker_root.add_child(marker)
		marker.global_position = _node_position(candidate) + Vector3.UP * 22.0
		var marker_scale := 7.0 if candidate is PlayerCarrier else 5.0
		marker.scale = Vector3.ONE * marker_scale

func _create_selection_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "FleetSelectionRing"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 42.0
	mesh.outer_radius = 48.0
	mesh.rings = 32
	mesh.ring_segments = 8
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.58, 0.12, 0.82)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.34, 0.05) * 2.4
	ring.material_override = material
	return ring

func _update_selection_ring() -> void:
	if selection_ring == null:
		return
	selection_ring.visible = enabled and is_instance_valid(selected)
	if not selection_ring.visible:
		return
	selection_ring.global_position = _selected_position() + Vector3.UP * 12.0
	var scale_value := 2.2 if selected is PlayerCarrier else (1.45 if selected is CombatShip else 1.0)
	selection_ring.scale = Vector3.ONE * scale_value

func _rebuild_objective_markers() -> void:
	if objective_marker_root == null:
		return
	for child in objective_marker_root.get_children():
		child.queue_free()
	for objective in objective_descriptors:
		var marker := MeshInstance3D.new()
		marker.name = String(objective.objective_id)
		var mesh := CylinderMesh.new()
		mesh.top_radius = objective.radius_m
		mesh.bottom_radius = objective.radius_m
		mesh.height = 8.0
		marker.mesh = mesh
		objective_marker_root.add_child(marker)
		marker.global_position = objective.position
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.55, 0.24, 0.92, 0.10)
		material.emission_enabled = true
		material.emission = Color(0.45, 0.16, 0.82) * 1.5
		marker.material_override = material
		var label := Label3D.new()
		label.text = "%s  //  %s" % [objective.label.to_upper(), objective.verb.to_upper()]
		label.font_size = 28
		label.outline_size = 9
		label.position = Vector3(0.0, 34.0, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(0.82, 0.58, 1.0)
		marker.add_child(label)

func _update_order_paths() -> void:
	if order_path_root == null:
		return
	var live_names: Dictionary = {}
	for candidate in commandables:
		if not is_instance_valid(candidate) or not "fleet_command" in candidate:
			continue
		var path_name := "path_%s" % String(candidate.stable_entity_id)
		live_names[path_name] = true
		var path := order_path_root.get_node_or_null(path_name) as MeshInstance3D
		if path == null:
			path = _create_order_path(path_name)
		var points: Array[Vector3] = [_node_position(candidate)]
		var waypoint_labels: Array[String] = []
		if candidate is PlayerCarrier:
			if candidate.target_navigation_mode != PlayerCarrier.TargetNavigationMode.NONE and is_instance_valid(candidate.target_navigation_target):
				points.append(candidate.target_navigation_target.global_position)
				waypoint_labels.append("1  %s  %.0fM" % [PlayerCarrier.TargetNavigationMode.keys()[candidate.target_navigation_mode], candidate.target_navigation_distance_m])
			elif candidate.autopilot_active:
				points.append(candidate.autopilot_destination)
				waypoint_labels.append("1  SET COURSE")
		var orders: Array[FleetOrder] = candidate.fleet_command.all_orders()
		var accumulated_distance := 0.0
		var last_position := points[-1]
		for order in orders:
			var order_position := _order_target_position(order)
			accumulated_distance += last_position.distance_to(order_position)
			points.append(_order_target_position(order))
			var speed := _group_max_speed(candidate)
			var status_suffix := order.status_label().to_upper()
			if order.status == FleetOrder.Status.TRANSMITTING:
				status_suffix += " %.1fs" % maxf(0.0, order.activation_time_seconds - _now_seconds())
			waypoint_labels.append("%d  %s  %s  ETA %.0fs" % [waypoint_labels.size() + 1, order.type_label().to_upper(), status_suffix, accumulated_distance / speed])
			last_position = order_position
		_update_path_mesh(path, points, candidate == selected, waypoint_labels)
	for child in order_path_root.get_children():
		if not live_names.has(child.name):
			child.queue_free()

func _create_order_path(path_name: String) -> MeshInstance3D:
	var path := MeshInstance3D.new()
	path.name = path_name
	path.mesh = ImmediateMesh.new()
	order_path_root.add_child(path)
	return path

func _update_path_mesh(path: MeshInstance3D, points: Array[Vector3], highlighted: bool, waypoint_labels: Array[String]) -> void:
	var mesh := path.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if points.size() < 2:
		for child in path.get_children():
			child.visible = false
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.58, 0.12, 0.9) if highlighted else Color(0.08, 0.65, 0.9, 0.54)
	material.emission_enabled = true
	material.emission = material.albedo_color
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(points.size() - 1):
		mesh.surface_add_vertex(points[index])
		mesh.surface_add_vertex(points[index + 1])
	mesh.surface_end()
	for index in range(1, points.size()):
		var label_name := "Waypoint%d" % index
		var label := path.get_node_or_null(label_name) as Label3D
		if label == null:
			label = Label3D.new()
			label.name = label_name
			label.font_size = 20
			label.outline_size = 7
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			path.add_child(label)
		label.position = points[index] + Vector3.UP * 24.0
		label.text = waypoint_labels[index - 1] if index - 1 < waypoint_labels.size() else "%d" % index
		label.modulate = material.albedo_color
		label.visible = true
	for child in path.get_children():
		if child is Label3D and int(String(child.name).trim_prefix("Waypoint")) >= points.size():
			child.visible = false


func _group_max_speed(candidate: Node) -> float:
	if candidate is CombatShip and candidate.definition != null:
		return maxf(1.0, candidate.definition.maximum_speed_mps)
	if candidate is SidebaySquadron and candidate.definition != null and candidate.definition.craft_definition != null:
		return maxf(1.0, candidate.definition.craft_definition.maximum_speed_mps)
	return 250.0

func _order_target_position(order: FleetOrder) -> Vector3:
	if not order.target_entity_id.is_empty():
		var contact := sensors.get_contact(order.target_entity_id)
		if contact != null:
			return contact.estimated_position
		var target := sensors.resolve_combat_target(order.target_entity_id)
		if is_instance_valid(target):
			return target.global_position
	return order.target_position

func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _create_grid() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "TacticalGrid"
	var mesh := ImmediateMesh.new()
	var minor_material := _grid_material(Color(0.035, 0.22, 0.36, 0.24), Color(0.01, 0.09, 0.17))
	var major_material := _grid_material(Color(0.07, 0.48, 0.68, 0.48), Color(0.02, 0.22, 0.38))
	var origin_material := _grid_material(Color(1.0, 0.58, 0.12, 0.82), Color(0.65, 0.22, 0.02))
	var grid_steps := int(GRID_EXTENT_M / GRID_MINOR_STEP_M)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, minor_material)
	for index in range(-grid_steps, grid_steps + 1):
		var axis := float(index) * GRID_MINOR_STEP_M
		if is_zero_approx(fmod(absf(axis), GRID_MAJOR_STEP_M)):
			continue
		mesh.surface_add_vertex(Vector3(axis, 0.0, -GRID_EXTENT_M))
		mesh.surface_add_vertex(Vector3(axis, 0.0, GRID_EXTENT_M))
		mesh.surface_add_vertex(Vector3(-GRID_EXTENT_M, 0.0, axis))
		mesh.surface_add_vertex(Vector3(GRID_EXTENT_M, 0.0, axis))
	mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, major_material)
	var major_steps := int(GRID_EXTENT_M / GRID_MAJOR_STEP_M)
	for index in range(-major_steps, major_steps + 1):
		var axis := float(index) * GRID_MAJOR_STEP_M
		mesh.surface_add_vertex(Vector3(axis, 0.0, -GRID_EXTENT_M))
		mesh.surface_add_vertex(Vector3(axis, 0.0, GRID_EXTENT_M))
		mesh.surface_add_vertex(Vector3(-GRID_EXTENT_M, 0.0, axis))
		mesh.surface_add_vertex(Vector3(GRID_EXTENT_M, 0.0, axis))
	for radius in [5000.0, 10000.0, 20000.0, 40000.0]:
		for segment in 96:
			var angle_a := TAU * float(segment) / 96.0
			var angle_b := TAU * float(segment + 1) / 96.0
			mesh.surface_add_vertex(Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius))
			mesh.surface_add_vertex(Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius))
	mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, origin_material)
	mesh.surface_add_vertex(Vector3(-700.0, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(700.0, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(0.0, 0.0, -700.0))
	mesh.surface_add_vertex(Vector3(0.0, 0.0, 700.0))
	for segment in 48:
		var angle_a := TAU * float(segment) / 48.0
		var angle_b := TAU * float(segment + 1) / 48.0
		mesh.surface_add_vertex(Vector3(cos(angle_a) * 420.0, 0.0, sin(angle_a) * 420.0))
		mesh.surface_add_vertex(Vector3(cos(angle_b) * 420.0, 0.0, sin(angle_b) * 420.0))
	mesh.surface_end()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _grid_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	return material


func _map_framing(reference_center: Vector3 = Vector3.ZERO) -> Dictionary:
	var positions: Array[Vector3] = [carrier.global_position]
	for contact in sensors.contacts.values():
		if contact.confidence > 0.05:
			positions.append(contact.estimated_position)
	for candidate in commandables:
		if is_instance_valid(candidate):
			positions.append(_node_position(candidate))
	var center := reference_center if reference_center != Vector3.ZERO else carrier.global_position
	var radius := 1000.0
	for position_value in positions:
		radius = maxf(radius, position_value.distance_to(center))
	return {"center": center, "distance": clampf(radius * 1.45, 4200.0, 24000.0)}

func _draw_order_line(from: Vector3, to: Vector3, color: Color) -> void:
	var line := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	line.mesh = mesh
	var scene_owner: Node = carrier.get_parent() if carrier.get_parent() != null else get_tree().root
	scene_owner.add_child(line)
	var tween := line.create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(line.queue_free)

func _node_position(node: Node) -> Vector3:
	if node is SidebaySquadron:
		return node.representative_position()
	if node is Node3D:
		return node.global_position
	return Vector3.ZERO

func _selected_position() -> Vector3:
	return _node_position(selected) if selected != null else carrier.global_position

func _selected_name() -> String:
	if selected == null:
		return "None"
	return selected.display_name if "display_name" in selected else selected.name

func _set_hostile_visibility(make_visible: bool) -> void:
	for candidate in get_tree().get_nodes_in_group("team_hostile"):
		if not candidate is Node3D:
			continue
		if make_visible:
			if hidden_hostiles.has(candidate.get_instance_id()):
				candidate.visible = hidden_hostiles[candidate.get_instance_id()]
		else:
			hidden_hostiles[candidate.get_instance_id()] = candidate.visible
			candidate.visible = false
	if make_visible:
		hidden_hostiles.clear()
