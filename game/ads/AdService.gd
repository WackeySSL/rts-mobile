extends Node
## The one facade for ads, consent and the Remove ads purchase (ADR 0039 section 1).
## Phase 5 calls only what is declared here; the signals, methods and their types are the
## agreed contract (docs/plans/2026-11-15-phase-6.md, "Interfaces with Phase 5", item 1).
##
## P401 lands the stub: fake mode only. Every call is a no-op that returns in the same frame,
## privacy options are not required, the banner height is 0, there is no start bonus and no
## entitlement. P403 and later (P402-P406) fill in the caps, the fake and the real backends,
## consent and billing behind these exact signatures. No plugin code and no ad IDs live here.
## Never touched by game/sim. No class_name: this is an autoload (tests/project/test_autoloads.gd).

## Fires when consent is settled, with whether ads may be requested. `ensure_consent` emits it
## (with false in the stub) before it returns.
signal consent_finished(can_request_ads: bool)
## Fires when the Remove ads entitlement changes, with the new state.
signal entitlement_changed(has_remove_ads: bool)
## Fires when the banner's height changes, with the new height in dp (0 = none).
signal banner_changed(height_dp: int)
## Fires when a full-screen ad opens, with its placement.
signal ad_opened(placement: StringName)
## Fires when a full-screen ad closes, with its placement.
signal ad_closed(placement: StringName)

## True: fake full-screen ads and fake flows close at once (gdUnit4, headless). False: the fake
## placeholders wait for their Close button and the fake flows for their buttons (P403 on).
## Tests may set it.
var fake_auto_close: bool = _default_auto_close(DisplayServer.get_name())


static func _default_auto_close(display_name: String) -> bool:
	return display_name == "headless"


## Awaitable; always finishes. True means ads may be requested. The stub emits
## `consent_finished(false)` and returns false: no ad is ever requested in fake mode.
func ensure_consent() -> bool:
	# A real coroutine that returns in the same frame, so callers must `await` from day one.
	@warning_ignore("redundant_await")
	await null
	consent_finished.emit(false)
	return false


## Synchronous.
func is_privacy_options_required() -> bool:
	return false


## Awaitable until UMP's privacy options form closes. The stub has no form.
func show_privacy_options() -> void:
	@warning_ignore("redundant_await")
	await null


## Synchronous.
func has_remove_ads() -> bool:
	return false


## Awaitable. True once the entitlement is granted. The stub cannot purchase.
func purchase_remove_ads() -> bool:
	@warning_ignore("redundant_await")
	await null
	return false


## Awaitable. True when a purchase was restored. The stub has none.
func restore_purchases() -> bool:
	@warning_ignore("redundant_await")
	await null
	return false


## Synchronous.
func banner_height_dp() -> int:
	return 0


## Awaitable. True means one interstitial showed. The stub shows none.
@warning_ignore("unused_parameter")
# gdlint: ignore=unused-argument
func maybe_show_interstitial(placement: StringName) -> bool:
	@warning_ignore("redundant_await")
	await null
	return false


## Called once per finished match (win, loss, surrender) with its play time in whole seconds.
@warning_ignore("unused_parameter")
# gdlint: ignore=unused-argument
func note_match_completed(play_seconds: int) -> void:
	pass


## Synchronous. The pending start-credits bonus once, then 0. The stub has none.
func take_start_credits_bonus() -> int:
	return 0
