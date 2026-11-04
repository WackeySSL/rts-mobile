extends RefCounted
## The scene suites' shared set-up for the collapsible build menu (ADR 0024 sections 7 and 8, plan
## P85f). Not a test suite. A suite that builds the main scene (so a `BuildSidebar`) calls `begin()`
## in `before_test` and `end()` in `after_test`:
## - the slide is 0 ms for the test, so a collapse or an opening shows its target layout at once and
##   the layouts the suites measure never catch the menu half way. The override is static state on
##   `BuildSidebar`; the loaded `data/input_settings.tres`, which every scene shares through the
##   resource cache, is never written (`tests/ui/test_build_menu_slide.gd` is the one suite that
##   sets another duration, through the same override).
## - `HudPrefs` reads and writes a file of the suite's own under `user://` (ADR 0024 section 7), so
##   no suite touches the machine's `user://settings.cfg` and a Vibration switch left off by one
##   suite never silences another's haptic.
## `tests/project/test_menu_rig_scan.gd` fails on a suite that loads the main scene without calling
## it.

const PREFS_PATH: String = "user://test_menu_rig_settings.cfg"


## Before each test of a suite that builds the main scene.
static func begin() -> void:
	BuildSidebar.set_slide_ms_override(0)
	HudPrefs.set_path_override(PREFS_PATH)
	DirAccess.remove_absolute(PREFS_PATH)


## After each test of the same suite: no state is left for the next one.
static func end() -> void:
	BuildSidebar.clear_slide_ms_override()
	HudPrefs.clear_path_override()
	DirAccess.remove_absolute(PREFS_PATH)
