class_name AdsSettingsDef
extends Resource
## Every cap, timeout, reward and gap of the ads layer (ADR 0039 section 4). The instance is
## `res://data/ads_settings.tres`, where all tuning happens; the defaults here are the values that
## file holds. Never read by `game/sim`. `validate()` lists every out-of-range field, so a data
## test and the loaders can reject a bad file without crashing.

## Where the shipped file lives.
const PATH: String = "res://data/ads_settings.tres"

const _MIN_FREE_MATCHES: int = 0
const _MAX_FREE_MATCHES: int = 20
const _MIN_PLAY_S: int = 0
const _MAX_PLAY_S: int = 3600
const _MIN_PER_MATCH: int = 1
const _MAX_PER_MATCH: int = 1
const _MIN_FULLSCREEN_MS: int = 1000
const _MAX_FULLSCREEN_MS: int = 30000
const _MIN_LATE_CAP_MS: int = 1
const _MAX_LATE_CAP_MS: int = 600000
const _MIN_BILLING_MS: int = 1000
const _MAX_BILLING_MS: int = 30000
const _MIN_CONSENT_MS: int = 1000
const _MAX_CONSENT_MS: int = 60000
const _MIN_XP_MULT: int = 2
const _MAX_XP_MULT: int = 4
const _MIN_CREDITS: int = 1
const _MAX_CREDITS: int = 5000
const _MIN_OFFERS: int = 1
const _MAX_OFFERS: int = 1
const _MIN_GAP_DP: int = 16
const _MAX_GAP_DP: int = 200
const _MIN_ARM_MS: int = 100
const _MAX_ARM_MS: int = 3000
const _MIN_RELOAD_MS: int = 1000
const _MAX_RELOAD_MS: int = 600000

static var _default: AdsSettingsDef

## None in a new player's first N completed matches.
@export_range(_MIN_FREE_MATCHES, _MAX_FREE_MATCHES) var interstitial_free_matches: int = 2
## At least this many seconds of play since the last interstitial.
@export_range(_MIN_PLAY_S, _MAX_PLAY_S) var interstitial_min_play_s: int = 240
## At most this many interstitials per completed match.
@export_range(_MIN_PER_MATCH, _MAX_PER_MATCH) var interstitial_per_match: int = 1
## The longest wait for a full-screen ad to open (ms).
@export_range(_MIN_FULLSCREEN_MS, _MAX_FULLSCREEN_MS) var fullscreen_timeout_ms: int = 8000
## The longest wait for a late full-screen ad (one that timed out) to fail or close before the next
## match is built (ms); see `AdService.settle_fullscreen`.
@export_range(_MIN_LATE_CAP_MS, _MAX_LATE_CAP_MS) var fullscreen_late_cap_ms: int = 20000
## The longest wait for the store sheet to show, or for a restore's answer (ms).
@export_range(_MIN_BILLING_MS, _MAX_BILLING_MS) var billing_timeout_ms: int = 8000
## The longest wait for the consent info and the form to load (ms).
@export_range(_MIN_CONSENT_MS, _MAX_CONSENT_MS) var consent_timeout_ms: int = 10000
## Double XP: the multiplier handed to `Progression.apply_bonus`.
@export_range(_MIN_XP_MULT, _MAX_XP_MULT) var reward_xp_multiplier: int = 2
## The starting-credits reward.
@export_range(_MIN_CREDITS, _MAX_CREDITS) var reward_start_credits: int = 500
## One pending bonus, no stacking: the most the ledger holds.
@export_range(_MIN_CREDITS, _MAX_CREDITS) var start_credits_bonus_max: int = 500
## One rewarded offer per screen.
@export_range(_MIN_OFFERS, _MAX_OFFERS) var rewarded_offers_per_screen: int = 1
## The least air between a banner and any control (dp).
@export_range(_MIN_GAP_DP, _MAX_GAP_DP) var banner_gap_dp: int = 16
## The start page's air round its banner (dp, ADR 0025 section 12).
@export_range(_MIN_GAP_DP, _MAX_GAP_DP) var start_banner_gap_dp: int = 48
## A turn reloads the banner at most this often (ms).
@export_range(_MIN_RELOAD_MS, _MAX_RELOAD_MS) var banner_reload_min_ms: int = 30000
## A shown rewarded offer ignores taps for this long, so a tap carried over from the match starts
## no ad (ms).
@export_range(_MIN_ARM_MS, _MAX_ARM_MS) var reward_arm_ms: int = 500
## The Double XP offer's button text; exactly one `%d`, which is `reward_xp_multiplier`.
@export var reward_xp_text: String = "Watch an ad for %dx XP"
## The starting-credits offer's button text; exactly one `%d`, which is `reward_start_credits`.
@export var reward_credits_text: String = "+%d credits next match"
## The same button once the bonus is granted and not yet used; exactly one `%d`, the credits.
@export var reward_credits_pending_text: String = "+%d credits ready"
## The Play product of the Remove ads purchase.
@export var remove_ads_product_id: String = "remove_ads"


