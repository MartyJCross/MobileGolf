shader_type spatial;
// Colours the hole from smooth surface fields (R green/fringe, G fairway/tee,
// B bunker, A water bed; see HoleGenerator._fields) with procedural grass
// variation and mowing stripes.

uniform sampler2D surface_map : filter_linear, repeat_disable;
uniform vec2 map_origin;
uniform vec2 map_size;
uniform vec2 line_dir = vec2(0.0, -1.0); // direction of play, for stripes

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - map_origin) / map_size;
	vec4 m = texture(surface_map, uv);
	float n = vnoise(wpos.xz * 0.15) * 0.55 + vnoise(wpos.xz * 1.3) * 0.3 + vnoise(wpos.xz * 6.0) * 0.15;

	vec3 rough = mix(vec3(0.17, 0.33, 0.11), vec3(0.25, 0.42, 0.15), n);
	vec3 fair = mix(vec3(0.33, 0.58, 0.21), vec3(0.38, 0.63, 0.25), n);
	float along = dot(wpos.xz, line_dir);
	float across = dot(wpos.xz, vec2(-line_dir.y, line_dir.x));
	float stripe = smoothstep(0.42, 0.5, abs(fract(along / 12.0) - 0.5) * 2.0);
	fair *= mix(0.9, 1.07, stripe);
	vec3 fringe = mix(vec3(0.36, 0.62, 0.24), vec3(0.40, 0.66, 0.27), n);
	vec3 green = mix(vec3(0.40, 0.70, 0.29), vec3(0.44, 0.74, 0.32), n);
	float gstripe = smoothstep(0.42, 0.5, abs(fract(across / 3.5) - 0.5) * 2.0);
	green *= mix(0.94, 1.05, gstripe);
	vec3 sand = mix(vec3(0.85, 0.78, 0.60), vec3(0.93, 0.87, 0.70), vnoise(wpos.xz * 3.0));
	vec3 mud = vec3(0.22, 0.25, 0.17);

	vec3 col = rough;
	float aa = 0.025; // edge softness in field units (~7 cm)
	col = mix(col, fair, smoothstep(0.5 - aa, 0.5 + aa, m.g));
	col = mix(col, fringe, smoothstep(0.312 - aa, 0.312 + aa, m.r));
	col = mix(col, green, smoothstep(0.6 - aa, 0.6 + aa, m.r));
	col = mix(col, sand, smoothstep(0.5 - aa, 0.5 + aa, m.b));
	col = mix(col, mud, smoothstep(0.5 - aa, 0.5 + aa, m.a));

	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = mix(0.95, 0.8, smoothstep(0.58, 0.62, m.r));
	SPECULAR = 0.2;
}
