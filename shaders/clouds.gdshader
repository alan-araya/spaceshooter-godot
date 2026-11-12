shader_type canvas_item;
render_mode unshaded, blend_mul;
// Sombras de nuvens passando pelo chão: escurecem (multiplicam) o que está embaixo.

uniform float strength = 0.2;
uniform vec2 wind = vec2(12.0, 4.0);
uniform vec3 tint = vec3(0.52, 0.58, 0.80);
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
	return noise(p) * 0.55 + noise(p * 2.1 + 7.3) * 0.30 + noise(p * 4.3 + 1.7) * 0.15;
}

void fragment() {
	vec2 p = (wp - wind * TIME) / 260.0;
	float c = smoothstep(0.46, 0.70, fbm(p));
	COLOR = vec4(mix(vec3(1.0), tint, c * strength), 1.0);
}
