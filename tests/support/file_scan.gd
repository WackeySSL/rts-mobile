extends RefCounted
## Recursive file listing and comment stripping for the contract tests. Not a test suite (no
## GdUnitTestSuite base).

## What a comment or a string looks like in GDScript, read from the left so that a comment hides the
## quote in it and a string hides the "#" in it. Group-free: the whole match is the token.
const TOKEN: String = (
	r'(?s)"""(?:[^\\]|\\.)*?"""|'
	+ r"'''(?:[^\\]|\\.)*?'''|"
	+ r'"(?:[^"\\]|\\.)*"|'
	+ r"'(?:[^'\\]|\\.)*'|"
	+ r"#[^\n]*"
)


## All files under `dir` (a res:// path) whose name ends with `extension`. Sorted by path, so a
## test never depends on the order the file system returns.
static func list_files(dir: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	_collect(dir, extension, found)
	found.sort()
	return found


## The lines of a GDScript source with its comments taken out. A string stays (a path in a string
## is code), and so does every line break, so a line keeps its number. A docstring in triple quotes
## is a string and stays.
static func code_lines(text: String) -> PackedStringArray:
	var token: RegEx = RegEx.create_from_string(TOKEN)
	var out: String = ""
	var at: int = 0
	for found: RegExMatch in token.search_all(text):
		out += text.substr(at, found.get_start() - at)
		if not found.get_string().begins_with("#"):
			out += found.get_string()
		at = found.get_end()
	return (out + text.substr(at)).split("\n")


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
