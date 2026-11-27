shader_type spatial;
// P655: procedural weathering for the detailed tank. Everything is a function of the model-space
// position, the normal and the bevel flag in COLOR.r, so the dirt turns with the tank.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base : source_color = vec3(0.2);
uniform float metal = 0.4;
uniform float rough = 0.5;
uniform int kind = 0; // 0 body, 1 team paint, 2 running gear, 3 glass, 4 lamp, 5 canvas
uniform float z_off = 0.0;
uniform bool vcol = true;
uniform float wear_amount = 1.0;
uniform float dirt_amount = 1.5;
uniform sampler2D nz : repeat_enable, filter_linear_mipmap;
uniform vec3 dust : source_color = vec3(0.40, 0.37, 0.31);
uniform vec3 mud : source_color = vec3(0.16, 0.11, 0.07);
uniform vec3 bare : source_color = vec3(0.62, 0.63, 0.65);
uniform vec3 soot_a = vec3(-9.0);
uniform vec3 soot_b = vec3(-9.0);

varying vec3 mp;
varying vec3 mn;
varying float edge;

void vertex() {
	mp = VERTEX;
	mn = NORMAL;
	edge = vcol ? COLOR.r : 0.0;
}

float hash3(vec3 c) {
	return fract(sin(dot(c, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float tri(vec3 p, vec3 n, float s) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z + 1e-5);
	return texture(nz, p.zy * s).r * w.x + texture(nz, p.xz * s).r * w.y + texture(nz, p.xy * s).r * w.z;
}

void fragment() {
	float n1 = tri(mp, mn, 2.6);
	float n2 = tri(mp, mn, 17.0);
	float n3 = tri(mp, mn, 7.0);
	float z = mp.y + z_off;
	float side = 1.0 - abs(mn.y);
	// plate tint: every ~0.11 tile cell of a face is a slightly different batch of paint or steel.
	vec3 cell = floor(mp * 9.0 + 0.5 * mn);
	float plate = hash3(cell + floor(abs(mn) * 3.0)) - 0.5;
	vec3 col = base * (0.86 + 0.28 * n2) * (0.88 + 0.24 * n1) * (1.0 + plate * (kind == 1 ? 0.10 : 0.34));
	float met = metal;
	float rgh = rough;
	if (kind == 3 || kind == 4) {
		ALBEDO = col;
		METALLIC = met;
		ROUGHNESS = rgh;
		if (kind == 4) {
			EMISSION = base * 1.6;
		}
	} else {
		// streaks: vertical runs of rain-washed dust and rust below edges and seams.
		float st = texture(nz, vec2((mp.x + mp.z) * 26.0 + n1 * 2.0, z * 1.1)).r;
		float streak = smoothstep(0.48, 0.74, st) * side * smoothstep(0.08, 0.34, z) * 0.8;
		float up = clamp(mn.y, 0.0, 1.0);
		float low = smoothstep(0.3, 0.0, z);
		float dust_a = (up * 0.34 + low * 0.50) * smoothstep(0.30, 0.70, n1 + 0.18 * n3 + 0.1);
		float mud_a = smoothstep(0.16, 0.02, z) * smoothstep(0.25, 0.62, n3 * 0.7 + n1 * 0.5 + 0.1);
		if (kind == 2) {
			mud_a = clamp(mud_a * 1.5 + smoothstep(0.2, 0.0, z) * 0.3, 0.0, 1.0);
			dust_a *= 1.2;
		}
		float soot = max(smoothstep(0.16, 0.02, distance(mp, soot_a)), smoothstep(0.16, 0.02, distance(mp, soot_b)));
		dust_a *= dirt_amount;
		mud_a *= dirt_amount;
		if (kind == 1) {
			// paint: stays in hue, so the team key survives. Dirt only darkens and thins.
			col *= (1.0 - 0.22 * streak - 0.28 * mud_a - 0.4 * soot);
			col = mix(col, col * vec3(1.0, 0.82, 0.62) * 0.9 + dust * 0.06, dust_a * 0.35);
			float chip = smoothstep(0.3, 0.9, edge) * smoothstep(0.34, 0.62, n2 * 0.7 + n3 * 0.45) * wear_amount;
			col *= (1.0 - 0.62 * chip);
			met = mix(met, 0.7, chip);
			rgh = mix(rgh, 0.38, chip) + 0.25 * dust_a;
		} else {
			col = mix(col, dust, dust_a * 0.62);
			col = mix(col, col * vec3(0.55, 0.45, 0.38), streak);
			col = mix(col, mud, mud_a * 0.85);
			col *= (1.0 - 0.7 * soot);
			float wear = smoothstep(0.2, 0.9, edge) * smoothstep(0.22, 0.5, n2 * 0.7 + n3 * 0.5) * wear_amount * (1.0 - 0.7 * mud_a);
			col = mix(col, bare, wear);
			met = mix(met, 0.95, wear) * (1.0 - 0.8 * (dust_a + mud_a));
			rgh = mix(rgh, 0.36, wear) + 0.3 * (dust_a + mud_a);
		}
		ALBEDO = col;
		METALLIC = clamp(met, 0.0, 1.0);
		ROUGHNESS = clamp(rgh, 0.05, 1.0);
	}
}
