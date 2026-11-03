class_name LifeFx
extends Node2D
## The pooled effect layers of the unit life (ADR 0027 section 3): one node in `main.tscn`, between
## `DecalLayer` and `WorldSort`, that makes its layers in code, so a later row adds a layer here
## and the scene stays as it is. Each layer is a ring of slots in packed arrays, drawn in one
## `_draw` from one texture. Today it holds `GroundFx` (z 3: dust behind vehicles); P141 adds
## `StrikeFx` and P145 `AirFx` one line each.
## View only: it reads the runner's snapshot and writes nothing back. The layers get this node's
## `runner`, `camera`, `life` and `reveal_enemies`.

const DEFAULT_LIFE: LifeSettings = preload("res://data/life_settings.tres")

@export var runner: MatchRunner
## The camera whose view rect says what is in view; without one nothing is.
@export var camera: RtsCamera
## The numbers (`data/life_settings.tres` when unset).
@export var life: LifeSettings
## Shows the effects of tiles the fog hides too: the perf arena, and tests that are not about fog.
@export var reveal_enemies: bool = false

var ground: GroundFx = null


func _ready() -> void:
	if life == null:
		life = DEFAULT_LIFE
	ground = _make_layer(GroundFx.new(), &"GroundFx") as GroundFx


func _make_layer(layer: Node2D, layer_name: StringName) -> Node2D:
	layer.name = layer_name
	layer.set("runner", runner)
	layer.set("camera", camera)
	layer.set("life", life)
	layer.set("reveal_enemies", reveal_enemies)
	add_child(layer)
	return layer
