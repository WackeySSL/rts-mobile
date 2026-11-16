class_name HowToPlayScreen
extends MenuScreen
## The How to play screen (plan P527, ADR 0044 section 3): a list of sections, one big button each
## (the thumb reaches them in portrait and in landscape alike); a section shows its entries as
## titles and wrapping text inside the screen's scroll. Back from a section goes to the list, back
## from the list pops the stack. It hosts no banner: its foot slot stays empty and 0 tall.
## Open it with `stack.push(HowToPlayScreen.new())`; it loads `DEF_PATH` itself unless `help` is set
## first.

const DEF_PATH: String = "res://data/help/how_to_play.tres"
## The screen's own words are English source strings: `tr()` returns one as it is until a
## translation table (ADR 0043 question 12) has an entry for it.
const TITLE: String = "HOW TO PLAY"
const BACK: String = "BACK"
const ALL_SECTIONS: String = "ALL SECTIONS"

var help: HelpDef
## The section on show, or null while the list shows.
var open_section: HelpSectionDef = null


func _ready() -> void:
	super()
	if help == null:
		help = load(DEF_PATH) as HelpDef
	_show_list()


func on_back() -> bool:
	if open_section == null:
		return false
	_show_list()
	return true


func _show_list() -> void:
	open_section = null
	_clear()
	_heading(tr(TITLE))
	for section: HelpSectionDef in help.sections:
		add_button(tr(section.title).to_upper(), _show_section.bind(section))
	add_button(tr(BACK), _go_back)
	scroll.scroll_vertical = 0


func _show_section(section: HelpSectionDef) -> void:
	open_section = section
	_clear()
	_heading(tr(section.title))
	for item: HelpEntryDef in section.entries:
		_heading(tr(item.title))
		_body(tr(item.body))
	add_button(tr(ALL_SECTIONS), _show_list)
	scroll.scroll_vertical = 0


func _go_back() -> void:
	var stack: MenuStack = get_parent() as MenuStack
	if stack != null:
		stack.pop()


func _clear() -> void:
	for child: Node in column.get_children():
		column.remove_child(child)
		child.queue_free()


func _heading(text: String) -> void:
	column.add_child(_label(text))


func _body(text: String) -> void:
	column.add_child(_label(text))


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
