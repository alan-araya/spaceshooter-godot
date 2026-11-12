class_name Fx
extends Node2D
## Partículas em lote, em três camadas:
##   matéria (poeira, fumaça, pétalas) — recebe a luz do cenário;
##   gotas (gosma, sangue) — pequenas gotas que saltam, caem e deixam um respingo que some;
##     têm luz própria (legíveis no escuro), mas não entram no buffer de brilho;
##   brilho aditivo (fogo, flashes) — luz própria e halo.
## Os efeitos que emitem luz também acendem um clarão em world.lights.
## Só aparência: sorteios pelo `rnd` daqui, nunca por world.rng (a simulação tem de dar o mesmo
## resultado com ou sem tela).

const MAX := 1500
const MAX_DROPS := 500
const GRAVITY := 560.0
const GOO := [Color(0.84, 0.94, 0.40), Color(0.66, 0.84, 0.24), Color(0.94, 1.0, 0.64)]
const BLOOD := [Color(0.74, 0.08, 0.08), Color(0.55, 0.05, 0.06), Color(0.88, 0.18, 0.13)]
const DIRT := [Color(0.42, 0.32, 0.22), Color(0.30, 0.22, 0.15), Color(0.55, 0.44, 0.30)]
const BRASS := Color(0.95, 0.78, 0.36)
## Forma da partícula: quadrado (padrão), nuvem macia (fumaça, poeira) ou risco (faísca).
const SQUARE := 0
const SOFT := 1
const STREAK := 2

var world: World
var rnd := RandomNumberGenerator.new()
var parts: Array = [] # Dictionary: p, v, life, max, col, size, drag, glow, shape
var drops: Array = [] # Dictionary: p (no chão), v, z (altura), vz, size, col, landed, life, max, casing
var pops: Array = [] # Dictionary: p, r, life, max, col (estalo no ponto do impacto)
var rings: Array = [] # Dictionary: p, r0, r1, life, max, col (anel de explosão)
var cones: Array = [] # Dictionary: p, a, life (clarão na boca da arma)
var lit_layer: Node2D
var goo_layer: Node2D
var glow_layer: Node2D
var soft: Texture2D


func _ready() -> void:
	rnd.randomize()
	soft = Art.soft_dot()
	visibility_layer = Stage.LAYER_BOTH
	lit_layer = Node2D.new()
	lit_layer.name = "Lit"
	lit_layer.material = Art.flat_material()
	add_child(lit_layer)
	lit_layer.draw.connect(_draw_lit)
	goo_layer = Node2D.new()
	goo_layer.name = "Drops"
	goo_layer.material = Art.unshaded()
	add_child(goo_layer)
	goo_layer.draw.connect(_draw_drops)
	glow_layer = Node2D.new()
	glow_layer.name = "Glow"
	glow_layer.visibility_layer = Stage.LAYER_BOTH
	glow_layer.material = Art.unshaded(true)
	add_child(glow_layer)
	glow_layer.draw.connect(_draw_glow)


## Grava o efeito como evento de rede. Retorna true se o mundo não apresenta (fantasma).
func _rec(fx_name: String, args: Array) -> bool:
	world.record("fx", [fx_name, args])
	return not world.present


func _add(p: Vector2, v: Vector2, life: float, col: Color, size: float, drag: float = 3.0, glow: bool = false, shape: int = SQUARE) -> void:
	if parts.size() >= MAX:
		return
	parts.append({ p = p, v = v, life = life, max = life, col = col, size = size, drag = drag, glow = glow, shape = shape })


func _rv(speed_min: float, speed_max: float) -> Vector2:
	var a := rnd.randf_range(0.0, TAU)
	return Vector2(cos(a), sin(a)) * rnd.randf_range(speed_min, speed_max)


## Uma gota: sai de `p` com velocidade `v` no chão e `vz` para cima; ao cair vira um respingo
## que some em `linger` segundos.
func _drop(p: Vector2, v: Vector2, vz: float, size: float, col: Color, linger: float) -> void:
	if drops.size() >= MAX_DROPS:
		return
	drops.append({ p = p, v = v, z = rnd.randf_range(4.0, 9.0), vz = vz, size = size, col = col, landed = false, life = linger, max = linger, casing = false })


