class_name IntroLoader
extends RefCounted
## The loads of the boot intro: `ResourceLoader`'s threaded API behind a seam, so a test swaps it
## for a fake that finishes when it says.

enum State { LOADING, LOADED, FAILED }


func request(path: String) -> void:
	ResourceLoader.load_threaded_request(path)


func state(path: String) -> State:
	match ResourceLoader.load_threaded_get_status(path):
		ResourceLoader.THREAD_LOAD_LOADED:
			return State.LOADED
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return State.LOADING
	return State.FAILED


## 0..1 of one load.
func progress(path: String) -> float:
	var found: Array = []
	ResourceLoader.load_threaded_get_status(path, found)
	return float(found[0]) if not found.is_empty() else 0.0


func take(path: String) -> Resource:
	return ResourceLoader.load_threaded_get(path)
