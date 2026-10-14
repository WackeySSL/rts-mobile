extends RefCounted
## The failure message of a determinism test (ADR 0007 section 8): which sections of the state hash
## differ between two Worlds, by the names of World.hash_section_names(). It calls hash_parts()
## only when the hashes differ, because that is the failure path. Not a test suite.


## "" when the two Worlds hash alike, else "tick A / B: header, pos_x" with the differing section
## names in hash order (a hash that differs without a differing section, which cannot happen,
## reads "no section").
static func mismatch(a: World, b: World) -> String:
	if a.state_hash() == b.state_hash():
		return ""
	var names: PackedStringArray = World.hash_section_names()
	var left: PackedInt64Array = a.hash_parts()
	var right: PackedInt64Array = b.hash_parts()
	var differing: PackedStringArray = PackedStringArray()
	for k: int in names.size():
		if left[k] != right[k]:
			differing.append(names[k])
	var which: String = ", ".join(differing) if not differing.is_empty() else "no section"
	return "tick %d / %d: %s" % [a.tick, b.tick, which]
