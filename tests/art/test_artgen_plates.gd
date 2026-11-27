extends GdUnitTestSuite
## No roof is a team plate (STYLE.md "Light" and "Generated art", ADR 0023 section 5, plan row P99):
## team colour is bands between wall segments, stripes, rings and lights, never a large plate on a
## roof or a cap on the top of a body. A team primitive is a roof plate when it is flat (lower than
## it is wide), its top face is open (less than a quarter of it has anything resting on it) and
## either it covers at least 30 % of the top of the primitive it rests on (a cab roof, a turret
## disc, a helmet cap) or its top face is larger than 0.2 square tiles (a slab). A band is covered
## by the wall segment above it, a stripe on a deck covers a small part of it, a lintel or a wall
## stripe is upright, and a ring lying along a barrel or a drum has no flat top.
## The one exception is the team marker of ADR 0050 section 3: a small plate (at most `MARKER`
## square tiles) with a light line round it (a `lamp` plate under it, larger on every side) and a
## dark rim round that (an `iron` plate under the lamp, larger again). Facet has no `lamp` or
## `iron`: its line is `ceramic` and its rim `graphite` (P639).
## The rule applies to models below detail 2. At detail 2 and up the team area is large panels by
## design (ADR 0050 amendment A3, P652), and the share of team pixels in the default view (30 to
## 65 % in the key band) is in test_artgen_readability.gd; below detail 2 the share is 2 to 12 %.

const REST: float = 0.011  ## Tiles: a primitive rests on another when its bottom is this close.
const OPEN: float = 0.25  ## A top face with less than this share covered is open.
const CAP: float = 0.3  ## A team primitive covering this share of its support is a cap.
const SLAB: float = 0.2  ## Square tiles: a larger open top face is a slab, whatever it rests on.
## Square tiles: the most a rimmed marker plate covers (ADR 0050 section 3).
const MARKER: float = 0.1
## The materials of a marker's light line and dark rim: Ironward's, then Facet's (P639).
const LINES: Array[StringName] = [&"lamp", &"ceramic"]
const RIMS: Array[StringName] = [&"iron", &"graphite"]


func test_no_team_primitive_below_detail_2_is_a_roof_plate() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		if model.detail >= 2:
			continue
		for part: StringName in model.parts():
			var found: Array[String] = _plates(model.primitives(part))
			(
				assert_array(found)
				. override_failure_message("%s %s has a team roof plate: %s" % [path, part, found])
				. is_empty()
			)


## The rule itself: a cap on a cab, a slab with nothing under it and a cap on a helmet are plates;
## a band between two segments, a stripe across a deck, a ring round a barrel and a thin vertical
## stripe are not. Without this the test above would pass for a rule that finds nothing.
func test_the_rule_finds_a_cap_and_a_slab_and_lets_a_band_a_stripe_and_a_ring_pass() -> void:
	var cab: Array[String] = [
		"box hull olive 0 0 0 0.4 0.5 0.3", "box hull team 0 0 0.3 0.4 0.5 0.02"
	]
	assert_int(_plates(_parse(cab)).size()).override_failure_message("cab roof").is_equal(1)
	var helmet: Array[String] = [
		"box hull steel 0 0 0 0.12 0.12 0.1", "box hull team 0 0 0.1 0.12 0.12 0.03"
	]
	assert_int(_plates(_parse(helmet)).size()).override_failure_message("helmet cap").is_equal(1)
	var disc: Array[String] = [
		"prism turret olive 0 0 0 0.52 0.52 0.16 sides=8",
		"prism turret team 0 0 0.16 0.34 0.34 0.02 sides=8"
	]
	assert_int(_plates(_parse(disc)).size()).override_failure_message("turret disc").is_equal(1)
	var slab: Array[String] = ["box hull team 0 0 0.5 1 1 0.1"]
	assert_int(_plates(_parse(slab)).size()).override_failure_message("slab").is_equal(1)
	var band: Array[String] = [
		"box hull olive 0 0 0 1 1 0.2",
		"box hull team 0 0 0.2 1.04 1.04 0.1",
		"box hull olive 0 0 0.3 0.9 0.9 0.2",
	]
	assert_array(_plates(_parse(band))).override_failure_message("band").is_empty()
	var deck: Array[String] = [
		"box hull olive 0 0 0 0.9 0.8 0.2", "box hull team -0.3 0 0.2 0.12 0.8 0.02"
	]
	assert_array(_plates(_parse(deck))).override_failure_message("deck stripe").is_empty()
	var ring: Array[String] = [
		"box hull olive 0.3 0 0 0.3 0.3 0.3", "prism hull team 0.1 0 0.1 0.12 0.2 0.2 axis=x"
	]
	assert_array(_plates(_parse(ring))).override_failure_message("ring").is_empty()
	var rimmed: Array[String] = [
		"box hull olive 0 0 0 0.4 0.5 0.3",
		"box hull iron 0 0 0.3 0.34 0.44 0.02",
		"box hull lamp 0 0 0.32 0.28 0.38 0.012",
		"box hull team 0 0 0.332 0.2 0.3 0.02",
	]
	assert_array(_plates(_parse(rimmed))).override_failure_message("rimmed marker").is_empty()
	var facet: Array[String] = [
		"box hull ceramic 0 0 0 0.4 0.5 0.3",
		"box hull graphite 0 0 0.3 0.34 0.44 0.02",
		"box hull ceramic 0 0 0.32 0.28 0.38 0.012",
		"box hull team 0 0 0.332 0.2 0.3 0.02",
	]
	assert_array(_plates(_parse(facet))).override_failure_message("facet marker").is_empty()
	var bare: Array[String] = [
		"box hull olive 0 0 0 0.4 0.5 0.3", "box hull team 0 0 0.3 0.2 0.3 0.02"
	]
	assert_int(_plates(_parse(bare)).size()).override_failure_message("bare plate").is_equal(1)
	var large: Array[String] = [
		"box hull olive 0 0 0 0.6 0.7 0.3",
		"box hull iron 0 0 0.3 0.54 0.64 0.02",
		"box hull lamp 0 0 0.32 0.48 0.58 0.012",
		"box hull team 0 0 0.332 0.4 0.5 0.02",
	]
	assert_int(_plates(_parse(large)).size()).override_failure_message("large plate").is_equal(1)
	var stripe: Array[String] = [
		"box hull concrete 0 0 0 1.5 1 0.3", "box hull team 0 0.5 0.3 1.5 0.04 0.2"
	]
	assert_array(_plates(_parse(stripe))).override_failure_message("wall stripe").is_empty()
	var lintel: Array[String] = [
		"box hull graphite 0 0 0 0.04 0.9 0.8", "box hull team 0 0 0.8 0.04 1.1 0.2"
	]
	assert_array(_plates(_parse(lintel))).override_failure_message("door lintel").is_empty()


