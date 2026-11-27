class_name TutorialScreen
extends MenuScreen
## The Tutorial screen (plan row P544, ADR 0044 sections 1 and 2): the lessons in teaching order,
## one big button each (the thumb reaches them in portrait and in landscape alike), a done mark
## beside the title of a finished one (the word DONE, never colour alone) and the next
## unfinished one marked NEXT. A lesson not paid yet shows its reward as a small amber "+40 XP"
## tag at the row's right end (P674b; the value is `ProgressionDef.lesson_xp`); a paid one shows
## none. A tap starts the lesson through `MenuFlow` (a finished one is a
## replay); a lesson's end, Skip and Leave tutorial return here (`TutorialStart.RETURN_SCREEN`). The
## main menu and Settings open it through `MenuRoutes.TUTORIAL`. It hosts no banner: its foot slot
## stays empty. No Command, no sim.

const TITLE: String = "TUTORIAL"
const DONE_MARK: String = "DONE"
const NEXT_MARK: String = "NEXT"
## The reward tag of a lesson not paid yet (P674b); `%d` is `ProgressionDef.lesson_xp`.
const XP_TAG: String = "+%d XP"
const TAG_VARIATION: StringName = &"MenuEyebrow"  ## 14 sp in the money amber.
const TAG_ROOM_DP: float = 72.0  ## Kept at each row's right end, so the title never runs under it.
const TAG_EDGE_DP: float = 12.0
const BUTTON_STYLES: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"
]
const HINT: String = "Each lesson is a short match. Finished ones can be played again."
const HEADING_VARIATION: StringName = &"CapsTitle"

## Tests inject the flow before the screen is pushed; null means the MenuFlow autoload.
var flow: Node = null

var _buttons: Dictionary[StringName, Button] = {}
var _tags: Dictionary[StringName, Label] = {}
var _starting: bool = false


func _ready() -> void:
	super()
	TutorialText.register()
	var heading: Label = Label.new()
	heading.text = tr(TITLE)
	heading.theme_type_variation = HEADING_VARIATION
	column.add_child(heading)
	var hint: Label = Label.new()
	hint.text = tr(HINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(hint)
	for id: StringName in TutorialStart.ORDER:
		var def: TutorialLessonDef = TutorialStart.lesson(id)
		if def == null:
			push_warning("TutorialScreen: no lesson file for %s" % id)
			continue
		_buttons[id] = add_button("", _on_lesson.bind(id))
		_add_tag(id)
	use_footer()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and not _buttons.is_empty():
		refresh()  # Back from a lesson or another screen: the marks may have changed.


## The button of each lesson reads its title and its mark; called again when the screen returns.
func refresh() -> void:
	var next: StringName = TutorialStart.next_lesson()
	for id: StringName in _buttons:
		var def: TutorialLessonDef = TutorialStart.lesson(id)
		var text: String = tr(def.title_key).to_upper()
		if TutorialDirector.is_done(id):
			text += "   " + tr(DONE_MARK)
		elif id == next:
			text += "   " + tr(NEXT_MARK)
		_buttons[id].text = text
		var unpaid: bool = not Progression.is_lesson_paid(id)
		_tags[id].visible = unpaid
		_tags[id].text = tr(XP_TAG) % Progression.lesson_xp()
		_buttons[id].disabled = _starting


## Back does nothing while a lesson starts: a pop would leave the flow starting it from the menu.
func on_back() -> bool:
	return _starting


## The tag sits at the row's right end (never takes a touch). The row keeps `TAG_ROOM_DP` free
## there whether the tag shows or not, so the title does not jump when a lesson is paid.
func _add_tag(id: StringName) -> void:
	var button: Button = _buttons[id]
	# A title that does not fit beside the tag wraps (the row grows) and never widens the column.
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for style_name: StringName in BUTTON_STYLES:
		var base: StyleBox = button.get_theme_stylebox(style_name)
		if base == null:
			continue
		var room: StyleBox = base.duplicate()
		room.content_margin_right = UiScale.dp(TAG_ROOM_DP)
		button.add_theme_stylebox_override(style_name, room)
	var tag: Label = Label.new()
	tag.name = &"XpTag"
	tag.theme_type_variation = TAG_VARIATION
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	tag.offset_left = -UiScale.dp(TAG_ROOM_DP)
	tag.offset_right = -UiScale.dp(TAG_EDGE_DP)
	_tags[id] = tag


func _on_lesson(id: StringName) -> void:
	if _starting:
		return
	_starting = true
	refresh()
	var error: Error = await TutorialStart.start(_flow(), id)
	if error != OK:
		push_warning("TutorialScreen: lesson %s did not start (%s)" % [id, error_string(error)])
		_starting = false
		if is_inside_tree():
			refresh()


func screen_name() -> String:
	return tr(TITLE)


func _flow() -> Node:
	return flow if flow != null else MenuFlow