## The shipped file, a shared cached instance; a test that wants another value calls duplicate()
## first.
static func load_default() -> AdsSettingsDef:
	# Not a preload: the file's script is this one, and a script cannot preload its own resource.
	if _default == null:
		_default = load(PATH) as AdsSettingsDef
		if _default == null:
			_default = AdsSettingsDef.new()
	return _default


## One line per field out of range; empty means valid.
func validate() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_check(
		out,
		"interstitial_free_matches",
		interstitial_free_matches,
		_MIN_FREE_MATCHES,
		_MAX_FREE_MATCHES
	)
	_check(out, "interstitial_min_play_s", interstitial_min_play_s, _MIN_PLAY_S, _MAX_PLAY_S)
	_check(out, "interstitial_per_match", interstitial_per_match, _MIN_PER_MATCH, _MAX_PER_MATCH)
	_check(
		out, "fullscreen_timeout_ms", fullscreen_timeout_ms, _MIN_FULLSCREEN_MS, _MAX_FULLSCREEN_MS
	)
	_check(
		out, "fullscreen_late_cap_ms", fullscreen_late_cap_ms, _MIN_LATE_CAP_MS, _MAX_LATE_CAP_MS
	)
	_check(out, "billing_timeout_ms", billing_timeout_ms, _MIN_BILLING_MS, _MAX_BILLING_MS)
	_check(out, "consent_timeout_ms", consent_timeout_ms, _MIN_CONSENT_MS, _MAX_CONSENT_MS)
	_check(out, "reward_xp_multiplier", reward_xp_multiplier, _MIN_XP_MULT, _MAX_XP_MULT)
	_check(out, "reward_start_credits", reward_start_credits, _MIN_CREDITS, _MAX_CREDITS)
	_check(
		out, "start_credits_bonus_max", start_credits_bonus_max, reward_start_credits, _MAX_CREDITS
	)
	_check(out, "rewarded_offers_per_screen", rewarded_offers_per_screen, _MIN_OFFERS, _MAX_OFFERS)
	_check(out, "banner_gap_dp", banner_gap_dp, _MIN_GAP_DP, _MAX_GAP_DP)
	_check(out, "start_banner_gap_dp", start_banner_gap_dp, _MIN_GAP_DP, _MAX_GAP_DP)
	_check(out, "banner_reload_min_ms", banner_reload_min_ms, _MIN_RELOAD_MS, _MAX_RELOAD_MS)
	_check(out, "reward_arm_ms", reward_arm_ms, _MIN_ARM_MS, _MAX_ARM_MS)
	if reward_xp_text.count("%") != 1 or reward_xp_text.count("%d") != 1:
		out.append("reward_xp_text must hold exactly one %d and no other %")
	for text: String in [reward_credits_text, reward_credits_pending_text]:
		if text.count("%") != 1 or text.count("%d") != 1:
			out.append("the credits texts must hold exactly one %d and no other %")
			break
	if remove_ads_product_id.strip_edges().is_empty():
		out.append("remove_ads_product_id is empty")
	return out


static func _check(out: PackedStringArray, field: String, value: int, low: int, high: int) -> void:
	if value < low or value > high:
		out.append("%s=%d outside %d..%d" % [field, value, low, high])
