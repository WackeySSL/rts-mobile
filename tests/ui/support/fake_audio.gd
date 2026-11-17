extends "res://game/view/audio/audio_service.gd"
## An AudioService for the result screen's tests (P532): `play_music` only records the ids.
## Not a suite.

var played: Array[StringName] = []


func play_music(id: StringName) -> bool:
	played.append(id)
	return true
