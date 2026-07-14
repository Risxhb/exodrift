class_name ExodriftCICOverlay
extends Control

const CYAN := Color(0.12, 0.82, 1.0, 0.88)
const AMBER := Color(1.0, 0.58, 0.12, 0.94)
const RED := Color(1.0, 0.18, 0.10, 0.96)

var carrier: PlayerCarrier
var tactical: TacticalController
var commandables: Array[Node] = []
var refresh_elapsed: float = 0.0
var recent_hits: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -1

func configure(player_carrier: PlayerCarrier, tactical_controller: TacticalController, fleet_groups: Array[Node]) -> void:
	carrier = player_carrier
	tactical = tactical_controller
	commandables = fleet_groups
	if is_instance_valid(carrier) and not carrier.damage_resolved.is_connected(_on_carrier_damage_resolved):
		carrier.damage_resolved.connect(_on_carrier_damage_resolved)
	queue_redraw()

func _process(delta: float) -> void:
	refresh_elapsed += delta
	for index in range(recent_hits.size() - 1, -1, -1):
		recent_hits[index].age = float(recent_hits[index].age) + delta
		if float(recent_hits[index].age) > 1.5:
			recent_hits.remove_at(index)
	if refresh_elapsed >= 0.08:
		refresh_elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(carrier) or not is_instance_valid(tactical):
		return
	var view_camera := tactical.camera if tactical.enabled else carrier.chase_camera
	if not is_instance_valid(view_camera):
		return
	if tactical.enabled:
		_draw_contacts(view_camera)
	_draw_fleet_groups(view_camera)
	_draw_ordnance(view_camera)
	_draw_damage_cues(view_camera)

func _draw_fleet_groups(view_camera: Camera3D) -> void:
	var occupied: Array[Rect2] = []
	var prioritized: Array[Node] = []
	if is_instance_valid(tactical.selected) and commandables.has(tactical.selected):
		prioritized.append(tactical.selected)
	for group in commandables:
		if is_instance_valid(group) and not prioritized.has(group):
			prioritized.append(group)
	for candidate in prioritized:
		if not is_instance_valid(candidate) or (candidate == carrier and not tactical.enabled):
			continue
		var world_position := _node_position(candidate)
		if view_camera.is_position_behind(world_position):
			continue
		var screen := view_camera.unproject_position(world_position)
		if not get_rect().grow(-20.0).has_point(screen):
			continue
		var snapshot: Dictionary = candidate.command_snapshot() if candidate.has_method("command_snapshot") else {}
		var current: Dictionary = snapshot.get("current_order", {})
		var selected := candidate == tactical.selected
		var color := AMBER if selected else CYAN
		var span := 28.0 if selected else 21.0
		_draw_brackets(screen, span, color, 2.0 if selected else 1.0)
		_draw_motion_vectors(view_camera, candidate, world_position, screen, color)
		var label_rect := _place_fleet_label(screen, Vector2(330.0, 58.0 if selected else 46.0), occupied)
		draw_line(screen + Vector2(span, 0.0), label_rect.position + Vector2(0.0, 13.0), Color(color, 0.42), 1.0)
		draw_rect(label_rect, Color(0.002, 0.018, 0.029, 0.76 if selected else 0.58), true)
		draw_line(label_rect.position, label_rect.position + Vector2(0.0, label_rect.size.y), color, 2.0 if selected else 1.0)
		var order_text := String(current.get("type", "Hold")).to_upper()
		var status_text := String(current.get("status", "Active")).to_upper()
		var link := String(snapshot.get("link", "Local")).to_upper()
		var label := "%s  //  %s %s  //  %s" % [String(snapshot.get("display_name", candidate.name)).to_upper(), status_text, order_text, link]
		_draw_label(label_rect.position + Vector2(7.0, 14.0), label, color, 10)
		var health: Dictionary = snapshot.get("health", {})
		_draw_layer_bar(label_rect.position + Vector2(7.0, label_rect.size.y - 7.0), 116.0, float(health.get("shields", 0.0)), float(health.get("armor", 0.0)), float(health.get("hull", 0.0)))
		if selected:
			var doctrine := "%s / %s / %s" % [String(snapshot.get("stance", "balanced")).to_upper(), String(snapshot.get("formation", "wedge")).to_upper(), String(snapshot.get("spacing", "standard")).to_upper()]
			_draw_label(label_rect.position + Vector2(7.0, 29.0), doctrine, color, 9)
			var ammunition := int(snapshot.get("ammunition", -1))
			var endurance := float(snapshot.get("endurance_seconds", -1.0))
			var telemetry := "AMMO %s  END %s" % ["--" if ammunition < 0 else str(ammunition), "--" if endurance < 0.0 else "%.0fs" % endurance]
			_draw_label(label_rect.position + Vector2(132.0, label_rect.size.y - 4.0), telemetry, color, 9)
			_draw_selected_envelopes(view_camera, candidate, world_position, screen)
		else:
			var brief_ammo := int(snapshot.get("ammunition", -1))
			var brief_endurance := float(snapshot.get("endurance_seconds", -1.0))
			var brief := "%s  AM %s  END %s" % [String(snapshot.get("formation", "wedge")).to_upper(), "--" if brief_ammo < 0 else str(brief_ammo), "--" if brief_endurance < 0.0 else "%.0fs" % brief_endurance]
			_draw_label(label_rect.position + Vector2(7.0, 29.0), brief, Color(color, 0.72), 8)


