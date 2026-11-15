extends RefCounted
## The scene suites' shared set-up for the collapsible build menu (ADR 0024 sections 7 and 8, plan
## P85f). Not a test suite. A suite that builds the main scene (so a `BuildSidebar`) calls `begin()`
## in `before_test` and `end()` in `after_test`:
## - the slide is 0 ms for the test, so a collapse or an opening shows its target layout at once and
##   the layouts the suites measure never catch the menu half way. The override is static state on
##   `BuildSidebar`; the loaded `data/input_settings.tres`, which every scene shares through the
##   resource cache, is never written (`tests/ui/test_build_menu_slide.gd` is the one suite that
##   sets another duration, through the same override).
## - `HudPrefs` and `SaveService` read and write a save file of the suite's own, in a folder of its
##   own under `user://` (ADR 0024 section 7, ADR 0042), so no suite touches the machine's
##   `user://save.cfg` or `settings.cfg` and a Vibration switch left off by one suite never
##   silences another's haptic.
## `tests/project/test_menu_rig_scan.gd` fails on a suite that loads the main scene without calling
## it.


## Before each test of a suite that builds the main scene.
static func begin() -> void:
	BuildSidebar.set_slide_ms_override(0)
	_clean()
	DirAccess.make_dir_recursive_absolute(prefs_dir())
	HudPrefs.set_path_override(prefs_path())


## After each test of the same suite: no state is left for the next one.
static func end() -> void:
	BuildSidebar.clear_slide_ms_override()
	HudPrefs.clear_path_override()  # Pending changes go to the temp path first.
	_clean()


## The save file of this process: one folder per process, so lanes that run tests on one machine at
## the same time never share it, and the legacy `settings.cfg` looked for beside it is not the
## device's.
static func prefs_path() -> String:
	return prefs_dir().path_join("save.cfg")


static func prefs_dir() -> String:
	return "user://test_menu_rig_%d" % OS.get_process_id()


static func _clean() -> void:
	for file_name: String in DirAccess.get_files_at(prefs_dir()):
		DirAccess.remove_absolute(prefs_dir().path_join(file_name))
	DirAccess.remove_absolute(prefs_dir())
