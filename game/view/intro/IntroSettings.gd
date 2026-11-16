class_name IntroSettings
extends Resource
## Every number of the boot intro (ADR 0043 section 2): view only, never loaded by `game/sim`. The
## instance is `res://data/intro_settings.tres`; the defaults here are the ones that file holds.
## The lockup rects are the splash PNG's (tools/artgen/ArtIntro.gd `lockup`, pinned by a test), in
## the PNG's own px; the stage scales them like the engine's Keep stretch does.

## Timing (ms): the open-out starts when loading is done and `min_ms` has passed; after `max_ms`
## the tank settles and the progress line shows.
@export var min_ms: int = 600
@export var max_ms: int = 3000
@export var open_ms: int = 400
@export var fade_ms: int = 250

## The splash PNG's square and where the icon and the wordmark stand in it.
@export var splash_side: int = 1024
@export var icon_rect: Rect2i = Rect2i(256, 225, 512, 512)
@export var wordmark_rect: Rect2i = Rect2i(435, 778, 154, 20)
@export var background: Color = Color("#06080C")

## Files: layers back to front (ArtIntro.order(), pinned by a test), the splash PNG (the wordmark is
## its `wordmark_rect`: the brand SVGs are never loaded at runtime), the loads.
@export var layer_dir: String = "res://assets/art/svg/intro/"
@export var background_layers: PackedStringArray = ["sky", "ring", "sweep", "ground"]
@export var foreground_layers: PackedStringArray = [
	"shadow",
	"underlay",
	"track_far",
	"cleats_far",
	"hull",
	"track_near",
	"cleats_near",
	"hull_deck",
	"turret",
	"gun",
	"rim_light",
	"clods",
	"sparks",
]
@export var splash_path: String = "res://assets/art/splash/boot_splash.png"
@export var menu_path: String = "res://scenes/menu/menu.tscn"
@export var load_paths: PackedStringArray = ["res://game/ui/theme.tres"]

## The drive, in icon px (the layers are 512 px squares).
@export var cleat_pitch_px: float = 9.0
@export var cleat_period_ms: int = 360
@export var cleat_dir: Vector2 = Vector2(2.0, 1.0)
@export var rock_px: float = 1.6
@export var rock_deg: float = 0.5
@export var rock_period_ms: int = 520
@export var clod_px: float = 5.0
@export var clod_period_ms: int = 300
@export var spark_period_ms: int = 220
@export var sweep_deg_per_s: float = 120.0
@export var ring_deg_per_s: float = 8.0
@export var radar_pivot: Vector2 = Vector2(256.0, 233.6)

## The progress line (dp) and the colour it has.
@export var line_dp: float = 3.0
@export var line_width_ratio: float = 0.5
@export var line_bottom_dp: float = 24.0
@export var line_color: Color = Color(0.7843137, 0.95686275, 1.0, 1.0)
