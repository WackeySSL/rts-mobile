extends GdUnitTestSuite
## P403: source scans. Nothing in the sim, the AI or the core names the ads layer, and the SDK
## classes are named only in their own backends (ADR 0039 section 1).

const NO_ADS_ROOTS: Array[String] = ["res://game/sim", "res://game/ai", "res://game/core"]
const SDK_ROOTS: Array[String] = ["res://game", "res://scenes", "res://data"]
const EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]
## Only these files may name the plugin's or Play Billing's classes (P405, P406).
const SDK_BACKENDS: Array[String] = [
	"res://game/ads/AdMobBackend.gd",
	"res://game/ads/UmpPluginBackend.gd",
	"res://game/ads/PlayBillingBackend.gd",
]
## Poing's and Play Billing's class names; P405 confirms the list against the plugin.
const SDK_NAMES: Array[String] = [
	"MobileAds",
	"InterstitialAdLoader",
	"RewardedAdLoader",
	"RewardedInterstitialAdLoader",
	"AdView",
	"AdRequest",
	"AdSize",
	"BillingClient",
	"UserMessagingPlatform",
	"ConsentInformation",
	"ConsentForm",
	"ConsentRequestParameters",
]


func test_no_ads_class_or_path_in_sim_ai_or_core() -> void:
	var names: Array[String] = ["AdService", "game/ads"]
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if String(entry["path"]).begins_with("res://game/ads/"):
			names.append(String(entry["class"]))
	assert_bool(names.size() > 2).is_true()
	var pattern: RegEx = RegEx.create_from_string("\\b(" + "|".join(names) + ")\\b|game/ads")
	for root: String in NO_ADS_ROOTS:
		var files: Array[String] = _files(root)
		assert_int(files.size()).override_failure_message(root).is_greater(0)
		for path: String in files:
			var text: String = FileAccess.get_file_as_string(path)
			assert_object(pattern.search(text)).override_failure_message(path).is_null()


func test_sdk_classes_are_named_only_in_their_backends() -> void:
	var pattern: RegEx = RegEx.create_from_string("\\b(" + "|".join(SDK_NAMES) + ")\\b")
	for root: String in SDK_ROOTS:
		var files: Array[String] = _files(root)
		assert_int(files.size()).override_failure_message(root).is_greater(0)
		for path: String in files:
			if path in SDK_BACKENDS:
				continue
			var text: String = FileAccess.get_file_as_string(path)
			assert_object(pattern.search(text)).override_failure_message(path).is_null()


func _files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for file_name: String in DirAccess.get_files_at(dir_path):
		if file_name.get_extension() in EXTENSIONS:
			out.append(dir_path.path_join(file_name))
	for sub: String in DirAccess.get_directories_at(dir_path):
		out.append_array(_files(dir_path.path_join(sub)))
	return out