## Jorro de `n` gotas. Com `angle`, saem num leque em torno dessa direção; sem, para todos os lados.
func _spray(p: Vector2, n: int, pal: Array, k: float, angle: float = NAN, spread: float = PI) -> void:
	var boost := sqrt(k)
	for i in n:
		var a := rnd.randf_range(0.0, TAU) if is_nan(angle) else angle + rnd.randf_range(-spread, spread)
		var sp := rnd.randf_range(50.0, 165.0) * boost
		var col: Color = pal[rnd.randi() % pal.size()]
		_drop(p, Vector2(cos(a), sin(a)) * sp, rnd.randf_range(40.0, 125.0) * boost, rnd.randf_range(1.5, 2.4) * (0.55 + 0.45 * k), col, 0.3 + 0.25 * k)


## Tiro acertando um inseto ou ninho: estalo no ponto do impacto e poucas gotas de gosma no
## sentido do tiro (uma volta na direção de quem atirou). `k` = tamanho: 1 aranha, ~2 matriarca.
## De propósito discreto: com dezenas de aranhas levando tiro ao mesmo tempo não pode poluir a tela.
func hit(p: Vector2, angle: float, k: float) -> void:
	if _rec("hit", [p, angle, k]):
		return
	pops.append({ p = p, r = 2.6 * k, life = 0.09, max = 0.09, col = GOO[2] })
	var n := clampi(roundi(3.4 * k), 2, 8)
	_spray(p, n - 1, GOO, k, angle, 0.7)
	_spray(p, 1, GOO, k * 0.6, angle + PI, 0.5)


func goo(p: Vector2, n: int) -> void:
	if _rec("goo", [p, n]):
		return
	var k := clampf(0.8 + n / 18.0, 1.0, 2.2)
	pops.append({ p = p, r = 3.0 * k, life = 0.12, max = 0.12, col = GOO[2] })
	_spray(p, mini(n, 30), GOO, k)


func blood(p: Vector2, n: int) -> void:
	if _rec("blood", [p, n]):
		return
	_spray(p, mini(n, 24), BLOOD, clampf(0.8 + n / 18.0, 1.0, 1.8))


func dust(p: Vector2, n: int) -> void:
	if _rec("dust", [p, n]):
		return
	_dust(p, n)


func _dust(p: Vector2, n: int) -> void:
	for i in n:
		_add(p, _rv(10.0, 70.0), rnd.randf_range(0.4, 0.9), Color(0.85, 0.72, 0.5, 0.55), rnd.randf_range(5.0, 9.0), 2.0, false, SOFT)


func spark(p: Vector2, n: int) -> void:
	if _rec("spark", [p, n]):
		return
	for i in n:
		_add(p, _rv(70.0, 230.0), rnd.randf_range(0.12, 0.3), Color(1.0, 0.85, 0.4), 1.5, 4.0, true, STREAK)
	world.lights.flash(p, Lighting.WARM, 44.0, 0.55, 0.09, "sp")


func muzzle(p: Vector2, angle: float) -> void:
	if _rec("muzzle", [p, angle]):
		return
	var d := Vector2(cos(angle), sin(angle))
	_add(p + d * 3.0, d * 40.0, 0.05, Color(1.0, 0.9, 0.5), 5.0, 0.0, true)
	cones.append({ p = p, a = angle, life = 0.05 })
	world.lights.flash(p + d * 10.0, Lighting.WARM, 84.0, 0.95, 0.07, "mz")
	# cápsula ejetada para o lado (nem todo tiro: são muitos)
	if drops.size() < 320 and rnd.randf() < 0.6:
		var side := Vector2(-d.y, d.x)
		drops.append({ p = p - d * 9.0, v = side * rnd.randf_range(30.0, 70.0) - d * rnd.randf_range(0.0, 22.0), z = 10.0,
			vz = rnd.randf_range(60.0, 110.0), size = 1.2, col = BRASS, landed = false, life = 1.3, max = 1.3, casing = true })


func smoke(p: Vector2) -> void:
	if _rec("smoke", [p]):
		return
	_add(p, Vector2(rnd.randf_range(-10, 10), -25.0), rnd.randf_range(0.7, 1.3), Color(0.25, 0.22, 0.2, 0.5), rnd.randf_range(7.0, 12.0), 1.0, false, SOFT)


