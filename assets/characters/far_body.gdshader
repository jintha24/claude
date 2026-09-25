shader_type spatial;
// A person seen from afar: every piece of their outfit in one mesh (one draw call).
// Each vertex's UV2 holds (colour channel, optional-part group). The channels take this
// person's colours from instance uniforms (no material per person), and optional parts
// they don't wear (a beard, a top hat...) are folded away.
render_mode cull_disabled, depth_draw_opaque;

instance uniform vec4 c_skin : source_color = vec4(0.8, 0.62, 0.52, 1.0);
instance uniform vec4 c_hair : source_color = vec4(0.12, 0.08, 0.05, 1.0);
instance uniform vec4 c_primary : source_color = vec4(0.1, 0.1, 0.1, 1.0);
instance uniform vec4 c_secondary : source_color = vec4(0.3, 0.3, 0.3, 1.0);
instance uniform vec4 c_legs : source_color = vec4(0.2, 0.2, 0.2, 1.0);
instance uniform vec4 c_dark : source_color = vec4(0.04, 0.03, 0.03, 1.0);
instance uniform vec4 c_linen : source_color = vec4(0.9, 0.88, 0.84, 1.0);
instance uniform vec4 c_accent : source_color = vec4(0.4, 0.1, 0.1, 1.0);
instance uniform vec4 c_hat : source_color = vec4(0.05, 0.05, 0.05, 1.0);
// Bit n set: optional group n is worn (1-3 beards, 4 top hat, 5 bowler, 6 cap, 7 bonnet).
instance uniform int variants = 0;

varying float channel;

void vertex() {
	channel = UV2.x;
	int group = int(UV2.y + 0.5);
	if (group > 0 && ((variants >> group) & 1) == 0) {
		VERTEX = vec3(0.0); // not worn: collapse to a point (no triangles drawn)
	}
}

void fragment() {
	int c = int(channel + 0.5);
	vec3 col = c_primary.rgb;
	float rough = 0.85;
	if (c == 0) { col = c_skin.rgb; rough = 0.6; }
	else if (c == 1) { col = c_hair.rgb; rough = 0.7; }
	else if (c == 3) { col = c_secondary.rgb; }
	else if (c == 4) { col = c_legs.rgb; }
	else if (c == 5) { col = c_dark.rgb; rough = 0.45; }
	else if (c == 6) { col = c_linen.rgb; }
	else if (c == 7) { col = c_accent.rgb; rough = 0.5; }
	else if (c == 8) { col = c_hat.rgb; rough = 0.6; }
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
