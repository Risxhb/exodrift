extends SceneTree

const ASSET_ROOT := "res://assets/ships"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures := PackedStringArray()
	var paths := _manifest_paths(ASSET_ROOT)
	for path in paths:
		var asset := load(path) as ShipVisualAsset
		if asset == null:
			failures.append("%s is not a ShipVisualAsset" % path)
			continue
		for error in asset.manifest_errors():
			failures.append("%s: %s" % [path, error])
		if asset.model_scene == null:
			continue
		var model := asset.instantiate_model()
		for error in asset.instance_errors(model):
			failures.append("%s: %s" % [path, error])
		if model != null:
			var metrics := asset.model_metrics(model)
			print("ASSET: %s // %d triangles // %d material slots" % [asset.ship_id, metrics.get("triangles", 0), metrics.get("material_slots", 0)])
			model.free()
	if failures.is_empty():
		print("PASS: %d production ship asset manifest(s) validated" % paths.size())
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _manifest_paths(root_path: String) -> Array[String]:
	var results: Array[String] = []
	var directory := DirAccess.open(root_path)
	if directory == null:
		return results
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			if not entry.begins_with(".") and entry != "_template":
				results.append_array(_manifest_paths(path))
		elif entry.ends_with("_visual_asset.tres"):
			results.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	results.sort()
	return results