func _place_fleet_label(anchor: Vector2, label_size: Vector2, occupied: Array[Rect2]) -> Rect2:
	var viewport_rect := get_rect().grow(-18.0)
	viewport_rect.size.y = maxf(1.0, viewport_rect.size.y - 58.0)
	var x := anchor.x + 42.0
	if x + label_size.x > viewport_rect.end.x:
		x = anchor.x - label_size.x - 42.0
	var candidate := Rect2(Vector2(clampf(x, viewport_rect.position.x, viewport_rect.end.x - label_size.x), anchor.y - label_size.y * 0.5), label_size)
	for _attempt in 8:
		var collision := false
		for used in occupied:
			if candidate.grow(3.0).intersects(used):
				collision = true
				break
		if not collision:
			break
		candidate.position.y += label_size.y + 5.0
	if candidate.end.y > viewport_rect.end.y:
		candidate.position.y = anchor.y - label_size.y - 34.0
		for _attempt in 8:
			var collision := false
			for used in occupied:
				if candidate.grow(3.0).intersects(used):
					collision = true
					break
			if not collision:
				break
			candidate.position.y -= label_size.y + 5.0
	candidate.position.y = clampf(candidate.position.y, viewport_rect.position.y, viewport_rect.end.y - label_size.y)
	occupied.append(candidate)
	return candidate


func _draw_contacts(view_camera: Camera3D) -> void:
	if not is_instance_valid(tactical.sensors):
		return
	var contacts: Array = tactical.sensors.contacts.values()
	contacts.sort_custom(func(a: SensorContact, b: SensorContact) -> bool: return a.confidence > b.confidence)
	for index in mini(16, contacts.size()):
		var contact: SensorContact = contacts[index]
		if contact.confidence <= 0.02 or view_camera.is_position_behind(contact.estimated_position):
			continue
		var screen := view_camera.unproject_position(contact.estimated_position)
		if not get_rect().grow(-18.0).has_point(screen):
			continue
		var color := RED if contact.is_targetable() else Color(1.0, 0.38, 0.12, 0.5)
		var uncertainty_edge := contact.estimated_position + view_camera.global_transform.basis.x.normalized() * contact.uncertainty_radius_m
		var uncertainty_radius := screen.distance_to(view_camera.unproject_position(uncertainty_edge))
		draw_arc(screen, clampf(uncertainty_radius, 5.0, 90.0), 0.0, TAU, 28, Color(color, 0.18), 1.0)
		var velocity_tip := contact.estimated_position + contact.estimated_velocity * 2.0
		if not view_camera.is_position_behind(velocity_tip):
			draw_line(screen, view_camera.unproject_position(velocity_tip), Color(color, 0.65), 1.0)


