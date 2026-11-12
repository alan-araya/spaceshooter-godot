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
	# padrão para missões sem `ambience`
	day = {
		ambient = Color(0.56, 0.60, 0.72), sun = Color(1.0, 0.92, 0.76), sun_energy = 0.62, sun_height = 0.55,
		sun_dir = Vector2(0.50, 0.87), shadow_len = 0.65, shadow_alpha = 0.34, lamps = 0.0, glow = 0.55,
		ground_sat = 0.88,
		grade = { bloom = 0.55, saturation = 0.92, contrast = 1.05, shadow_tint = Color(0.95, 0.98, 1.08),
			light_tint = Color(1.04, 1.0, 0.94), vignette = 0.22 },
	},
	# amanhecer: sol baixo e rosado vindo da direita, sombras longas para a esquerda, postes ainda acesos
	dawn = {
		ambient = Color(0.48, 0.49, 0.66), sun = Color(1.0, 0.80, 0.64), sun_energy = 0.74, sun_height = 0.34,
		sun_dir = Vector2(-0.86, 0.50), shadow_len = 1.5, shadow_alpha = 0.36, lamps = 0.35, glow = 0.8,
		ground_sat = 0.78, unit_boost = 1.1,
		grade = { bloom = 0.8, saturation = 0.98, contrast = 1.04, shadow_tint = Color(0.94, 0.96, 1.10),
			light_tint = Color(1.06, 1.0, 0.95), vignette = 0.32 },
	},
	# meio-dia: sol a pino, sombras curtas e duras, cores cheias
	noon = {
		ambient = Color(0.48, 0.50, 0.57), sun = Color(1.0, 0.97, 0.88), sun_energy = 0.54, sun_height = 0.85,
		sun_dir = Vector2(0.20, 0.98), shadow_len = 0.35, shadow_alpha = 0.44, lamps = 0.0, glow = 0.5,
		ground_sat = 0.86,
		grade = { bloom = 0.5, saturation = 0.98, contrast = 1.10, shadow_tint = Color(0.98, 0.99, 1.04),
			light_tint = Color(1.03, 1.01, 0.96), vignette = 0.18 },
	},
	# tarde: luz dourada, sombras médias
	afternoon = {
		ambient = Color(0.50, 0.53, 0.68), sun = Color(1.0, 0.86, 0.62), sun_energy = 0.72, sun_height = 0.45,
		sun_dir = Vector2(0.75, 0.66), shadow_len = 1.0, shadow_alpha = 0.36, lamps = 0.0, glow = 0.6,
		ground_sat = 0.82,
		grade = { bloom = 0.6, saturation = 0.97, contrast = 1.05, shadow_tint = Color(0.95, 0.97, 1.08),
			light_tint = Color(1.05, 1.0, 0.93), vignette = 0.26 },
	},
	# tempestade de areia: luz difusa e empoeirada, sombras fracas, postes acesos na poeira
	storm = {
		ambient = Color(0.60, 0.51, 0.42), sun = Color(1.0, 0.80, 0.54), sun_energy = 0.36, sun_height = 0.60,
		sun_dir = Vector2(0.55, 0.83), shadow_len = 0.5, shadow_alpha = 0.18, lamps = 0.55, glow = 0.8,
		ground_sat = 0.72, unit_boost = 1.08,
		grade = { bloom = 0.75, saturation = 0.84, contrast = 0.98, shadow_tint = Color(1.0, 0.93, 0.84),
			light_tint = Color(1.05, 0.97, 0.86), vignette = 0.40, haze_color = Color(0.70, 0.55, 0.38), haze = 0.14 },
	},
	# entardecer: ambiente frio e arroxeado, sol baixo alaranjado, postes acesos
	dusk = {
		ambient = Color(0.34, 0.35, 0.56), sun = Color(1.0, 0.62, 0.38), sun_energy = 0.70, sun_height = 0.30,
		sun_dir = Vector2(0.90, 0.43), shadow_len = 1.9, shadow_alpha = 0.42, lamps = 1.0, glow = 1.0,
		ground_sat = 0.58, unit_boost = 1.25,
		grade = { bloom = 1.0, saturation = 1.0, contrast = 1.06, shadow_tint = Color(0.92, 0.95, 1.12),
			light_tint = Color(1.05, 1.0, 0.92), vignette = 0.45 },
	},
	# interior da colmeia: escuro, sem sol; a luz vem dos ninhos, do ácido, dos tiros e das lanternas
	hive = {
		ambient = Color(0.30, 0.28, 0.44), sun = Color(0.62, 0.70, 1.0), sun_energy = 0.22, sun_height = 1.0,
		sun_dir = Vector2(0.30, 0.95), shadow_len = 0.45, shadow_alpha = 0.30, lamps = 1.0, glow = 1.35,
		ground_sat = 0.92, unit_boost = 1.3,
		grade = { bloom = 1.1, saturation = 1.0, contrast = 1.08, shadow_tint = Color(0.90, 0.92, 1.15),
			light_tint = Color(1.04, 1.0, 0.96), vignette = 0.52 },
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
