class_name SidebayAudio
extends Node

var sector_index: int = 0
var intensity: float = 0.25
var target_intensity: float = 0.25
var base_music: AudioStreamPlayer
var pulse_music: AudioStreamPlayer
var last_radio_message: String = ""
var radio_history: Array[String] = []

func _process(delta: float) -> void:
	intensity = move_toward(intensity, target_intensity, delta * 0.35)
	if is_instance_valid(base_music):
		base_music.volume_db = lerpf(-15.0, -8.0, intensity)
	if is_instance_valid(pulse_music):
		pulse_music.volume_db = lerpf(-42.0, -9.0, intensity)

func configure_sector(index: int, command_battle: bool = false) -> void:
	sector_index = clampi(index, 0, 2)
	target_intensity = 0.48 if command_battle else 0.24
	if DisplayServer.get_name() == "headless":
		return
	_stop_music()
	var roots := [55.0, 46.25, 41.2]
	base_music = _music_player(_create_score_stream(float(roots[sector_index]), false), -12.0)
	pulse_music = _music_player(_create_score_stream(float(roots[sector_index]) * 2.0, true), -28.0)
	base_music.name = "SectorScore"
	pulse_music.name = "CombatPulse"
	add_child(base_music)
	add_child(pulse_music)
	base_music.play()
	pulse_music.play()

func set_intensity(value: float) -> void:
	target_intensity = clampf(value, 0.0, 1.0)

func play_tone(frequency_hz: float, duration_seconds: float = 0.12, volume_db: float = -18.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var player := AudioStreamPlayer.new()
	player.stream = _create_tone_stream(frequency_hz, duration_seconds)
	player.volume_db = volume_db
	player.bus = &"SFX"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func play_radio(message: String, urgency: float = 0.5) -> void:
	last_radio_message = message
	radio_history.append(message)
	while radio_history.size() > 12:
		radio_history.pop_front()
	if DisplayServer.get_name() == "headless":
		return
	_radio_sequence(clampf(urgency, 0.0, 1.0))

func play_stinger(victory: bool) -> void:
	set_intensity(0.12 if victory else 0.75)
	play_tone(740.0 if victory else 90.0, 0.8, -10.0)

func _radio_sequence(urgency: float) -> void:
	var root_frequency := 520.0 + float(sector_index) * 65.0
	for multiplier in [1.0, 1.5, 1.25]:
		var player := AudioStreamPlayer.new()
		player.stream = _create_tone_stream(root_frequency * multiplier, 0.055 + urgency * 0.025)
		player.volume_db = -18.0 + urgency * 5.0
		player.bus = &"Radio"
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()
		await get_tree().create_timer(0.07, true, false, true).timeout

func _stop_music() -> void:
	for player in [base_music, pulse_music]:
		if is_instance_valid(player):
			player.queue_free()
	base_music = null
	pulse_music = null

func _music_player(stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = &"Music"
	return player

func _create_tone_stream(frequency_hz: float, duration_seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var sample_count := maxi(1, int(rate * duration_seconds))
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	for index in sample_count:
		var time := float(index) / float(rate)
		var envelope := pow(1.0 - float(index) / float(sample_count), 1.7)
		samples[index] = sin(TAU * frequency_hz * time) * envelope * 0.45
	return _stream_from_samples(samples, rate, false)

func _create_score_stream(root_frequency: float, rhythmic: bool) -> AudioStreamWAV:
	var rate := 22050
	var duration := 8.0
	var sample_count := int(rate * duration)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var intervals := [1.0, 1.2, 1.5] if sector_index == 0 else ([1.0, 1.1892, 1.4142] if sector_index == 1 else [1.0, 1.3333, 1.4983])
	for index in sample_count:
		var time := float(index) / float(rate)
		var value := 0.0
		if rhythmic:
			var beat := fposmod(time * (1.5 + float(sector_index) * 0.18), 1.0)
			var envelope := exp(-beat * 8.0)
			value = (sin(TAU * root_frequency * time) + sin(TAU * root_frequency * 0.5 * time) * 0.45) * envelope * 0.14
		else:
			for interval in intervals:
				value += sin(TAU * root_frequency * float(interval) * time + sin(time * 0.22) * 0.35)
			value = value / float(intervals.size()) * (0.16 + sin(time * 0.31) * 0.025)
		samples[index] = value
	return _stream_from_samples(samples, rate, true)

func _stream_from_samples(samples: PackedFloat32Array, rate: int, looped: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in samples.size():
		bytes.encode_s16(index * 2, clampi(int(samples[index] * 32767.0), -32768, 32767))
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
