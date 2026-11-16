class_name AdIds
extends RefCounted
## The ad unit IDs for Android (ADR 0039 section 9). Google's published test units are constants
## here; real unit IDs come only from the git-ignored `res://ad_ids.cfg` that a release workflow
## writes into the export (`scripts/ci/write-ad-ids.sh`, P414). A debug build never reads that
## file. The file holds unit IDs only (never the App ID), as a `[units]` section:
##
##     [units]
##     banner="..."
##     interstitial="..."
##     rewarded="..."
##
## A missing file, a missing key or a malformed value falls back to the test unit for that format,
## so a build is never left without a unit and never sends a made-up one.
## Never put a real ID in this repository.

## Google's test units for Android (https://developers.google.com/admob/android/test-ads):
## adaptive banner, interstitial, rewarded.
const TEST_BANNER: String = "ca-app-pub-3940256099942544/9214589741"
const TEST_INTERSTITIAL: String = "ca-app-pub-3940256099942544/1033173712"
const TEST_REWARDED: String = "ca-app-pub-3940256099942544/5224354917"

const CFG_PATH: String = "res://ad_ids.cfg"
const KIND_BANNER: StringName = &"banner"

var banner: String = TEST_BANNER
var interstitial: String = TEST_INTERSTITIAL
var rewarded: String = TEST_REWARDED
## True while every unit is Google's test unit.
var uses_test_units: bool = true


## Debug builds always get the test units; a release build gets the file's, per key.
static func load_units(is_debug: bool, cfg_path: String = CFG_PATH) -> AdIds:
	var ids: AdIds = AdIds.new()
	if is_debug:
		return ids
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return ids
	ids.banner = _unit(cfg, "banner", TEST_BANNER)
	ids.interstitial = _unit(cfg, "interstitial", TEST_INTERSTITIAL)
	ids.rewarded = _unit(cfg, "rewarded", TEST_REWARDED)
	ids.uses_test_units = (
		ids.banner == TEST_BANNER
		and ids.interstitial == TEST_INTERSTITIAL
		and ids.rewarded == TEST_REWARDED
	)
	return ids


## The unit for `kind` (`KIND_BANNER`, `AdBackend.KIND_INTERSTITIAL`, `AdBackend.KIND_REWARDED`).
func unit(kind: StringName) -> String:
	match kind:
		KIND_BANNER:
			return banner
		&"interstitial":
			return interstitial
		&"rewarded":
			return rewarded
	return ""


static func _unit(cfg: ConfigFile, key: String, fallback: String) -> String:
	var value: String = String(cfg.get_value("units", key, "")).strip_edges()
	var pattern: RegEx = RegEx.create_from_string("^ca-app-pub-[0-9]{16}/[0-9]{10}$")
	return value if pattern.search(value) != null else fallback
