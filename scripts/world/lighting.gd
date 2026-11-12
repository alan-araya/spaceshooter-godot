class_name Lighting
extends Node2D
## LUZ da missão: ambiente (CanvasModulate), sol (DirectionalLight2D) e luzes pontuais —
## fixas (gerador, postes, ácido, ninhos, relés), seguidoras (plasma, chamas, pickups, poças)
## e clarões (tiros, explosões).
## Só aparência: lê o estado do mundo, nunca escreve nele e não usa world.rng. Vale igual no
## host e no cliente, porque só depende do estado replicado e dos eventos de efeito (Fx).
##
## Limite do motor: 16 luzes por item desenhado. Por isso o chão é cortado em blocos (World) e
## os clarões próximos do mesmo tipo se fundem num só.

const MAX_FLASH := 14
const MAX_FOLLOW := 10
const WARM := Color(1.0, 0.74, 0.42)
const LAMP := Color(1.0, 0.80, 0.52)
const ACID := Color(0.50, 1.0, 0.28)
const CYAN := Color(0.35, 0.90, 1.0)
const NEST := Color(1.0, 0.36, 0.86)

var world: World
var amb: Dictionary
var active := false
var quality := 2
var t := 0.0
var sun: DirectionalLight2D
var glow: Node2D
var tex: Texture2D
var fixed: Array = [] # Dictionary: l, owner, pos, kind, e, col, halo, hpos, ph, on
var flashes: Array = [] # Dictionary: l, life, max, e, kind, prio
var spare: Array = [] # PointLight2D livres para clarões
var follow: Array = [] # PointLight2D reaproveitadas a cada quadro
var cmd: Array = []


func setup(w: World) -> void:
	world = w
	amb = w.amb
	quality = Game.gfx
	visibility_layer = Stage.LAYER_BOTH
	active = w.visuals
	if not active:
		return
	var cm := CanvasModulate.new()
	cm.name = "Ambient"
	add_child(cm)
	if quality == 0:
		# sem luzes dinâmicas: o sol entra direto na cor ambiente
		cm.color = Ambience.flat_light(amb).lightened(0.18)
		return
	cm.color = amb.ambient
	tex = Art.light_texture()
	sun = DirectionalLight2D.new()
	sun.name = "Sun"
	sun.color = amb.sun
	sun.energy = amb.sun_energy
	sun.height = amb.sun_height
	var dir: Vector2 = amb.sun_dir
	sun.rotation = dir.angle() - PI / 2.0 # a luz viaja no +Y local do nó
	add_child(sun)
	glow = Node2D.new()
	glow.name = "Glow"
	glow.visibility_layer = Stage.LAYER_BOTH
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = m
	add_child(glow)
	glow.draw.connect(_draw_glow)
	var n_flash := MAX_FLASH if quality >= 2 else 6
	for i in n_flash:
		spare.append(_light())
	for i in (MAX_FOLLOW if quality >= 2 else 5):
		follow.append(_light())


func _light() -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.enabled = false
	add_child(l)
	return l


func _put(l: PointLight2D, p: Vector2, col: Color, radius: float, energy: float, h: float) -> void:
	l.position = p
	l.color = col
	l.texture_scale = radius / 64.0
	l.energy = energy
	l.height = h
	l.enabled = true


## Luzes presas ao cenário. Chamado pelo World depois de carregar o mapa.
func build_fixed() -> void:
	if not active or quality == 0:
		return
	var g = world.generator
	if g != null:
		_fixed(g, g.position + Vector2(0, 6), CYAN, 200.0, 1.0, 70.0, "generator", 30.0, g.position + Vector2(0, -17))
	for tu in world.turrets:
		_fixed(tu, tu.position + Vector2(0, 2), Color(1.0, 0.4, 0.3), 46.0, 0.6, 16.0, "turret", 9.0, tu.position + Vector2(0, -11))
	for sw in world.switches:
		_fixed(sw, sw.position, Color(1.0, 0.4, 0.3), 80.0, 0.8, 30.0, "switch", 14.0, sw.position + Vector2(0, -32))
	for n in world.nests:
		var big: bool = n.kind == "heart"
		_fixed(n, n.position + Vector2(0, 8), NEST, 230.0 if big else 130.0, 0.85, 46.0, "nest", 0.0, n.position)
	if world.extraction != Vector2.INF:
		_fixed(null, world.extraction, CYAN, 110.0, 0.7, 40.0, "zone", 0.0, world.extraction)
	_acid_lights()
	_wall_lamps()


