class_name IntroPlayer
extends Control
## The boot intro (ADR 0043 section 2): the splash's picture as the first frame, the tank driving
## while the loads and the consent run, then the icon opens out into the menu. Every number is in
## `data/intro_settings.tres`. The clock, the loader, the consent call, the reduced switch and the
## log line are fields a test replaces. `step()` runs from `_process`; a test calls it itself.
## The brand lockup stays still and fades with the open-out, so it adds no time.

signal finished(menu: Node)

enum Phase { DRIVE, SETTLED, OPEN, FADE, DONE }


## Awaits the consent call away from the player, so a player freed meanwhile is never resumed.
class ConsentWait:
	extends RefCounted
	var done: bool = false

	func run(call: Callable) -> void:
		if call.is_valid():
			await call.call()
		done = true


@export var settings: IntroSettings = preload("res://data/intro_settings.tres")
var clock: Callable = Time.get_ticks_msec
var loader: IntroLoader = IntroLoader.new()
## Awaited while the intro plays; always finishes. Invalid means there is no ad service.
var consent: Callable = Callable()
## Reduced effects: a fade instead of the drive. TODO(P526): P526 stores the saved switch; the boot
## reads it and sets this field before it adds the player to the tree.
var reduced: bool = false
var log_line: Callable = print
## Where the menu is added; null is the tree's root (then it becomes the current scene).
var host: Node = null

var phase: Phase = Phase.DRIVE
var icon_box: Control
var wordmark: TextureRect
var tank: Control
var line: ColorRect

var _bg: ColorRect
var _layers: Dictionary[String, TextureRect] = {}
var _t0: int = -1
var _exit_t0: int = 0
var _skipped: bool = false
var _wait: ConsentWait = ConsentWait.new()
var _blocker: Control = null
var _held: Array[Resource] = []
var _failed: bool = false
var _menu: Control = null
var _cover: float = 1.0
var _line_full: float = 0.0


func _enter_tree() -> void:
	# TODO(P533): ADR 0043 section 4 wants application/config/quit_on_go_back = false for the whole
	# app; the project setting comes with the row that edits project.godot. Until then the intro
	# switches it off (as MenuStack does), so Back skips the intro and never quits the app.
	get_tree().quit_on_go_back = false


func _ready() -> void:
	if not consent.is_valid():
		var ads: Node = get_node_or_null("/root/AdService")
		if ads != null:
			consent = Callable(ads, "ensure_consent")
	build()
	resized.connect(func() -> void: apply_layout(size, UiScale.safe_rect_base()))
	apply_layout(size, UiScale.safe_rect_base())
	begin()


func _process(_delta: float) -> void:
	step()


func _input(event: InputEvent) -> void:
	if phase == Phase.DONE:
		return
	var touch: bool = event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if touch or click:
		skip()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and phase != Phase.DONE:
		skip()  # ADR 0043 section 4: Back in the intro is a tap.
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## Makes the nodes: backdrop, the icon's layers in a box, the wordmark, the progress line. The
## `load()` calls are synchronous on purpose: the first frame is the still picture, so the 17 small
## layer textures and the splash PNG must be there before it, and they are tiny imported files.
func build() -> void:
	_bg = ColorRect.new()
	_bg.color = settings.background
	add_child(_bg)
	wordmark = TextureRect.new()
	var crop: AtlasTexture = AtlasTexture.new()
	crop.atlas = load(settings.splash_path) as Texture2D
	crop.region = Rect2(settings.wordmark_rect)
	wordmark.texture = crop
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(wordmark)  # Under the icon, so the growing icon covers it.
	icon_box = Control.new()
	add_child(icon_box)
	for stem: String in settings.background_layers:
		_layers[stem] = _layer(icon_box, stem)
	tank = Control.new()
	icon_box.add_child(tank)
	for stem: String in settings.foreground_layers:
		_layers[stem] = _layer(tank, stem)
	line = ColorRect.new()
	line.color = settings.line_color
	line.visible = false
	add_child(line)
	var parts: Array[Control] = [_bg, icon_box, tank, wordmark, line]
	for part: Control in parts:
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rest_pose()  # Reduced effects never drive: the tank rests from the first frame.


