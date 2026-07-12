extends Node3D

signal return_to_campaign(victory: bool, battle_report: Dictionary)

var carrier: PlayerCarrier
var escort: CombatShip
var interceptor: SidebaySquadron
var scout: SidebaySquadron
var hostile_fighters: SidebaySquadron
var hostile_command: CombatShip
var hostile_corvette: CombatShip
var sensors: SidebaySensorSystem
var tactical: TacticalController
var hud: SidebayHUD
var audio: SidebayAudio
var battle_finished: bool = false
var target_lock: CombatShip
var elapsed_seconds: float = 0.0
var hosted_campaign: bool = false
var campaign_node_id: StringName = &""
var campaign_threat_multiplier: float = 1.0
var battle_result_victory: bool = false
var battle_outcome: String = "victory"
var campaign_fleet_snapshot: Dictionary = {}
var campaign_objective_type: int = SidebayCampaignNode.ObjectiveType.COMMAND_STRIKE
var extraction_requested: bool = false
var extraction_position: Vector3
var extraction_beacon: Node3D
var hostile_corvette_destroyed: bool = false
var hostile_fighters_destroyed: bool = false
var objective_ship: CombatShip
var objective_marker: Node3D
var objective_destination: Vector3
var objective_elapsed: float = 0.0
var capture_progress: float = 0.0
var withdrawal_elapsed: float = 0.0
var pursuit_ship: CombatShip
var pursuit_spawned: bool = false
var escape_pods: Array[Dictionary] = []
var destroyed_hostile_count: int = 0
var emergency_bay_seal: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var graphics := _graphics_quality()
	if graphics != null and not graphics.quality_changed.is_connected(_on_graphics_quality_changed):
		graphics.quality_changed.connect(_on_graphics_quality_changed)
	_configure_input_map()
	_build_environment()
	_build_battlefield()
	_configure_objective()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("web") else Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_campaign_fleet_snapshot()
	_deploy_initial_forces()
	_connect_feedback()
	hud.notify("Passive contacts detected. Launch scouts or press P for active ping.")

func _graphics_quality() -> Node:
	return get_node_or_null("/root/GraphicsQualityManager")

func _on_graphics_quality_changed(_profile_name: StringName) -> void:
	_apply_graphics_quality()

func _process(delta: float) -> void:
	if get_tree().paused or battle_finished:
		return
	elapsed_seconds += delta
	if is_instance_valid(escort) and is_instance_valid(carrier):
		escort.command_link.update_for_distance(escort.global_position.distance_to(carrier.global_position), carrier.definition.command_range_m)
	if not tactical.enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if carrier.fire_flak():
			audio.play_tone(180.0, 0.045, -28.0)
	_update_target_lock()
	_process_objective(delta)
	_process_escape_pods()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER:
			_restart_encounter()
			return
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
			return
	if battle_finished or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		tactical.set_enabled(not tactical.enabled)
		hud.notify("Tactical map is live; carrier maintains helm orders." if tactical.enabled else "Direct flight control restored.")
		audio.play_tone(620.0 if tactical.enabled else 420.0, 0.1)
		return
	if tactical.handle_input(event):
		return
	if event is InputEventMouseMotion:
		if carrier.camera_orbiting:
			carrier.apply_camera_orbit(event.relative)
		elif OS.has_feature("web"):
			carrier.set_web_cursor_steering(event.position, get_viewport().get_visible_rect().size)
		else:
			carrier.apply_mouse_look(event.relative)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			carrier.set_camera_orbiting(event.pressed)
			if event.pressed:
				hud.notify("COMBAT CAMERA ORBIT — drag to rotate view")
		elif not event.pressed:
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			carrier.adjust_chase_zoom(1.0)
			hud.notify("Combat camera zoom %d%%" % carrier.chase_zoom_percent())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			carrier.adjust_chase_zoom(-1.0)
			hud.notify("Combat camera zoom %d%%" % carrier.chase_zoom_percent())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if target_lock == null:
				hud.notify("Missile rejected: no identified target in lock cone")
			elif carrier.fire_missile(target_lock):
				hud.notify("LONG-RANGE SALVO AWAY — %d missiles tracking %s" % [carrier.missile_salvo_count, target_lock.display_name])
				audio.play_tone(110.0, 0.3, -14.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P:
				sensors.emit_active_ping()
				hud.notify("ACTIVE PING — emissions reveal the carrier")
				audio.play_tone(880.0, 0.45, -12.0)
			KEY_Z:
				_toggle_wing(interceptor)
			KEY_X:
				_toggle_wing(scout)
			KEY_V:
				request_withdrawal()

func _configure_input_map() -> void:
	var bindings := {
		"move_forward": KEY_W,
		"move_backward": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"move_up": KEY_SPACE,
		"move_down": KEY_C,
		"boost": KEY_SHIFT,
		"brake": KEY_CTRL
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = bindings[action]
		if not InputMap.action_has_event(action, key_event):
			InputMap.action_add_event(action, key_event)

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.004, 0.012)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.16, 0.22, 0.34)
	environment.ambient_light_energy = 0.92
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key_light.light_color = Color(0.65, 0.76, 1.0)
	key_light.light_energy = 1.38
	add_child(key_light)
	_build_starfield()
	_apply_graphics_quality()

func _build_starfield() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 2.0
	mesh.height = 4.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.7, 0.84, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.8, 0.9, 1.0) * 2.0
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 720
	var random := RandomNumberGenerator.new()
	random.seed = 724911
	for index in multimesh.instance_count:
		var direction := Vector3(random.randf_range(-1.0, 1.0), random.randf_range(-0.7, 0.7), random.randf_range(-1.0, 1.0)).normalized()
		var transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * random.randf_range(0.35, 1.4)), direction * random.randf_range(9000.0, 18000.0))
		multimesh.set_instance_transform(index, transform)
	var stars := MultiMeshInstance3D.new()
	stars.name = "DeepStarfield"
	stars.multimesh = multimesh
	add_child(stars)
	_build_nebula_star_band()
	_build_dust_field()
	_add_nebula_card(Vector3(-6200.0, 1900.0, -11500.0), Vector2(6200.0, 3000.0), Color(0.48, 0.34, 0.92, 0.5), 2)
	_add_nebula_card(Vector3(6900.0, -1700.0, -13200.0), Vector2(4800.0, 2300.0), Color(0.18, 0.72, 0.82, 0.34), 3)
	_add_distant_body(Vector3(-7600.0, 2800.0, -11200.0), 760.0, Color(0.08, 0.16, 0.28, 1.0), 0.18, Vector3(1.0, 1.0, 1.0), 1)
	_add_distant_body(Vector3(9200.0, -2100.0, -13800.0), 240.0, Color(1.0, 0.42, 0.12, 1.0), 2.8, Vector3(1.0, 1.0, 1.0), 2)
	_add_distant_body(Vector3(5600.0, 1800.0, -9800.0), 520.0, Color(0.18, 0.08, 0.34, 0.12), 0.65, Vector3(3.8, 1.3, 2.2), 3)
	_add_distant_body(Vector3(-4200.0, -2600.0, -8600.0), 430.0, Color(0.04, 0.28, 0.34, 0.10), 0.55, Vector3(4.2, 1.1, 2.7), 3)

