class_name SameSceneBands
extends Resource
## The roster, scene layout and tolerance bands of the same-scene check (ADR 0050 section 8,
## `tools/artgen/same_scene.tres`). It lives outside `data/`, so a band change starts no balance
## run. `scene` is a unit, a building, a unit, a building: Nordvaern, then Facet.

@export_group("Scene")
@export var scene: PackedStringArray = PackedStringArray()
@export var roster: PackedStringArray = PackedStringArray()  ## Art ids the audit measures.
@export var wanted_dir: Dictionary[StringName, int] = {}  ## Faction -> the default view of a unit.
@export var terrains: PackedStringArray = PackedStringArray()
@export var zooms: PackedFloat32Array = PackedFloat32Array()
@export var glyphs: PackedStringArray = PackedStringArray()
@export var effects: Dictionary[String, Rect2i] = {}  ## Name -> region of the effects atlas, px.
@export var grade_warm: Color = Color.WHITE  ## ADR 0035 section 3: warm at the top left,
@export var grade_cool: Color = Color.WHITE  ## cool at the bottom right, a low alpha.

@export_group("Bands")
@export var light_up_min: float = 0.0  ## Upper half minus lower half, mean luminance 0 to 1.
@export var light_left_min: float = 0.0  ## Left half minus right half.
@export var shadow_dx_min: float = 0.0  ## Shadow centre east of the body's, share of width.
@export var tone_value: Vector2 = Vector2.ZERO  ## Mean value (HSV) of the opaque body.
@export var tone_sat: Vector2 = Vector2.ZERO  ## Mean saturation of the neutral body (below).
## The most the mean saturation of every opaque pixel may be (P638): the cap of the whole sprite,
## fixed faction panels included.
@export var tone_sat_all_max: float = 1.0
@export var black_edge_max: float = 1.0  ## Share of the rim that is near black (no black outline).
@export var density: Vector2 = Vector2.ZERO  ## Edges per 100 px squared at zoom 1.0.
@export var shadow_alpha: Vector2 = Vector2.ZERO  ## Peak alpha of the cast shadow.
@export var spread_min: float = 0.0  ## 32 px greyscale spread, 5th to 95th percentile, 0 to 255.

@export_group("Faction classifier")
## A pixel is faction material (not the neutral body) when its hue is within `faction_hue_band`
## degrees of one of `faction_hues` (the mid tones of Nordvaern orange and Facet blue) and its
## saturation is at least `faction_sat_min`; a pixel within `key_tolerance` (summed channels, 0 to
## 3) of the sentinel or a route triad is the team marker. Both are left out of `tone_sat`.
@export var faction_hues: PackedFloat32Array = PackedFloat32Array()
@export var faction_hue_band: float = 0.0
@export var faction_sat_min: float = 1.0
@export var key_tolerance: float = 0.0

@export_group("Transition exemptions")
## 2026-11-25 (P632): old models that paint their whole team areas in the marker read greyer and
## lighter with your own white one. Art id -> the measured value that misses the band. The audit
## skips these ids for the saturation band (`exempt_sat`) and the light band (`exempt_up`) only;
## the list may only shrink, and a model that is fixed leaves it (P647 empties it).
@export var exempt_sat: Dictionary[StringName, float] = {}
@export var exempt_up: Dictionary[StringName, float] = {}
