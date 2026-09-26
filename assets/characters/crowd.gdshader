shader_type spatial;
// The background crowd (scripts/world/throng.gd): people walking the pavements beyond the
// real, thinking townsfolk. Every walker is one MultiMesh instance of a look's one-piece far
// body, baked in two strides (tools/bake_crowd.gd): the mesh is the left-foot-forward pose
// and CUSTOM0 the move to the right-foot-forward one. The walking itself - along their
// stretch of pavement and back round - is all done here, so they cost no CPU.
//
// INSTANCE_CUSTOM: x = length of their stretch (m), y = walking speed (m/s),
// z = how far along it they started (m), w = packed: bits 0-5 how busy the streets must be
// for them to be out (0-63), 6-9 coat colour, 10-12 second colour, 13-15 legs, 16-17 skin,
// 18-19 hair, 20-21 hat, 22-23 beard.
render_mode cull_disabled, depth_draw_opaque;

// How busy the streets are now (0 = empty, 1 = the busiest hour): set by Throng.
uniform float busy = 1.0;
// Nearer than this the real townsfolk are about; the crowd fades in beyond it.
uniform float near_fade = 13.0;
uniform float far_fade = 150.0;
// This look's clothes (from CharacterLook.PALETTES).
uniform vec3 primary[16];
uniform vec3 secondary[8];
uniform vec3 legs[8];
uniform vec3 hat_col = vec3(0.05);
uniform vec3 linen = vec3(0.85, 0.83, 0.78);
uniform vec3 accent = vec3(0.35, 0.1, 0.1);
// Which optional part each hat code puts on (far body groups: 4 top hat, 5 bowler,
// 6 cap, 7 bonnet; 0 none).
uniform ivec4 hat_group = ivec4(0, 4, 5, 6);

const vec3 SKIN[4] = vec3[4](vec3(0.86, 0.66, 0.56), vec3(0.8, 0.6, 0.5), vec3(0.72, 0.52, 0.42), vec3(0.5, 0.35, 0.27));
const vec3 HAIR[4] = vec3[4](vec3(0.06, 0.045, 0.035), vec3(0.2, 0.13, 0.07), vec3(0.34, 0.22, 0.12), vec3(0.45, 0.43, 0.41));

varying float channel;
varying flat float fade;
varying flat vec3 c_primary;
varying flat vec3 c_secondary;
varying flat vec3 c_legs;
varying flat vec3 c_skin;
varying flat vec3 c_hair;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void vertex() {
	int packed = int(INSTANCE_CUSTOM.w + 0.5);
	float need = float(packed & 63) / 63.0;
	float len = max(INSTANCE_CUSTOM.x, 1.0);
	float walked = TIME * INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.z;
	float d = mod(walked, len);
	// Where the walker is (the whole person fades together, never piece by piece).
	vec3 at = (MODEL_MATRIX * vec4(0.0, 0.0, -d, 1.0)).xyz;
	float cam = distance(at, CAMERA_POSITION_WORLD);
	float f = smoothstep(near_fade - 1.5, near_fade + 1.0, cam) * (1.0 - smoothstep(far_fade - 25.0, far_fade, cam));
	f *= smoothstep(0.0, 0.6, d) * smoothstep(0.0, 0.6, len - d); // in and out at the ends
	f *= step(need, busy);
	fade = f;
	// Striding: a step every 0.72 m, a little bob.
	float cyc = walked / 1.44 * 6.2831853;
	float m = 0.5 + 0.5 * sin(cyc);
	vec3 v = VERTEX + CUSTOM0.xyz * m;
	v.y += abs(cos(cyc)) * 0.03;
	v.z -= d;
	// Optional parts they don't wear, and anyone not out now, fold away.
	int group = int(UV2.y + 0.5);
	int hat = (packed >> 20) & 3;
	int beard = (packed >> 22) & 3;
	int worn = (hat_group[hat] > 0 ? (1 << hat_group[hat]) : 0) | (beard > 0 ? (1 << beard) : 0);
	if ((group > 0 && ((worn >> group) & 1) == 0) || f <= 0.001) {
		v = vec3(0.0);
	}
	VERTEX = v;
	channel = UV2.x;
	c_primary = primary[(packed >> 6) & 15];
	c_secondary = secondary[(packed >> 10) & 7];
	c_legs = legs[(packed >> 13) & 7];
	c_skin = SKIN[(packed >> 16) & 3];
	c_hair = HAIR[(packed >> 18) & 3];
}

void fragment() {
	if (fade < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	int c = int(channel + 0.5);
	vec3 col = c_primary;
	float rough = 0.85;
	if (c == 0) { col = c_skin; rough = 0.6; }
	else if (c == 1) { col = c_hair; rough = 0.7; }
	else if (c == 3) { col = c_secondary; }
	else if (c == 4) { col = c_legs; }
	else if (c == 5) { col = vec3(0.04, 0.03, 0.03); rough = 0.45; }
	else if (c == 6) { col = linen; }
	else if (c == 7) { col = accent; rough = 0.5; }
	else if (c == 8) { col = hat_col; rough = 0.6; }
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