func _build_nebula_star_band() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.4
	mesh.height = 2.8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.42, 0.28, 0.78)
	material.emission_enabled = true
	material.emission = Color(0.28, 0.18, 0.7) * 2.2
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 320
	var random := RandomNumberGenerator.new()
	random.seed = 918273
	for index in multimesh.instance_count:
		var angle := random.randf_range(-PI, PI)
		var direction := Vector3(cos(angle), random.randf_range(-0.13, 0.13), sin(angle)).normalized()
		var star_scale := random.randf_range(0.45, 2.8)
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * star_scale), direction * random.randf_range(10500.0, 19500.0)))
	var band := MultiMeshInstance3D.new()
	band.name = "NebulaStarBand"
	band.multimesh = multimesh
	band.rotation_degrees = Vector3(18.0, 0.0, -12.0)
	band.add_to_group("quality_backdrop")
	band.set_meta("quality_layer", 2)
	add_child(band)

func _build_dust_field() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 4.0
	mesh.height = 8.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.18, 0.5, 0.7, 0.16)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.08, 0.28, 0.42)
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 180
	var random := RandomNumberGenerator.new()
	random.seed = 190427
	for index in multimesh.instance_count:
		var point := Vector3(random.randf_range(-4800.0, 4800.0), random.randf_range(-1300.0, 1300.0), random.randf_range(-6500.0, 3200.0))
		var scale_value := random.randf_range(0.35, 1.7)
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_value), point))
	var dust := MultiMeshInstance3D.new()
	dust.name = "ParallaxDust"
	dust.multimesh = multimesh
	dust.add_to_group("quality_backdrop")
	dust.set_meta("quality_layer", 3)
	add_child(dust)

func _add_nebula_card(position_value: Vector3, size_value: Vector2, tint: Color, quality_layer: int) -> void:
	var card := MeshInstance3D.new()
	card.name = "NebulaBillboard"
	var mesh := QuadMesh.new()
	mesh.size = size_value
	card.mesh = mesh
	card.position = position_value
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = tint
	var nebula_texture := load("res://assets/textures/nebula_card.svg") as Texture2D
	material.albedo_texture = nebula_texture
	material.emission_enabled = true
	material.emission = Color(tint.r, tint.g, tint.b) * 0.7
	material.emission_texture = nebula_texture
	card.material_override = material
	card.add_to_group("quality_backdrop")
	card.set_meta("quality_layer", quality_layer)
	add_child(card)

func _add_distant_body(position_value: Vector3, radius: float, color: Color, emission_energy: float, scale_value: Vector3, quality_layer: int = 1) -> void:
	var body := MeshInstance3D.new()
	body.name = "DistantBackdropBody"
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	body.mesh = mesh
	body.position = position_value
	body.scale = scale_value
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b) * emission_energy
	body.material_override = material
	body.add_to_group("quality_backdrop")
	body.set_meta("quality_layer", quality_layer)
	add_child(body)

func _apply_graphics_quality() -> void:
	var graphics := _graphics_quality()
	var profile: Dictionary = graphics.profile() if graphics != null else {"effect_density": 0.75, "backdrop_layers": 2}
	var density := clampf(float(profile.get("effect_density", 0.75)), 0.2, 1.0)
	var backdrop_layers := clampi(int(profile.get("backdrop_layers", 2)), 1, 3)
	var starfield := get_node_or_null("DeepStarfield") as MultiMeshInstance3D
	if starfield != null and starfield.multimesh != null:
		starfield.multimesh.visible_instance_count = int(starfield.multimesh.instance_count * density)
	var band := get_node_or_null("NebulaStarBand") as MultiMeshInstance3D
	if band != null and band.multimesh != null:
		band.multimesh.visible_instance_count = int(band.multimesh.instance_count * density)
	for backdrop in get_tree().get_nodes_in_group("quality_backdrop"):
		if backdrop is Node3D and is_ancestor_of(backdrop):
			backdrop.visible = int(backdrop.get_meta("quality_layer", 1)) <= backdrop_layers

