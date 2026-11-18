class_name LicenceEntry
extends RefCounted
## One row of the Licences screen (ADR 0043 section 7): a title for its button and the full text.

var title: String = ""
var text: String = ""


static func make(entry_title: String, entry_text: String) -> LicenceEntry:
	var entry: LicenceEntry = LicenceEntry.new()
	entry.title = entry_title
	entry.text = entry_text
	return entry
