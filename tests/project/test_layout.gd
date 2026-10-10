extends GdUnitTestSuite
## The folder layout of CLAUDE.md (Layout) and ADR 0002 section 1 (game/core).

const REQUIRED_DIRS: Array[String] = [
	"res://game/core",
	"res://game/sim",
	"res://game/view",
	"res://game/input",
	"res://game/ui",
	"res://game/ai",
	"res://game/ads",
	"res://game/meta",
	"res://data",
	"res://assets/art/svg",
	"res://assets/audio",
	"res://scenes/dev",
	"res://tests",
]


func test_required_folders_exist() -> void:
	var missing: Array[String] = []
	for dir: String in REQUIRED_DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			missing.append(dir)
	assert_array(missing).is_empty()