func burn(p: Vector2) -> void:
	if _rec("burn", [p]):
		return
	_add(p + _rv(0.0, 6.0), Vector2(0, -40), 0.35, Color(1.0, 0.55, 0.15), 4.0, 1.0, true)
	world.lights.flash(p, Color(1.0, 0.55, 0.2), 76.0, 0.75, 0.2, "bn")


func petals(p: Vector2) -> void:
	if _rec("petals", [p]):
		return
	for i in 8:
		var c := Color(0.95, 0.4, 0.8) if i % 2 == 0 else Color(0.6, 0.85, 0.3)
		_add(p, _rv(20.0, 90.0), rnd.randf_range(0.4, 0.8), c, 2.5, 3.0)


func sparkle(p: Vector2, col: Color) -> void:
	if _rec("sparkle", [p, col]):
		return
	for i in 16:
		_add(p, _rv(40.0, 140.0), rnd.randf_range(0.3, 0.7), col, 2.5, 3.0, true)
	world.lights.flash(p, col, 120.0, 1.0, 0.4, "", 1)


func plasma_pop(p: Vector2) -> void:
	if _rec("plasma_pop", [p]):
		return
	for i in 10:
		_add(p, _rv(40.0, 160.0), rnd.randf_range(0.15, 0.35), Color(0.4, 0.95, 1.0), 3.0, 4.0, true)
	world.lights.flash(p, Lighting.CYAN, 140.0, 1.3, 0.24, "pp", 1)


func explosion(p: Vector2, scale_k: float) -> void:
	if _rec("explosion", [p, scale_k]):
		return
	_add(p, Vector2.ZERO, 0.18, Color(1.0, 0.95, 0.7), 26.0 * scale_k, 0.0, true)
	world.lights.flash(p, Color(1.0, 0.62, 0.25), 240.0 * scale_k, 1.9, 0.5, "", 2)
	rings.append({ p = p, r0 = 10.0 * scale_k, r1 = 78.0 * scale_k, life = 0.26, max = 0.26, col = Color(1.0, 0.86, 0.58) })
	world.shock_requested.emit(p, scale_k) # distorção da tela (Stage)
	_spray(p, int(7 * scale_k), DIRT, 1.3 * scale_k) # torrões de terra
	for i in int(7 * scale_k):
		_add(p + _rv(0.0, 12.0), _rv(6.0, 32.0) + Vector2(0, -16), rnd.randf_range(1.0, 2.0), Color(0.15, 0.13, 0.12, 0.5),
			rnd.randf_range(13.0, 22.0) * scale_k, 0.9, false, SOFT)
	for i in int(8 * scale_k):
		_add(p, _rv(120.0, 320.0) * scale_k, rnd.randf_range(0.2, 0.45), Color(1.0, 0.8, 0.35), 1.5, 3.0, true, STREAK)
	for i in int(22 * scale_k):
		var c := Color(1.0, rnd.randf_range(0.4, 0.8), 0.15)
		_add(p, _rv(40.0, 220.0) * scale_k, rnd.randf_range(0.2, 0.5), c, rnd.randf_range(3.0, 6.0) * scale_k, 4.0, true)
	for i in int(10 * scale_k):
		_add(p + _rv(0.0, 10.0), _rv(10.0, 60.0) + Vector2(0, -20), rnd.randf_range(0.6, 1.2), Color(0.2, 0.18, 0.16, 0.55),
			rnd.randf_range(9.0, 15.0) * scale_k, 1.5, false, SOFT)
	_dust(p, int(8 * scale_k))


func tick(dt: float) -> void:
	var keep: Array = []
	for q in parts:
		q.life -= dt
		if q.life <= 0.0:
			continue
		q.p += q.v * dt
		q.v *= maxf(0.0, 1.0 - q.drag * dt)
		if q.shape == STREAK:
			q.v.y += 260.0 * dt # faíscas caem
		keep.append(q)
	parts = keep
	if not rings.is_empty() or not cones.is_empty():
		var keep_r: Array = []
		for o in rings:
			o.life -= dt
			if o.life > 0.0:
				keep_r.append(o)
		rings = keep_r
		var keep_c: Array = []
		for o in cones:
			o.life -= dt
			if o.life > 0.0:
				keep_c.append(o)
		cones = keep_c
	if not drops.is_empty() or not pops.is_empty():
		var keep_d: Array = []
		for d in drops:
			if d.landed:
				d.life -= dt
				if d.life <= 0.0:
					continue
			else:
				d.p += d.v * dt
				d.v *= maxf(0.0, 1.0 - 1.2 * dt)
				d.vz -= GRAVITY * dt
				d.z += d.vz * dt
				if d.z <= 0.0:
					d.z = 0.0
					d.landed = true
			keep_d.append(d)
		drops = keep_d
		var keep_p: Array = []
		for o in pops:
			o.life -= dt
			if o.life > 0.0:
				keep_p.append(o)
		pops = keep_p
	lit_layer.queue_redraw()
	goo_layer.queue_redraw()
	glow_layer.queue_redraw()


