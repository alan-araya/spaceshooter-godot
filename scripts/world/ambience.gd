class_name Ambience
extends RefCounted
## Clima visual de cada missão (hora do dia): luz ambiente, sol, sombras, postes e cor final.
## Só aparência — nada aqui altera a simulação. A missão escolhe com `ambience = "dusk"` (missions.gd).
##
## ambient      cor que multiplica tudo que não está sob luz (CanvasModulate)
## sun*         luz direcional; sun_dir = para onde a luz VIAJA na tela; sun_height 0 (rasante) .. 1 (a pino)
## shadow_len   comprimento da sombra em relação à altura do objeto; shadow_alpha = quão escura
## lamps        energia dos postes e da lanterna dos comandantes (0 = apagados, de dia)
## glow         energia das luzes "vivas" (gerador, ácido, ninhos, pickups)
## ground_sat   saturação do chão (1 = arte original; menos = tons mais naturais sob luz colorida)
## unit_boost   quanto os humanos ficam mais claros que o cenário (legibilidade no escuro; padrão 1)
## grade        pós-processamento do palco (Stage.apply)

const PRESETS := {
	day = {
		ambient = Color(0.56, 0.60, 0.72), sun = Color(1.0, 0.92, 0.76), sun_energy = 0.62, sun_height = 0.55,
		sun_dir = Vector2(0.50, 0.87), shadow_len = 0.65, shadow_alpha = 0.34, lamps = 0.0, glow = 0.55,
		ground_sat = 0.88,
		grade = { bloom = 0.55, saturation = 0.92, contrast = 1.05, shadow_tint = Color(0.95, 0.98, 1.08),
			light_tint = Color(1.04, 1.0, 0.94), vignette = 0.22 },
	},
	dusk = {
		ambient = Color(0.34, 0.35, 0.56), sun = Color(1.0, 0.62, 0.38), sun_energy = 0.70, sun_height = 0.30,
		sun_dir = Vector2(0.90, 0.43), shadow_len = 1.9, shadow_alpha = 0.42, lamps = 1.0, glow = 1.0,
		ground_sat = 0.58, unit_boost = 1.25,
		grade = { bloom = 1.0, saturation = 1.0, contrast = 1.06, shadow_tint = Color(0.92, 0.95, 1.12),
			light_tint = Color(1.05, 1.0, 0.92), vignette = 0.45 },
	},
}


static func of(mission: Dictionary) -> Dictionary:
	var key: String = mission.get("ambience", "day")
	return PRESETS.get(key, PRESETS.day)


## Luz que um chão plano recebe do sol (para o modo sem luzes dinâmicas).
static func flat_light(amb: Dictionary) -> Color:
	var h: float = amb.sun_height
	var ndl := h / sqrt((1.0 - h) * (1.0 - h) + h * h)
	var a: Color = amb.ambient
	var s: Color = amb.sun
	var e: float = amb.sun_energy
	return Color(minf(1.0, a.r + s.r * e * ndl), minf(1.0, a.g + s.g * e * ndl), minf(1.0, a.b + s.b * e * ndl))