func _build_battlefield() -> void:
	audio = SidebayAudio.new()
	add_child(audio)
	carrier = PlayerCarrier.new()
	add_child(carrier)
	carrier.configure(_carrier_definition(), &"player_carrier", &"friendly", Color(0.18, 0.38, 0.58))
	carrier.global_position = Vector3(0.0, 0.0, 2600.0)
	carrier.chase_camera.current = true
	if bool(campaign_fleet_snapshot.get("escort_active", true)):
		escort = CombatShip.new()
		add_child(escort)
		var escort_id := StringName(campaign_fleet_snapshot.get("active_escort_id", "iss_resolute"))
		escort.configure(_friendly_escort_definition(escort_id), escort_id, &"friendly", _friendly_escort_color(escort_id))
		escort.global_position = Vector3(-520.0, 40.0, 2820.0)
		escort.ai_enabled = true
	interceptor = SidebaySquadron.new()
	add_child(interceptor)
	interceptor.configure(_interceptor_squadron_definition(), &"interceptor_wing", &"friendly", carrier, &"port", Color(0.25, 0.7, 1.0))
	scout = SidebaySquadron.new()
	add_child(scout)
	scout.configure(_scout_squadron_definition(), &"scout_wing", &"friendly", carrier, &"starboard", Color(0.35, 1.0, 0.82))
	hostile_command = CombatShip.new()
	add_child(hostile_command)
	hostile_command.configure(_frigate_definition("Acheron Command", true), &"hostile_command", &"hostile", Color(0.62, 0.13, 0.1))
	hostile_command.is_command_ship = true
	hostile_command.global_position = Vector3(1050.0, 280.0, -5200.0)
	hostile_command.ai_enabled = true
	hostile_corvette = CombatShip.new()
	add_child(hostile_corvette)
	hostile_corvette.configure(_corvette_definition(), &"hostile_corvette", &"hostile", Color(0.72, 0.18, 0.08))
	hostile_corvette.global_position = Vector3(-1300.0, -170.0, -4050.0)
	hostile_corvette.ai_enabled = true
	hostile_fighters = SidebaySquadron.new()
	add_child(hostile_fighters)
	hostile_fighters.configure(_hostile_squadron_definition(), &"hostile_fighter_wing", &"hostile", null, &"port", Color(1.0, 0.24, 0.08))
	sensors = SidebaySensorSystem.new()
	add_child(sensors)
	sensors.configure(carrier)
	tactical = TacticalController.new()
	add_child(tactical)
	var commandables: Array[Node] = [interceptor, scout]
	if is_instance_valid(escort):
		commandables.append(escort)
	commandables.append(carrier)
	tactical.configure(carrier, sensors, commandables)
	hud = SidebayHUD.new()
	add_child(hud)
	hud.configure(carrier, interceptor, scout, sensors, tactical)

func _deploy_initial_forces() -> void:
	hostile_fighters.start_deployed(Vector3(100.0, 420.0, -3550.0))
	var priority_target_id := objective_ship.stable_entity_id if is_instance_valid(objective_ship) else carrier.stable_entity_id
	var priority_attack := FleetOrder.at_entity(FleetOrder.OrderType.ATTACK, priority_target_id, elapsed_seconds)
	priority_attack.requires_command_link = false
	hostile_command.issue_order(priority_attack)
	var corvette_attack := FleetOrder.at_entity(FleetOrder.OrderType.ATTACK, priority_target_id, elapsed_seconds)
	corvette_attack.requires_command_link = false
	hostile_corvette.issue_order(corvette_attack)
	var fighter_attack := FleetOrder.at_entity(FleetOrder.OrderType.ATTACK, priority_target_id, elapsed_seconds)
	fighter_attack.requires_command_link = false
	hostile_fighters.issue_order(fighter_attack)
	if campaign_objective_type == SidebayCampaignNode.ObjectiveType.ESCORT and is_instance_valid(objective_ship):
		var convoy_order := FleetOrder.at_position(FleetOrder.OrderType.MOVE, objective_destination, elapsed_seconds)
		convoy_order.requires_command_link = false
		objective_ship.issue_order(convoy_order)
	if is_instance_valid(escort):
		var escort_order := FleetOrder.at_entity(FleetOrder.OrderType.ESCORT, carrier.stable_entity_id, elapsed_seconds)
		escort.issue_order(escort_order)

func _connect_feedback() -> void:
	carrier.ship_destroyed.connect(_on_ship_destroyed)
	if is_instance_valid(escort):
		escort.ship_destroyed.connect(_on_ship_destroyed)
		escort.ship_destroyed.connect(_on_friendly_capital_destroyed.bind(escort))
	hostile_command.ship_destroyed.connect(_on_ship_destroyed)
	hostile_corvette.ship_destroyed.connect(_on_ship_destroyed)
	for ship in [escort, hostile_command, hostile_corvette]:
		if is_instance_valid(ship):
			ship.order_acknowledged.connect(_on_order_feedback)
	for wing in [interceptor, scout, hostile_fighters]:
		wing.status_changed.connect(_on_wing_feedback)
	hostile_fighters.squadron_destroyed.connect(_on_hostile_squadron_destroyed)
	for wing in [interceptor, scout]:
		for craft in wing.crafts:
			if is_instance_valid(craft):
				craft.ship_destroyed.connect(_on_friendly_craft_destroyed.bind(craft))
	for craft in hostile_fighters.crafts:
		if is_instance_valid(craft):
			craft.ship_destroyed.connect(_on_hostile_craft_destroyed)
	if is_instance_valid(objective_ship):
		objective_ship.ship_destroyed.connect(_on_objective_ship_destroyed)
	tactical.notification_requested.connect(hud.notify)
	tactical.selection_changed.connect(func(name: String) -> void: hud.notify("Selected: %s" % name))

func _update_target_lock() -> void:
	if not is_instance_valid(carrier):
		return
	target_lock = sensors.best_target_in_direction(carrier.global_position, carrier.aim_direction, 8500.0)
	if is_instance_valid(target_lock):
		var contact := sensors.get_contact(target_lock.stable_entity_id)
		hud.update_target(contact, target_lock.display_name, target_lock)
	else:
		hud.update_target(null)

func _toggle_wing(wing: SidebaySquadron) -> void:
	if extraction_requested:
		hud.notify("FLIGHT OPS LOCKED — jump preparation is active")
		return
	if wing.operation.state == BayOperation.State.READY:
		if wing.request_launch():
			audio.play_tone(340.0, 0.16)
	elif wing.operation.state in [BayOperation.State.DEPLOYED, BayOperation.State.LAUNCHING]:
		wing.request_recall()
	else:
		hud.notify("%s is %s" % [wing.display_name, wing.operation.label()])

func _on_order_feedback(_entity_id: StringName, message: String) -> void:
	if hud != null:
		hud.notify(message)

func _on_wing_feedback(_entity_id: StringName, message: String) -> void:
	if hud != null:
		hud.notify(message)

func _on_friendly_craft_destroyed(entity_id: StringName, craft: FighterCraft) -> void:
	var pod_position := craft.global_position if is_instance_valid(craft) else carrier.global_position
	_spawn_escape_pod(entity_id, pod_position)

func _on_friendly_capital_destroyed(entity_id: StringName, ship: CombatShip) -> void:
	var pod_position := ship.global_position if is_instance_valid(ship) else carrier.global_position
	_spawn_escape_pod(entity_id, pod_position, 3)

func _on_hostile_craft_destroyed(_entity_id: StringName) -> void:
	destroyed_hostile_count += 1

