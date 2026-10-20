extends MatchRunner
## A MatchRunner whose guard, _shared(), answers `allow` instead of the rule and logs nothing, so
## test_match_runner_access.gd closes the guard of `world`, `loop`, `replay` and `probe` with no
## job in flight and without the error that would fail verify.sh's log scan. Not a test suite. It
## has its own file because an inner class may not extend a script, and it never names itself
## (tests/project/test_inner_classes_extend_engine_classes.gd).

## What the guard answers.
var allow: bool = true


func _shared(_what: StringName) -> bool:
	return allow
