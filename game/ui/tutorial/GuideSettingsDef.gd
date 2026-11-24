class_name GuideSettingsDef
extends Resource
## Every number of the tutorial guide (ADR 0048 section 7): the instance is
## res://data/tutorial/guide_settings.tres, where all tuning happens. The colours are in the
## theme's `GuideTokens`. A test that wants another value calls `duplicate()` first.

## The card.
@export var card_max_width_dp: float = 0.0
@export var card_wide_dp: float = 0.0
@export var card_max_height_pct: int = 0
## The blinking frame: its opacity eases between `blink_low_alpha_pct` and 100 over a period.
@export var blink_period_ms: int = 0
@export var blink_low_alpha_pct: int = 0
## The gesture hint.
@export var hint_cycle_ms: int = 0
@export var hint_rest_ms: int = 0
@export var hint_idle_ms: int = 0
@export var hint_tap_ms: int = 0
@export var hint_drag_ms: int = 0
@export var hint_pinch_ms: int = 0
@export var hint_hold_extra_ms: int = 0
@export var hint_size_dp: float = 0.0
