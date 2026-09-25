shader_type sky;
// The sky over London: a blue dome that pales to a smoky haze at the horizon, a sun with
// its glow, clouds that drift with the wind and follow the weather (fair-weather cumulus
// on a clear day, a grey lid in rain, a dark one in a storm), sunset colours, and stars.
// DayNightCycle and WeatherEffects set the uniforms; LIGHT0 is the sun.

uniform vec3 zenith_color : source_color = vec3(0.13, 0.3, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.55, 0.65, 0.78);
uniform vec3 ground_color : source_color = vec3(0.1, 0.095, 0.09);
uniform float coverage : hint_range(0.0, 1.0) = 0.35;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform float haze : hint_range(0.0, 1.0) = 0.0;
uniform float day : hint_range(0.0, 1.0) = 1.0;
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float sky_energy = 1.0;
uniform vec2 wind_offset = vec2(0.0);
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D cloud_detail : repeat_enable, filter_linear_mipmap;

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float cloud_density(vec2 uv) {
	float n = texture(cloud_noise, uv).r * 0.68 + texture(cloud_detail, uv * 3.3 + wind_offset * 0.6).r * 0.32;
	float thr = mix(0.7, 0.22, coverage);
	return smoothstep(thr, thr + 0.2, n);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sun = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : vec3(0.0, -1.0, 0.0);
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0);
	float up = max(d.y, 0.0);
	float t = pow(1.0 - up, 4.0);
	// Day sky: deep blue overhead, hazy near the ground.
	vec3 col = mix(zenith_color, horizon_color, t);
	// Sunrise and sunset: warm towards the sun, low in the sky.
	float low_sun = smoothstep(0.4, 0.0, sun.y) * smoothstep(-0.15, 0.0, sun.y);
	vec2 flat_d = normalize(d.xz + vec2(1e-5));
	vec2 flat_s = normalize(sun.xz + vec2(1e-5));
	float toward = max(dot(flat_d, flat_s), 0.0);
	col = mix(col, vec3(1.0, 0.5, 0.24), low_sun * t * (0.25 + 0.75 * toward * toward));
	col = mix(col, vec3(0.4, 0.28, 0.42), low_sun * (1.0 - t) * 0.25);
	// Night: a deep blue-black.
	vec3 night = mix(vec3(0.008, 0.013, 0.035), vec3(0.03, 0.038, 0.065), t);
	col = mix(night, col, day);
	// The sun's glow.
	float cs = max(dot(d, sun), 0.0);
	col += sun_col * (pow(cs, 800.0) * 1.2 + pow(cs, 60.0) * 0.25 + pow(cs, 6.0) * 0.08) * day;
	// Overcast: the blue gives way to grey.
	float over = clamp((coverage - 0.62) * 2.6, 0.0, 1.0);
	vec3 grey = mix(vec3(0.56, 0.58, 0.62), vec3(0.26, 0.27, 0.3), darkness) * max(day, 0.02);
	col = mix(col, grey, over * 0.85);
	// Clouds on a curved dome.
	float a = 0.0;
	vec3 ccol = vec3(0.0);
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.15) * 0.3 + wind_offset;
		float dens = cloud_density(uv);
		// Light from the sun side: thinner there means brighter tops, grey bellies.
		float toward_sun = cloud_density(uv + flat_s * 0.025);
		float shade = clamp(1.0 - (toward_sun - dens) * 1.6 - dens * 0.45, 0.25, 1.0);
		vec3 base = mix(vec3(0.46, 0.49, 0.56), vec3(1.0, 0.99, 0.97), shade);
		base = mix(base, base * 0.42, darkness);
		vec3 lit = mix(vec3(1.0), sun_col, 0.55 + low_sun * 0.45);
		ccol = base * lit * mix(0.035, 1.0, day);
		// Moonlit clouds at night: faint blue-grey.
		ccol = mix(ccol, vec3(0.05, 0.06, 0.09) * (0.6 + shade * 0.4), (1.0 - day) * 0.8);
		// Silver linings round the sun.
		ccol += sun_col * pow(cs, 10.0) * 0.5 * (1.0 - dens) * day;
		a = dens * smoothstep(0.0, 0.1, d.y) * mix(0.82, 1.0, coverage);
	}
	col = mix(col, ccol, a);
	// The sun's disc, behind the clouds.
	float disk = smoothstep(0.99975, 0.99988, dot(d, sun));
	col += disk * sun_col * 24.0 * (1.0 - a) * day;
	// Stars on clear nights.
	if (stars > 0.0 && d.y > 0.0) {
		vec3 p = d * 350.0;
		vec3 cell = floor(p);
		float r = hash3(cell);
		if (r > 0.9965) {
			float dist = length(fract(p) - 0.5);
			float b = smoothstep(0.35, 0.0, dist) * (r - 0.9965) / 0.0035;
			col += vec3(0.9, 0.92, 1.0) * b * 2.5 * stars * (1.0 - a) * smoothstep(0.0, 0.2, d.y);
		}
	}
	// Fog and haze swallow the view.
	col = mix(col, horizon_color * mix(0.06, 0.95, day), haze * 0.75 * mix(1.0, 0.4, up));
	// Below the horizon.
	col = mix(col, ground_color * max(day, 0.04), smoothstep(0.0, -0.08, d.y));
	COLOR = col * sky_energy;
}
