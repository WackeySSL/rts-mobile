class_name AdCaps
extends RefCounted
## Whether an interstitial may show (ADR 0039 section 4). Pure and static: it reads the settings
## and the ledger and nothing else, no Node and no time source. The caller (AdService, P403) adds
## the one fact the caps cannot know, that an ad is loaded, and calls
## `AdLedger.note_interstitial_shown` when one showed.

## The only placement an interstitial may show at: after the player taps Continue on the result.
const PLACEMENT_POST_MATCH: StringName = &"post_match"


## True only for `&"post_match"`, without Remove ads, with consent, after more than
## `interstitial_free_matches` completed matches, after `interstitial_min_play_s` of play since the
## last one, and not beyond `interstitial_per_match` for the latest completed match.
static func may_show_interstitial(
	settings: AdsSettingsDef,
	ledger: AdLedger,
	placement: StringName,
	can_request_ads: bool,
) -> bool:
	return denial_reason(settings, ledger, placement, can_request_ads).is_empty()


## The reason an interstitial may not show, or an empty StringName when it may.
static func denial_reason(
	settings: AdsSettingsDef,
	ledger: AdLedger,
	placement: StringName,
	can_request_ads: bool,
) -> StringName:
	if placement != PLACEMENT_POST_MATCH:
		return &"placement"
	if ledger.remove_ads:
		return &"remove_ads"
	if not can_request_ads:
		return &"consent"
	if ledger.completed_matches <= settings.interstitial_free_matches:
		return &"free_matches"
	if ledger.play_s_since_interstitial < settings.interstitial_min_play_s:
		return &"play_time"
	# Shown once for a match is the ledger's record; the save has no finer count.
	var shown_this_match: int = 1 if ledger.shown_for_current_match() else 0
	if shown_this_match >= settings.interstitial_per_match:
		return &"per_match"
	return &""
