shader_type canvas_item;
// Composição final do palco: cena (pixel art nítida em qualquer escala) + brilho + cor + vinheta.

uniform sampler2D scene_tex : filter_linear, repeat_disable;
uniform sampler2D bloom_tex : filter_linear, repeat_disable;
uniform vec2 scene_size = vec2(1280.0, 640.0);
uniform float bloom = 0.0;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform vec3 shadow_tint = vec3(1.0);
uniform vec3 light_tint = vec3(1.0);
uniform float vignette = 0.0;
uniform vec3 haze_color = vec3(0.0);
uniform float haze = 0.0;
uniform float heat = 0.0;

void fragment() {
	// "sharp bilinear": cada pixel da cena fica nítido, só a borda entre dois pixels é suavizada
	vec2 suv = UV;
	if (heat > 0.0) {
		// ar quente: a imagem ondula de leve na horizontal
		float wv = sin(UV.y * 120.0 + TIME * 3.1) * 0.6 + sin(UV.y * 53.0 - TIME * 2.2 + UV.x * 9.0) * 0.4;
		suv.x += wv * heat * 0.0012;
	}
	vec2 texel = suv * scene_size;
	vec2 scale = 1.0 / max(fwidth(texel), vec2(0.0001));
	vec2 base = floor(texel);
	vec2 f = fract(texel) - 0.5;
	vec2 range = 0.5 - 0.5 / max(scale, vec2(1.0));
	f = (f - clamp(f, -range, range)) * scale + 0.5;
	vec3 col = texture(scene_tex, (base + f) / scene_size).rgb;

	col += texture(bloom_tex, UV).rgb * bloom;

	col = mix(col, haze_color, haze); // poeira/névoa: puxa tudo para uma cor
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col *= mix(shadow_tint, light_tint, smoothstep(0.05, 0.75, l));

	vec2 q = (UV - 0.5) * vec2(1.0, 0.9);
	float v = smoothstep(0.38, 0.80, length(q));
	col *= 1.0 - vignette * v;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
