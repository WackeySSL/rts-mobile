class_name MusicLane
extends Resource
## One lane of a generated piece (plan row P506, ADR 0041 section 5): a voice (an `SfxLayer` used
## as the instrument), a level, a pan and a pattern of 16 steps per bar. In a pattern '.' is a
## rest, 'x' a hit, 'o' an accent (bass: the octave up, drums: louder), 'f' a fifth (bass), 'g' a
## ghost note (drums, quieter).

enum Kind { PAD, BASS, ARP, DRUM }
enum Dir { UP, DOWN, PING }

@export var lane_name: StringName = &""
@export var kind: Kind = Kind.DRUM
@export var voice: SfxLayer
@export_range(0.0, 1.0) var level: float = 0.5
## -1 left, 1 right. A pad with `detune_cents` above 0 plays each note twice, detuned and panned
## to both sides by this much (the width), and ignores the sign.
@export_range(-1.0, 1.0) var pan: float = 0.0
@export var detune_cents: float = 0.0
## Share of this lane that also goes to the echo bus.
@export_range(0.0, 1.0) var send: float = 0.0
## Semitones added to every note of a pitched lane.
@export var octave_shift: int = 0
## Share of the step run a note holds (bass, arp).
@export_range(0.05, 1.0) var gate: float = 0.8
@export var arp_dir: Dir = Dir.UP
## One pattern per bar, cycled; empty for a pad.
@export var patterns: PackedStringArray = PackedStringArray()
## Replaces the pattern on the last bar of each `fill_every` bars (0 = no fills).
@export var fill: String = ""
@export var fill_every: int = 0
## One digit per bar, cycled: '1' the lane plays that bar, '0' it rests. Empty = always.
@export var mask: String = ""


func active(bar: int) -> bool:
	return mask.is_empty() or mask[bar % mask.length()] == "1"


## The 16-step pattern of `bar`, "" for none.
func pattern_for(bar: int) -> String:
	if fill_every > 0 and not fill.is_empty() and bar % fill_every == fill_every - 1:
		return fill
	if patterns.is_empty():
		return ""
	return patterns[bar % patterns.size()]
