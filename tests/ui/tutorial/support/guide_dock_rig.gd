extends RefCounted
## What the GuideDock suites share (plan P584). Not a suite.


## Whether a `GuideDock.MIN_DP` square fits at the dock's fixed top (64 dp under the safe top, the
## landscape top row), 8 dp clear of every part (the economy card aside) and inside the safe rect.
## Independent of `GuideDock.place`: a 4 dp scan along that row.
static func free_rect(rects: Dictionary[StringName, Rect2], safe: Rect2, dp: float) -> bool:
	var size: float = GuideDock.MIN_DP * dp
	var gap: float = 8.0 * dp
	var y: float = safe.position.y + 64.0 * dp
	var x: float = safe.position.x
	while x + size <= safe.end.x:
		var square: Rect2 = Rect2(x, y, size, size)
		var clear: bool = true
		for key: StringName in rects:
			if key != HudCorners.CARD and square.grow(gap - 0.01).intersects(rects[key]):
				clear = false
				break
		if clear:
			return true
		x += 4.0 * dp
	return false


static func rects(
	safe: Rect2, portrait: bool, dp: float, args: Array
) -> Dictionary[StringName, Rect2]:
	var extra: Array = args.slice(5)
	extra.resize(3)
	var shown: HudCorners.Shown = GuideDock.shown_for_dock(
		portrait,
		args[0],
		args[1],
		args[2],
		args[3],
		extra[0] == true,
		extra[1] == true,
		extra[2] == true
	)
	return GuideDock.hud_for_dock(safe, portrait, dp, args[4], shown)
