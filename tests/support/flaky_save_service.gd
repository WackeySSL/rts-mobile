extends "res://game/meta/save_service.gd"
## SaveService whose first write fails its read-back (test_save_service_values.gd). A file of its
## own: an inner class with a script base is not allowed (test_inner_classes_extend_engine_classes).

var fail_once: bool = true


func _write() -> Error:
	if fail_once:
		fail_once = false
		return ERR_FILE_CORRUPT
	return super()
