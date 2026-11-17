class_name HelpDef
extends Resource
## The player text of the How to play screen (ADR 0044 section 3), `data/help/how_to_play.tres`.

@export var sections: Array[HelpSectionDef] = []


## The entry with this id in any section, or null.
func entry(entry_id: StringName) -> HelpEntryDef:
	for section: HelpSectionDef in sections:
		for item: HelpEntryDef in section.entries:
			if item.id == entry_id:
				return item
	return null
