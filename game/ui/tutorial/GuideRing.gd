class_name GuideRing
extends RefCounted
## Where the coach mark's ring stands (ADR 0048 sections 3 and 5): pure functions of the active
## step, the control found for it and the screen, so `CoachMark` keeps only what changes.

const RING_GROW_DP: float = 6.0  ## The ring stands this far outside a control.
const MIN_TARGET_DP: float = 48.0  ## A ring is never smaller than a touch target.


## The ring's box for step `aim`, global px: a control's rect grown a little (the part of a card in
## a scroll list that is in view, or the list's edge nearest a card scrolled out of it), or the
## tile's ground ellipse, at least a touch target and pinned into `safe`. Empty with no anchor or no
## control to point at.
static func box(
	aim: TutorialLeadInDef,
	target: Control,
	camera: RtsCamera,
	hud_root: Node,
	view: Vector2,
	safe: Rect2,
	dp: float
) -> Rect2:
	var rect: Rect2 = Rect2()
	if aim == null:
		return rect
	match aim.anchor:
		TutorialBeatDef.Anchor.CONTROL:
			if not is_instance_valid(target):
				return Rect2()
			var shown: Rect2 = target.get_global_rect()
			var list: ScrollContainer = list_of(target, hud_root)
			if list != null:
				var seen: Rect2 = visible_rect(target, hud_root, view)
				shown = seen if seen.has_area() else _edge(list, shown, dp)
			rect = shown.grow(RING_GROW_DP * dp)
		TutorialBeatDef.Anchor.TILE:
			if camera == null:
				return Rect2()
			var world: Vector2 = IsoProjection.cell_centre_px(aim.anchor_tile.x, aim.anchor_tile.y)
			var radius: Vector2 = IsoProjection.ellipse_px(ViewScale.MILLI_PER_TILE) * camera.zoom
			rect = Rect2(camera.world_to_screen(world) - radius, radius * 2.0)
		_:
			return Rect2()
	var least: float = MIN_TARGET_DP * dp
	var fit: Vector2 = rect.size.max(Vector2(least, least))
	rect = Rect2(rect.get_center() - fit * 0.5, fit)
	if aim.anchor == TutorialBeatDef.Anchor.CONTROL and rect.intersects(safe):
		return rect.intersection(safe)  # A control's frame is cut at the edge, not moved off it.
	rect.position = rect.position.clamp(safe.position, (safe.end - rect.size).max(safe.position))
	return rect.intersection(safe) if rect.intersects(safe) else rect  # Never past an edge.


## `control`'s rect as the player sees it: cut by the scroll areas it stands in and by the screen.
static func visible_rect(control: Control, hud_root: Node, view: Vector2) -> Rect2:
	var shown: Rect2 = control.get_global_rect()
	var up: Node = control.get_parent()
	while up != null and up != hud_root:
		var area: ScrollContainer = up as ScrollContainer
		if area != null:
			shown = shown.intersection(area.get_global_rect())
		up = up.get_parent()
	return shown.intersection(Rect2(Vector2.ZERO, view))


## The scroll area `control` stands in below `hud_root`, or null.
static func list_of(control: Control, hud_root: Node) -> ScrollContainer:
	var up: Node = control.get_parent()
	while up != null and up != hud_root:
		if up is ScrollContainer:
			return up as ScrollContainer
		up = up.get_parent()
	return null


## The nearest ancestor of `tile` that can reveal a card (the `BuildSidebar`), or null.
static func sidebar_of(tile: Control) -> Node:
	var up: Node = tile.get_parent()
	while up != null and not up.has_method(&"reveal_tile"):
		up = up.get_parent()
	return up


## A least-size strip on the edge of `list` nearest to the scrolled-out `card` (global px).
static func _edge(list: ScrollContainer, card: Rect2, dp: float) -> Rect2:
	var area: Rect2 = list.get_global_rect()
	var strip: float = MIN_TARGET_DP * dp
	var above: bool = card.get_center().y < area.get_center().y
	return Rect2(
		area.position.x, area.position.y if above else area.end.y - strip, area.size.x, strip
	)
