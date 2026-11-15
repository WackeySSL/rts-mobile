class_name AdsSettingsDef
extends Resource
## Every cap, timeout, reward and gap of the ads layer (ADR 0039 section 4). The instance is
## `res://data/ads_settings.tres`, where all tuning happens; the defaults here are the values that
## file holds. Never read by `game/sim`. `problems()` lists every out-of-range field, so a data
## test and the loaders can reject a bad file without crashing.

const PATH: String = "res://data/ads_settings.tres"

## None in a new player's first N completed matches.
@export var interstitial_free_matches: int = 2
## At least this many seconds of play since the last interstitial.
@export var interstitial_min_play_s: int = 240
## At most this many interstitials per completed match.
@export var interstitial_per_match: int = 1
## The longest wait for a full-screen ad to open (ms).
@export var fullscreen_timeout_ms: int = 8000
## The longest wait for the consent info and the form to load (ms).
@export var consent_timeout_ms: int = 10000
## Double XP: the multiplier handed to `Progression.apply_bonus`.
@export var reward_xp_multiplier: int = 2
## The starting-credits reward.
@export var reward_start_credits: int = 500
## One pending bonus, no stacking: the most the ledger holds.
@export var start_credits_bonus_max: int = 500
## One rewarded offer per screen.
@export var rewarded_offers_per_screen: int = 1
## The least air between a banner and any control (dp).
@export var banner_gap_dp: int = 16
## The start page's air round its banner (dp, ADR 0025 section 12).
@export var start_banner_gap_dp: int = 48
## A turn reloads the banner at most this often (ms).
@export var banner_reload_min_ms: int = 30000
## The Play product of the Remove ads purchase.
@export var remove_ads_product_id: String = "remove_ads"


## Loads the shipped file; a fresh default instance when it is missing or of another type.
static func load_default() -> AdsSettingsDef:
	var loaded: AdsSettingsDef = load(PATH) as AdsSettingsDef
	if loaded == null:
		return AdsSettingsDef.new()
	return loaded


## One line per field out of range; empty means valid.
func problems() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_check(out, "interstitial_free_matches", interstitial_free_matches, 0, 20)
	_check(out, "interstitial_min_play_s", interstitial_min_play_s, 0, 3600)
	_check(out, "interstitial_per_match", interstitial_per_match, 1, 1)
	_check(out, "fullscreen_timeout_ms", fullscreen_timeout_ms, 1000, 30000)
	_check(out, "consent_timeout_ms", consent_timeout_ms, 1000, 60000)
	_check(out, "reward_xp_multiplier", reward_xp_multiplier, 2, 4)
	_check(out, "reward_start_credits", reward_start_credits, 1, 5000)
	_check(out, "start_credits_bonus_max", start_credits_bonus_max, reward_start_credits, 5000)
	_check(out, "rewarded_offers_per_screen", rewarded_offers_per_screen, 1, 1)
	_check(out, "banner_gap_dp", banner_gap_dp, 16, 200)
	_check(out, "start_banner_gap_dp", start_banner_gap_dp, 16, 200)
	_check(out, "banner_reload_min_ms", banner_reload_min_ms, 1000, 600000)
	if remove_ads_product_id.strip_edges().is_empty():
		out.append("remove_ads_product_id is empty")
	return out


static func _check(out: PackedStringArray, field: String, value: int, low: int, high: int) -> void:
	if value < low or value > high:
		out.append("%s=%d outside %d..%d" % [field, value, low, high])
