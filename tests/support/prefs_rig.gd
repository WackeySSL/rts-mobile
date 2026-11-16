extends RefCounted
## Test support (P510b): points `HudPrefs` and `SaveService` at a save file in a folder of this
## process under `user://`, never at the device's `user://save.cfg` or `settings.cfg` (the legacy
## file is looked for beside the save file). `begin` starts clean; `end` leaves the services on
## the same temp default, not on the real path. `use(path)` is for a suite with its own folder;
## `restore` goes back to the default.


static func dir() -> String:
	return "user://test_prefs_%d" % OS.get_process_id()


static func path() -> String:
	return dir().path_join("save.cfg")


## A clean default save file, in use.
static func begin() -> void:
	use(path())  # Drains whatever was pending, to wherever it was pointed.
	for failure: String in clean(dir()):
		push_error("PrefsRig: could not remove " + failure)
	use(path())


## The services read and write `save_path`.
static func use(save_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	HudPrefs.set_path_override(save_path)


## Back on the clean default.
static func restore() -> void:
	begin()


static func end() -> void:
	begin()


## Removes the files and subfolders of `folder`, not the folder; returns what it could not remove.
static func clean(folder: String) -> Array[String]:
	var failures: Array[String] = []
	_empty(folder, failures)
	return failures


static func _empty(folder: String, failures: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub: String in DirAccess.get_directories_at(folder):
		_empty(folder.path_join(sub), failures)
		var dir_err: Error = DirAccess.remove_absolute(folder.path_join(sub))
		if dir_err != OK:
			failures.append("%s (%d)" % [folder.path_join(sub), dir_err])
	for file_name: String in DirAccess.get_files_at(folder):
		var err: Error = DirAccess.remove_absolute(folder.path_join(file_name))
		if err != OK:
			failures.append("%s (%d)" % [folder.path_join(file_name), err])