func _on_objective_ship_destroyed(entity_id: StringName) -> void:
	var pod_position := objective_ship.global_position if is_instance_valid(objective_ship) else carrier.global_position
	_spawn_escape_pod(entity_id, pod_position, 4)
	if battle_finished:
		return
	if campaign_objective_type == SidebayCampaignNode.ObjectiveType.DEFENSE:
		_finish_battle(true, "defense_failed")
	elif campaign_objective_type == SidebayCampaignNode.ObjectiveType.ESCORT:
		_finish_battle(true, "escort_failed")

func _spawn_escape_pod(source_entity_id: StringName, at_position: Vector3, occupants: int = 1) -> void:
	var pod_node := Node3D.new()
	pod_node.name = "EscapePod_%02d" % (escape_pods.size() + 1)
	add_child(pod_node)
	pod_node.global_position = at_position
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 4.5
	mesh.height = 9.0
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.42, 0.08)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.24, 0.02) * 4.0
	body.material_override = material
	pod_node.add_child(body)
	var label := Label3D.new()
	label.text = "SOS"
	label.font_size = 22
	label.modulate = Color(1.0, 0.62, 0.2)
	label.position = Vector3(0.0, 9.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pod_node.add_child(label)
	escape_pods.append({
		"pod_id": "pod_%02d" % (escape_pods.size() + 1),
		"source_entity_id": String(source_entity_id),
		"occupants": occupants,
		"rescued": false,
		"node": pod_node
	})
	hud.notify("ESCAPE POD DETECTED — close within 180 m to recover survivors")

func _process_escape_pods() -> void:
	for index in escape_pods.size():
		var pod: Dictionary = escape_pods[index]
		if bool(pod.get("rescued", false)):
			continue
		var pod_node: Node3D = pod.get("node")
		if is_instance_valid(pod_node) and carrier.global_position.distance_to(pod_node.global_position) <= 180.0:
			pod["rescued"] = true
			pod_node.visible = false
			escape_pods[index] = pod
			hud.notify("SURVIVORS RECOVERED — %d personnel aboard" % int(pod.get("occupants", 1)))

func _on_ship_destroyed(entity_id: StringName) -> void:
	if battle_finished:
		return
	if entity_id in [&"hostile_command", &"hostile_corvette", &"hostile_pursuit"]:
		destroyed_hostile_count += 1
	if entity_id == carrier.stable_entity_id:
		_finish_battle(false, "carrier_lost")
	elif entity_id == hostile_command.stable_entity_id and campaign_objective_type == SidebayCampaignNode.ObjectiveType.COMMAND_STRIKE:
		_finish_battle(true, "command_strike")
	elif entity_id == hostile_corvette.stable_entity_id:
		hostile_corvette_destroyed = true
		_check_objective_completion()

func _on_hostile_squadron_destroyed(squadron_id: StringName) -> void:
	if squadron_id == &"hostile_fighter_wing":
		hostile_fighters_destroyed = true
		_check_objective_completion()

func _spawn_withdrawal_pursuit() -> void:
	if pursuit_spawned or battle_finished:
		return
	pursuit_spawned = true
	pursuit_ship = CombatShip.new()
	add_child(pursuit_ship)
	var definition := _corvette_definition()
	definition.ship_id = &"hostile_pursuit_corvette"
	definition.display_name = "Acheron Pursuit Corvette"
	definition.maximum_speed_mps *= 1.18
	pursuit_ship.configure(definition, &"hostile_pursuit", &"hostile", Color(0.92, 0.2, 0.05))
	var away_from_exit := (carrier.global_position - extraction_position).normalized()
	if away_from_exit.length_squared() < 0.1:
		away_from_exit = Vector3.FORWARD
	pursuit_ship.global_position = carrier.global_position + away_from_exit * 1350.0 + Vector3.UP * 180.0
	pursuit_ship.ai_enabled = true
	var pursuit_order := FleetOrder.at_entity(FleetOrder.OrderType.ATTACK, carrier.stable_entity_id, elapsed_seconds)
	pursuit_order.requires_command_link = false
	pursuit_ship.issue_order(pursuit_order)
	pursuit_ship.ship_destroyed.connect(_on_ship_destroyed)
	hud.notify("PURSUIT CONTACT — hostile corvette entering the withdrawal lane")

func _check_objective_completion() -> void:
	if campaign_objective_type == SidebayCampaignNode.ObjectiveType.INTERCEPTION and hostile_corvette_destroyed and hostile_fighters_destroyed:
		_finish_battle(true, "interception")

func _configure_objective() -> void:
	match campaign_objective_type:
		SidebayCampaignNode.ObjectiveType.INTERCEPTION:
			hud.set_objective("INTERCEPTION  Destroy the hostile corvette and fighter screen")
		SidebayCampaignNode.ObjectiveType.EXTRACTION:
			hud.set_objective("EXTRACTION  Survive until the withdrawal corridor opens")
		SidebayCampaignNode.ObjectiveType.DEFENSE:
			_spawn_defense_objective()
			hud.set_objective("DEFENSE  Protect the Longwatch relay for 25 seconds")
		SidebayCampaignNode.ObjectiveType.ESCORT:
			_spawn_escort_objective()
			hud.set_objective("ESCORT  Protect the Atlas convoy ship to the jump corridor")
		SidebayCampaignNode.ObjectiveType.CAPTURE:
			objective_destination = Vector3(150.0, 80.0, -1900.0)
			objective_marker = _spawn_mission_marker("CaptureZone", objective_destination, Color(0.62, 0.35, 1.0), "CAPTURE")
			hud.set_objective("CAPTURE  Hold friendly forces inside the violet control zone")
		_:
			hud.set_objective("COMMAND STRIKE  Identify and destroy the hostile command frigate")

func _spawn_defense_objective() -> void:
	objective_ship = CombatShip.new()
	add_child(objective_ship)
	objective_ship.configure(_objective_ship_definition("Longwatch Relay", true), &"friendly_defense_relay", &"friendly", Color(0.18, 0.75, 0.86))
	objective_ship.global_position = Vector3(0.0, 20.0, 650.0)
	objective_ship.ai_enabled = false

func _spawn_escort_objective() -> void:
	objective_ship = CombatShip.new()
	add_child(objective_ship)
	objective_ship.configure(_objective_ship_definition("Atlas Convoy", false), &"friendly_convoy", &"friendly", Color(0.72, 0.62, 0.25))
	objective_ship.global_position = Vector3(460.0, 40.0, 3100.0)
	objective_ship.ai_enabled = true
	objective_destination = Vector3(900.0, 120.0, -3600.0)
	objective_marker = _spawn_mission_marker("EscortDestination", objective_destination, Color(0.2, 0.88, 1.0), "CONVOY EXIT")

func _spawn_mission_marker(marker_name: String, at_position: Vector3, color: Color, caption: String) -> Node3D:
	var marker := Node3D.new()
	marker.name = marker_name
	add_child(marker)
	marker.global_position = at_position
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 135.0
	mesh.height = 270.0
	sphere.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, 0.16)
	material.emission_enabled = true
	material.emission = color * 2.5
	sphere.material_override = material
	marker.add_child(sphere)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 38
	label.modulate = color
	label.position = Vector3(0.0, 170.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.add_child(label)
	return marker

func request_withdrawal() -> void:
	if battle_finished:
		return
	if extraction_requested:
		if not carrier.are_bays_closed() and not emergency_bay_seal:
			emergency_bay_seal = true
			carrier.request_bays_closed()
			hud.notify("EMERGENCY BAY SEAL — deployed craft may be left as stragglers")
			audio.play_tone(190.0, 0.55, -8.0)
		return
	extraction_requested = true
	battle_outcome = "withdrawal"
	extraction_position = carrier.global_position + carrier.global_transform.basis.z.normalized() * 2400.0 + Vector3.UP * 120.0
	_spawn_extraction_beacon()
	_prepare_wings_for_jump()
	hud.notify("JUMP PREPARATION — recalling wings; bays must retract and seal")
	audio.play_tone(510.0, 0.5, -10.0)

func _prepare_wings_for_jump() -> bool:
	var interceptor_aboard := interceptor.prepare_for_jump() if is_instance_valid(interceptor) else true
	var scout_aboard := scout.prepare_for_jump() if is_instance_valid(scout) else true
	var all_aboard := interceptor_aboard and scout_aboard
	if all_aboard or emergency_bay_seal:
		carrier.request_bays_closed()
	else:
		carrier.request_bays_open()
	return all_aboard

func _spawn_extraction_beacon() -> void:
	extraction_beacon = Node3D.new()
	extraction_beacon.name = "ExtractionBeacon"
	add_child(extraction_beacon)
	extraction_beacon.global_position = extraction_position
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 105.0
	mesh.height = 210.0
	sphere.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.08, 0.85, 1.0, 0.18)
	material.emission_enabled = true
	material.emission = Color(0.05, 0.72, 1.0) * 3.0
	sphere.material_override = material
	extraction_beacon.add_child(sphere)
	var label := Label3D.new()
	label.text = "EXTRACT"
	label.font_size = 42
	label.modulate = Color(0.25, 0.92, 1.0)
	label.position = Vector3(0.0, 145.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	extraction_beacon.add_child(label)

func _process_objective(delta: float) -> void:
	if battle_finished:
		return
	objective_elapsed += delta
	if campaign_objective_type == SidebayCampaignNode.ObjectiveType.EXTRACTION and not extraction_requested:
		var remaining := maxf(0.0, 10.0 - elapsed_seconds)
		hud.set_objective("EXTRACTION  Hold the line — corridor opens in %.0f seconds" % remaining)
		if elapsed_seconds >= 10.0:
			request_withdrawal()
	elif campaign_objective_type == SidebayCampaignNode.ObjectiveType.DEFENSE:
		var remaining := maxf(0.0, 25.0 - objective_elapsed)
		if is_instance_valid(objective_ship):
			var relay_layers := objective_ship.layer_percentages()
			hud.set_objective("DEFENSE  Longwatch relay hull %.0f%% — hold %.0f seconds" % [relay_layers.z * 100.0, remaining])
		if objective_elapsed >= 25.0:
			_finish_battle(true, "defense")
	elif campaign_objective_type == SidebayCampaignNode.ObjectiveType.ESCORT and is_instance_valid(objective_ship):
		var distance_to_exit := objective_ship.global_position.distance_to(objective_destination)
		var convoy_layers := objective_ship.layer_percentages()
		hud.set_objective("ESCORT  Atlas convoy %.0f m to exit — hull %.0f%%" % [distance_to_exit, convoy_layers.z * 100.0])
		if distance_to_exit <= 260.0:
			_finish_battle(true, "escort")
	elif campaign_objective_type == SidebayCampaignNode.ObjectiveType.CAPTURE:
		_process_capture_objective(delta)
	if extraction_requested:
		withdrawal_elapsed += delta
		if withdrawal_elapsed >= 2.0 and not pursuit_spawned:
			_spawn_withdrawal_pursuit()
		var distance := carrier.global_position.distance_to(extraction_position)
		var wings_aboard := _prepare_wings_for_jump()
		if not carrier.are_bays_closed():
			var interlock := "RECOVERING WINGS — press V again for emergency seal" if not wings_aboard and not emergency_bay_seal else carrier.bay_status()
			hud.set_objective("JUMP PREP  %.0f m to corridor — %s" % [distance, interlock])
		elif distance > 300.0:
			hud.set_objective("JUMP READY  Bays sealed — %.0f m to corridor" % distance)
		if distance <= 300.0 and carrier.are_bays_closed():
			_finish_battle(true, "withdrawal")

func _process_capture_objective(delta: float) -> void:
	var friendly_inside := _count_team_near(&"friendly", objective_destination, 420.0)
	var hostile_inside := _count_team_near(&"hostile", objective_destination, 520.0)
	if friendly_inside > 0 and hostile_inside == 0:
		capture_progress = minf(12.0, capture_progress + delta * minf(2.0, float(friendly_inside)))
	elif hostile_inside > 0:
		capture_progress = maxf(0.0, capture_progress - delta * 0.5)
	hud.set_objective("CAPTURE  Control %.0f%% — friendly %d / hostile %d" % [capture_progress / 12.0 * 100.0, friendly_inside, hostile_inside])
	if capture_progress >= 12.0:
		_finish_battle(true, "capture")

func _count_team_near(team_name: StringName, center: Vector3, radius: float) -> int:
	var count := 0
	for candidate in get_tree().get_nodes_in_group("team_%s" % team_name):
		if candidate is CombatShip and not candidate.is_destroyed and candidate.global_position.distance_to(center) <= radius:
			count += 1
	return count

func _finish_battle(victory: bool, outcome: String = "victory") -> void:
	battle_finished = true
	battle_result_victory = victory
	battle_outcome = outcome
	hud.set_result(victory, "Press Enter to return to sector map" if hosted_campaign else "Press Enter to restart", outcome)
	audio.play_tone(740.0 if victory else 90.0, 0.8, -10.0)
	get_tree().paused = true

func _toggle_pause() -> void:
	if battle_finished:
		return
	var next := not get_tree().paused
	get_tree().paused = next
	hud.set_paused(next)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if next else (Input.MOUSE_MODE_VISIBLE if tactical.enabled else Input.MOUSE_MODE_CAPTURED)

func _restart_encounter() -> void:
	get_tree().paused = false
	if hosted_campaign:
		return_to_campaign.emit(battle_result_victory, _create_battle_report())
	else:
		get_tree().reload_current_scene()

func _installed_module(slot: String) -> StringName:
	var installed: Dictionary = campaign_fleet_snapshot.get("installed_modules", {})
	return StringName(installed.get(slot, ""))

func _apply_campaign_fleet_snapshot() -> void:
	if campaign_fleet_snapshot.is_empty():
		return
	if is_instance_valid(carrier) and carrier.damage_state != null:
		carrier.damage_state.shields = carrier.damage_state.definition.max_shields * clampf(float(campaign_fleet_snapshot.get("carrier_shields", 1.0)), 0.0, 1.0)
		carrier.damage_state.armor = carrier.damage_state.definition.max_armor * clampf(float(campaign_fleet_snapshot.get("carrier_armor", 1.0)), 0.0, 1.0)
		carrier.damage_state.hull = carrier.damage_state.definition.max_hull * clampf(float(campaign_fleet_snapshot.get("carrier_hull", 1.0)), 0.01, 1.0)
	_apply_squadron_ammunition(interceptor, int(campaign_fleet_snapshot.get("interceptor_ammunition", 112)))
	_apply_squadron_ammunition(scout, int(campaign_fleet_snapshot.get("scout_ammunition", 54)))

func _apply_squadron_ammunition(wing: SidebaySquadron, total: int) -> void:
	if not is_instance_valid(wing) or wing.crafts.is_empty():
		return
	var quotient := total / wing.crafts.size()
	var remainder := total % wing.crafts.size()
	for index in wing.crafts.size():
		var craft := wing.crafts[index]
		if is_instance_valid(craft):
			craft.ammunition = quotient + (1 if index < remainder else 0)

func _create_battle_report() -> Dictionary:
	var carrier_layers := Vector3.ZERO
	if is_instance_valid(carrier) and carrier.damage_state != null:
		carrier_layers = carrier.layer_percentages()
	var interceptor_living := interceptor.living_craft_count() if is_instance_valid(interceptor) else 0
	var scout_living := scout.living_craft_count() if is_instance_valid(scout) else 0
	var interceptor_stragglers := _count_wing_stragglers(interceptor)
	var scout_stragglers := _count_wing_stragglers(scout)
	var escort_alive := is_instance_valid(escort) and not escort.is_destroyed
	var escort_straggler := battle_outcome == "withdrawal" and escort_alive and escort.global_position.distance_to(extraction_position) > 1200.0
	var pod_totals := _escape_pod_totals()
	var objective_success := not battle_outcome in ["carrier_lost", "defense_failed", "escort_failed"]
	var salvage_value := destroyed_hostile_count * 4 + (4 if objective_success else 0)
	return {
		"outcome": battle_outcome,
		"objective_type": campaign_objective_type,
		"objective_success": objective_success,
		"objective_ship_survived": not is_instance_valid(objective_ship) or not objective_ship.is_destroyed,
		"carrier_shields": carrier_layers.x,
		"carrier_armor": carrier_layers.y,
		"carrier_hull": carrier_layers.z,
		"interceptor_craft_count": maxi(0, interceptor_living - interceptor_stragglers),
		"interceptor_ammunition": interceptor.total_ammunition() if is_instance_valid(interceptor) else 0,
		"scout_craft_count": maxi(0, scout_living - scout_stragglers),
		"scout_ammunition": scout.total_ammunition() if is_instance_valid(scout) else 0,
		"escort_active": escort_alive and not escort_straggler,
		"escort_id": String(campaign_fleet_snapshot.get("active_escort_id", "iss_resolute")),
		"escort_name": escort.display_name if escort_alive else str(SidebayRunState.escort_data(StringName(campaign_fleet_snapshot.get("active_escort_id", "iss_resolute"))).get("name", "Escort")),
		"interceptor_stragglers": interceptor_stragglers,
		"scout_stragglers": scout_stragglers,
		"escort_straggler": escort_straggler,
		"escape_pods_total": pod_totals.pods_total,
		"escape_pods_rescued": pod_totals.pods_rescued,
		"escape_pods_adrift": pod_totals.pods_adrift,
		"survivors_rescued": pod_totals.survivors_rescued,
		"survivors_adrift": pod_totals.survivors_adrift,
		"rescued_sources": pod_totals.rescued_sources,
		"adrift_sources": pod_totals.adrift_sources,
		"destroyed_hostile_count": destroyed_hostile_count,
		"salvage_value": salvage_value
	}

func _count_wing_stragglers(wing: SidebaySquadron) -> int:
	if battle_outcome != "withdrawal" or not is_instance_valid(wing):
		return 0
	var count := 0
	for craft in wing.crafts:
		if is_instance_valid(craft) and not craft.is_destroyed and craft.deployed and craft.global_position.distance_to(extraction_position) > 800.0:
			count += 1
	return count

func _escape_pod_totals() -> Dictionary:
	var result := {
		"pods_total": escape_pods.size(),
		"pods_rescued": 0,
		"pods_adrift": 0,
		"survivors_rescued": 0,
		"survivors_adrift": 0,
		"rescued_sources": [],
		"adrift_sources": []
	}
	for pod in escape_pods:
		var rescued := bool(pod.get("rescued", false))
		var occupants := int(pod.get("occupants", 1))
		if rescued:
			result["pods_rescued"] += 1
			result["survivors_rescued"] += occupants
			result["rescued_sources"].append(str(pod.get("source_entity_id", "unknown")))
		else:
			result["pods_adrift"] += 1
			result["survivors_adrift"] += occupants
			result["adrift_sources"].append(str(pod.get("source_entity_id", "unknown")))
	return result

func _objective_ship_definition(ship_name: String, stationary: bool) -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"longwatch_relay" if stationary else &"atlas_convoy"
	definition.display_name = ship_name
	definition.role = "frigate"
	definition.dimensions_m = Vector3(34.0, 18.0, 82.0) if stationary else Vector3(27.0, 14.0, 74.0)
	definition.acceleration_mps2 = 0.0 if stationary else 28.0
	definition.maximum_speed_mps = 0.0 if stationary else 185.0
	definition.rotation_speed_radians = 0.0 if stationary else 0.65
	definition.signature = 1.25
	definition.damage_layers = _damage_layers(420.0, 520.0, 650.0, 7.0, 0.25) if stationary else _damage_layers(260.0, 330.0, 420.0, 4.0, 0.18)
	definition.weapons = []
	return definition

func _carrier_definition() -> ShipDefinition:
	var carrier_id := StringName(campaign_fleet_snapshot.get("active_carrier_id", "cvn_sidebay"))
	var frame := SidebayRunState.carrier_data(carrier_id)
	if frame.is_empty():
		frame = SidebayRunState.carrier_data(&"cvn_sidebay")
	var definition := ShipDefinition.new()
	definition.ship_id = StringName(frame.id)
	definition.display_name = str(frame.name)
	definition.role = "carrier"
	definition.dimensions_m = Vector3(float(frame.width), float(frame.height), float(frame.length))
	definition.acceleration_mps2 = 34.0 * float(frame.acceleration)
	definition.maximum_speed_mps = 260.0 * float(frame.speed)
	definition.rotation_speed_radians = 0.75 * float(frame.rotation)
	definition.signature = 1.5 * float(frame.signature)
	definition.passive_sensor_range_m = 8000.0 * float(frame.sensors)
	definition.active_sensor_range_m = 12000.0 * float(frame.sensors)
	definition.command_range_m = 7000.0 * float(frame.command)
	var personnel: Dictionary = campaign_fleet_snapshot.get("personnel_bonuses", {})
	var command_skill := int(personnel.get("command", 0))
	var gunnery_skill := int(personnel.get("gunnery", 0))
	var engineering_skill := int(personnel.get("engineering", 0))
	var sensor_skill := int(personnel.get("sensors", 0))
	var shield_multiplier := 1.2 if _installed_module("defense") == &"aegis_relay" else 1.0
	var armor_multiplier := 1.2 if _installed_module("defense") == &"ablative_citadel" else 1.0
	var hull_multiplier := (1.15 if _installed_module("support") == &"field_fabricator" else 1.0) * (1.0 + engineering_skill * 0.025)
	definition.passive_sensor_range_m *= 1.2 if _installed_module("sensor") == &"longwatch_array" else 1.0
	definition.active_sensor_range_m *= 1.2 if _installed_module("sensor") == &"longwatch_array" else 1.0
	definition.command_range_m *= 1.25 if _installed_module("sensor") == &"command_uplink" else 1.0
	definition.passive_sensor_range_m *= 1.0 + sensor_skill * 0.03
	definition.active_sensor_range_m *= 1.0 + sensor_skill * 0.03
	definition.command_range_m *= 1.0 + command_skill * 0.03
	definition.damage_layers = _damage_layers(600.0 * shield_multiplier * float(frame.shields), 700.0 * armor_multiplier * float(frame.armor), 950.0 * hull_multiplier * float(frame.hull), 12.0 * float(frame.shield_regen), 0.28 * float(frame.armor_mitigation))
	definition.weapons = [_weapon(&"carrier_flak", "Flak Barrage", "flak", 2200.0, 0.18, 12.0, 1900.0, false, false, true), _weapon(&"carrier_missile", "Long-Range Strike Missile", "missile", 8500.0, 6.5, 62.0, 720.0, true, true, false)]
	for weapon in definition.weapons:
		weapon.damage *= (1.0 + gunnery_skill * 0.025) * float(frame.weapon_damage)
	if _installed_module("weapon") == &"siege_missile_cell":
		definition.weapons[1].damage *= 1.2
	elif _installed_module("weapon") == &"flak_director":
		definition.weapons[0].range_m *= 1.25
	return definition

func _frigate_definition(ship_name: String, hostile: bool) -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"hostile_command_frigate" if hostile else &"human_missile_frigate"
	definition.display_name = ship_name
	definition.role = "frigate"
	definition.dimensions_m = Vector3(24.0, 12.0, 65.0)
	definition.acceleration_mps2 = 42.0
	definition.maximum_speed_mps = 220.0
	definition.rotation_speed_radians = 0.9
	definition.signature = 1.05
	var scale_value := campaign_threat_multiplier if hostile else 1.0
	definition.damage_layers = _damage_layers(260.0 * scale_value, 300.0 * scale_value, 340.0 * scale_value, 5.0, 0.22)
	definition.weapons = [_weapon(&"frigate_missile", "Frigate Missile", "missile", 4400.0, 4.0, 68.0 * scale_value, 570.0, false, true, false)]
	return definition

func _friendly_escort_definition(escort_id: StringName) -> ShipDefinition:
	var data := SidebayRunState.escort_data(escort_id)
	if data.is_empty():
		data = SidebayRunState.escort_data(&"iss_resolute")
	var definition := ShipDefinition.new()
	definition.ship_id = StringName(data.id)
	definition.display_name = str(data.name)
	definition.role = str(data.role)
	definition.dimensions_m = Vector3(float(data.width), float(data.height), float(data.length))
	definition.acceleration_mps2 = float(data.acceleration)
	definition.maximum_speed_mps = float(data.speed)
	definition.rotation_speed_radians = float(data.rotation)
	definition.signature = float(data.signature)
	definition.damage_layers = _damage_layers(float(data.shields), float(data.armor), float(data.hull), float(data.shield_regen), float(data.armor_mitigation))
	definition.weapons = [_weapon(StringName(data.weapon_id), str(data.weapon_name), str(data.weapon_role), float(data.weapon_range), float(data.weapon_cooldown), float(data.weapon_damage), float(data.projectile_speed), false, bool(data.weapon_tracks), bool(data.weapon_intercepts))]
	return definition

func _friendly_escort_color(escort_id: StringName) -> Color:
	match escort_id:
		&"iss_harrier":
			return Color(0.18, 0.62, 0.72)
		&"iss_bulwark":
			return Color(0.32, 0.44, 0.72)
		_:
			return Color(0.2, 0.48, 0.68)

func _corvette_definition() -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = &"hostile_screen_corvette"
	definition.display_name = "Acheron Screen Corvette"
	definition.role = "corvette"
	definition.dimensions_m = Vector3(16.0, 8.0, 42.0)
	definition.acceleration_mps2 = 58.0
	definition.maximum_speed_mps = 310.0
	definition.rotation_speed_radians = 1.25
	definition.signature = 0.8
	definition.damage_layers = _damage_layers(150.0 * campaign_threat_multiplier, 160.0 * campaign_threat_multiplier, 190.0 * campaign_threat_multiplier, 4.0, 0.16)
	definition.weapons = [_weapon(&"corvette_cannon", "Screen Cannon", "cannon", 1700.0, 0.8, 18.0 * campaign_threat_multiplier, 950.0)]
	return definition

func _fighter_definition(ship_id: StringName, name_value: String, role_value: String, hostile: bool = false) -> ShipDefinition:
	var definition := ShipDefinition.new()
	definition.ship_id = ship_id
	definition.display_name = name_value
	definition.role = role_value
	definition.dimensions_m = Vector3(6.0, 2.2, 8.0)
	definition.acceleration_mps2 = 210.0
	definition.maximum_speed_mps = 620.0 if hostile else 680.0
	definition.rotation_speed_radians = 3.0
	definition.signature = 0.45
	var scale_value := campaign_threat_multiplier if hostile else 1.0
	definition.damage_layers = _damage_layers(24.0 * scale_value, 16.0 * scale_value, 32.0 * scale_value, 1.0, 0.05)
	definition.weapons = [_weapon(&"fighter_cannon", "Pulse Cannon", "cannon", 780.0, 0.65, 10.0 * scale_value, 1400.0)]
	return definition

func _interceptor_squadron_definition() -> SquadronDefinition:
	var complement := SidebayRunState.hangar_complement_data(StringName(campaign_fleet_snapshot.get("active_hangar_complement_id", "balanced_wings")))
	if complement.is_empty():
		complement = SidebayRunState.hangar_complement_data(&"balanced_wings")
	var definition := SquadronDefinition.new()
	definition.squadron_id = &"raptor_interceptors"
	definition.display_name = "Raptor Interceptors"
	definition.role = "interceptor"
	definition.craft_count = int(campaign_fleet_snapshot.get("interceptor_craft_count", 4))
	definition.endurance_seconds = 125.0 * float(complement.interceptor_endurance)
	definition.ammunition_per_craft = int(complement.interceptor_ammo_per_craft)
	var flight_skill := int((campaign_fleet_snapshot.get("personnel_bonuses", {}) as Dictionary).get("flight", 0))
	definition.service_seconds = (4.5 if _installed_module("hangar") == &"rapid_turnaround_deck" else 6.0) * (1.0 - flight_skill * 0.04) * float(complement.service_time)
	definition.craft_definition = _fighter_definition(&"raptor", "Raptor", "fighter")
	return definition

func _scout_squadron_definition() -> SquadronDefinition:
	var complement := SidebayRunState.hangar_complement_data(StringName(campaign_fleet_snapshot.get("active_hangar_complement_id", "balanced_wings")))
	if complement.is_empty():
		complement = SidebayRunState.hangar_complement_data(&"balanced_wings")
	var definition := SquadronDefinition.new()
	definition.squadron_id = &"watcher_drones"
	definition.display_name = "Watcher Scout Drones"
	definition.role = "scout"
	definition.craft_count = int(campaign_fleet_snapshot.get("scout_craft_count", 3))
	definition.endurance_seconds = 155.0 * float(complement.scout_endurance)
	definition.ammunition_per_craft = int(complement.scout_ammo_per_craft)
	var flight_skill := int((campaign_fleet_snapshot.get("personnel_bonuses", {}) as Dictionary).get("flight", 0))
	definition.service_seconds = (4.5 if _installed_module("hangar") == &"rapid_turnaround_deck" else 6.0) * (1.0 - flight_skill * 0.04) * float(complement.service_time)
	definition.craft_definition = _fighter_definition(&"watcher", "Watcher", "drone")
	return definition

func _hostile_squadron_definition() -> SquadronDefinition:
	var definition := SquadronDefinition.new()
	definition.squadron_id = &"acheron_fighters"
	definition.display_name = "Acheron Fighter Wing"
	definition.role = "interceptor"
	definition.craft_count = 4
	definition.endurance_seconds = 300.0
	definition.ammunition_per_craft = 36
	definition.default_stance = "aggressive"
	definition.craft_definition = _fighter_definition(&"acheron_fighter", "Acheron Fighter", "fighter", true)
	return definition

func _damage_layers(shields: float, armor: float, hull: float, regen: float, mitigation: float) -> DamageLayerDefinition:
	var definition := DamageLayerDefinition.new()
	definition.max_shields = shields
	definition.max_armor = armor
	definition.max_hull = hull
	definition.shield_regeneration_per_second = regen
	definition.armor_mitigation = mitigation
	return definition

func _weapon(id_value: StringName, name_value: String, role_value: String, range_value: float, cooldown: float, damage_value: float, speed: float, lock_required: bool = false, tracks: bool = false, intercepts: bool = false) -> WeaponDefinition:
	var definition := WeaponDefinition.new()
	definition.weapon_id = id_value
	definition.display_name = name_value
	definition.role = role_value
	definition.range_m = range_value
	definition.cooldown_seconds = cooldown
	definition.damage = damage_value
	definition.projectile_speed_mps = speed
	definition.requires_identified_lock = lock_required
	definition.tracks_target = tracks
	definition.can_intercept_projectiles = intercepts
	return definition
