class_name GuideLookup
extends RefCounted
## What the coach mark looks up in the HUD, with the throttles that keep it off the per-frame path
## (ADR 0048 sections 3 and 5): the control a step names, the ad band of its scope, and the one
## reveal of a drawer card per step entry. State is only counters and a cache; the mark owns the
## rest.

const FIND_EVERY: int = 15  ## Frames between looks for a control that is not there.
const STILL_FRAMES: int = 2  ## Frames a card's rect holds before it is revealed.

var _next_find: int = 0
var _revealed: bool = false
var _still: int = 0
var _last: Rect2 = Rect2()
var _band_scope: Node = null  ## The scope whose ad bands are cached.
var _bands: Array[Control] = []
var _band_scan: int = 0


## A new step: look for its control now and reveal its card once more.
func reset_step() -> void:
	_next_find = 0
	_revealed = false
	_still = 0
	_last = Rect2()


## A new beat: its controls may be new, list the ad bands again.
func rescan() -> void:
	_band_scan = 0


## `current` while it stands and shows, else the control `aim` names under `hud_root` (looked for
## every `FIND_EVERY` frames only), else null.
func find(aim: TutorialLeadInDef, hud_root: Node, current: Control) -> Control:
	if aim == null or aim.anchor != TutorialBeatDef.Anchor.CONTROL:
		return null
	if is_instance_valid(current) and current.is_visible_in_tree():
		return current
	var frame: int = Engine.get_process_frames()
	if hud_root == null or aim.anchor_control == &"" or frame < _next_find:
		return null
	_next_find = frame + FIND_EVERY
	var found: Control = hud_root.find_child(String(aim.anchor_control), true, false) as Control
	return found if found != null and found.is_visible_in_tree() else null


## Asks the sidebar to scroll the drawer card `tile` clear of the foot room: once per step entry,
## and only after its rect has held for `STILL_FRAMES` looks, since the grid sorts and the drawer
## slides after a tab change. A player who scrolls away is not fought. A tile outside a sidebar is
## given up on at once.
func reveal(tile: ItemTile) -> void:
	if _revealed or tile == null or tile.size.y <= 0.0:
		return
	var rect: Rect2 = tile.get_global_rect()
	_still = _still + 1 if rect == _last else 0
	_last = rect
	if _still < STILL_FRAMES:
		return
	_revealed = true
	var sidebar: BuildSidebar = GuideRing.sidebar_of(tile)
	if sidebar != null:
		sidebar.reveal_tile(tile)


## The visible rect of the ad band of `scope` (the modal, else the HUD): the dock ends 16 dp above
## it (ad policy). The bands are listed once per scope and again every `FIND_EVERY` frames; whether
## one shows and its rect are read each frame. Empty with none.
func ad_band(scope: Node, hud_root: Node, view: Vector2) -> Rect2:
	if scope == null:
		_band_scope = null
		return Rect2()
	var frame: int = Engine.get_process_frames()
	if scope != _band_scope or frame >= _band_scan:
		_band_scope = scope
		_band_scan = frame + FIND_EVERY
		_bands.clear()
		for node: Node in scope.find_children("*", "AdBannerBand", true, false):
			_bands.append(node as Control)
	for band: Control in _bands:
		if is_instance_valid(band) and band.is_visible_in_tree():
			var shown: Rect2 = GuideRing.visible_rect(band, hud_root, view)
			if shown.has_area():
				return shown
	return Rect2()


## Whether `host`'s children hold a visible modal (the pause menu, a question, the result screen,
## an overlay of the menu) that does not hold `target`: the mark `self_node` must stand down, since
## its card and ring would sit over a menu they have nothing to say about and would eat its taps.
## Only a card that points into the modal shows over it (the `resume` card over the pause menu).
static func covered(host: Node, self_node: Node, target: Control) -> bool:
	if host == null:
		return false
	for node: Node in host.get_children():
		if _covers(node, self_node, target):
			return true
		if node is ModalFrame:  # The questions and the overlays of a menu are its children.
			for inner: Node in node.get_children():
				if _covers(inner, self_node, target):
					return true
	return false


static func _covers(node: Node, self_node: Node, target: Control) -> bool:
	var control: Control = node as Control
	if control == null or control == self_node:
		return false
	if not (control is ModalFrame or control is MenuStack) or not control.is_visible_in_tree():
		return false
	return not (is_instance_valid(target) and control.is_ancestor_of(target))


## Whether `box` is under 8 dp from a visible button of `modal`.
static func touches(box: Rect2, modal: Node, dp: float) -> bool:
	var near: Rect2 = box.grow(8.0 * dp - 0.01)
	for node: Node in modal.find_children("*", "BaseButton", true, false):
		var button: Control = node as Control
		if button.is_visible_in_tree() and near.intersects(button.get_global_rect()):
			return true
	return false
