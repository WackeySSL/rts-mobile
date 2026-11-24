class_name MusicParams
extends Resource
## The parameter file of one generated piece (`tools/musgen/params/<id>.tres`). `MusicSynth`
## renders it to stereo samples; the same file always gives the same samples.

const DEFAULT_ROOT: String = "res://assets/audio/music"

## [a-z0-9_]+; the output is <root>/<id>.ogg.
@export var id: StringName = &""
@export_range(40.0, 220.0) var bpm: float = 100.0
@export var bars: int = 8
@export var seed_value: int = 1
@export_range(8000, 48000) var sample_rate: int = 32000
## A loop renders `bars` bars that wrap (tails run into the start); a sting plays once and rings
## out for `tail` seconds after its last bar.
@export var loop: bool = true
@export var tail: float = 0.0
## The mix is scaled so its peak is exactly this (dBFS).
@export_range(-24.0, -1.0) var peak_db: float = -6.0
## Bars per chord, the chords (MIDI notes of the pad) and their bass roots, cycled.
@export var chord_bars: int = 2
@export var chords: Array[PackedInt32Array] = []
@export var roots: PackedInt32Array = PackedInt32Array()
## The ping-pong echo of the lanes' `send`: delay in beats, feedback and return level.
@export var echo_beats: float = 0.75
@export_range(0.0, 0.9) var echo_feedback: float = 0.4
@export_range(0.0, 1.0) var echo_mix: float = 0.5
@export var lanes: Array[MusicLane] = []


func bar_seconds() -> float:
	return 240.0 / bpm


## Frames of the rendered piece (a loop is exactly its bars).
func frames() -> int:
	return int(round((bars * bar_seconds() + (0.0 if loop else tail)) * float(sample_rate)))


func output_path(root: String = DEFAULT_ROOT) -> String:
	return "%s/%s.ogg" % [root, id]


func chord_at(bar: int) -> PackedInt32Array:
	return chords[(bar / chord_bars) % chords.size()]


func root_at(bar: int) -> int:
	return roots[(bar / chord_bars) % roots.size()]


## What is wrong with the file, one message per problem; empty when it can be rendered.
func problems() -> Array[String]:
	var found: Array[String] = []
	if RegEx.create_from_string("^[a-z0-9_]+$").search(String(id)) == null:
		found.append("id '%s' must match [a-z0-9_]+" % id)
	if bars < 1 or chord_bars < 1 or chords.is_empty() or roots.is_empty():
		found.append("bars, chord_bars, chords and roots must be set")
	if lanes.is_empty():
		found.append("needs at least one lane")
	for chord: PackedInt32Array in chords:
		if chord.is_empty():
			found.append("a chord has no notes")
	for lane: MusicLane in lanes:
		if lane == null or lane.voice == null:
			found.append("a lane has no voice")
		elif (
			lane.kind == MusicLane.Kind.DRUM
			and (lane.voice.freq <= 0.0 or lane.voice.freq_end <= 0.0)
		):
			found.append("drum lane '%s': freq and freq_end must be above 0" % lane.lane_name)
	return found
