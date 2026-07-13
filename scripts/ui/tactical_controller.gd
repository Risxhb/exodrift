class_name TacticalController
extends Node

signal mode_changed(enabled: bool)
signal notification_requested(message: String)
signal selection_changed(name: String)
signal target_lock_requested(entity_id: StringName)
signal context_menu_requested(screen_position: Vector2, entity_id: StringName)

var enabled: bool = false
var carrier: PlayerCarrier
var sensors: SidebaySensorSystem
var camera: Camera3D
var selected: Node
var commandables: Array[Node] = []
var contact_marker_root: Node3D
var friendly_marker_root: Node3D
var grid_instance: MeshInstance3D
var yaw: float = 0.35
var pitch: float = -0.95
var distance_m: float = 4200.0
var zoom_factor: float = 1.0
var middle_dragging: bool = false
var hidden_hostiles: Dictionary = {}

func configure(player_carrier: PlayerCarrier, sensor_system: SidebaySensorSystem, friendly_commandables: Array[Node]) -> void:
	carrier = player_carrier
	sensors = sensor_system
	commandables = friendly_commandables
	camera = Camera3D.new()
	camera.name = "TacticalCamera"
	camera.fov = 58.0
	camera.near = 5.0
	camera.far = 40000.0
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
	if not commandables.is_empty():
		select_commandable(commandables[0])

func set_enabled(value: bool) -> void:
	enabled = value
	carrier.control_enabled = not enabled
	if enabled:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		contact_marker_root.visible = true
		friendly_marker_root.visible = true
		grid_instance.visible = true
		_set_hostile_visibility(false)
	else:
		carrier.chase_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		contact_marker_root.visible = false
		friendly_marker_root.visible = false
		grid_instance.visible = false
		_set_hostile_visibility(true)
	mode_changed.emit(enabled)

func _process(_delta: float) -> void:
	if not enabled or not is_instance_valid(carrier):
		return
	var framing := _map_framing()
	var target: Vector3 = framing.center
	distance_m = lerpf(distance_m, framing.distance * zoom_factor, 0.08)
	var direction := Vector3(cos(pitch) * sin(yaw), sin(-pitch), cos(pitch) * cos(yaw)).normalized()
	camera.global_position = target + direction * distance_m
	camera.look_at(target, Vector3.UP)
	grid_instance.global_position = Vector3(carrier.global_position.x, carrier.global_position.y - 80.0, carrier.global_position.z)
	_update_contact_markers()
	_update_friendly_markers()

func handle_input(event: InputEvent) -> bool:
	if not enabled:
		return false
	if event is InputEventMouseButton:
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
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var contact := _contact_near_screen_point(event.position)
			if selected == carrier and contact != null:
				if contact.is_targetable():
					context_menu_requested.emit(event.position, contact.tracked_entity_id)
				else:
					notification_requested.emit("Navigation rejected: contact not identified")
			else:
				_issue_context_order(event.position, event.shift_pressed)
			return true
	if event is InputEventMouseMotion and middle_dragging:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch - event.relative.y * 0.005, -1.35, -0.3)
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1, KEY_F2, KEY_F3, KEY_F4:
				var index := int(event.keycode - KEY_F1)
				if index < commandables.size():
					select_commandable(commandables[index])
				return true
			KEY_Q:
				_cycle_stance()
				return true
			KEY_F:
				if selected != null and selected.has_method("cycle_formation"):
					selected.cycle_formation()
				return true
			KEY_R:
				_issue_recall()
				return true
			KEY_I:
				_issue_best_contact_order(FleetOrder.OrderType.INTERCEPT, event.shift_pressed)
				return true
			KEY_E:
				_issue_escort_carrier(event.shift_pressed)
				return true
			KEY_H:
				_issue_position_order(FleetOrder.OrderType.HOLD, _selected_position(), event.shift_pressed)
				return true
			KEY_X:
				_issue_position_order(FleetOrder.OrderType.WITHDRAW, carrier.global_position + carrier.global_transform.basis.z * 5000.0, event.shift_pressed)
				return true
	return false

func zoom_percent() -> int:
	return int(round(inverse_lerp(2.5, 0.35, zoom_factor) * 100.0))

func select_commandable(node: Node) -> void:
	selected = node
	selection_changed.emit(_selected_name())

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
	var order := FleetOrder.at_position(order_type, position_value, Time.get_ticks_msec() / 1000.0, queued)
	if selected is PlayerCarrier:
		selected.set_autopilot(position_value)
		notification_requested.emit("Carrier autopilot destination set")
	elif selected.has_method("issue_order"):
		selected.issue_order(order)
	_draw_order_line(_selected_position(), position_value, Color(0.2, 0.85, 1.0))

func _issue_entity_order(order_type: FleetOrder.OrderType, entity_id: StringName, queued: bool) -> void:
	var order := FleetOrder.at_entity(order_type, entity_id, Time.get_ticks_msec() / 1000.0, queued)
	if selected.has_method("issue_order"):
		selected.issue_order(order)
	var target := sensors.resolve_combat_target(entity_id)
	if is_instance_valid(target):
		_draw_order_line(_selected_position(), target.global_position, Color(1.0, 0.25, 0.12))

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

func _screen_to_command_plane(screen_point: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var plane := Plane(Vector3.UP, carrier.global_position.y)
	var intersection = plane.intersects_ray(origin, direction)
	return intersection if intersection != null else carrier.global_position

func flak_placement_world_point(screen_point: Vector2, range_m: float) -> Vector3:
	var plane_point := _screen_to_command_plane(screen_point)
	var direction := plane_point - carrier.global_position
	if direction.length_squared() < 1.0:
		direction = -carrier.global_transform.basis.z.normalized()
	return carrier.global_position + direction.normalized() * range_m

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
		marker.scale = Vector3.ONE * (7.0 if candidate is PlayerCarrier else 5.0)

func _create_grid() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "TacticalGrid"
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.05, 0.28, 0.46, 0.42)
	material.emission_enabled = true
	material.emission = Color(0.02, 0.14, 0.28)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(-7, 8):
		var axis := float(index) * 1000.0
		mesh.surface_add_vertex(Vector3(axis, 0.0, -7000.0))
		mesh.surface_add_vertex(Vector3(axis, 0.0, 7000.0))
		mesh.surface_add_vertex(Vector3(-7000.0, 0.0, axis))
		mesh.surface_add_vertex(Vector3(7000.0, 0.0, axis))
	mesh.surface_end()
	instance.mesh = mesh
	return instance

func _map_framing() -> Dictionary:
	var positions: Array[Vector3] = [carrier.global_position]
	for contact in sensors.contacts.values():
		if contact.confidence > 0.05:
			positions.append(contact.estimated_position)
	for candidate in commandables:
		if is_instance_valid(candidate):
			positions.append(_node_position(candidate))
	var center := Vector3.ZERO
	for position_value in positions:
		center += position_value
	center /= float(positions.size())
	var radius := 1000.0
	for position_value in positions:
		radius = maxf(radius, position_value.distance_to(center))
	return {"center": center, "distance": clampf(radius * 1.45, 4200.0, 15000.0)}

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
