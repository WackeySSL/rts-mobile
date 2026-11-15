class_name AdServiceHarness
extends RefCounted
## Shared setup for the AdService suites: a fresh service on the fake backend with consent granted,
## a fake clock (the timeouts never read wall time) and a log of the ad_opened/ad_closed signals.
## The caller frees the service (`auto_free`) and makes a new harness per test.

const SCRIPT_PATH: String = "res://game/ads/AdService.gd"

var clock_ms: int = 0
var events: Array[String] = []


## A new service. Auto close is on, so a suite run from the editor does not wait for a button.
func make(consent: bool = true, script_path: String = SCRIPT_PATH) -> Node:
	var script: GDScript = load(script_path) as GDScript
	var service: Node = script.new()
	service.fake_auto_close = true
	service._can_request_ads = consent
	service._now_ms = func() -> int: return clock_ms
	service.ad_opened.connect(
		func(placement: StringName) -> void: events.append("open:" + placement)
	)
	service.ad_closed.connect(
		func(placement: StringName) -> void: events.append("close:" + placement)
	)
	return service


static func fake(service: Node) -> FakeAdBackend:
	return service._backend as FakeAdBackend


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
