extends GdUnitTestSuite
## Plan P529 (ADR 0043 section 7): the licence texts the Licences screen shows from the pack are
## copies under assets/licenses/ of docs/licenses/ (the pack holds assets/, not docs/). The two
## folders hold the same files with the same bytes, so a text updated in one cannot go stale in the
## other.

const DOCS: String = "res://docs/licenses"
const PACKED: String = "res://assets/licenses"


func test_every_doc_text_has_an_equal_copy_in_the_pack_folder() -> void:
	var docs: Array[String] = _files(DOCS)
	assert_int(docs.size()).is_greater_equal(5)
	for relative: String in docs:
		var copy: String = PACKED + relative
		assert_bool(FileAccess.file_exists(copy)).override_failure_message(copy).is_true()
		(
			assert_str(FileAccess.get_sha256(copy))
			. override_failure_message(relative + " differs from its copy")
			. is_equal(FileAccess.get_sha256(DOCS + relative))
		)


func test_the_pack_folder_holds_nothing_the_doc_folder_lacks() -> void:
	var docs: Array[String] = _files(DOCS)
	for relative: String in _files(PACKED):
		assert_array(docs).override_failure_message(relative).contains([relative])


## Paths below `root`, each starting with a slash, sorted.
func _files(root: String) -> Array[String]:
	var found: Array[String] = []
	_walk(root, "", found)
	found.sort()
	return found


func _walk(root: String, relative: String, found: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(root + relative):
		found.append(relative + "/" + file)
	for folder: String in DirAccess.get_directories_at(root + relative):
		_walk(root, relative + "/" + folder, found)