## Starts the loads and the consent. The first `step` is the first frame (time 0).
func begin() -> void:
	for path: String in _paths():
		loader.request(path)
	_wait.run(consent)


## The still frame for a window of `area` px (the splash PNG scaled by min side / side and
## centred, as the engine's Keep stretch shows it) and the progress line inside `safe`.
func apply_layout(area: Vector2, safe: Rect2) -> void:
	var fit: float = minf(area.x, area.y) / float(settings.splash_side)
	var origin: Vector2 = (area - Vector2.ONE * settings.splash_side * fit) / 2.0
	_bg.position = Vector2.ZERO
	_bg.size = area
	icon_box.position = origin + Vector2(settings.icon_rect.position) * fit
	icon_box.size = Vector2(settings.icon_rect.size) * fit
	icon_box.pivot_offset = icon_box.size / 2.0
	tank.pivot_offset = icon_box.size / 2.0
	for layer: TextureRect in _layers.values():
		layer.size = Vector2(settings.icon_rect.size)
		layer.scale = Vector2.ONE * fit
	wordmark.position = origin + Vector2(settings.wordmark_rect.position) * fit
	wordmark.size = Vector2(settings.wordmark_rect.size) * fit
	_rest_pose()
	_cover = maxf(area.x / icon_box.size.x, area.y / icon_box.size.y) * settings.cover_margin
	_line_full = safe.size.x * settings.line_width_ratio
	line.size = Vector2(0.0, UiScale.dp(settings.line_dp))
	line.position = Vector2(
		safe.position.x + (safe.size.x - _line_full) / 2.0,
		safe.end.y - UiScale.dp(settings.line_bottom_dp) - line.size.y
	)


## A tap or Back: the motion ends at once. Before loading is done that leaves the still frame and
## the line; after it, the open-out starts without waiting for `min_ms`.
func skip() -> void:
	_skipped = true
	if phase == Phase.DRIVE:
		_settle()


func consent_done() -> bool:
	return _wait.done


## The tank stops in its rest pose (a still idle) and the progress line may show.
func _settle() -> void:
	phase = Phase.SETTLED
	_rest_pose()


## Every animated part back where the still frame has it: the tank, the layers' offsets, turns,
## pivots and alpha. Run on settling, on a new layout and when reduced effects never drive.
func _rest_pose() -> void:
	tank.position = Vector2.ZERO
	tank.rotation = 0.0
	for layer: TextureRect in _layers.values():
		layer.position = Vector2.ZERO
		layer.rotation = 0.0
		layer.pivot_offset = Vector2.ZERO
		layer.modulate.a = 1.0


func step() -> void:
	if phase == Phase.DONE:
		return
	var now: int = int(clock.call())
	if _t0 < 0:
		_t0 = now
	var t: int = now - _t0
	if phase == Phase.OPEN or phase == Phase.FADE:
		_advance_exit(now)
		return
	if phase == Phase.DRIVE and t >= settings.max_ms:
		_settle()
	if not _failed and is_loaded() and (_skipped or t >= settings.min_ms):
		_begin_exit(now)
		return
	if phase == Phase.DRIVE and not reduced:
		_drive(t)
	line.visible = phase == Phase.SETTLED
	line.size.x = _line_full * progress()


## Every load and the consent are done (a failed load counts so the intro never hangs on it).
func is_loaded() -> bool:
	if not _wait.done:
		return false
	for path: String in _paths():
		if loader.state(path) == IntroLoader.State.LOADING:
			return false
	return true


## 0..1 over the consent and every load.
func progress() -> float:
	var total: float = 1.0 if _wait.done else 0.0
	var paths: Array[String] = _paths()
	for path: String in paths:
		var done: bool = loader.state(path) != IntroLoader.State.LOADING
		total += 1.0 if done else loader.progress(path)
	return minf(1.0, total / float(paths.size() + 1))


