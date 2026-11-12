shader_type canvas_item;
render_mode unshaded;
// Sombra projetada: a silhueta do sprite em preto.

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(0.0, 0.0, 0.0, step(0.5, a) * COLOR.a);
}
