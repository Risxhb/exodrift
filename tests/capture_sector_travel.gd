extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	for _frame in 4:
		await process_frame
	var node := SidebayCampaignNode.create(&"travel_capture", "Vesper Relay", 1, 3, 1, SidebayCampaignNode.NodeType.COMBAT, 3, SidebayCampaignNode.ObjectiveType.INTERCEPTION)
	var state := SidebayRunState.create_new()
	var screen = (load("res://scripts/ui/sector_travel_screen.gd") as GDScript).new()
	root.add_child(screen)
	screen.configure(node, state.fleet_snapshot(), 0)
	for _frame in 120:
		if screen.loaded_scene != null:
			break
		await process_frame
	screen._enter_phase(screen.Phase.TRANSIT)
	screen.phase_elapsed = 1.85
	screen.displayed_progress = 0.62
	screen._update_transit(0.0)
	screen._update_loading_interface(0.0)
	screen.set_process(false)
	for _frame in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png(ProjectSettings.globalize_path("res://build/sector-travel-screen.png"))
	quit(0 if error == OK else 3)
