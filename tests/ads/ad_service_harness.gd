class_name AdServiceHarness
extends RefCounted
## Shared setup for the AdService suites: a fresh service on the fake backend with consent granted,
## a fake clock (the timeouts never read wall time) and a log of the ad_opened/ad_closed signals.
## The caller frees the service (`auto_free`) and makes a new harness per test.

const SCRIPT_PATH: String = "res://game/ads/AdService.gd"
const SaveServiceScript: GDScript = preload("res://game/meta/save_service.gd")
const SAVE_SUFFIXES: Array[String] = ["", ".tmp", ".bak", ".bad", ".bak.bad"]

var clock_ms: int = 0
var events: Array[String] = []

var _save_service: SaveServiceScript = null
var _save_path: String = "user://test_ads_save_%d.cfg" % OS.get_process_id()


## The harness's own SaveService on a temp file, made on first use. The `/root/SaveService`
## autoload is never touched. It is not in the tree: tests flush it themselves.
func save_service() -> SaveServiceScript:
	if _save_service == null:
		_remove_files()
		_save_service = SaveServiceScript.new()
		_save_service.set_path_override(_save_path)
	return _save_service


## The temp file's path, for a second SaveService that reads what is on disk.
func save_path() -> String:
	return _save_path


## Puts the `ads` section in the temp save before a service is made, as an earlier run left it.
func seed_section(values: Dictionary) -> void:
	assert(save_service().set_section(&"ads", values), "the section was refused")


## Flushes, deletes the temp files and frees the SaveService. Call it from `after_test`.
func dispose() -> void:
	if _save_service != null:
		_save_service.flush()
		_save_service.free()
		_save_service = null
	_remove_files()


func _remove_files() -> void:
	for suffix: String in SAVE_SUFFIXES:
		if FileAccess.file_exists(_save_path + suffix):
			DirAccess.remove_absolute(_save_path + suffix)


## A new service with the harness's SaveService injected. Auto close is on, so a suite run from
## the editor does not wait for a button. `script_path` names a subclass of the service (P431's
## counting service). `load_ledger` reads the `ads` section now, as the service's `_ready` would;
## pass false to let `add_child` do it.
func make(
	consent: bool = true, script_path: String = SCRIPT_PATH, load_ledger: bool = true
) -> Node:
	var script: GDScript = load(script_path) as GDScript
	var service: Node = script.new()
	service.save_service = save_service()
	if load_ledger:
		service._load_ledger()
	service.fake_auto_close = true
	# The editor's non-headless default requires consent; the suites script it where they need it.
	ump(service).consent_required = false
	service._set_can_request(consent)
	service._now_ms = func() -> int: return clock_ms
	service.ad_opened.connect(
		func(placement: StringName) -> void: events.append("open:" + placement)
	)
	service.ad_closed.connect(
		func(placement: StringName) -> void: events.append("close:" + placement)
	)
	return service


static func ump(service: Node) -> FakeUmp:
	return service._consent.backend as FakeUmp


static func consent_timeout_ms(service: Node) -> int:
	return service._settings.consent_timeout_ms


static func fake(service: Node) -> FakeAdBackend:
	return service._backend as FakeAdBackend


static func billing(service: Node) -> FakeBilling:
	return service._billing as FakeBilling


## Three finished matches, 240 s in all: the first interstitial may show.
static func play_three_matches(service: Node) -> void:
	service.note_match_completed(100)
	service.note_match_completed(100)
	service.note_match_completed(40)


## Starts a coroutine without awaiting it; the result lands in the returned array.
static func start(call: Callable) -> Array:
	var out: Array = []
	var run: Callable = func() -> void: out.append(await call.call())
	run.call()
	return out


static func frames(count: int) -> void:
	for step: int in count:
		await (Engine.get_main_loop() as SceneTree).process_frame
