extends "res://tests/ui/support/attack_suite.gd"
## The attack cue of a Dusk Array's blackout (ADR 0047 sections 5 and 8, plan P575b): one cue per
## STRIKE record of kind 2 when an own building lies in its radius and the point is out of view;
## none in view, none for the player's own strike, none for a rupture (a Deep Bore); the toast
## alone, with no rim wedge, while the radar is dark.

const BLACKOUT: int = 2
const RUPTURE: int = 1
const WIDE: int = 12000  ## The ring's radius, in milli-tiles.


## A point a few tiles off home, out of view once the camera is zoomed in (`_zoom_in`).
func _off() -> Vector2i:
	return Vector2i((HOME.x + 8) * 1000 + 500, HOME.y * 1000 + 500)


func _zoom_in() -> void:
	_camera.zoom = Vector2(4.0, 4.0)
	(
		assert_bool(
			_camera.visible_world_rect().has_point(IsoProjection.ground_to_px(_off().x, _off().y))
		)
		. is_false()
	)


## A blackout of the enemy row `_enemy` (the firer, in the tests) at `point`.
func _strike(point: Vector2i, kind: int = BLACKOUT, owner: int = 2, firer: int = 0) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var from: int = firer if firer > 0 else _enemy
	var type: int = snap.type_index[snap.index_of(from)]
	snap.type_strike_radius.resize(maxi(snap.type_strike_radius.size(), type + 1))
	snap.type_strike_radius[type] = WIDE
	_tick([World.Event.STRIKE, from, point.x, point.y, kind, owner, 0, 0])


func test_a_blackout_out_of_view_over_an_own_building_raises_one_cue_with_a_wedge() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_zoom_in()
	_strike(_off())
	assert_bool(_cues.active).is_true()
	assert_bool(_cues.rim_wedge).is_true()
	assert_bool(_toast.visible).is_true()
	assert_int(_emitted).is_equal(1)
	_strike(_off())  # The same area again soon after: no second cue.
	assert_int(_emitted).is_equal(1)


func test_no_cue_for_a_blackout_in_view_the_players_own_or_a_rupture() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_zoom_in()
	_strike(Vector2i(HOME.x * 1000 + 500, HOME.y * 1000 + 500))
	assert_bool(_cues.active).is_false()
	_strike(_off(), BLACKOUT, 1)  # The player fired it.
	assert_bool(_cues.active).is_false()
	_strike(_off(), RUPTURE)  # A Deep Bore raises no cue of its own.
	assert_bool(_cues.active).is_false()


func test_no_cue_when_no_own_building_lies_in_the_radius() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_zoom_in()
	var snap: MatchSnapshot = _runner.snapshot
	_strike(_off())
	assert_bool(_cues.active).is_true()
	_cues.dismiss()
	_cues.advance(_feed.state.settings.attack_cue_ms + 1.0)
	snap.type_strike_radius[snap.type_index[snap.index_of(_enemy)]] = 1000
	_tick([World.Event.STRIKE, _enemy, _off().x, _off().y, BLACKOUT, 2, 0, 0])
	assert_bool(_cues.active).is_false()


func test_the_cue_is_the_toast_alone_while_the_radar_is_dark() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_zoom_in()
	_runner.snapshot.radar_dark = PackedInt32Array([0, 1, 0])
	_strike(_off())
	assert_bool(_cues.active).is_true()
	assert_bool(_cues.rim_wedge).is_false()
	assert_bool(_toast.visible).is_true()
	_cues.dismiss()
	_cues.advance(_feed.state.settings.attack_cue_ms + 1.0)
	_runner.snapshot.radar_dark = PackedInt32Array([0, 0, 0])
	_strike(_off())
	assert_bool(_cues.rim_wedge).is_true()


func test_the_cue_names_an_own_building_in_the_ring() -> void:
	await _open(ScreenSizes.PORTRAIT[0])
	_zoom_in()
	_strike(_off())
	var snap: MatchSnapshot = _runner.snapshot
	assert_str(_cues.title).is_equal(
		snap.type_names[_lowest_own_building_type()].to_upper() + " UNDER ATTACK"
	)


func _lowest_own_building_type() -> int:
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		if snap.owner[row] == 1 and snap.type_foot_w[snap.type_index[row]] > 0:
			return snap.type_index[row]
	return -1
