extends SceneTree

func _initialize() -> void:
	call_deferred("_profile")

func _profile() -> void:
	root.size = Vector2i(1920, 1080)
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(2.0).timeout
	var samples: Array[float] = []
	var frame_times_ms: Array[float] = []
	var started_usec := Time.get_ticks_usec()
	var previous_usec := started_usec
	for _frame in 600:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		frame_times_ms.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		var fps := Engine.get_frames_per_second()
		if fps > 0.0:
			samples.append(fps)
	var average := 0.0
	for sample in samples:
		average += sample
	average /= maxf(1.0, float(samples.size()))
	var elapsed_seconds := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var effective_fps := 600.0 / maxf(0.001, elapsed_seconds)
	frame_times_ms.sort()
	var p95 := _percentile(frame_times_ms, 0.95)
	var p99 := _percentile(frame_times_ms, 0.99)
	print("PERF: resolution=%dx%d engine_average=%.1f effective=%.1f p95=%.2fms p99=%.2fms samples=%d" % [root.size.x, root.size.y, average, effective_fps, p95, p99, samples.size()])
	quit(0 if average >= 60.0 and effective_fps >= 60.0 and p95 <= 16.7 and p99 <= 25.0 else 1)

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(ceili(float(values.size()) * fraction) - 1, 0, values.size() - 1)
	return values[index]