## The team primitives of `prims` that are roof plates, one description each.
func _plates(prims: Array[ArtPrim]) -> Array[String]:
	var found: Array[String] = []
	for prim: ArtPrim in prims:
		if prim.material != ArtPalette.TEAM or prim.shape == &"sphere":
			continue
		if prim.shape == &"prism" and prim.axis != 2:
			continue  # A ring or a rod lying down has no flat top.
		if prim.size.z > minf(prim.size.x, prim.size.y):
			continue  # A stripe on a wall or a column is upright; a plate is lower than it is wide.
		var top: Rect2 = _footprint(prim)
		var area: float = top.get_area()
		var lid: float = prim.z0 + prim.size.z
		var covered: float = 0.0
		var cap: float = 0.0
		for other: ArtPrim in prims:
			if other == prim or other.material == ArtPalette.TEAM:
				continue
			if absf(other.z0 - lid) < REST:
				covered += top.intersection(_footprint(other)).get_area()
			if absf(other.z0 + other.size.z - prim.z0) < REST:
				var base: Rect2 = _footprint(other)
				cap = maxf(cap, top.intersection(base).get_area() / base.get_area())
		if covered / area >= OPEN:
			continue
		if area <= MARKER and _rimmed(prim, prims):
			continue
		if cap >= CAP or area > SLAB:
			found.append("%s %s at %s z %.2f" % [prim.shape, prim.size, prim.centre, prim.z0])
	return found


## Whether `plate` rests on a light-line plate (`lamp`, or Facet's `ceramic`) that is larger than it
## on every side, which rests on a dark-rim plate (`iron`, or Facet's `graphite`) larger than the
## line on every side: the marker's light line and dark rim.
func _rimmed(plate: ArtPrim, prims: Array[ArtPrim]) -> bool:
	var inner: ArtPrim = _under(plate, prims, LINES)
	return inner != null and _under(inner, prims, RIMS) != null


## The plate of one of `materials` that `top` rests on and that is larger than `top` on every side.
func _under(top: ArtPrim, prims: Array[ArtPrim], materials: Array[StringName]) -> ArtPrim:
	for other: ArtPrim in prims:
		if other.material not in materials or absf(other.z0 + other.size.z - top.z0) >= REST:
			continue
		if _footprint(other).encloses(_footprint(top).grow(0.01)):
			return other
	return null


func _footprint(prim: ArtPrim) -> Rect2:
	var box: AABB = prim.aabb()
	return Rect2(box.position.x, box.position.y, box.size.x, box.size.y)


func _parse(lines: Array[String]) -> Array[ArtPrim]:
	var prims: Array[ArtPrim] = []
	for line: String in lines:
		var prim: ArtPrim = ArtPrim.parse(line)
		assert_object(prim).override_failure_message(line).is_not_null()
		prims.append(prim)
	return prims
