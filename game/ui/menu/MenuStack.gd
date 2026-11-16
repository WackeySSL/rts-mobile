class_name MenuStack
extends Control
## The stack of menu screens (ADR 0043 sections 3 and 4). `push`, `pop` and `replace` slide a screen
## for `slide_ms`; with `reduced` (the player's Reduced effects switch) or `slide_ms` 0 they cut.
## Only the top screen is in the tree (a covered one is detached, not freed: its scroll and focus
## are kept, and a banner band it hosts gets exit_tree, so the banner request drops). During a
## slide a blocker takes every touch and push, pop, replace and back are ignored, so two screens
## never stack by a double tap.
## Back (`NOTIFICATION_WM_GO_BACK_REQUEST`, or `back()`): an open question closes, a screen above
## the root pops, the root asks "Quit Treadline?". Back in a match is the pause menu's job.
## It holds no game rule and sends no Command. Call `push` and the rest once the stack is ready.

signal screen_changed(screen: MenuScreen)

@export var slide_ms: int = 200
## Handed to every screen as its opaque backdrop (set in menu.tscn).
@export var backdrop_color: Color
## Reduced effects: every change of screen is a cut. The owner sets it (the settings screen, P526).
var reduced: bool = false
## What a yes to the quit question does; tests replace it.
var quit_handler: Callable = _quit_app

var _screens: Array[MenuScreen] = []
var _focus: Dictionary = {}  ## Screen -> the Control that had the focus (may be freed since).
var _blocker: Control
var _quit: ConfirmDialog
var _tween: Tween = null
var _finish: Callable = Callable()


func _enter_tree() -> void:
	# TODO(P521/P533): ADR 0043 section 4 wants application/config/quit_on_go_back = false for the
	# whole app; the project setting comes with the row that edits project.godot. Until then the
	# first menu switches it off and nothing switches it back on.
	get_tree().quit_on_go_back = false


func _ready() -> void:
	MenuText.register()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker = Control.new()
	_blocker.name = &"Blocker"
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	add_child(_blocker)
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quit = ConfirmDialog.new()
	_quit.name = &"QuitQuestion"
	_quit.question = tr(MenuText.QUIT_TITLE)
	_quit.detail = tr(MenuText.QUIT_DETAIL)
	_quit.yes_text = tr(MenuText.QUIT_YES)
	_quit.no_text = tr(MenuText.QUIT_NO)
	_quit.confirmed.connect(func() -> void: quit_handler.call())
	_quit.cancelled.connect(func() -> void: _restore_focus(current()))
	add_child(_quit)
	_quit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back.call_deferred()  # Never change scenes inside a notification dispatch.
	elif what == NOTIFICATION_PREDELETE:
		for screen: MenuScreen in _screens:  # The covered ones are not our children: free them.
			if is_instance_valid(screen) and screen.get_parent() == null:
				screen.free()


func depth() -> int:
	return _screens.size()


func current() -> MenuScreen:
	return null if _screens.is_empty() else _screens.back()


func is_asking_to_quit() -> bool:
	return _quit.visible


func is_sliding() -> bool:
	return _tween != null


## Puts `screen` on top; the one under it leaves the tree when the slide ends. During a slide the
## call is ignored: false, and `screen` (which the stack would own) is freed.
func push(screen: MenuScreen) -> bool:
	if is_sliding():
		screen.free()
		return false
	var below: MenuScreen = current()
	_remember_focus(below)
	_add(screen)
	_screens.append(screen)
	_run(screen, below, true, false)
	return true


## Removes the top screen (never the root) and shows the one under it. False at the root and
## during a slide.
func pop() -> bool:
	if is_sliding() or _screens.size() < 2:
		return false
	var gone: MenuScreen = _screens.pop_back()
	var below: MenuScreen = current()
	add_child(below)
	move_child(below, gone.get_index())  # Under the screen that leaves.
	_run(below, gone, false, true)
	return true


## Swaps the top screen for `screen` (the old one is freed); the stack gets no deeper. False, and
## `screen` freed, during a slide.
func replace(screen: MenuScreen) -> bool:
	if is_sliding():
		screen.free()
		return false
	var old: MenuScreen = current()
	_add(screen)
	if old != null:
		_screens.pop_back()
	_screens.append(screen)
	_run(screen, old, true, true)
	return true


## The back request. A closed question or a pop; at the root it asks to quit. Ignored while a
## screen slides.
func back() -> void:
	if is_sliding():
		return
	if _quit.visible:
		_quit.close()
		_restore_focus(current())
		return
	var top: MenuScreen = current()
	if top != null and top.on_back():
		return
	if not pop():
		_remember_focus(top)
		_quit.open()


func _add(screen: MenuScreen) -> void:
	screen.backdrop_color = backdrop_color
	add_child(screen)
	move_child(screen, _blocker.get_index())  # Blocker and question stay above every screen.


func _run(incoming: MenuScreen, outgoing: MenuScreen, forward: bool, free_out: bool) -> void:
	_finish = _end.bind(incoming, outgoing, free_out)
	if reduced or slide_ms <= 0 or outgoing == null:
		_complete()
		return
	var moving: MenuScreen = incoming if forward else outgoing
	var width: float = size.x
	moving.position.x = width if forward else 0.0
	_blocker.visible = true
	_tween = create_tween()
	_tween.tween_property(moving, "position:x", 0.0 if forward else width, slide_ms / 1000.0)
	_tween.finished.connect(_complete)


func _complete() -> void:
	_tween = null
	_blocker.visible = false
	var done: Callable = _finish
	_finish = Callable()
	if done.is_valid():
		done.call()


func _end(incoming: MenuScreen, outgoing: MenuScreen, free_out: bool) -> void:
	incoming.position.x = 0.0
	if outgoing != null:
		outgoing.position.x = 0.0
		if free_out:
			_focus.erase(outgoing)
			outgoing.queue_free()
		else:
			remove_child(outgoing)  # Kept, not freed: it comes back on pop.
	_restore_focus(incoming)
	screen_changed.emit(incoming)


func _remember_focus(screen: MenuScreen) -> void:
	if screen == null:
		return
	var owner_control: Control = get_viewport().gui_get_focus_owner()
	if owner_control != null and screen.is_ancestor_of(owner_control):
		_focus[screen] = owner_control


func _restore_focus(screen: MenuScreen) -> void:
	var stored: Variant = _focus.get(screen)
	if not is_instance_valid(stored):
		return
	var target: Control = stored as Control
	if target.is_visible_in_tree():
		target.grab_focus(true)


func _quit_app() -> void:
	get_tree().quit()
