extends RefCounted
## Recursive file listing for the contract tests. Not a test suite (no GdUnitTestSuite base).


## All files under `dir` (a res:// path) whose name ends with `extension`. Sorted by path, so a
## test never depends on the order the file system returns.
static func list_files(dir: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	_collect(dir, extension, found)
	found.sort()
	return found


static func _collect(dir: String, extension: String, found: Array[String]) -> void:
	var access: DirAccess = DirAccess.open(dir)
	if access == null:
		return
	for file_name: String in access.get_files():
		if file_name.ends_with(extension):
			found.append(dir.path_join(file_name))
	for sub_dir: String in access.get_directories():
		if not sub_dir.begins_with("."):
			_collect(dir.path_join(sub_dir), extension, found)
