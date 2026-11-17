class_name HelpEntryDef
extends Resource
## One help entry of the How to play screen (ADR 0044 section 3): a row of
## `docs/HOW_TO_PLAY.md` in player words. `id` is the row's kebab-case id, prefixed with its
## section's id (`camera-pinch`); `title` and `body` are English and go through `tr()` when shown.

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var body: String = ""
