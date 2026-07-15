extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var input_path := ""
	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--input="):
			input_path = argument.trim_prefix("--input=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	if input_path.is_empty() or output_path.is_empty():
		push_error("Usage: --input=res://path/source.svg --output=res://path/source.png")
		quit(2)
		return
	var texture := load(input_path) as Texture2D
	if texture == null:
		push_error("Unable to load texture: %s" % input_path)
		quit(1)
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		push_error("Unable to read image data: %s" % input_path)
		quit(1)
		return
	var error := image.save_png(ProjectSettings.globalize_path(output_path))
	if error != OK:
		push_error("Unable to write PNG %s: error %d" % [output_path, error])
		quit(1)
		return
	print("WROTE: %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
	quit(0)
