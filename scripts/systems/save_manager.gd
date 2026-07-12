class_name ExodriftSaveManager
extends RefCounted

var save_file: String = "sidebay_run.json"
var backup_file: String = "sidebay_run.json.bak"
var temp_file: String = "sidebay_run.json.tmp"
var save_path: String = "user://sidebay_run.json"
var backup_path: String = "user://sidebay_run.json.bak"
var temp_path: String = "user://sidebay_run.json.tmp"

var last_message: String = ""
var last_source: StringName = &"none"

func _init(base_name: String = "sidebay_run") -> void:
	save_file = "%s.json" % base_name
	backup_file = "%s.json.bak" % base_name
	temp_file = "%s.json.tmp" % base_name
	save_path = "user://%s" % save_file
	backup_path = "user://%s" % backup_file
	temp_path = "user://%s" % temp_file

func has_any_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(backup_path)

func write_state(state: SidebayRunState, reason: String = "manual") -> Error:
	if state == null:
		last_message = "Save rejected: no active operation."
		return ERR_INVALID_DATA
	var temp := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp == null:
		last_message = "Save failed: %s" % error_string(FileAccess.get_open_error())
		return FileAccess.get_open_error()
	temp.store_string(JSON.stringify(state.to_dictionary(), "  "))
	temp.flush()
	temp.close()
	var directory := DirAccess.open("user://")
	if directory == null:
		last_message = "Save failed: persistent storage unavailable."
		return ERR_CANT_OPEN
	if directory.file_exists(backup_file):
		directory.remove(backup_file)
	if directory.file_exists(save_file):
		var backup_error := DirAccess.copy_absolute(save_path, backup_path)
		if backup_error != OK:
			last_message = "Save failed while preserving backup: %s" % error_string(backup_error)
			return backup_error
		directory.remove(save_file)
	var rename_error := DirAccess.rename_absolute(temp_path, save_path)
	if rename_error != OK:
		var copy_error := DirAccess.copy_absolute(temp_path, save_path)
		if copy_error == OK:
			directory.remove(temp_file)
		else:
			last_message = "Atomic save failed: %s" % error_string(rename_error)
			return rename_error
	last_source = &"primary"
	last_message = "%s checkpoint saved." % reason.capitalize()
	return OK

func read_state() -> SidebayRunState:
	var primary := _read_path(save_path)
	if primary != null:
		last_source = &"primary"
		last_message = "Operation restored from the latest checkpoint."
		return primary
	var backup := _read_path(backup_path)
	if backup != null:
		_restore_backup_to_primary()
		last_source = &"backup"
		last_message = "Primary checkpoint was invalid; the backup was recovered."
		return backup
	last_source = &"corrupt" if has_any_save() else &"missing"
	last_message = "Checkpoint data is corrupt or unsupported." if has_any_save() else "No operation checkpoint exists."
	return null

func _read_path(path: String) -> SidebayRunState:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return null
	return SidebayRunState.from_dictionary(parser.data)

func _restore_backup_to_primary() -> void:
	var directory := DirAccess.open("user://")
	if directory == null or not directory.file_exists(backup_file):
		return
	if directory.file_exists(save_file):
		directory.remove(save_file)
	DirAccess.copy_absolute(backup_path, save_path)
