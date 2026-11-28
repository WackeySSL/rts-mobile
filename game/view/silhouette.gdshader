// The silhouette of a unit behind a raised rock wall (ADR 0053 section 7, amendment A7, plan P656d3).
// One material for every silhouette sprite, so all of them are one draw call. The sprite stands at
// the unit's ground point (its origin, MODEL_MATRIX) and shows the Hull or Turret region of the
// atlas. A texel is drawn only where a wall in front of the unit covers it: one of the three cells
// that the ground segment from the texel's flat ground point (u, v) to (u + 1, v + 1) crosses is
// raised and its centre y is larger than the unit's ground y. `WallCover` is the GDScript twin of
// this test; change both together. Team colour texels keep their hue, every other texel is one flat
// dark body colour. Two looks, chosen by `look`: 0 (A) draws all of it at one alpha; 1 (B) draws it
// at the lower veil alpha with a screen-space diagonal hatch (every hatch_period-th diagonal of
// FRAGCOORD) at the hatch alpha, so a covered unit reads as behind the wall, not parked on it.
// `WallCover.silhouette_colour` is the twin of the colouring.
shader_type canvas_item;

uniform sampler2D wall_mask : filter_nearest, repeat_disable; // One byte per cell, 255 for a wall.
uniform ivec2 grid_size = ivec2(1, 1); // Columns and rows of the mask.
uniform float half_w = 32.0; // IsoProjection.HALF_W and HALF_H, set by WorldSort.
uniform float half_h = 16.0;
uniform float team_sat_min : hint_range(0.0, 1.0) = 0.35;
uniform vec4 body_colour : source_color = vec4(0.09, 0.10, 0.12, 1.0);
uniform int look : hint_range(0, 1) = 1; // 0 = A, 1 = B.
uniform float silhouette_alpha : hint_range(0.0, 1.0) = 0.85; // Look A.
uniform float veil_alpha : hint_range(0.0, 1.0) = 0.55; // Look B.
uniform float hatch_alpha : hint_range(0.0, 1.0) = 0.25; // Look B, on the hatch lines.
uniform float hatch_period : hint_range(2.0, 8.0) = 4.0;

varying flat vec2 ground; // The unit's ground point, world px.
varying vec2 world; // This texel's world px.

bool covers(ivec2 cell) {
	if (cell.x < 0 || cell.y < 0 || cell.x >= grid_size.x || cell.y >= grid_size.y) {
		return false;
	}
	return texelFetch(wall_mask, cell, 0).r > 0.5 && float(cell.x + cell.y + 1) * half_h > ground.y;
}

void vertex() {
	ground = MODEL_MATRIX[3].xy;
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float sum = world.y / half_h;
	float diff = world.x / half_w;
	float u = (sum + diff) * 0.5;
	float v = (sum - diff) * 0.5;
	ivec2 a = ivec2(int(floor(u)), int(floor(v)));
	bool right = (u - floor(u)) > (v - floor(v));
	ivec2 b = right ? a + ivec2(1, 0) : a + ivec2(0, 1);
	if (!(covers(a) || covers(b) || covers(a + ivec2(1, 1)))) {
		discard;
	}
	vec4 tex = COLOR;
	float top = max(tex.r, max(tex.g, tex.b));
	float sat = top > 0.0 ? (top - min(tex.r, min(tex.g, tex.b))) / top : 0.0;
	float alpha = silhouette_alpha;
	if (look == 1) {
		alpha = mod(FRAGCOORD.x + FRAGCOORD.y, hatch_period) < 1.0 ? hatch_alpha : veil_alpha;
	}
	COLOR = vec4(sat >= team_sat_min ? tex.rgb : body_colour.rgb, tex.a * alpha);
}
