extends SceneTree

var failures: Array[String] = []
const TEST_BASE := "exodrift_m15_save_test"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var manager := ExodriftSaveManager.new(TEST_BASE)
	_cleanup(manager)
	var first := SidebayRunState.create_new(1501)
	first.supplies = 73
	_assert_true(manager.write_state(first, "test") == OK, "first checkpoint writes atomically")
	var second := SidebayRunState.create_new(1502)
	second.supplies = 41
	_assert_true(manager.write_state(second, "test") == OK, "second checkpoint preserves a backup")
	_assert_true(FileAccess.file_exists(manager.backup_path), "backup checkpoint exists after replacement")
	var corrupt := FileAccess.open(manager.save_path, FileAccess.WRITE)
	corrupt.store_string("{broken checkpoint")
	corrupt.close()
	var recovered := manager.read_state()
	_assert_true(recovered != null and recovered.supplies == 73, "corrupt primary recovers the previous valid checkpoint")
	_assert_true(manager.last_source == &"backup", "save manager reports backup recovery")

	ExodriftInputSettings.ensure_actions()
	var original_ping := ExodriftInputSettings.action_key("sensor_ping")
	ExodriftInputSettings.rebind("sensor_ping", KEY_O)
	var config := ConfigFile.new()
	ExodriftInputSettings.save_bindings(config)
	ExodriftInputSettings.rebind("sensor_ping", KEY_P)
	ExodriftInputSettings.load_bindings(config)
	_assert_true(ExodriftInputSettings.action_key("sensor_ping") == KEY_O, "remapped controls persist through settings serialization")
	ExodriftInputSettings.rebind("sensor_ping", original_ping)
	var original_wings := ExodriftInputSettings.action_key("toggle_all_wings")
	ExodriftInputSettings.rebind("toggle_all_wings", KEY_N)
	_assert_true(ExodriftInputSettings.action_key("toggle_all_wings") == KEY_N, "aggregate hangar-wing control is remappable")
	ExodriftInputSettings.rebind("toggle_all_wings", original_wings)

	_assert_true(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Radio") >= 0, "independent music, SFX, and radio buses are configured")
	var menu := ExodriftMainMenu.new()
	root.add_child(menu)
	menu.configure(true)
	menu._request_new_run()
	_assert_true(menu.confirmation_panel.visible and not menu.main_panel.visible, "new operation requires confirmation when a checkpoint exists")
	menu.queue_free()
	_cleanup(manager)
	await process_frame
	if failures.is_empty():
		print("PASS: M15 save recovery, overwrite protection, audio buses, and control remapping")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d save/settings assertion(s)" % failures.size())
		quit(1)

func _cleanup(manager: ExodriftSaveManager) -> void:
	var directory := DirAccess.open("user://")
	if directory == null:
		return
	for file_name in [manager.save_file, manager.backup_file, manager.temp_file]:
		if directory.file_exists(file_name):
			directory.remove(file_name)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
