shader_type canvas_item;
render_mode unshaded;
// Poeira/névoa em duas camadas que andam com o vento em velocidades diferentes.
// streaks > 0 acrescenta rajadas finas e rápidas (tempestade de areia).

uniform float density = 0.15;
uniform vec3 fog_color = vec3(0.8, 0.7, 0.6);
uniform vec2 wind = vec2(20.0, 6.0);
uniform float streaks = 0.0;
varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.3 + 5.1) * 0.4;
}

void fragment() {
	float t = TIME;
	float a = fbm((wp - wind * t) / 190.0) * 0.6 + fbm((wp - wind * t * 1.7) / 90.0 + 31.0) * 0.4;
	a = smoothstep(0.34, 0.78, a) * density;
	if (streaks > 0.0) {
		vec2 d = normalize(wind);
		vec2 q = vec2(dot(wp, d), dot(wp, vec2(-d.y, d.x)));
		float s = noise(vec2((q.x - t * length(wind) * 5.0) / 130.0, q.y / 6.0));
		a += smoothstep(0.64, 0.92, s) * streaks;
	}
	COLOR = vec4(fog_color, clamp(a, 0.0, 0.85));
}
