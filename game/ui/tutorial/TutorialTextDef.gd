class_name TutorialTextDef
extends Resource
## The English words of the tutorial (ADR 0044 section 3, plan row P543): the title of each lesson
## and the prompt of each beat, `words[i]` for the translation key `keys[i]`. A word may hold
## `{type_id}` for a card or building of the player's faction; `TutorialText` puts that unit's
## display name in, so a rename in `data/units/` reaches the prompt. One string per prompt, so a
## translation tool gets whole sentences.

@export var keys: PackedStringArray = PackedStringArray()
@export var words: PackedStringArray = PackedStringArray()
