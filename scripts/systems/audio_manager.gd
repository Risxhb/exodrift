class_name SidebayAudio
extends Node

func play_tone(frequency_hz: float, duration_seconds: float = 0.12, volume_db: float = -18.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var sample_count := int(stream.mix_rate * duration_seconds)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in sample_count:
		var envelope := 1.0 - float(index) / float(sample_count)
		var wave := sin(TAU * frequency_hz * float(index) / float(stream.mix_rate))
		bytes.encode_s16(index * 2, int(wave * envelope * 15000.0))
	stream.data = bytes
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
