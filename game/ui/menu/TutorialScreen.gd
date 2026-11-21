class_name TutorialScreen
extends MenuScreen
## The Tutorial screen (plan row P544, ADR 0044 sections 1 and 2): the lessons in teaching order,
## one big button each (the thumb reaches them in portrait and in landscape alike), a done mark
## beside the title of a finished one (the word DONE, never colour alone) and the next
## unfinished one marked NEXT. A tap starts the lesson through `MenuFlow` (a finished one is a
## replay); a lesson's end, Skip and Leave tutorial return here (`TutorialStart.RETURN_SCREEN`). The
## main menu and Settings open it through `MenuRoutes.TUTORIAL`. It hosts no banner: its foot slot
## stays empty. No Command, no sim.

const TITLE: String = "TUTORIAL"
const BACK: String = "BACK"
const DONE_MARK: String = "DONE"
const NEXT_MARK: String = "NEXT"
const HINT: String = "Each lesson is a short match. Finished ones can be played again."
const HEADING_VARIATION: StringName = &"CapsTitle"

## Tests inject the flow before the screen is pushed; null means the MenuFlow autoload.
var flow: Node = null

var _buttons: Dictionary[StringName, Button] = {}
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
	add_button(tr(BACK), _go_back)
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
		_buttons[id].disabled = _starting


## Back does nothing while a lesson starts: a pop would leave the flow starting it from the menu.
func on_back() -> bool:
	return _starting


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


func _go_back() -> void:
	var stack: MenuStack = get_parent() as MenuStack
	if stack != null:
		stack.back()


func _flow() -> Node:
	return flow if flow != null else MenuFlow
