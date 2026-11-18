class_name HudState
extends RefCounted
## Which panel of the corner HUD is unfolded (ADR 0025 section 1, plan P119c): none, the build
## drawer, the full radar map, the economy card or the pause menu, one at a time. View state only:
## no Command, nothing in the sim, the replay or the hash. It knows no node, no screen and no
## clock. The parts that show an unfold (the drawer, the scope, the card, the pause menu) read
## `current`, listen to `changed` and ask `open`/`close`; `HudStateFeed` tells it what the screen
## does (a gesture on the map, a finger down, a frame, a mode that began, a new match).
## The rules:
## - Opening an unfold closes the open one; requests apply in order, the last one wins.
## - PAUSE is modal and takes every touch: nothing opens behind it and nothing but `close(PAUSE)`
##   (Resume) or a new match leaves it.
## - A gesture on the map (`map_gesture`; the placement or strike aim that begins, `mode_started`)
##   closes the drawer, the economy card and the full map unless it is pinned. The gesture's own
##   work (the order, the selection, the pan) is its router's: this class only folds.
## - A finger down anywhere (`touch_down`) closes the economy card and nothing else, so a touch on
##   a HUD control leaves the drawer and the full map as they are. That touch's own release cannot
##   open the card again (a tap on the pill's numbers while the card shows only dismisses it): after
##   a touch closes the card, `open(ECONOMY)` is refused until the next first finger down (a code
##   path that opens the card with no finger down would be refused; none exists today).
## - The full map folds `radar_close_ms` of frame time after it opened or was last touched
##   (`touch_radar`), unless it is pinned. The pin is view state for the match.
## - A turn is no event here: the state is kept. A new match (`reset`) starts with nothing unfolded.
## `fill` hands the layout (`HudCorners.place`) the three entries the unfolds decide; `fill_bar`
## the two the command bar decides (whether it holds its slot, and how wide it asks to be, P122).

## The unfold changed (`previous` was open before it), or the pin flipped (then `previous` is the
## unfold that stays).
signal changed(previous: Unfold)

enum Unfold { NONE, DRAWER, RADAR, ECONOMY, PAUSE }

var settings: InputSettings  ## `radar_close_ms` is read from here at each frame.
## The open unfold. Read-only: change it with `open` and `close`, so that the rules and `changed`
## run. (A property with a getter alone ignores an assignment without a word; this one asserts.)
var current: Unfold:
	get:
		return _current
	set(_value):
		assert(false, "HudState.current is read-only: use open() and close().")
## The full map stays open: no gesture, no timer closes it. Opening another unfold, the collapse
## button (`close(RADAR)`) and a new match do.
var pinned: bool:
	get:
		return _pinned
	set(value):
		if value == _pinned:
			return
		_pinned = value
		_idle_ms = 0.0  # Unpinning starts a fresh count.
		changed.emit(_current)

var _current: Unfold = Unfold.NONE
var _bar: bool = false  ## The command bar holds its slot (a selection, or the slot a mode keeps).
var _bar_width: float = 0.0  ## The bar's content width in dp (landscape), 0 for its least.
var _pinned: bool = false
var _idle_ms: float = 0.0  ## Frame time since the full map opened or was touched.
var _card_guard: bool = false  ## A touch closed the card; no first finger has gone down since.


func _init(from: InputSettings = null) -> void:
	settings = from if from != null else InputSettings.new()  # The script defaults are the table.


func is_open(which: Unfold) -> bool:
	return _current == which


## Unfolds `which` (not NONE) and closes the one that was open. False when nothing changed because
## PAUSE is open, or because the finger that just closed the card is the one asking for it again.
func open(which: Unfold) -> bool:
	if which == Unfold.NONE or (_current == Unfold.PAUSE and which != Unfold.PAUSE):
		return false
	if which == Unfold.ECONOMY and _card_guard:
		return false
	_switch(which)
	return true


## Folds `which` when it is the open one (the drawer's close button, the radar's collapse button,
## Resume), so a late request never closes what replaced it.
func close(which: Unfold) -> void:
	if _current == which and which != Unfold.NONE:
		_switch(Unfold.NONE)


## A gesture on the map began (`TouchInput.map_gesture`).
func map_gesture() -> void:
	_fold_for_map()


## Placement or a strike aim began: it folds what a gesture on the map folds.
func mode_started() -> void:
	_fold_for_map()


## A finger went down, on the map or on a HUD control; `first` says that no other finger was down.
## It closes the economy card. Only a first finger clears the card's guard, so a second finger
## cannot let the first one's release open the card again.
func touch_down(first: bool = true) -> void:
	if first:
		_card_guard = false
	if _current == Unfold.ECONOMY:
		_card_guard = true
		_switch(Unfold.NONE)


## The full map was touched (a tap, a drag or a hold on it, or on its head): the count starts over.
func touch_radar() -> void:
	_idle_ms = 0.0


## A frame of `delta_ms` passed. The full map folds when it has gone `radar_close_ms` untouched.
func advance(delta_ms: float) -> void:
	if _current != Unfold.RADAR or _pinned:
		return
	_idle_ms += delta_ms
	if _idle_ms >= float(settings.radar_close_ms):
		_switch(Unfold.NONE)


## A new match: nothing unfolded, nothing pinned, and no touch remembered. Tells `changed` once.
func reset() -> void:
	var previous: Unfold = _current
	var moved: bool = _current != Unfold.NONE or _pinned
	_current = Unfold.NONE
	_pinned = false
	_idle_ms = 0.0
	_card_guard = false
	if moved:
		changed.emit(previous)


## Sets the entries of `shown` that the unfolds decide: the open drawer, the full map and the
## economy card (`HudCorners.place` lays them out). PAUSE is no entry: its menu covers the HUD.
func fill(shown: HudCorners.Shown) -> void:
	shown.drawer = _current == Unfold.DRAWER
	shown.map = _current == Unfold.RADAR
	shown.card = _current == Unfold.ECONOMY


## The command bar's slot and width changed (`CommandBar`): the parts that stand by it (the group
## column's foot, the full map) place themselves again through `changed`, which carries
## the open unfold unchanged. Nothing is emitted when neither value moved.
func set_bar(slot: bool, width_dp: float) -> void:
	if slot == _bar and is_equal_approx(width_dp, _bar_width):
		return
	_bar = slot
	_bar_width = width_dp
	changed.emit(_current)


## Sets the entries of `shown` that the command bar decides (the bar's own rect and the group
## column's foot read them).
func fill_bar(shown: HudCorners.Shown) -> void:
	shown.bar = _bar
	shown.bar_width = _bar_width


func _fold_for_map() -> void:
	if _current == Unfold.DRAWER or _current == Unfold.ECONOMY:
		_switch(Unfold.NONE)
	elif _current == Unfold.RADAR and not _pinned:
		_switch(Unfold.NONE)


func _switch(next: Unfold) -> void:
	_idle_ms = 0.0
	if next == _current:
		return
	var previous: Unfold = _current
	_current = next
	changed.emit(previous)
