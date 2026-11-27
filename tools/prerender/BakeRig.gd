class_name BakeRig
extends Node
## The bake's camera and light (ADR 0053 section 5): one SubViewport, an orthographic camera at
## the isometric angles, a sun along the shadow's direction, a fill light and a sky, with SSAO.
## The projection is never retyped here. The elevation comes from `IsoProjection`'s 2:1 diamond
## (`ArtRender.VIEW` is the same view, and a test holds the two equal), the scale from the
## generator's tile, and the sun from `ArtShadow.REACH`. Models are in the grid frame; the rig
## works in Godot's (X, Y, Z) = (gx, z, gy).

## How far the sun leans towards +gy, tiles per tile of height: a look, the left faces a little
## brighter than the right (STYLE.md). Its reach along gx is `ArtShadow.REACH`.
const SUN_LEAN: float = 0.25
const FILL_DIRECTION: Vector3 = Vector3(0.1, 1.0, 0.45)  ## Grid frame, towards the fill.
const CAMERA_DISTANCE: float = 30.0

var viewport: SubViewport
var camera: Camera3D
var holder: Node3D


## sin of the elevation: a tile's diamond is `HALF_W` wide and `HALF_H` high.
static func elevation_sin() -> float:
	return float(IsoProjection.HALF_H) / float(IsoProjection.HALF_W)


## The direction from the scene to the camera, Godot frame, unit length.
static func view_direction() -> Vector3:
	var s: float = elevation_sin()
	var flat: float = sqrt(1.0 - s * s) / IsoProjection.SQRT2
	return Vector3(flat, s, flat)


## Art px (at the 2x of the sheets) per tile at the camera: a tile's diagonal is 4 `HALF_W`.
static func px_per_unit() -> float:
	return 4.0 * IsoProjection.HALF_W / IsoProjection.SQRT2


## The direction to the sun in the grid frame (gx, gy, z): shadows fall `ArtShadow.REACH` tiles
## towards +gx per tile of height.
static func sun_grid() -> Vector3:
	return Vector3(-ArtShadow.REACH, SUN_LEAN, 1.0).normalized()


## Screen right and up in the Godot frame, from the view direction.
static func screen_axes() -> Array[Vector3]:
	var back: Vector3 = view_direction()
	var right: Vector3 = Vector3(1.0, 0.0, -1.0).normalized()
	return [right, back.cross(right)]


## Where a screen offset of `px` (art px, y down) lands in the Godot frame, on the camera's
## image plane: the shift of the camera's target.
static func screen_offset(px: Vector2) -> Vector3:
	var axes: Array[Vector3] = screen_axes()
	return (axes[0] * px.x - axes[1] * px.y) / px_per_unit()


## The Godot-frame point of a mount `px` from the hull's ground point (`IsoSheetDef.mount`, art
## px, y down): a lift, and sideways along gx - gy, the one ground axis that moves a point only
## across the screen. Exact for a mount straight above the ground point, which the sheets have.
static func seat(px: Vector2) -> Vector3:
	var across: float = px.x / (4.0 * IsoProjection.HALF_W)
	return Vector3(across, -px.y / ArtRender.Z_PX, -across)


func setup(ssao: bool = true, sun_energy: float = 0.95) -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = _environment(ssao)
	viewport.add_child(world)
	var sun: DirectionalLight3D = _light(
		BakeMesh.to_godot(sun_grid()), sun_energy, Color(1.0, 0.96, 0.88)
	)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_max_distance = 40.0
	sun.light_angular_distance = 1.2
	_light(BakeMesh.to_godot(FILL_DIRECTION.normalized()), 0.35, Color(0.78, 0.86, 1.0))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = 200.0
	viewport.add_child(camera)
	holder = Node3D.new()
	viewport.add_child(holder)


## Shows `node` (the caller keeps it) in place of the last one.
func set_node(node: Node3D) -> void:
	clear()
	holder.add_child(node)


## Takes the shown node out (the caller keeps it).
func clear() -> void:
	for old: Node in holder.get_children():
		holder.remove_child(old)


## A canvas of `w` x `h` art px whose model origin lies at (`ax`, `ay`) in it, at `scale` texels
## per art px.
func render(w: int, h: int, ax: float, ay: float, scale: float) -> Image:
	viewport.size = Vector2i(roundi(w * scale), roundi(h * scale))
	camera.size = float(h) / px_per_unit()
	var target: Vector3 = screen_offset(Vector2(float(w) * 0.5 - ax, float(h) * 0.5 - ay))
	camera.look_at_from_position(target + view_direction() * CAMERA_DISTANCE, target, Vector3.UP)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _light(towards: Vector3, energy: float, colour: Color) -> DirectionalLight3D:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.light_energy = energy
	light.light_color = colour
	viewport.add_child(light)
	light.look_at_from_position(towards * 10.0, Vector3.ZERO, Vector3.UP)
	return light


func _environment(ssao: bool) -> Environment:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.46, 0.55, 0.68)
	sky_material.sky_horizon_color = Color(0.72, 0.68, 0.62)
	sky_material.ground_horizon_color = Color(0.45, 0.40, 0.34)
	sky_material.ground_bottom_color = Color(0.22, 0.19, 0.16)
	sky_material.sun_angle_max = 0.0
	env.sky = Sky.new()
	env.sky.sky_material = sky_material
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = ssao
	env.ssao_radius = 0.28
	env.ssao_intensity = 2.6
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.4
	return env
