extends RefCounted
## Reads one function out of a GDScript source for the scan tests of the life layer (plan P136):
## test_life_purity.gd and test_life_frames.gd. Not a test suite.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")


## The code of function `name` of the script at `path`, comments taken out: from its `func` line
## to the line before the next function, an annotation or the end of the file. Empty when the
## script has no such function.
static func function(path: String, name: String) -> String:
	var out: String = ""
	var inside: bool = false
	for line: String in FileScan.code_lines(FileAccess.get_file_as_string(path)):
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
		elif inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		elif inside and line.begins_with("@"):
			break
		if inside:
			out += line + "\n"
	return out
