shader_type spatial;
// An animal's coat (tools/animals/build_animals.py). The model's vertex colours are masks,
// not colours: R the dark points (legs, mane, muzzle), G white markings, B the paler parts
// (belly, rump patch), A occlusion. The colours come from here, so one horse model is bay,
// chestnut, black or grey. A fine lie of hair runs through it and catches the light.

uniform vec3 coat : source_color = vec3(0.3, 0.15, 0.07);
uniform vec3 pale : source_color = vec3(0.5, 0.36, 0.22);
uniform vec3 points : source_color = vec3(0.035, 0.028, 0.022);
uniform vec3 marks : source_color = vec3(0.86, 0.84, 0.8);
// Short glossy coat (a groomed horse) ~0.45; a wild deer's or a sheep's ~0.85.
uniform float roughness = 0.55;
// How fine the hair is (per metre) and how much it shows.
uniform float hair_scale = 90.0;
uniform float hair_strength = 0.22;
// Dappling and uneven colour over the body.
uniform float mottle = 0.07;
// Mud and dust on the legs (0 = clean).
uniform float dirt = 0.25;

varying vec3 p_obj;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	p_obj = VERTEX;
}

void fragment() {
	vec4 m = COLOR;
	vec3 c = mix(coat, pale, m.b);
	c = mix(c, points, m.r);
	c = mix(c, marks, m.g);
	// Hair: fine streaks lying back along the body (stretched along Z and down Y).
	vec3 q = p_obj * vec3(hair_scale, hair_scale * 0.6, hair_scale * 0.18);
	float h = noise(q) * 0.65 + noise(q * 2.3) * 0.35;
	float big = noise(p_obj * 5.0);
	c *= 1.0 + (h - 0.5) * hair_strength + (big - 0.5) * mottle * 2.0;
	// Dust and mud rising up the legs from the ground.
	float mud = dirt * clamp(1.0 - p_obj.y / 0.45, 0.0, 1.0) * (0.6 + 0.4 * noise(p_obj * 14.0));
	c = mix(c, vec3(0.16, 0.12, 0.08), mud);
	ALBEDO = c;
	AO = m.a;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = clamp(roughness + (h - 0.5) * 0.2 + mud * 0.3, 0.0, 1.0);
	SPECULAR = 0.35;
	// The coat's nap: a little tilt of the normal with the hair.
	float hx = noise(q + vec3(3.1, 0.0, 0.0)) - 0.5;
	float hy = noise(q + vec3(0.0, 5.7, 0.0)) - 0.5;
	NORMAL_MAP = normalize(vec3(0.5 + hx * hair_strength * 0.6, 0.5 + hy * hair_strength * 0.6, 1.0));
	NORMAL_MAP_DEPTH = 1.0;
	// Fur softens the silhouette against the light.
	RIM = 0.3;
	RIM_TINT = 0.7;
}
