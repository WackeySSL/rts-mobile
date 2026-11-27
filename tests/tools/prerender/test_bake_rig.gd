extends GdUnitTestSuite
## The bake rig's constants (plan row P656a, ADR 0053 section 5): every one is read from
## IsoProjection, ArtShadow and the generator's projection, so the baked frames lie on today's
## frames. No renderer is needed: the rig's static functions are pure.

const EPS: float = 1e-5


func test_the_view_is_isometric_projections_two_to_one_diamond() -> void:
	assert_float(BakeRig.elevation_sin()).is_equal_approx(
		float(IsoProjection.HALF_H) / IsoProjection.HALF_W, EPS
	)
	# The generator's own view vector, grid (x, y, z) to Godot (X, Y, Z) = (gx, z, gy).
	var view: Vector3 = BakeRig.view_direction()
	assert_float(view.x).is_equal_approx(ArtRender.VIEW.x, EPS)
	assert_float(view.y).is_equal_approx(ArtRender.VIEW.z, EPS)
	assert_float(view.z).is_equal_approx(ArtRender.VIEW.y, EPS)
	assert_float(view.length()).is_equal_approx(1.0, EPS)


func test_the_scale_is_the_generators_tile() -> void:
	assert_float(BakeRig.px_per_unit()).is_equal_approx(ArtRender.TILE_PX, EPS)
	assert_float(BakeRig.px_per_unit()).is_equal_approx(128.0 / IsoProjection.SQRT2, EPS)


func test_the_sun_throws_shadows_by_the_shadows_reach_along_plus_gx() -> void:
	var sun: Vector3 = BakeRig.sun_grid()
	assert_float(sun.x / sun.z).is_equal_approx(-ArtShadow.REACH, EPS)
	assert_float(sun.length()).is_equal_approx(1.0, EPS)
	assert_float(sun.y).is_greater(0.0)  # from the north-west: the left faces are lit


func test_the_camera_lands_a_model_point_where_the_generator_projects_it() -> void:
	var axes: Array[Vector3] = BakeRig.screen_axes()
	var scale: float = BakeRig.px_per_unit()
	for point: Vector3 in [
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(2.5, -1, 0.7)
	]:
		var godot: Vector3 = BakeMesh.to_godot(point)
		var screen: Vector2 = Vector2(godot.dot(axes[0]), -godot.dot(axes[1])) * scale
		var wanted: Vector2 = ArtRender.project(point)
		assert_float(screen.x).is_equal_approx(wanted.x, 1e-3)
		assert_float(screen.y).is_equal_approx(wanted.y, 1e-3)


func test_a_mount_seats_the_turret_where_the_sheet_says() -> void:
	var sheet: IsoSheetDef = load("res://assets/art/iso/fossil/veh/heavy_tank_sheet.tres")
	var axes: Array[Vector3] = BakeRig.screen_axes()
	for dir: int in [0, 6, 13]:
		var mount: Vector2 = sheet.mount(dir)
		var seat: Vector3 = BakeRig.seat(mount)
		var screen: Vector2 = Vector2(seat.dot(axes[0]), -seat.dot(axes[1])) * BakeRig.px_per_unit()
		assert_float(screen.x).is_equal_approx(mount.x, 1e-3)
		assert_float(screen.y).is_equal_approx(mount.y, 1e-3)
	# The model's own mount (0, 0, 0.32) is the same point.
	var model_seat: Vector3 = BakeMesh.to_godot(Vector3(0.0, 0.0, 0.32))
	assert_vector(BakeRig.seat(sheet.mount(6))).is_equal_approx(model_seat, Vector3.ONE * 1e-3)
