class_name IntroRig
extends RefCounted
## What the IntroPlayer suites share: a fake clock, a fake loader, a fake consent, a host for the
## menu and a log of the console lines. `setup` before each test, `teardown` after it.

var now: int = 0
var loader: FakeIntroLoader
var consent: FakeConsent
var host: Control
var logs: Array[String] = []
var presses: int = 0

var _quit_on_back: bool = false


## A consent that waits until `release` is emitted.
class FakeConsent:
	extends RefCounted
	signal release
	var calls: int = 0

	func wait() -> bool:
		calls += 1
		await release
		return true


func setup(suite: GdUnitTestSuite, menu: PackedScene, size: Vector2) -> void:
	now = 0
	presses = 0
	logs.clear()
	loader = FakeIntroLoader.new()
	loader.scene = menu
	consent = FakeConsent.new()
	host = suite.auto_free(Control.new())
	host.size = size
	suite.add_child(host)
	_quit_on_back = suite.get_tree().quit_on_go_back


func teardown(suite: GdUnitTestSuite) -> void:
	UiScale.clear_override()
	suite.get_tree().quit_on_go_back = _quit_on_back
	consent.release.emit()  # A pending fake consent never outlives its test.


func instant_consent() -> bool:
	return true


## A player on the fakes, in the tree and begun. `consent_call` replaces the instant consent.
func make(
	suite: GdUnitTestSuite,
	size: Vector2,
	reduced: bool = false,
	wait_consent: bool = false,
	consent_call: Callable = Callable()
) -> IntroPlayer:
	var player: IntroPlayer = IntroPlayer.new()
	player.clock = func() -> int: return now
	player.loader = loader
	player.reduced = reduced
	player.host = host
	player.log_line = func(text: String) -> void: logs.append(text)
	player.consent = instant_consent
	if wait_consent:
		player.consent = consent.wait
	elif consent_call.is_valid():
		player.consent = consent_call
	player.size = size
	suite.add_child(suite.auto_free(player))
	return player


func at(player: IntroPlayer, ms: int) -> void:
	now = ms
	player.step()
