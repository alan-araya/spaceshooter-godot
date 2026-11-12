shader_type canvas_item;
render_mode unshaded, blend_add;
// Superfície do ácido: brilho próprio com veios claros que se movem (somado sobre o chão iluminado).

uniform float strength = 1.0;
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

void fragment() {
	vec2 p = floor(wp / 2.0) * 2.0; // blocos de 2 px, para combinar com a pixel art
	float t = TIME;
	float n = noise(p * 0.05 + vec2(t * 0.11, t * 0.07)) * 0.6 + noise(p * 0.11 - vec2(t * 0.09, t * 0.13)) * 0.4;
	float veins = smoothstep(0.52, 0.55, n) - smoothstep(0.56, 0.60, n);
	float pulse = 0.5 + 0.5 * sin(t * 1.3 + p.x * 0.02);
	vec3 col = vec3(0.30, 0.85, 0.16) * (0.16 + 0.10 * pulse) + vec3(0.75, 1.0, 0.45) * veins * 0.5;
	COLOR = vec4(col * strength, 1.0);
}
