class_name HelpSectionDef
extends Resource
## One section of the How to play screen: a `## ` heading of `docs/HOW_TO_PLAY.md` (`id` is its
## kebab case, `camera`) with the entries that belong under it.

@export var id: StringName = &""
@export var title: String = ""
@export var entries: Array[HelpEntryDef] = []
