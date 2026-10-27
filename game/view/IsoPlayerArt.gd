class_name IsoPlayerArt
extends RefCounted
## The art one player draws (ADR 0023 section 5): its faction's frames with the faction's key
## triad replaced by the player's. A triad is three `#RRGGBB` strings, light, mid and dark
## (`FactionDef.key_triad`), upper-cased here as P99 writes the frames. `recolour` finds the key
## colours of a frame in one pass and gives each the colour of its own place in the player's triad,
## so a triad that holds another key colour never changes twice.

var faction: StringName = &""  ## The art's faction (`fossil` or `renew`), as `IsoSheetDef.faction`.
var key: PackedStringArray = PackedStringArray()  ## The faction's key triad.
var triad: PackedStringArray = PackedStringArray()  ## The player's triad.
var _matcher: RegEx = RegEx.new()


## The art of a player of `faction_id` wearing `player_triad`, for frames painted in `key_triad`.
static func make(
	faction_id: StringName, key_triad: PackedStringArray, player_triad: PackedStringArray
) -> IsoPlayerArt:
	var art: IsoPlayerArt = IsoPlayerArt.new()
	art.faction = faction_id
	art.key = _upper(key_triad)
	art.triad = _upper(player_triad)
	if art.is_valid():
		# No hex digit may follow a key colour, so #FF9446 never matches inside #FF94461.
		var any: String = "|".join(art.key)
		art._matcher.compile("(?i)(?:%s)(?![0-9a-f])" % any)
	return art


## Whether both triads are three `#RRGGBB` colours and the key colours differ from each other.
func is_valid() -> bool:
	for colours: PackedStringArray in [key, triad]:
		if colours.size() != 3:
			return false
		for colour: String in colours:
			if colour.length() != 7 or not colour.begins_with("#"):
				return false
			if not colour.substr(1).is_valid_hex_number():
				return false
	return key[0] != key[1] and key[0] != key[2] and key[1] != key[2]


## `text` with every key colour replaced by the player's colour of the same place, in one pass;
## `text` itself for art that is not valid.
func recolour(text: String) -> String:
	if not _matcher.is_valid():
		return text
	var hits: Array[RegExMatch] = _matcher.search_all(text)
	if hits.is_empty():
		return text
	var out: PackedStringArray = PackedStringArray()
	var from: int = 0
	for hit: RegExMatch in hits:
		out.append(text.substr(from, hit.get_start() - from))
		out.append(triad[key.find(hit.get_string().to_upper())])
		from = hit.get_end()
	out.append(text.substr(from))
	return "".join(out)


static func _upper(colours: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for colour: String in colours:
		out.append(colour.to_upper())
	return out
