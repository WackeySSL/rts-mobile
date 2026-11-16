extends Node
## Stands in for AudioService where the cue itself is the subject (BattleSounds suites): records
## each play. Not a test suite.

var settings: AudioSettings
var plays: int = 0
var cues: Array[StringName] = []
var last_db: float = 0.0
var last_pitch: float = 0.0
var streams: Array[AudioStream] = []
var positions: Array[Vector2] = []
var pitches: Array[float] = []
var ended: int = 0


func can_play(_bus: StringName) -> bool:
	return true


func begin_tick() -> void:
	pass


func end_ticking() -> void:
	ended += 1


func play_world(
	stream: AudioStream,
	position: Vector2,
	cue: StringName,
	_priority: int = 0,
	_max_voices: int = 0,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0
) -> bool:
	plays += 1
	cues.append(cue)
	last_db = volume_db
	last_pitch = pitch_scale
	streams.append(stream)
	positions.append(position)
	pitches.append(pitch_scale)
	return true
