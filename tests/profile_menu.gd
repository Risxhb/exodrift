extends SceneTree

const RESOLUTIONS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2560, 1440)]
const SAMPLE_FRAMES := 600

func _initialize() -> void:
	call_deferred("_profile")

func _profile() -> void:
	var passed := true
	for resolution in RESOLUTIONS:
		var result: Dictionary = await _profile_resolution(resolution)
		passed = passed and bool(result.passed)
	quit(0 if passed else 1)

func _profile_resolution(resolution: Vector2i) -> Dictionary:
	root.size = resolution
	var app := (load("res://scenes/app.tscn") as PackedScene).instantiate()
	root.add_child(app)
	await create_timer(1.0).timeout
	var samples: Array[float] = []
	var started_usec := Time.get_ticks_usec()
	for _frame in SAMPLE_FRAMES:
		await process_frame
		var fps := Engine.get_frames_per_second()
		if fps > 0.0:
			samples.append(fps)
	var average := 0.0
	for sample in samples:
		average += sample
	average /= maxf(1.0, float(samples.size()))
	var elapsed_seconds := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var effective_fps := float(SAMPLE_FRAMES) / maxf(0.001, elapsed_seconds)
	print("MENU PERF: resolution=%dx%d engine_average=%.1f effective=%.1f samples=%d" % [root.size.x, root.size.y, average, effective_fps, samples.size()])
	var passed := average >= 60.0 and effective_fps >= 60.0
	app.queue_free()
	await process_frame
	await process_frame
	return {"resolution": resolution, "passed": passed}
