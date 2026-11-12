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
## The edge pan of a ghost drag (ADR 0019 section 2): while a finger that holds the ghost is within
## `edge_band_dp` of the left, right or bottom edge of the map view (the safe area, and in portrait
## the top of the build band), or the ghost's point, `ghost_lift_dp` above the finger, is within it
## of the top edge, the map scrolls toward that edge at `edge_pan_dp_per_s` of screen, whatever the
## zoom and the frame rate. One frame scrolls for `edge_pan_max_step_ms` at most.
@export var edge_band_dp: float = 32.0
@export var edge_pan_dp_per_s: float = 300.0
@export var edge_pan_max_step_ms: int = 100
## The build menu's slide (ADR 0024 section 8): the time its height takes between the collapsed
## and the open state, eased out. 0 shows the state's layout at once.
@export var menu_slide_ms: int = 160
## The corner HUD (ADR 0025, plan HUD v2). All of its numbers are here so that the rows that use
## them (P119b the pill, P120 the drawer, P121 the scope, P123 the cues) only read them.
@export var economy_flash_ms: int = 1000  ## A spend or income chip on the pill stays this long.
@export var radar_close_ms: int = 4000  ## An unpinned full map folds after this long untouched.
@export var scope_radius_tiles: int = 16  ## Tiles from the camera's ground centre to the rim.
@export var attack_toast_ms: int = 4000  ## The attack toast and the rim wedge stay this long.
## One attack cue per area and interval: a hit within `attack_cue_area_tiles` of the last cue's
## point, less than `attack_cue_ms` after it, raises none (ADR 0025 section 8). PLACEHOLDERS: no
## planned values exist (ADR 0019 section 5 names none); P123, the row that builds the cues, tunes
## them on the phone. The interval is the toast's, so a steady attack keeps one toast up.
@export var attack_cue_ms: int = 4000
@export var attack_cue_area_tiles: int = 12
@export var drawer_swipe_dp: float = 48.0  ## A drag past this toward its edge closes the drawer.
## The command bar's two-tap Sell (ADR 0037 section 3, P272): the first tap arms, and the second
## sends one SELL only from `sell_arm_min_ms` to before `sell_confirm_ms` after it. A second tap
## sooner is ignored and keeps the arm; a late one arms again. Never a hold.
@export var sell_arm_min_ms: int = 400
@export var sell_confirm_ms: int = 3000
