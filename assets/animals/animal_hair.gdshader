shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// An animal's long hair (mane, tail, fox's brush, stag's shaggy neck): cards of strands
// (hair.png) coloured like the coat (animal.gdshader) - vertex colour masks: R points,
// G marks, B pale, A the coat's own colour; none = the hair colour.

uniform sampler2D strands : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 hair : source_color = vec3(0.03, 0.025, 0.02);
uniform vec3 coat : source_color = vec3(0.3, 0.15, 0.07);
uniform vec3 pale : source_color = vec3(0.5, 0.36, 0.22);
uniform vec3 points : source_color = vec3(0.035, 0.028, 0.022);
uniform vec3 marks : source_color = vec3(0.86, 0.84, 0.8);

void fragment() {
	vec4 t = texture(strands, UV);
	vec4 m = COLOR;
	vec3 c = mix(hair, coat, m.a);
	c = mix(c, pale, m.b);
	c = mix(c, points, m.r);
	c = mix(c, marks, m.g);
	ALBEDO = c * t.rgb;
	ALPHA = t.a;
	ALPHA_HASH_SCALE = 1.0;
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
	// Light through the strands' edges.
	BACKLIGHT = c * 0.4;
}
