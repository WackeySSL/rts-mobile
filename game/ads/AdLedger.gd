class_name AdLedger
extends RefCounted
## The ads layer's counters (ADR 0039 sections 4, 7 and 10): completed matches, play seconds since
## the last interstitial, the match number of the last one, the cached Remove ads entitlement and
## the pending start-credits bonus. Pure: no Node, no clock. `to_dict` and `from_dict` match the
## `ads` section of Phase 5's SaveService; until P407 wires that, the ledger lives in memory.
## Tutorial lessons never call `note_match_completed`.

const KEY_COMPLETED: String = "completed_matches"
const KEY_PLAY_S: String = "play_s_since_interstitial"
const KEY_LAST_MATCH: String = "last_interstitial_match"
const KEY_REMOVE_ADS: String = "remove_ads"
const KEY_PENDING: String = "pending_start_credits"

var completed_matches: int = 0
var play_s_since_interstitial: int = 0
## The `completed_matches` value at the last shown interstitial; 0 when none showed yet.
var last_interstitial_match: int = 0
## The cached entitlement; Play's answer is the truth when it answers (ADR 0039 section 8).
var remove_ads: bool = false
var pending_start_credits: int = 0


## One finished match (win, loss, surrender): counts it and adds its play time.
func note_match_completed(play_seconds: int) -> void:
	completed_matches += 1
	play_s_since_interstitial += maxi(play_seconds, 0)


## A shown interstitial resets the play counter and records the match number.
func note_interstitial_shown() -> void:
	play_s_since_interstitial = 0
	last_interstitial_match = completed_matches


## Whether an interstitial already showed for the latest completed match.
func shown_for_current_match() -> bool:
	return completed_matches > 0 and last_interstitial_match == completed_matches


## Records one pending bonus: `amount` replaces nothing and never stacks past `cap`.
func grant_start_credits_bonus(amount: int, cap: int) -> void:
	pending_start_credits = clampi(pending_start_credits + maxi(amount, 0), 0, maxi(cap, 0))


## The pending bonus once, then 0.
func take_start_credits_bonus() -> int:
	var taken: int = pending_start_credits
	pending_start_credits = 0
	return taken


func set_remove_ads(value: bool) -> void:
	remove_ads = value


func to_dict() -> Dictionary:
	return {
		KEY_COMPLETED: completed_matches,
		KEY_PLAY_S: play_s_since_interstitial,
		KEY_LAST_MATCH: last_interstitial_match,
		KEY_REMOVE_ADS: remove_ads,
		KEY_PENDING: pending_start_credits,
	}


## A missing section (an empty or null dictionary) gives the defaults. A key of another type or a
## negative number falls back to its default; a last-interstitial match beyond the completed count
## is clamped to it.
static func from_dict(section: Variant) -> AdLedger:
	var ledger: AdLedger = AdLedger.new()
	if not (section is Dictionary):
		return ledger
	var data: Dictionary = section
	ledger.completed_matches = _int_of(data, KEY_COMPLETED)
	ledger.play_s_since_interstitial = _int_of(data, KEY_PLAY_S)
	ledger.last_interstitial_match = mini(_int_of(data, KEY_LAST_MATCH), ledger.completed_matches)
	ledger.pending_start_credits = _int_of(data, KEY_PENDING)
	var cached: Variant = data.get(KEY_REMOVE_ADS, false)
	ledger.remove_ads = cached is bool and cached
	return ledger


static func _int_of(data: Dictionary, key: String) -> int:
	var value: Variant = data.get(key, 0)
	if value is int:
		return maxi(value, 0)
	if value is float and is_finite(value):
		return maxi(int(value), 0)
	return 0