func _paths() -> Array[String]:
	var found: Array[String] = [settings.menu_path]
	for path: String in settings.load_paths:
		found.append(path)
	return found


func _layer(parent: Control, stem: String) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = load(settings.layer_dir + stem + ".svg") as Texture2D
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	parent.add_child(rect)
	return rect


## The tank's motion at `t` ms: cleats scroll, the hull rocks, clods and sparks loop, the radar
## turns. Offsets are in icon px, scaled with the layer.
func _drive(t: int) -> void:
	var fit: float = _layers["sky"].scale.x
	var dir: Vector2 = settings.cleat_dir.normalized()
	var cycle: float = fposmod(float(t), float(settings.cleat_period_ms)) / settings.cleat_period_ms
	for stem: String in ["cleats_far", "cleats_near"]:
		_layers[stem].position = dir * settings.cleat_pitch_px * cycle * fit
	var rock: float = sin(TAU * t / settings.rock_period_ms)
	tank.position = Vector2(0.0, rock * settings.rock_px * fit)
	tank.rotation = deg_to_rad(rock * settings.rock_deg)
	var hop: float = absf(sin(PI * t / settings.clod_period_ms))
	_layers["clods"].position = Vector2(0.0, -hop * settings.clod_px * fit)
	_layers["sparks"].modulate.a = 0.55 + 0.45 * sin(TAU * t / settings.spark_period_ms)
	_turn("sweep", settings.sweep_deg_per_s * t / 1000.0)
	_turn("ring", settings.ring_deg_per_s * t / 1000.0)


func _turn(stem: String, degrees: float) -> void:
	var layer: TextureRect = _layers[stem]
	var fit: float = layer.scale.x
	layer.pivot_offset = settings.radar_pivot
	layer.position = settings.radar_pivot * (fit - 1.0)  # The pivot stays put under the scale.
	layer.rotation = deg_to_rad(degrees)


func _begin_exit(now: int) -> void:
	var scene: PackedScene = loader.take(settings.menu_path) as PackedScene
	if scene == null:
		_failed = true  # Said once; the still frame and the line stay.
		log_line.call("boot_error: %s did not load" % settings.menu_path)
		_settle()
		line.visible = true
		return
	_exit_t0 = now
	line.visible = false
	phase = Phase.FADE if reduced else Phase.OPEN
	for path: String in settings.load_paths:
		var extra: Resource = loader.take(path)
		if extra != null:
			_held.append(extra)  # Kept alive until the menu holds them.
	_menu = scene.instantiate() as Control
	_menu.modulate.a = 0.0
	var parent: Node = host if host != null else get_tree().root
	parent.add_child(_menu)
	# The faded menu must not take a touch before it is shown: a blocker stands above it.
	_blocker = Control.new()
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(_blocker)
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _advance_exit(now: int) -> void:
	var span: int = settings.fade_ms if phase == Phase.FADE else settings.open_ms
	var p: float = clampf(float(now - _exit_t0) / maxf(1.0, float(span)), 0.0, 1.0)
	if phase == Phase.FADE:
		_menu.modulate.a = p
	else:
		icon_box.scale = Vector2.ONE * lerpf(1.0, _cover, ease(p, 0.5))
		tank.position.y = (size.y / _cover + icon_box.size.y) * ease(p, 2.0)
		wordmark.modulate.a = 1.0 - clampf(p / 0.4, 0.0, 1.0)
		_menu.modulate.a = clampf((p - 0.4) / 0.6, 0.0, 1.0)
	if p >= 1.0:
		_finish(now)


func _finish(now: int) -> void:
	phase = Phase.DONE
	_blocker.queue_free()
	_held.clear()
	_menu.modulate.a = 1.0
	log_line.call("boot_ms=%d" % (now - _t0))
	finished.emit(_menu)
	if host == null:
		get_tree().current_scene = _menu
		queue_free()
