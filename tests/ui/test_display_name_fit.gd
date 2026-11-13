extends GdUnitTestSuite
## The guard of the build card's names (P120j, ADR 0025 section 5): every display name of the data
## fits the caption under the floor card (88 dp) without the ellipsis, and every name a locked card
## can show on its sash (a `requires` target, or a def that makes a tab's items) fits the sash in
## one line. Measured at each profile's rounded font px through the scaled theme, so a new name, a
## font, a theme or a card-size change that brings back a second line or a cut name fails here.

const DisplayNames: GDScript = preload("res://tests/ui/support/display_names.gd")
const HudThemes: GDScript = preload("res://tests/support/hud_theme.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")


func after_test() -> void:
	UiScale.clear_override()


func test_every_display_name_fits_the_caption_and_every_requirement_fits_the_sash() -> void:
	var names: Dictionary[String, String] = DisplayNames.all()
	var needed: Dictionary[String, String] = DisplayNames.requirements()
	assert_int(names.size()).is_greater(20)
	assert_int(needed.size()).is_greater(8)
	var misfits: PackedStringArray = PackedStringArray()
	for profile: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profile:
			misfits.append_array(_misfits(profile_name, profile[profile_name], names, needed))
	assert_array(misfits).override_failure_message("\n".join(misfits)).is_empty()


## The space centres' names (P234) are in the checked set. Nothing requires a space centre, so
## neither name shows on a sash: both are measured as captions only.
func test_the_space_centres_are_in_the_checked_names() -> void:
	var names: Dictionary[String, String] = DisplayNames.all()
	assert_str(names.get("fossil_space", "")).is_equal("Skyrig")
	assert_str(names.get("renew_space", "")).is_equal("Zenith")


## The engineering centres' and the four upgrades' names (P247) are in the checked set, as captions
## (no sash: nothing requires a centre or an upgrade).
func test_the_engineering_centres_and_upgrades_are_in_the_checked_names() -> void:
	var names: Dictionary[String, String] = DisplayNames.all()
	assert_str(names.get("fossil_engineering", "")).is_equal("Draft Shop")
	assert_str(names.get("renew_engineering", "")).is_equal("Lens Works")
	assert_str(names.get("heavy_bombs", "")).is_equal("Heavy Bombs")
	assert_str(names.get("plated_hull", "")).is_equal("Plated Hull")
	assert_str(names.get("focus_bombs", "")).is_equal("Focus Bombs")
	assert_str(names.get("glaze_hull", "")).is_equal("Glaze Hull")


## The names of `names` and `needed` that overrun at one profile, each as a line of the report.
func _misfits(
	profile_name: StringName,
	metrics: UiMetrics,
	names: Dictionary[String, String],
	needed: Dictionary[String, String]
) -> PackedStringArray:
	UiScale.set_override(metrics)
	var theme: Theme = HudTheme.scaled(HudThemes.source(), UiScale.base_px_per_dp())
	var px_per_dp: float = UiScale.dp(1.0)
	# The container floors the card to whole px, and the sash is drawn on that.
	var card: Vector2 = UiScale.dp_vec(ItemTile.CARD_DP.x, ItemTile.CARD_DP.y).floor()
	var frame: StyleBoxFlat = theme.get_stylebox(&"normal", ItemTile.VARIATION) as StyleBoxFlat
	var caption_room: float = card.x - frame.border_width_left - frame.border_width_right
	var sash_room: float = ItemTile.sash_room_px(card)
	var found: PackedStringArray = PackedStringArray()
	for id: String in names:
		var wide: float = _width(theme, ItemTile.CAPTION_VARIATION, names[id])
		if wide > caption_room:
			found.append(
				_line(id, names[id], wide, caption_room, px_per_dp, profile_name, "caption")
			)
	for id: String in needed:
		var wide: float = _width(theme, ItemTile.SASH_VARIATION, needed[id])
		if wide > sash_room:
			found.append(_line(id, needed[id], wide, sash_room, px_per_dp, profile_name, "sash"))
	return found


## `<id> "<name>" is <w> dp, room <r> dp, at <profile> (caption|sash)`
func _line(
	id: String,
	shown: String,
	wide: float,
	room: float,
	px_per_dp: float,
	at: StringName,
	what: String
) -> String:
	return (
		'%s "%s" is %.1f dp, room %.1f dp, at %s (%s)'
		% [id, shown, wide / px_per_dp, room / px_per_dp, at, what]
	)


## The width of `text` in the font and rounded size that `variation` has in `theme`.
func _width(theme: Theme, variation: StringName, text: String) -> float:
	var font: Font = theme.get_font(&"font", variation)
	var size: int = theme.get_font_size(&"font_size", variation)
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
