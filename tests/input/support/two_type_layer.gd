extends UnitLayer
## Phase 1 has one unit type, so this layer fakes the snapshot: own units 1 and 3 are type 0, own
## unit 2 is type 1 and enemy 4 is type 0. These four are on screen, 200 px apart. Own unit 5 is
## type 0 with its centre 10 px left of the screen. Not a test suite. It has its own file because an
## inner class may not extend a script (tests/project/test_inner_classes_extend_engine_classes.gd).


func fill_pick_snapshot(snap: PickSnapshot, _min_radius_px: float) -> void:
	snap.ids = PackedInt32Array([1, 2, 3, 4, 5])
	snap.owners = PackedInt32Array([1, 1, 1, 2, 1])
	snap.type_index = PackedInt32Array([0, 1, 0, 0, 0])
	snap.screen_pos = PackedVector2Array()
	snap.radius_px = PackedFloat32Array()
	for x: int in [100, 300, 500, 700, -10]:
		snap.screen_pos.append(Vector2(x, 300))
		snap.radius_px.append(30.0)
