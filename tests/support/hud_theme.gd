extends RefCounted
## The HUD's theme for a test that builds a HUD Control outside main.tscn, where nothing is
## inherited (P58). Not a test suite. In the scene the dp copy comes from HudTheme and follows a
## resize; here it is made once, at the dp factor of the moment, so set the UiScale override (if
## the test sets one) before calling `scaled()`.

const PATH: String = "res://game/ui/theme.tres"


## The theme as the file holds it, in dp.
static func source() -> Theme:
	return load(PATH)


## The theme in base px at the current dp factor: what HudTheme gives a HUD root.
static func scaled() -> Theme:
	return HudTheme.scaled(source(), UiScale.base_px_per_dp())
