class_name AdBackend
extends RefCounted
## The seam between AdService and an ad SDK (ADR 0039 sections 1 and 2). AdService owns every
## rule (consent, caps, timeouts, the reward); a backend only loads, shows and reports. Methods
## never block: a load answers through `load_state` and a show through the signals. This base is
## an inert backend that never fills. `FakeAdBackend` is the scriptable fake. The real backend
## (`AdMobBackend`, P405) is the only class that may name Poing's plugin.
##
## To confirm in P405:
## - `cancel_show` is best effort. AdMob cannot recall a show it has started, so the real backend
##   may still open the ad after the timeout. AdService listens for that late open (see
##   `FullscreenRun`) and keeps its ledger and signals right, but it cannot stop the ad.
## - Which thread the plugin's callbacks arrive on. Every signal below must be emitted on the main
##   thread (deferred by the backend when the plugin calls from another).
## - Whether the reward callback may arrive after the close. AdService grants only when it comes
##   before the close.

## A full-screen ad opened on screen.
signal opened(kind: StringName)
## A full-screen ad was dismissed. Emitted after `reward_earned` when the viewer earned one.
signal closed(kind: StringName)
## The SDK's reward callback: the only place a reward may be granted.
signal reward_earned(kind: StringName)
## A show failed before it opened (the SDK's "failed to show"); nothing is on screen.
signal show_failed(kind: StringName)

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


## Shows the loaded ad: `opened` then, later, `closed`; or `show_failed`.
func show_ad(_kind: StringName) -> void:
	pass


## Asks that a show that has not opened never opens (best effort, see the notes above).
func cancel_show(_kind: StringName) -> void:
	pass


func show_banner() -> void:
	pass


func hide_banner() -> void:
	pass


## The anchored banner's height in dp.
func banner_height_dp() -> int:
	return 0
