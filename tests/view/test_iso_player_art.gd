extends GdUnitTestSuite
## The team colour step of the per-match bake (plan P113, ADR 0023 section 5): one regex pass over
## the SVG text replaces the faction's key triad, three upper-case `#RRGGBB` strings, with the
## player's triad, each key colour by the colour of its own place, and nothing else.

const KEY: PackedStringArray = ["#FF9446", "#E8681F", "#B04B12"]  ## Signal, the Derrick League's.
const ARKTISK: PackedStringArray = ["#62D6EE", "#1FA6C8", "#137C99"]
const FRAME: String = (
	'<svg width="16" height="4"><polygon fill="#FF9446" stroke="#B04B12"/>'
	+ '<polygon fill="#E8681F"/><polygon fill="#808080" stroke="#1C2127"/></svg>'
)
const SHEEN: String = (
	'<svg><defs><linearGradient id="s0"><stop offset="0" stop-color="#8A9398"/>'
	+ '<stop offset="1" stop-color="#6B7366"/></linearGradient>'
	+ '<linearGradient id="m0"><stop offset="0" stop-color="#F07AF0"/>'
	+ '<stop offset="1" stop-color="#9A1F9A"/></linearGradient></defs>'
	+ '<polygon fill="url(#s0)" stroke="#1C2127"/><polygon fill="#D234D2" stroke="#9A1F9A"/>'
	+ '<polygon fill="url(#m0)" stroke="#F07AF0"/></svg>'
)


func test_each_key_colour_becomes_the_colour_of_its_place_in_the_players_triad() -> void:
	var art: IsoPlayerArt = IsoPlayerArt.make(&"fossil", KEY, ARKTISK)
	assert_bool(art.is_valid()).is_true()
	assert_str(art.recolour(FRAME)).is_equal(
		(
			'<svg width="16" height="4"><polygon fill="#62D6EE" stroke="#137C99"/>'
			+ '<polygon fill="#1FA6C8"/><polygon fill="#808080" stroke="#1C2127"/></svg>'
		)
	)


func test_a_triad_that_holds_other_key_colours_is_replaced_in_one_pass() -> void:
	# The player's triad is the key triad turned by one place: a pass per key colour would turn
	# light into mid into dark into light again and leave one colour for all three.
	var turned: PackedStringArray = [KEY[1], KEY[2], KEY[0]]
	var art: IsoPlayerArt = IsoPlayerArt.make(&"fossil", KEY, turned)
	var text: String = '<g fill="#FF9446"/><g fill="#E8681F"/><g fill="#B04B12"/>'
	var want: String = '<g fill="#E8681F"/><g fill="#B04B12"/><g fill="#FF9446"/>'
	assert_str(art.recolour(text)).is_equal(want)


func test_a_colour_that_only_looks_like_a_key_colour_is_left_alone() -> void:
	var art: IsoPlayerArt = IsoPlayerArt.make(&"fossil", KEY, ARKTISK)
	for text: String in [
		'<g fill="#FF9447"/>',  # One digit off.
		'<g fill="#FF94461"/>',  # A hex digit follows: another colour.
		'<g fill="#FF944"/>',  # Too short.
		'<g fill="FF9446"/>',  # No hash: not a colour literal.
	]:
		assert_str(art.recolour(text)).is_equal(text)


func test_triads_are_upper_cased_and_the_text_may_be_lower_case() -> void:
	var low_key: PackedStringArray = ["#ff9446", "#e8681f", "#b04b12"]
	var low_triad: PackedStringArray = ["#62d6ee", "#1fa6c8", "#137c99"]
	var art: IsoPlayerArt = IsoPlayerArt.make(&"fossil", low_key, low_triad)
	assert_array(art.key).is_equal(Array(KEY))
	assert_array(art.triad).is_equal(Array(ARKTISK))
	assert_str(art.recolour('<g fill="#ff9446"/>')).is_equal('<g fill="#62D6EE"/>')