func _draw_motion_vectors(view_camera: Camera3D, candidate: Node, world_position: Vector3, screen: Vector2, color: Color) -> void:
	var velocity: Vector3 = Vector3.ZERO
	if candidate is SidebaySquadron:
		velocity = candidate.representative_velocity()
	elif candidate is CharacterBody3D:
		velocity = candidate.velocity
	var facing: Vector3 = velocity.normalized()
	if candidate is Node3D and not candidate is SidebaySquadron:
		facing = -candidate.global_transform.basis.z.normalized()
	if velocity.length_squared() > 1.0:
		var velocity_tip: Vector3 = world_position + velocity * 2.0
		if not view_camera.is_position_behind(velocity_tip):
			draw_line(screen, view_camera.unproject_position(velocity_tip), Color(color, 0.58), 1.5)
	if facing.length_squared() > 0.5:
		var facing_tip: Vector3 = world_position + facing * 160.0
		if not view_camera.is_position_behind(facing_tip):
			draw_line(screen, view_camera.unproject_position(facing_tip), color, 2.0)


func _draw_selected_envelopes(view_camera: Camera3D, candidate: Node, world_position: Vector3, screen: Vector2) -> void:
	if not tactical.enabled:
		return
	var weapon_range := 0.0
	var footprint := 0.0
	if candidate is CombatShip and candidate.definition != null:
		if not candidate.definition.weapons.is_empty():
			weapon_range = candidate.definition.weapons[0].range_m
		footprint = candidate.collision_radius_m * 2.2
	elif candidate is SidebaySquadron and candidate.definition != null:
		if candidate.definition.craft_definition != null and not candidate.definition.craft_definition.weapons.is_empty():
			weapon_range = candidate.definition.craft_definition.weapons[0].range_m
		footprint = candidate.formation_spacing_m * candidate.fleet_command.spacing_multiplier() * maxf(1.0, candidate.living_craft_count() * 0.5)
	for envelope in [{"radius": weapon_range, "color": Color(1.0, 0.58, 0.12, 0.22)}, {"radius": footprint, "color": Color(0.12, 0.82, 1.0, 0.28)}]:
		if float(envelope.radius) <= 1.0:
			continue
		var edge_world := world_position + view_camera.global_transform.basis.x.normalized() * float(envelope.radius)
		if view_camera.is_position_behind(edge_world):
			continue
		var radius := screen.distance_to(view_camera.unproject_position(edge_world))
		draw_arc(screen, clampf(radius, 5.0, 2000.0), 0.0, TAU, 64, envelope.color, 1.0)

func _draw_ordnance(view_camera: Camera3D) -> void:
	var registry := get_node_or_null("/root/CombatRegistry")
	var projectiles: Array = registry.active_projectiles() if registry != null else get_tree().get_nodes_in_group("projectiles")
	var threats: Array[Dictionary] = []
	var outgoing: Array[Dictionary] = []
	for candidate in projectiles:
		if not candidate is SidebayProjectile or candidate.expired:
			continue
		var distance := carrier.global_position.distance_to(candidate.global_position)
		var remaining := maxf(0.0, candidate.maximum_distance_m - candidate.distance_travelled_m)
		var tti := distance / maxf(1.0, candidate.speed_mps)
		if candidate.team != carrier.team and candidate.can_be_intercepted:
			threats.append({"node": candidate, "tti": tti, "distance": distance})
		elif candidate.team == carrier.team and candidate.projectile_role in ["missile", "nuclear"]:
			outgoing.append({"node": candidate, "tti": remaining / maxf(1.0, candidate.speed_mps), "distance": remaining})
	threats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.tti) < float(b.tti))
	outgoing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.tti) < float(b.tti))
	for index in mini(6, threats.size()):
		_draw_projectile_cue(view_camera, threats[index], true)
	for index in mini(5, outgoing.size()):
		_draw_projectile_cue(view_camera, outgoing[index], false)

