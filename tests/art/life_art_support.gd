extends RefCounted
## What the suites of the life atlases (plan row P135) share: STYLE.md's "Life effects" section,
## its region table and the cells it implies. The ink of the two SVGs is checked against these
## cells (test_life_atlases.gd), and so are `LifeRegions` and the gallery's Life page, so the three
## agree with each other only by agreeing with the guide.

const STYLE_PATH: String = "res://assets/art/STYLE.md"


## The text of STYLE.md from the "Life effects" heading to the next one.
static func section() -> String:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	var start: int = style.find("## Life effects")
	return style.substr(start, style.find("\n## ", start + 1) - start)


## The table's rows in the order the guide gives them: kind, atlas, region of frame 0, frames, step
## and anchor.
static func table() -> Array[Dictionary]:
	var row: RegEx = (
		RegEx
		. create_from_string(
			(
				"\\| `(\\w+)` \\| (life|strike) \\| (\\d+), (\\d+), (\\d+), (\\d+) \\| (\\d+) \\| (\\d+) "
				+ "\\| [a-z ]+ (\\d+), (\\d+) \\|"
			)
		)
	)
	var rows: Array[Dictionary] = []
	for found: RegExMatch in row.search_all(section()):
		(
			rows
			. append(
				{
					"kind": StringName(found.get_string(1)),
					"atlas": found.get_string(2),
					"rect":
					Rect2i(
						int(found.get_string(3)),
						int(found.get_string(4)),
						int(found.get_string(5)),
						int(found.get_string(6))
					),
					"frames": int(found.get_string(7)),
					"step": int(found.get_string(8)),
					"anchor": Vector2(int(found.get_string(9)), int(found.get_string(10))),
				}
			)
		)
	return rows


## Every frame of every kind: atlas, kind, frame number and its cell.
static func cells() -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for row: Dictionary in table():
		var box: Rect2i = row["rect"]
		for frame: int in row["frames"]:
			(
				cells
				. append(
					{
						"atlas": row["atlas"],
						"kind": row["kind"],
						"frame": frame,
						"rect": Rect2i(box.position + Vector2i(frame * row["step"], 0), box.size),
					}
				)
			)
	return cells


## The joins the guide names, "`trail` joins `lance_down` at 17, 65": the sprite and the point.
static func joins() -> Dictionary[StringName, Vector2]:
	var found: Dictionary[StringName, Vector2] = {}
	var join: RegEx = RegEx.create_from_string("joins\\s+`(\\w+)`\\s+at (\\d+), (\\d+)")
	for hit: RegExMatch in join.search_all(section()):
		found[StringName(hit.get_string(1))] = Vector2(
			int(hit.get_string(2)), int(hit.get_string(3))
		)
	return found
