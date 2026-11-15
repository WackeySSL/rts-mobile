class_name AdLedger
extends RefCounted
## The ads layer's counters (ADR 0039 sections 4, 7 and 10): completed matches, play seconds since
## the last interstitial, the match number of the last one, the cached Remove ads entitlement and
## the pending start-credits bonus. Pure: no Node, no clock. `to_dict` and `from_dict` match the
## `ads` section of Phase 5's SaveService; until P407 wires that, the ledger lives in memory.
## Tutorial lessons never call `note_match_completed`.

## Counters saturate here, so a hostile or corrupt save cannot overflow them.
const LIMIT: int = 1_000_000_000

const KEY_COMPLETED: String = "completed_matches"
const KEY_PLAY_S: String = "play_s_since_interstitial"
const KEY_LAST_MATCH: String = "last_interstitial_match"
const KEY_REMOVE_ADS: String = "remove_ads"
const KEY_PENDING: String = "pending_start_credits"

## Matches finished so far (win, loss or surrender).
var completed_matches: int = 0
## Seconds of play since the last shown interstitial.
var play_s_since_interstitial: int = 0
## The `completed_matches` value at the last shown interstitial; 0 when none showed yet.
var last_interstitial_match: int = 0
## The cached entitlement; Play's answer is the truth when it answers (ADR 0039 section 8).
var remove_ads: bool = false
## The start-credits bonus waiting for the next match; 0 when none.
var pending_start_credits: int = 0


## One finished match (win, loss, surrender): counts it and adds its play time.
func note_match_completed(play_seconds: int) -> void:
	completed_matches = mini(completed_matches + 1, LIMIT)
	play_s_since_interstitial = mini(
		play_s_since_interstitial + clampi(play_seconds, 0, LIMIT), LIMIT
	)


## A shown interstitial resets the play counter and records the match number.
func note_interstitial_shown() -> void:
	play_s_since_interstitial = 0
	last_interstitial_match = completed_matches


## Whether an interstitial already showed for the latest completed match.
func shown_for_current_match() -> bool:
	return completed_matches > 0 and last_interstitial_match == completed_matches


## Records the one pending bonus: returns false and changes nothing while one is pending (no
## stacking, ADR 0039 section 7); otherwise holds `amount`, at most `cap`, and returns true.
func grant_start_credits_bonus(amount: int, cap: int) -> bool:
	if pending_start_credits > 0:
		return false
	pending_start_credits = mini(maxi(amount, 0), maxi(cap, 0))
	return true


## The pending bonus, at most `cap`, once; then 0.
func take_start_credits_bonus(cap: int) -> int:
	var taken: int = mini(pending_start_credits, maxi(cap, 0))
	pending_start_credits = 0
	return taken


func to_dict() -> Dictionary:
	return {
		KEY_COMPLETED: completed_matches,
		KEY_PLAY_S: play_s_since_interstitial,
		KEY_LAST_MATCH: last_interstitial_match,
		KEY_REMOVE_ADS: remove_ads,
		KEY_PENDING: pending_start_credits,
	}


## A missing section (an empty or null dictionary) gives the defaults. A key of another type, a
## negative or an oversized number falls back to its default; a last-interstitial match beyond the
## completed count is clamped to it.
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
	if value is int and value >= 0 and value <= LIMIT:
		return value
	if value is float and is_finite(value) and value >= 0.0 and value <= float(LIMIT):
		return int(value)
	return 0
