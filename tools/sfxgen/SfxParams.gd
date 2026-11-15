class_name SfxParams
extends Resource
## The parameter file of one generated sound (`tools/sfxgen/params/<id>.tres`). `SfxSynth` turns
## it into a mono 16-bit WAV; the same file always gives the same bytes.

@export var id: StringName = &""
## Output goes to assets/audio/sfx/<family>/<id>.wav.
@export var family: StringName = &"ui"
@export_range(8000, 48000) var sample_rate: int = 22050
## Length of the file in seconds (the tail after the last voice is silence).
@export var duration: float = 0.3
## Seed of the noise generator.
@export var seed_value: int = 1
## Master gain applied after mixing, 0..1; the mix is also hard-limited to [-1, 1].
@export_range(0.0, 1.0) var gain: float = 0.8
@export var layers: Array[SfxLayer] = []


func output_path() -> String:
	return "res://assets/audio/sfx/%s/%s.wav" % [family, id]
