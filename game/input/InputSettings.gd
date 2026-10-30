class_name InputSettings
extends Resource
## Gesture and feel thresholds (ADR 0004 section 2): distances in dp, times in ms. The instance
## is res://data/input_settings.tres, where all tuning happens. These defaults are the ADR table.
## A test that wants another value calls `duplicate()` first.

@export var tap_slop_dp: float = 12.0  ## Movement beyond this, before the long-press, is a pan.
@export var long_press_ms: int = 300  ## Held within the slop this long: long-press, then box.
@export var double_tap_ms: int = 300  ## From the first tap's release to the second tap's press.
@export var double_tap_slop_dp: float = 32.0  ## Maximum distance between the two taps.
@export var hit_radius_dp: float = 24.0  ## Minimum hit radius around a unit (48 dp diameter).
@export var group_assign_ms: int = 500  ## Hold on a group button to assign it.
@export var zoom_levels: PackedFloat32Array = PackedFloat32Array([0.75, 1.0, 1.5])
@export var zoom_start_index: int = 1  ## Index into `zoom_levels`.
@export var pinch_overshoot: float = 0.15  ## Fraction a pinch may pass the outer levels.
@export var zoom_snap_ms: int = 150  ## Snap animation. 0 is immediate (tests).
@export var marker_ms: int = 600  ## Move-marker lifetime.
@export var haptic_ms: int = 15  ## Vibration on long-press and group assign.
@export var haptics_enabled: bool = true
## Placement mode (ADR 0019 section 2, ADR 0023 section 3): a drag that starts within this many dp
## of the ghost's silhouette moves it, and the ghost follows the finger this many dp above it.
@export var ghost_grab_dp: float = 24.0
@export var ghost_lift_dp: float = 64.0
