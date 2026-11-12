shader_type canvas_item;
// Desfoque gaussiano separável (9 amostras em 5 leituras) para o buffer de brilho.

uniform sampler2D src : filter_linear, repeat_disable;
uniform vec2 step_uv = vec2(0.003, 0.0);
uniform float gain = 1.0;

void fragment() {
	vec3 c = texture(src, UV).rgb * 0.227027;
	c += (texture(src, UV + step_uv * 1.3846).rgb + texture(src, UV - step_uv * 1.3846).rgb) * 0.316216;
	c += (texture(src, UV + step_uv * 3.2308).rgb + texture(src, UV - step_uv * 3.2308).rgb) * 0.070270;
	COLOR = vec4(c * gain, 1.0);
}