func _fixed(owner, p: Vector2, col: Color, radius: float, energy: float, h: float, kind: String, halo: float, hpos: Vector2) -> void:
	var l := _light()
	_put(l, p, col, radius, energy, h)
	fixed.append({ l = l, owner = owner, kind = kind, e = energy, col = col, cur = col, halo = halo, hpos = hpos, ph = fixed.size() * 1.7, on = true })


func _acid_lights() -> void:
	var placed: Array = []
	for c in world.acid_cells:
		var near := false
		for q in placed:
			if q.distance_squared_to(c) < 88.0 * 88.0:
				near = true
				break
		if near:
			continue
		placed.append(c)
		_fixed(null, c, ACID, 104.0, 0.42, 26.0, "acid", 0.0, c)


## Postes nos cantos dos muros e luzes âmbar nos portões.
func _wall_lamps() -> void:
	var g := world.grid
	var placed: Array = []
	for cell in world.walls:
		var wl: Prop = world.walls[cell]
		var cx: int = cell % g.cols
		var cy: int = cell / g.cols
		if wl.kind == "gate":
			if not _is_wall(cx - 1, cy) or world.walls[g.idx(cx - 1, cy)].kind != "gate":
				_fixed(wl, wl.position + Vector2(0, 26), Color(1.0, 0.66, 0.25), 84.0, 0.75, 34.0, "gate", 0.0, wl.position)
			continue
		var n := _is_wall(cx, cy - 1)
		var s := _is_wall(cx, cy + 1)
		var e := _is_wall(cx + 1, cy)
		var w := _is_wall(cx - 1, cy)
		var corner := (n != s) and (e != w)
		if not corner:
			continue
		var near := false
		for q in placed:
			if q.distance_squared_to(wl.position) < 120.0 * 120.0:
				near = true
				break
		if near:
			continue
		placed.append(wl.position)
		wl.lamp = true
		_fixed(wl, wl.position + Vector2(0, 26), LAMP, 150.0, 1.0, 54.0, "lamp", 13.0, wl.position + Vector2(0, -Prop.WALL_H - 15.0))


func _is_wall(cx: int, cy: int) -> bool:
	var g := world.grid
	return g.in_bounds(cx, cy) and world.walls.has(g.idx(cx, cy))


## Clarão de curta duração (tiro, explosão). `kind` igual e posição próxima = funde com o que já existe.
func flash(p: Vector2, col: Color, radius: float, energy: float, life: float, kind: String = "", prio: int = 0) -> void:
	if not active or quality == 0:
		return
	if kind != "":
		for f in flashes:
			if f.kind == kind and f.l.position.distance_squared_to(p) < 46.0 * 46.0:
				f.life = maxf(f.life, life)
				f.max = maxf(f.max, life)
				f.e = maxf(f.e, energy)
				f.l.position = f.l.position.lerp(p, 0.5)
				return
	var l: PointLight2D = null
	if spare.is_empty():
		# rouba o clarão menos importante e mais perto de apagar
		var worst := -1
		var score := INF
		for i in flashes.size():
			var f2: Dictionary = flashes[i]
			var sc: float = f2.prio * 10.0 + f2.life / f2.max
			if f2.prio <= prio and sc < score:
				score = sc
				worst = i
		if worst < 0:
			return
		l = flashes[worst].l
		flashes.remove_at(worst)
	else:
		l = spare.pop_back()
	_put(l, p, col, radius, energy, radius * 0.3)
	flashes.append({ l = l, life = life, max = life, e = energy, kind = kind, prio = prio })


func update(dt: float) -> void:
	if not active or quality == 0:
		return
	t += dt
	var i := flashes.size() - 1
	while i >= 0:
		var f: Dictionary = flashes[i]
		f.life -= dt
		if f.life <= 0.0:
			f.l.enabled = false
			spare.append(f.l)
			flashes.remove_at(i)
		else:
			var k: float = f.life / f.max
			f.l.energy = f.e * k * sqrt(k)
		i -= 1
	_update_fixed()
	_update_follow()
	_update_commanders()
	glow.queue_redraw()