func test_text_without_a_key_colour_and_art_with_the_key_as_triad_come_out_equal() -> void:
	var art: IsoPlayerArt = IsoPlayerArt.make(&"fossil", KEY, ARKTISK)
	var plain: String = '<g fill="#000000" opacity="0.35"/>'
	assert_str(art.recolour(plain)).is_equal(plain)
	var identity: IsoPlayerArt = IsoPlayerArt.make(&"fossil", KEY, KEY)
	assert_str(identity.recolour(FRAME)).is_equal(FRAME)


func test_art_is_valid_with_two_triads_of_three_hex_colours_and_distinct_keys() -> void:
	var short: PackedStringArray = ["#FF9446", "#E8681F"]
	var not_hex: PackedStringArray = ["#FF9446", "#E8681F", "#B04BZZ"]
	var no_hash: PackedStringArray = ["FF9446", "E8681F", "B04B12"]
	var twice: PackedStringArray = ["#FF9446", "#FF9446", "#B04B12"]
	assert_bool(IsoPlayerArt.make(&"fossil", short, ARKTISK).is_valid()).is_false()
	assert_bool(IsoPlayerArt.make(&"fossil", KEY, short).is_valid()).is_false()
	assert_bool(IsoPlayerArt.make(&"fossil", KEY, not_hex).is_valid()).is_false()
	assert_bool(IsoPlayerArt.make(&"fossil", no_hash, ARKTISK).is_valid()).is_false()
	assert_bool(IsoPlayerArt.make(&"fossil", twice, ARKTISK).is_valid()).is_false()
	assert_bool(IsoPlayerArt.make(&"fossil", KEY, twice).is_valid()).is_true()  # A triad may repeat.
	# Invalid art replaces nothing.
	assert_str(IsoPlayerArt.make(&"fossil", short, ARKTISK).recolour(FRAME)).is_equal(FRAME)


## P632 (ADR 0050 section 3): one sentinel triad for both factions, in the factions' data, is what
## the bake replaces. A frame holds it in fills, strokes and gradient stops; the bake gives all
## eight triads their colours in each, leaves every other colour alone, and handles a marker
## colour inside a gradient (P631's sheen never puts one there, the bake does not rely on it).


func test_both_factions_data_carry_the_one_sentinel_triad() -> void:
	for id: String in ["fossil", "renew"]:
		for path: String in [
			"res://data/factions/%s.tres", "res://data/dev/arena/factions/%s.tres"
		]:
			var faction: FactionDef = load(path % id) as FactionDef
			assert_array(Array(faction.key_triad)).is_equal(ArtPalette.SENTINEL)


func test_all_eight_triads_replace_the_sentinel_in_fills_strokes_and_gradient_stops() -> void:
	var sentinel: PackedStringArray = PackedStringArray(ArtPalette.SENTINEL)
	assert_int(WorldSort.TRIADS.size()).is_equal(8)
	for faction: StringName in [&"fossil", &"renew"]:
		for at: int in WorldSort.TRIADS.size():
			var triad: Array = WorldSort.TRIADS[at]
			var art: IsoPlayerArt = IsoPlayerArt.make(faction, sentinel, PackedStringArray(triad))
			var baked: String = art.recolour(SHEEN)
			var want: String = (
				SHEEN
				. replace(sentinel[0], triad[0])
				. replace(sentinel[1], triad[1])
				. replace(sentinel[2], triad[2])
			)
			assert_str(baked).override_failure_message("triad %d" % at).is_equal(want)
			for hex: String in sentinel:
				assert_bool(baked.contains(hex) and not triad.has(hex)).is_false()
			# The sheen's own stops and the outline are not the marker's.
			assert_str(baked).contains('stop-color="#8A9398"').contains('stop-color="#6B7366"')
			assert_str(baked).contains('stroke="#1C2127"')
