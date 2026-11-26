class_name ProtoRig
extends Node
## P653 prototype: one SubViewport with the ArtGen projection as an orthographic camera (ADR 0023:
## ground (gx, gy, z) is drawn at ((gx - gy) * 64, (gx + gy) * 32 - z * 78.38) art px at 2x, so the
## camera looks down at 30 degrees from the (+gx, +gy) corner, yawed 45 degrees), one sun from the
## NW (STYLE.md: top 100 %, left 82 %, right 62 %) and a sky for ambient and reflections.

const ELEV: float = deg_to_rad(30.0)
const PPU_ART: float = 90.50966799187809
## Direction to the sun in the grid frame (gx, gy, z); shadows fall towards +gx (ArtShadow.REACH 0.8).
const SUN_GRID: Vector3 = Vector3(-0.8, 0.25, 1.0)

var vp: SubViewport
var cam: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var env: Environment
var holder: Node3D
var unlit: bool = false


func setup(ssao: bool = true, sun_energy: float = 0.95) -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky: Sky = Sky.new()
	var psm: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.46, 0.55, 0.68)
	psm.sky_horizon_color = Color(0.72, 0.68, 0.62)
	psm.ground_horizon_color = Color(0.45, 0.40, 0.34)
	psm.ground_bottom_color = Color(0.22, 0.19, 0.16)
	psm.sun_angle_max = 0.0
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if ssao:
		env.ssao_enabled = true
		env.ssao_radius = 0.28
		env.ssao_intensity = 2.6
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssao_light_affect = 0.4
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = sun_energy
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_max_distance = 40.0
	sun.light_angular_distance = 1.2
	vp.add_child(sun)
	sun.look_at_from_position(ProtoBuild.g(SUN_GRID.normalized()) * 10.0, Vector3.ZERO, Vector3.UP)
	fill = DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.78, 0.86, 1.0)
	vp.add_child(fill)
	fill.look_at_from_position(ProtoBuild.g(Vector3(0.1, 1.0, 0.45).normalized()) * 10.0, Vector3.ZERO, Vector3.UP)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 200.0
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)


func set_node(n: Node3D) -> void:
	for c: Node in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	holder.add_child(n)


## Renders a canvas of w x h art px anchored at (ax, ay) (the model origin lands there), at
## `scale` texels per art px.
func render(w: int, h: int, ax: float, ay: float, scale: float) -> Image:
	vp.size = Vector2i(roundi(w * scale), roundi(h * scale))
	cam.size = float(h) / PPU_ART
	var right: Vector3 = Vector3(1, 0, -1).normalized()
	var up: Vector3 = Vector3(-sin(ELEV) / sqrt(2.0), cos(ELEV), -sin(ELEV) / sqrt(2.0))
	var target: Vector3 = right * ((w * 0.5 - ax) / PPU_ART) + up * (-(h * 0.5 - ay) / PPU_ART)
	var dir: Vector3 = Vector3(cos(ELEV) / sqrt(2.0), sin(ELEV), cos(ELEV) / sqrt(2.0))
	cam.look_at_from_position(target + dir * 30.0, target, Vector3.UP)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()