func _update_fixed() -> void:
	var lamps: float = amb.lamps
	var gl: float = amb.glow
	for f in fixed:
		var o = f.owner
		var on := true
		if o != null and (not is_instance_valid(o) or o.is_queued_for_deletion() or o.dead):
			on = false
		var e: float = f.e
		var col: Color = f.col
		var ph: float = f.ph
		match f.kind:
			"generator":
				e *= gl * (0.82 + 0.18 * sin(t * 4.0))
				if on and o.hp < o.max_hp * 0.35:
					e *= 0.55 + 0.45 * absf(sin(t * 17.0)) # falhando
					col = Color(1.0, 0.45, 0.35)
			"turret":
				e *= maxf(lamps, 0.4)
				if on and o.operator != null:
					col = Color(0.5, 1.0, 0.42)
			"switch":
				e *= maxf(gl, 0.6)
				if on and o.active:
					col = Color(0.5, 1.0, 0.42)
			"nest":
				e *= gl * (0.75 + 0.25 * sin(t * 2.2 + ph))
			"acid":
				e *= gl * (0.8 + 0.2 * sin(t * 1.3 + ph))
			"zone":
				e *= gl * (0.8 + 0.2 * sin(t * 3.0))
			"lamp", "gate":
				e *= lamps * (0.97 + 0.03 * sin(t * 23.0 + ph))
		on = on and e > 0.02
		f.on = on
		f.cur = col
		var l: PointLight2D = f.l
		l.enabled = on
		if on:
			l.energy = e
			l.color = col


func _update_follow() -> void:
	var n := 0
	var cap := follow.size()
	var gl: float = amb.glow
	# plasma: uma luz por projétil; chamas e obuses: agrupados em células de 56 px
	var cells := {}
	for pr in world.projectiles.list:
		match pr.kind:
			"plasma":
				if n < cap:
					_put(follow[n], pr.p, CYAN, 100.0, 1.0, 30.0)
					n += 1
			"flame", "shell":
				var p: Vector2 = pr.p
				var key := Vector2i(int(p.x / 56.0), int(p.y / 56.0))
				if cells.has(key):
					cells[key].n += 1
					cells[key].p += p
				else:
					cells[key] = { p = p, n = 1 }
	for key in cells:
		if n >= cap:
			break
		var c: Dictionary = cells[key]
		_put(follow[n], c.p / c.n, Color(1.0, 0.55, 0.2), 90.0, minf(1.1, 0.5 + 0.12 * c.n), 28.0)
		n += 1
	for gr in world.projectiles.grenades:
		if n >= cap:
			break
		if gr.acid:
			var k: float = gr.t / gr.T
			_put(follow[n], gr.b, ACID, 80.0, 0.35 + 0.5 * k, 24.0)
			n += 1
	for hz in world.hazards:
		if n >= cap:
			break
		var kk: float = clampf(hz.t / Bal.MOTHER.pool_time, 0.0, 1.0)
		_put(follow[n], hz.p, ACID, float(hz.r) * 2.4, 0.7 * kk * gl, 22.0)
		n += 1
	if world.crystal != null and n < cap:
		_put(follow[n], world.crystal.p, Color(1.0, 0.25, 0.35), 96.0, 0.9 * gl, 30.0)
		n += 1
	for pk in world.pickups:
		if n >= cap:
			break
		if pk.dead or not pk.visible:
			continue
		var info: Dictionary = World.PICKUP_INFO.get(pk.pick, {})
		var col: Color = info.get("color", Color.WHITE)
		_put(follow[n], pk.position, col, 64.0, 0.6 * maxf(gl, 0.7), 24.0)
		n += 1
	while n < cap:
		follow[n].enabled = false
		n += 1


## Lanterna de cada comandante: só acende quando o clima tem postes (entardecer, noite).
func _update_commanders() -> void:
	var lamps: float = amb.lamps
	if lamps <= 0.0:
		return
	while cmd.size() < world.commanders.size():
		cmd.append(_light())
	for i in world.commanders.size():
		var c = world.commanders[i]
		var l: PointLight2D = cmd[i]
		if c.dead:
			l.enabled = false
		else:
			_put(l, c.position + Vector2(0, -6), Color(1.0, 0.93, 0.80), 120.0, 0.5 * lamps, 44.0)


## Halos das lâmpadas e núcleos brilhantes (aditivo, sem luz; entra no buffer de brilho).
func _draw_glow() -> void:
	for f in fixed:
		if not f.on or f.halo <= 0.0:
			continue
		var h: float = f.halo
		var col: Color = f.cur
		var p: Vector2 = f.hpos
		var e: float = clampf(f.l.energy, 0.0, 1.2) * 0.6
		glow.draw_texture_rect(tex, Rect2(p - Vector2(h, h), Vector2(h, h) * 2.0), false, Color(col.r * e, col.g * e, col.b * e, 1.0))
		glow.draw_circle(p, maxf(1.5, h * 0.16), col.lerp(Color.WHITE, 0.6))
