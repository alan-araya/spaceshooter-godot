shader_type canvas_item;
// Para desenhos sem mapa de relevo (formas, decalques, partículas): normal "deitada no chão",
// para receberem a mesma quantidade de luz que o terreno.

void fragment() {
	NORMAL = vec3(0.0, 0.0, 1.0);
}