func _draw_lit() -> void:
	for q in parts:
		if q.glow:
			continue
		var k: float = q.life / q.max
		var c: Color = q.col
		if q.shape == SOFT:
			# nuvem macia que cresce e some; recebe a luz do cenário
			c.a *= minf(1.0, k * 1.6)
			var rs: float = q.size * (0.6 + 0.9 * (1.0 - k))
			lit_layer.draw_texture_rect(soft, Rect2(q.p - Vector2(rs, rs), Vector2(rs, rs) * 2.0), false, c)
			continue
		c.a *= minf(1.0, k * 2.0)
		var s: float = q.size * (0.5 + 0.5 * k)
		lit_layer.draw_rect(Rect2(q.p - Vector2(s, s) * 0.5, Vector2(s, s)), c)


func _draw_drops() -> void:
	for d in drops:
		var col: Color = d.col
		var p: Vector2 = d.p
		var s: float = d.size
		if d.casing:
			# cápsula de latão: gira no ar, fica um instante no chão
			var cp := p - Vector2(0.0, d.z)
			col.a = minf(1.0, d.life / 0.35) if d.landed else 1.0
			goo_layer.draw_rect(Rect2(cp.x - 1.0, cp.y - 0.5, 2.0, 1.0) if (d.landed or int(d.z) % 2 == 0) else Rect2(cp.x - 0.5, cp.y - 1.0, 1.0, 2.0), col)
			continue
		if d.landed:
			# respingo achatado no chão, sumindo
			var k: float = d.life / d.max
			col.a = 0.8 * k
			goo_layer.draw_circle(p, s * 0.85, col)
		else:
			# gota no ar: risco curto no sentido do movimento na tela, com a ponta mais clara
			var q := p - Vector2(0.0, d.z)
			var v: Vector2 = d.v
			var tail := Vector2(v.x, v.y - d.vz) * 0.02
			goo_layer.draw_line(q - tail, q, col, s)
			goo_layer.draw_rect(Rect2(q.x - s * 0.5, q.y - s * 0.5, s, s), col.lightened(0.35))
	for o in pops:
		var k2: float = o.life / o.max
		var c2: Color = o.col
		c2.a = 0.85 * k2
		goo_layer.draw_circle(o.p, o.r * (1.0 + 1.3 * (1.0 - k2)), c2)


func _draw_glow() -> void:
	for q in parts:
		if not q.glow:
			continue
		var k: float = q.life / q.max
		var c: Color = q.col
		c.a *= k
		if q.shape == STREAK:
			var v: Vector2 = q.v
			glow_layer.draw_line(q.p - v * 0.035, q.p, c, q.size)
			continue
		glow_layer.draw_circle(q.p, q.size * (0.4 + 0.6 * k), c)
	for o in rings:
		var kr: float = o.life / o.max
		var rc: Color = o.col
		rc.a = kr
		glow_layer.draw_arc(o.p, lerpf(o.r1, o.r0, kr), 0.0, TAU, 30, rc, 1.0 + 3.0 * kr)
	for o in cones:
		# clarão em cone na boca da arma, com duas pontas laterais
		var a: float = o.a
		var d := Vector2(cos(a), sin(a))
		var nrm := Vector2(-d.y, d.x)
		var mp: Vector2 = o.p
		glow_layer.draw_colored_polygon(PackedVector2Array([mp - nrm * 2.5, mp + d * 14.0, mp + nrm * 2.5]), Color(1.0, 0.88, 0.5, 0.9))
		glow_layer.draw_colored_polygon(PackedVector2Array([mp + d * 2.0 - nrm * 6.0, mp + d * 5.0, mp + d * 2.0 + nrm * 6.0]), Color(1.0, 0.8, 0.4, 0.7))
