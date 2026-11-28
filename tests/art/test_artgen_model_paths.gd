extends GdUnitTestSuite
## `ArtGen.model_paths()` lists only `ArtModel` files: a pre-render `_detail.tres` (ADR 0053) that
## sits in a models folder is skipped, so the generator, the galleries and the art tests never load
## one as an `ArtModel` (the terrain kit, P656c, and the building detail files, P644b).

const PROBE_DIR: String = "res://assets/art/models/zz_probe"
const PROBE: String = PROBE_DIR + "/probe_detail.tres"


func after_test() -> void:
	DirAccess.remove_absolute(PROBE)
	DirAccess.remove_absolute(PROBE_DIR)


func test_a_detail_file_in_a_models_folder_is_not_listed() -> void:
	assert_int(DirAccess.make_dir_recursive_absolute(PROBE_DIR)).is_equal(OK)
	var file: FileAccess = FileAccess.open(PROBE, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string('[gd_resource type="Resource" format=3]\n\n[resource]\n')
	file.close()
	assert_bool(FileAccess.file_exists(PROBE)).is_true()
	assert_array(ArtGen.model_paths()).not_contains([PROBE])


func test_every_listed_path_is_an_art_model() -> void:
	var paths: Array[String] = ArtGen.model_paths()
	assert_array(paths).is_not_empty()
	for path: String in paths:
		assert_str(path).not_contains("_detail.tres")
		assert_object(load(path) as ArtModel).is_not_null()
