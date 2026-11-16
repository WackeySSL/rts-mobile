class_name FakeIntroLoader
extends IntroLoader
## A loader that finishes when the test says: every request stays LOADING until `finish`.

var states: Dictionary[String, IntroLoader.State] = {}
var requested: Array[String] = []
var taken: Array[String] = []
var scene: PackedScene = null


func request(path: String) -> void:
	requested.append(path)
	states[path] = IntroLoader.State.LOADING


func state(path: String) -> IntroLoader.State:
	return states[path]


func progress(path: String) -> float:
	return 1.0 if states[path] == IntroLoader.State.LOADED else 0.25


func take(path: String) -> Resource:
	taken.append(path)
	return scene if path.ends_with(".tscn") else null


func finish(state_now: IntroLoader.State = IntroLoader.State.LOADED) -> void:
	for path: String in states:
		states[path] = state_now