func _draw_projectile_cue(view_camera: Camera3D, data: Dictionary, hostile: bool) -> void:
	var projectile := data.node as SidebayProjectile
	if not is_instance_valid(projectile) or view_camera.is_position_behind(projectile.global_position):
		return
	var screen := view_camera.unproject_position(projectile.global_position)
	if not get_rect().grow(-18.0).has_point(screen):
		return
	var color := RED if hostile else (AMBER if projectile.projectile_role == "nuclear" else CYAN)
	var diamond := PackedVector2Array([screen + Vector2(0, -7), screen + Vector2(7, 0), screen + Vector2(0, 7), screen + Vector2(-7, 0)])
	draw_polyline(diamond, color, 2.0)
	draw_line(diamond[3], diamond[0], color, 2.0)
	var label := "%s  %.1fS  %.0fM" % [("THREAT " if hostile else "") + projectile.projectile_role.to_upper(), float(data.tti), float(data.distance)]
	if projectile.projectile_role == "nuclear":
		label += "  %s" % ("ARMED" if projectile.is_armed() else "SAFE")
	_draw_label(screen + Vector2(10.0, 3.0), label, color, 9)
	if hostile:
		var carrier_screen := view_camera.unproject_position(carrier.global_position)
		draw_dashed_line(screen, carrier_screen, Color(1.0, 0.18, 0.1, 0.42), 1.0, 7.0)

func _draw_damage_cues(view_camera: Camera3D) -> void:
	var center := get_rect().size * 0.5
	for hit in recent_hits:
		var world_position: Vector3 = hit.position
		var camera_space := view_camera.global_transform.affine_inverse() * world_position
		var projected := view_camera.unproject_position(world_position)
		var direction := projected - center
		if camera_space.z > 0.0:
			direction = -direction
		if direction.length_squared() < 1.0:
			direction = Vector2.UP
		var age := float(hit.age)
		var alpha := 1.0 - age / 1.5
		var edge := center + direction.normalized() * minf(get_rect().size.x * 0.34, get_rect().size.y * 0.3)
		var layer := String(hit.layer).to_upper()
		_draw_label(edge, "HIT %s" % layer, Color(1.0, 0.24, 0.12, alpha), 11)

func _on_carrier_damage_resolved(_entity_id: StringName, _source_id: StringName, layers: Dictionary, context: Dictionary) -> void:
	var layer := "SHIELD"
	if float(layers.get("hull", 0.0)) > 0.0:
		layer = "HULL"
	elif float(layers.get("armor", 0.0)) > 0.0:
		layer = "ARMOR"
	recent_hits.append({"position": context.get("position", carrier.global_position), "layer": layer, "age": 0.0})
	while recent_hits.size() > 4:
		recent_hits.pop_front()

func _node_position(node: Node) -> Vector3:
	if node is SidebaySquadron:
		return node.representative_position()
	if node is Node3D:
		return node.global_position
	return Vector3.ZERO

func _draw_brackets(center: Vector2, span: float, color: Color, width: float) -> void:
	var corner := span * 0.42
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var point := center + Vector2(x * span, y * span)
			draw_line(point, point - Vector2(x * corner, 0.0), color, width)
			draw_line(point, point - Vector2(0.0, y * corner), color, width)

func _draw_layer_bar(position: Vector2, width: float, shields: float, armor: float, hull: float) -> void:
	var segment := (width - 4.0) / 3.0
	draw_rect(Rect2(position, Vector2(segment * clampf(shields, 0.0, 1.0), 3.0)), Color(0.1, 0.65, 1.0, 0.85))
	draw_rect(Rect2(position + Vector2(segment + 2.0, 0.0), Vector2(segment * clampf(armor, 0.0, 1.0), 3.0)), Color(0.95, 0.65, 0.12, 0.85))
	draw_rect(Rect2(position + Vector2((segment + 2.0) * 2.0, 0.0), Vector2(segment * clampf(hull, 0.0, 1.0), 3.0)), Color(0.9, 0.15, 0.12, 0.85))

func _draw_label(position: Vector2, text: String, color: Color, font_size: int) -> void:
	draw_string(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
