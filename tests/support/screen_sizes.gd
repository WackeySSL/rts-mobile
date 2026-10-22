extends RefCounted
## The window sizes that UI and layout suites run at (ADR 0015 section 6, plan P60). Not a test
## suite. A suite under tests/ui, tests/scenes or tests/view reads its sizes from here or from a
## profile of ui_profiles.gd and never spells one out; tests/project/test_screen_sizes_scan.gd
## fails on a suite that does.
## A phone is the middle size of each orientation. `PORTRAIT[i]` is `LANDSCAPE[i]` turned: the same
## screen held the other way, which has the same dp(48) (the UiOrientation autoload turns the base
## size with the window, so the stretch follows, ADR 0015 section 2).

## 1280x720 (the base size), 2400x1080 (20:9 phone) and 2048x1536 (4:3 tablet).
const LANDSCAPE: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(2048, 1536)]
## 720x1280, 1080x2400 and 1536x2048: the transposes of LANDSCAPE, entry by entry.
const PORTRAIT: Array[Vector2i] = [Vector2i(720, 1280), Vector2i(1080, 2400), Vector2i(1536, 2048)]
## All six: LANDSCAPE, then PORTRAIT (a test pins that it is exactly that).
const ALL: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(2400, 1080),
	Vector2i(2048, 1536),
	Vector2i(720, 1280),
	Vector2i(1080, 2400),
	Vector2i(1536, 2048),
]
