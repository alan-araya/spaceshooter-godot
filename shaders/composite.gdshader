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
uniform vec4 shock[4]; // ondas de choque: xy = centro (UV), z = raio, w = força
uniform float hurt = 0.0; // comandante ferido: borda vermelha e cores separadas

void fragment() {
	// "sharp bilinear": cada pixel da cena fica nítido, só a borda entre dois pixels é suavizada
	vec2 suv = UV;
	if (heat > 0.0) {
		// ar quente: a imagem ondula de leve na horizontal
		float wv = sin(UV.y * 120.0 + TIME * 3.1) * 0.6 + sin(UV.y * 53.0 - TIME * 2.2 + UV.x * 9.0) * 0.4;
		suv.x += wv * heat * 0.0012;
	}
	vec2 aspect = vec2(1.0, scene_size.y / scene_size.x);
	for (int i = 0; i < 4; i++) {
		if (shock[i].w > 0.0) {
			vec2 dd = (suv - shock[i].xy) * aspect;
			float dist = length(dd);
			float ring = exp(-pow((dist - shock[i].z) / 0.014, 2.0));
			suv += dd / max(dist, 0.0001) / aspect * ring * shock[i].w * 0.006;
		}
	}
	vec2 texel = suv * scene_size;
	vec2 scale = 1.0 / max(fwidth(texel), vec2(0.0001));
	vec2 base = floor(texel);
	vec2 f = fract(texel) - 0.5;
	vec2 range = 0.5 - 0.5 / max(scale, vec2(1.0));
	f = (f - clamp(f, -range, range)) * scale + 0.5;
	vec2 uvs = (base + f) / scene_size;
	vec3 col = texture(scene_tex, uvs).rgb;
	if (hurt > 0.0) {
		float off = hurt * 0.0025;
		col.r = texture(scene_tex, uvs + vec2(off, 0.0)).r;
		col.b = texture(scene_tex, uvs - vec2(off, 0.0)).b;
	}

	col += texture(bloom_tex, UV).rgb * bloom;

	col = mix(col, haze_color, haze); // poeira/névoa: puxa tudo para uma cor
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col *= mix(shadow_tint, light_tint, smoothstep(0.05, 0.75, l));

	vec2 q = (UV - 0.5) * vec2(1.0, 0.9);
	float v = smoothstep(0.38, 0.80, length(q));
	col *= 1.0 - vignette * v;
	col = mix(col, vec3(0.75, 0.04, 0.04), hurt * smoothstep(0.22, 0.72, length(q)) * 0.55);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
