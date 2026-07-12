class_name ExodriftRadarDisplay
extends Control

var carrier: PlayerCarrier
var sensors: SidebaySensorSystem
var pulse_phase: float = 0.0
var sweep_angle: float = -PI * 0.5
var display_range_m: float = 12000.0
var contact_refresh_accumulator: float = 0.0
var contact_cache: Array[Dictionary] = []

func configure(player_carrier: PlayerCarrier, sensor_system: SidebaySensorSystem) -> void:
	carrier = player_carrier
	sensors = sensor_system
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_refresh_contact_cache()
	queue_redraw()

func _process(delta: float) -> void:
	pulse_phase = fmod(pulse_phase + delta * 0.42, 1.0)
	sweep_angle = wrapf(sweep_angle + delta * 1.35, -PI, PI)
	contact_refresh_accumulator += delta
	if contact_refresh_accumulator >= 0.1:
		contact_refresh_accumulator = 0.0
		_refresh_contact_cache()
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.45
	draw_circle(center, radius + 2.0, Color(0.03, 0.24, 0.31, 0.42))
	draw_circle(center, radius, Color(0.004, 0.035, 0.05, 0.96))
	draw_circle(center, radius * 0.66, Color(0.005, 0.045, 0.06, 0.55))
	for ring_fraction in [0.33, 0.66, 1.0]:
		draw_arc(center, radius * ring_fraction, 0.0, TAU, 64, Color(0.12, 0.63, 0.75, 0.42), 1.0)
	for bearing_index in 12:
		var bearing := float(bearing_index) / 12.0 * TAU
		var bearing_direction := Vector2(cos(bearing), sin(bearing))
		draw_line(center + bearing_direction * (radius - 5.0), center + bearing_direction * radius, Color(0.2, 0.72, 0.82, 0.52), 1.0)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), Color(0.1, 0.45, 0.56, 0.3), 1.0)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), Color(0.1, 0.45, 0.56, 0.3), 1.0)
	var pulse_radius := radius * pulse_phase
	draw_arc(center, pulse_radius, 0.0, TAU, 64, Color(0.18, 0.88, 1.0, (1.0 - pulse_phase) * 0.48), 1.5)
	var sweep_end := center + Vector2(cos(sweep_angle), sin(sweep_angle)) * radius
	var sweep_wedge := PackedVector2Array([
		center,
		center + Vector2(cos(sweep_angle - 0.11), sin(sweep_angle - 0.11)) * radius,
		sweep_end
	])
	draw_colored_polygon(sweep_wedge, Color(0.12, 0.76, 0.9, 0.08))
	draw_line(center, sweep_end, Color(0.3, 0.95, 1.0, 0.68), 1.5)
	_draw_carrier(center)
	_draw_contacts(center, radius)

func _draw_carrier(center: Vector2) -> void:
	var ship := PackedVector2Array([
		center + Vector2(0.0, -9.0),
		center + Vector2(6.0, 7.0),
		center,
		center + Vector2(-6.0, 7.0)
	])
	draw_colored_polygon(ship, Color(0.24, 0.9, 1.0, 0.95))
	draw_polyline(PackedVector2Array([ship[0], ship[1], ship[2], ship[3], ship[0]]), Color(0.75, 0.98, 1.0, 0.92), 1.0)

func _draw_contacts(center: Vector2, radius: float) -> void:
	if not is_instance_valid(carrier):
		return
	display_range_m = maxf(1000.0, carrier.definition.active_sensor_range_m)
	for cached in contact_cache:
		var offset: Vector3 = cached.position - carrier.global_position
		var local := carrier.global_transform.basis.inverse() * offset
		var planar := Vector2(local.x, local.z) / display_range_m * radius
		if planar.length() > radius:
			planar = planar.normalized() * radius
		var point := center + planar
		var identified: bool = cached.identified
		var color := Color(1.0, 0.3, 0.1, 0.96) if identified else Color(1.0, 0.72, 0.16, 0.82)
		if identified:
			var marker := PackedVector2Array([point + Vector2(0, -5), point + Vector2(5, 0), point + Vector2(0, 5), point + Vector2(-5, 0)])
			draw_colored_polygon(marker, color)
		else:
			draw_circle(point, 2.5, color)
		var uncertainty_radius: float = cached.uncertainty
		if uncertainty_radius > 20.0:
			var uncertainty := clampf(uncertainty_radius / display_range_m * radius, 4.0, 24.0)
			draw_arc(point, uncertainty, 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.25), 1.0)

func _refresh_contact_cache() -> void:
	contact_cache.clear()
	if sensors == null:
		return
	for contact_value in sensors.contacts.values():
		var contact: SensorContact = contact_value
		contact_cache.append({
			"position": contact.estimated_position,
			"identified": contact.identification_state == SensorContact.IdentificationState.IDENTIFIED,
			"uncertainty": contact.uncertainty_radius_m
		})
