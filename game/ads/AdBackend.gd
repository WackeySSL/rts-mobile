class_name AdBackend
extends RefCounted
## The seam between AdService and an ad SDK (ADR 0039 sections 1 and 2). AdService owns every
## rule (consent, caps, timeouts, the reward); a backend only loads, shows and reports. Methods
## never block: a load answers through `load_state` and a show through the signals. This base is
## an inert backend that never fills. `FakeAdBackend` is the scriptable fake. The real backend
## (`AdMobBackend`, P405) is the only class that may name Poing's plugin.

## A full-screen ad opened on screen.
signal opened(kind: StringName)
## A full-screen ad was dismissed. Emitted after `reward_earned` when the viewer earned one.
signal closed(kind: StringName)
## The SDK's reward callback: the only place a reward may be granted.
signal reward_earned(kind: StringName)

enum LoadState { IDLE, LOADING, READY, FAILED }

const KIND_INTERSTITIAL: StringName = &"interstitial"
const KIND_REWARDED: StringName = &"rewarded"


## True only when the OS is Android, not the editor, the plugin's singleton exists and the build
## carries the `play` feature tag (ADR 0039 section 2); every other case is fake mode.
static func is_admob_mode(
	os_name: String, in_editor: bool, has_plugin: bool, has_play_tag: bool
) -> bool:
	return os_name == "Android" and not in_editor and has_plugin and has_play_tag


func load_state(_kind: StringName) -> LoadState:
	return LoadState.FAILED


## Asks for one ad of `kind` to be loaded; the answer shows in `load_state`.
func request_load(_kind: StringName) -> void:
	pass


## Shows the loaded ad: `opened` then, later, `closed`. `auto_close` is a fake-only hint.
func show_ad(_kind: StringName, _auto_close: bool) -> void:
	pass


## Withdraws a show that has not opened, so it never opens later.
func cancel_show(_kind: StringName) -> void:
	pass


func show_banner(_draw_placeholder: bool) -> void:
	pass


func hide_banner() -> void:
	pass


## The anchored banner's height in dp.
func banner_height_dp() -> int:
	return 0
