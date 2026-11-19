extends GdUnitTestSuite
## The tutorial progress in the save (plan row P541): section `tutorial`, key `done`. A write keeps
## the section's other keys (P544 keeps "Basics offered" there) and a corrupt value reads as none.

var _dir: String = ""


func before_test() -> void:
	_dir = "user://test_tutorial_progress_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveService.set_path_override(_dir.path_join("save.cfg"))


func after_test() -> void:
	SaveService.clear_path_override()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func test_the_save_keeps_the_sections_other_keys() -> void:
	SaveService.set_section(TutorialDirector.SECTION, {"offered": true})
	assert_bool(TutorialDirector.mark_done(&"basics")).is_true()
	var values: Dictionary = SaveService.get_section(TutorialDirector.SECTION)
	assert_bool(values.get("offered", false)).is_true()
	assert_bool(TutorialDirector.is_done(&"basics")).is_true()


func test_a_corrupt_done_value_reads_as_none() -> void:
	SaveService.set_section(TutorialDirector.SECTION, {"done": 5, "offered": true})
	assert_int(TutorialDirector.lessons_done().size()).is_equal(0)
	assert_bool(TutorialDirector.mark_done(&"basics")).is_true()
	assert_array(Array(TutorialDirector.lessons_done())).is_equal(["basics"])
	assert_bool(SaveService.get_section(TutorialDirector.SECTION).get("offered", false)).is_true()
