class_name LicencesScreen
extends MenuScreen
## The Licences screen (plan P529, ADR 0043 section 7): a list of licences, one big button each; a
## licence shows its full text as wrapping paragraphs inside the screen's scroll (the engine's own
## texts are long, so a text is cut into chunks of labels rather than one huge label). Back from a
## text goes to the list, back from the list pops the stack. No banner: the foot slot stays empty.
## Open it with `stack.push(LicencesScreen.new())`; it reads the build's rows itself unless
## `catalog` is set first.

const HEADING_VARIATION: StringName = &"CapsTitle"
const TITLE: String = "LICENCES"
const BACK: String = "BACK"
const ALL_LICENCES: String = "ALL LICENCES"
const CHUNK_CHARS: int = 2000

var catalog: LicenceCatalog
## The licence on show, or null while the list shows.
var open_entry: LicenceEntry = null

var _entries: Array[LicenceEntry] = []


func _ready() -> void:
	super()
	if catalog == null:
		catalog = LicenceCatalog.from_build()
	_entries = catalog.build()
	_show_list()


## The column gives the scroll bar's width back, as the How to play screen does.
func _apply() -> void:
	super()
	if scroll != null and column != null and is_inside_tree():
		var bar_px: float = scroll.get_v_scroll_bar().get_combined_minimum_size().x
		column.custom_minimum_size.x = maxf(column.custom_minimum_size.x - bar_px, 0.0)


func on_back() -> bool:
	if open_entry == null:
		return false
	_show_list()
	return true


func _show_list() -> void:
	open_entry = null
	_clear()
	_heading(tr(TITLE))
	for entry: LicenceEntry in _entries:
		add_button(entry.title.to_upper(), _show_entry.bind(entry))
	add_button(tr(BACK), _go_back).set_meta(UiSounds.META_CUE, UiSounds.CUE_BACK)
	scroll.scroll_vertical = 0


func _show_entry(entry: LicenceEntry) -> void:
	open_entry = entry
	_clear()
	_heading(entry.title)
	add_button(tr(ALL_LICENCES), _show_list)
	for chunk: String in _chunks(entry.text):
		column.add_child(_label(chunk))
	add_button(tr(ALL_LICENCES), _show_list)
	scroll.scroll_vertical = 0


## Paragraphs (split at blank lines) joined up to about CHUNK_CHARS, a longer one on its own.
func _chunks(text: String) -> PackedStringArray:
	var chunks: PackedStringArray = []
	var current: String = ""
	for paragraph: String in text.replace("\r\n", "\n").split("\n\n"):
		if not current.is_empty() and current.length() + 2 + paragraph.length() > CHUNK_CHARS:
			chunks.append(current)
			current = ""
		current = paragraph if current.is_empty() else current + "\n\n" + paragraph
	if not current.is_empty():
		chunks.append(current)
	return chunks


func _go_back() -> void:
	var stack: MenuStack = get_parent() as MenuStack
	if stack != null:
		stack.back()


func _clear() -> void:
	for child: Node in column.get_children():
		column.remove_child(child)
		child.queue_free()


func _heading(text: String) -> void:
	var label: Label = _label(text.to_upper())
	label.theme_type_variation = HEADING_VARIATION
	column.add_child(label)


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
