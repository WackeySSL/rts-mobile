extends Node
## The one facade for ads, consent and the Remove ads purchase (ADR 0039 section 1).
## Phase 5 calls only what is declared here; the signals, methods and their types are the
## agreed contract (docs/plans/2026-11-15-phase-6.md, "Interfaces with Phase 5", item 1).
##
## P401 lands the stub: fake mode only. Every call is a no-op that returns at once, privacy
## options are not required, the banner height is 0, there is no start bonus and no entitlement.
## P402-P406 fill in the caps, the fake and the real backends, consent and billing behind these
## exact signatures. No plugin code and no ad IDs live here. Never touched by game/sim.
## No class_name: this is an autoload (tests/project/test_autoloads.gd).

signal consent_finished(can_request_ads: bool)
signal entitlement_changed(has_remove_ads: bool)
signal banner_changed(height_dp: int)
signal ad_opened(placement: StringName)
signal ad_closed(placement: StringName)

## True: fake full-screen ads and fake flows close at once (gdUnit4, headless). False: the fake
## placeholders wait for their Close and buttons (P403 on). Tests may set it.
var fake_auto_close: bool = DisplayServer.get_name() == "headless"


## Awaitable; always finishes. True means ads may be requested. The stub returns false: no ad is
## ever requested in fake mode.
func ensure_consent() -> bool:
	return false


func is_privacy_options_required() -> bool:
	return false


## Awaitable until UMP's privacy options form closes. The stub has no form.
func show_privacy_options() -> void:
	pass


func has_remove_ads() -> bool:
	return false


## Awaitable. True once the entitlement is granted. The stub cannot purchase.
func purchase_remove_ads() -> bool:
	return false


## Awaitable. True when a purchase was restored. The stub has none.
func restore_purchases() -> bool:
	return false


func banner_height_dp() -> int:
	return 0


## Awaitable. True means one interstitial showed. The stub shows none.
func maybe_show_interstitial(_placement: StringName) -> bool:
	return false


## Called once per finished match (win, loss, surrender) with its play time in whole seconds.
func note_match_completed(_play_seconds: int) -> void:
	pass


## The pending start-credits bonus once, then 0. The stub has none.
func take_start_credits_bonus() -> int:
	return 0
