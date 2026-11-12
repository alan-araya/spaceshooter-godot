class_name Bug
extends Unit
## Aracnídeo: comum ("bug"), filhote ("larva") ou matriarca ("mother").
## IA dos comuns:
## - BANDO: os que nascem do ninho se juntam em volta dele e partem juntos (ondas visíveis);
## - CERCO: cada inseto tem um lado preferido e se abre pelo flanco quando ainda está longe;
## - BOTE: perto do alvo dá uma arrancada curta;
## - CUSPIDOR: mantém distância de tiro, anda de lado e cospe com antecipação;
## - COLETOR: procura flores para virar matriarca;
## - ESQUIVA: os "espertos" fogem do ponto onde uma granada vai cair;
## - FRENESI: perto de uma matriarca ficam mais rápidos e mordem mais rápido.
## IA da MATRIARCA:
## - não entra na linha de tiro: mantém distância e circula atrás da ninhada;
## - MORTEIRO de ácido em arco, com aviso no chão, deixando uma poça que fere;
## - INVESTIDA com empurrão quando alguém chega perto demais;
## - RECUO para o ninho com pouca vida; pare mais rápido quando ameaçada;
## - ao perder 1/3 e 2/3 da vida, solta uma ninhada de filhotes (World.damage_enemy).

enum State { HUNT, GATHER }

var speed := 160.0
var damage := 1.0
var bite_cd := 0.0
var forager := false
var spitter := false
var smart := false # esquiva de granadas
var spit_cd := 3.0
var birth_cd := 4.0
var wob := 0.0
var flank := 0.0
var lunge_t := 0.0
var lunge_cd := 0.0
var impulse := Vector2.ZERO
var state := State.HUNT
var home: Unit = null # ninho de origem (enquanto junta o bando)
var gather_t := 0.0
var gather_spot := Vector2.ZERO
var attacking := 0.0 # anima o bote/mordida
var frenzy := false
# matriarca
var mortar_cd := 3.0
var charge_t := 0.0
var charge_cd := 0.0
var charge_dir := Vector2.ZERO
var brood_stage := 0 # ninhadas de emergência já soltas (World.damage_enemy)
var threatened := false

var _los_t := 0.0 # cache da linha de visão até o humano mais próximo (custo alto)
var _los_target = null
var _los_ok := false
var _push := Vector2.ZERO # separação (recalculada em quadros alternados)
var _near = null # humano percebido (recalculado a cada 3 quadros)
var _spd := 0.0
var _dodge := Vector2.ZERO
var _dodge_t := 0.0


func setup(w: World, type: String, x: Vector2, emerge_time: float) -> void:
	world = w
	kind = type
	position = x
	add_to_group("bugs")
	var d: Dictionary = w.diff
	var aggro: float = d.aggro
	var base: Dictionary = Bal.BUG
	if type == "mother":
		base = Bal.MOTHER
	elif type == "larva":
		base = Bal.LARVA
	r = base.radius
	max_hp = ceilf(base.hp * d.bug_hp)
	hp = max_hp
	speed = base.speed * d.bug_speed * w.rng.randf_range(0.9, 1.1)
	damage = base.damage
	face = w.rng.randf_range(-PI, PI)
	walk_t = w.rng.randf() * 4.0
	emerge = emerge_time
	wob = w.rng.randf() * 10.0
	flank = w.rng.randf_range(-1.0, 1.0)
	if type == "bug":
		forager = w.rng.randf() < Bal.BUG.forager_chance
		spitter = w.rng.randf() < Bal.BUG.spitter_chance * aggro
		smart = w.rng.randf() < Bal.BUG.dodge_chance * aggro
	spit_cd = w.rng.randf_range(Bal.BUG.spit_cd_min, Bal.BUG.spit_cd_max) / aggro
	birth_cd = Bal.MOTHER.birth_interval * w.rng.randf_range(0.5, 1.0)
	mortar_cd = Bal.MOTHER.mortar_cd * w.rng.randf_range(0.4, 0.8)
	Art.apply(visual, type)
	if spitter:
		visual.modulate = Color(0.85, 1.0, 0.8) # cuspidores levemente esverdeados


func start_gather(nest: Unit, wait: float) -> void:
	state = State.GATHER
	home = nest
	gather_t = wait
	var a := world.rng.randf_range(0.0, TAU)
	gather_spot = nest.position + Vector2(cos(a), sin(a)) * world.rng.randf_range(nest.r + 12.0, Bal.NEST.gather_radius)


func release() -> void:
	state = State.HUNT
	home = null


func tick(dt: float) -> void:
	if flash > 0.0:
		flash -= dt
	if bite_cd > 0.0:
		bite_cd -= dt
	if attacking > 0.0:
		attacking -= dt
	if lunge_t > 0.0:
		lunge_t -= dt
	if lunge_cd > 0.0:
		lunge_cd -= dt
	if charge_t > 0.0:
		charge_t -= dt
	if charge_cd > 0.0:
		charge_cd -= dt
	if _dodge_t > 0.0:
		_dodge_t -= dt
	if emerge > 0.0:
		emerge -= dt
		return
	_perceive()
	var dir: Vector2
	if kind == "mother":
		dir = _mother_intent()
	else:
		dir = _bug_intent(dt)
	_move(dir, _spd, dt)
	if kind == "bug":
		_touch_flower()
	if dead:
		return
	_try_bite()
	if spitter:
		_try_spit(dt)
	if kind == "mother":
		_tick_birth(dt)
		_try_mortar(dt)


## Percepção escalonada: humano mais próximo, frenesi e esquiva (a cada 3 quadros).
func _perceive() -> void:
	if (world.frame + uid) % 3 != 0:
		if _near != null and (not is_instance_valid(_near) or _near.dead):
			_near = null
		return
	var radius: float = Bal.MOTHER.mortar_range if kind == "mother" else Bal.BUG.sense
	_near = world.human_hash.nearest(position, radius)
	if kind == "mother":
		return
	frenzy = false
	var ar: float = Bal.MOTHER.aura_radius
	for m in world.mothers:
		if m != self and not m.dead and position.distance_squared_to(m.position) < ar * ar:
			frenzy = true
			break
	if smart and _dodge_t <= 0.0:
		for gr in world.projectiles.grenades:
			if gr.acid:
				continue
			var land: Vector2 = gr.b
			var rad: float = (Bal.PICKUPS.bomb_radius if gr.bomb else Bal.GRENADE.radius) + 18.0
			if gr.T - gr.t < 0.5 and position.distance_to(land) < rad:
				_dodge = (position - land).normalized()
				if _dodge == Vector2.ZERO:
					_dodge = Vector2(cos(wob), sin(wob))
				_dodge_t = 0.35
				break


func _bug_intent(dt: float) -> Vector2:
	var B: Dictionary = Bal.BUG
	var dir := Vector2.ZERO
	_spd = speed * (Bal.MOTHER.aura_speed if frenzy else 1.0)
	var near = _near
	if near != null and position.distance_to(near.position) > B.sense:
		near = null

	# bando: espera em volta do ninho até juntar gente ou alguém chegar perto
	if state == State.GATHER:
		gather_t -= dt
		if near != null or gather_t <= 0.0 or not Unit.ok(home):
			if Unit.ok(home):
				home.release_pack()
			release()
		else:
			var to := gather_spot - position
			if to.length() > 6.0:
				dir = to.normalized()
				_spd = speed * 0.45
			else:
				dir = Vector2(cos(wob + world.time), sin(wob + world.time)) * 0.2
				_spd = speed * 0.2

	var used := state == State.GATHER
	# coletor: vai até a flor aberta mais próxima
	if not used and forager and near == null and world.flowers.size() > 0:
		var fd := world.ff_flower.dir_from(position)
		if fd != Vector2.ZERO and world.ff_flower.at(position) < B.forager_range:
			dir = fd
			used = true
		for f in world.flowers:
			if not f.dead and f.grow <= 0.0 and position.distance_to(f.position) < 40.0:
				dir = (f.position - position).normalized()
				used = true
				break

	if not used:
		var direct = null
		if near != null:
			_los_t -= dt
			if _los_t <= 0.0 or _los_target != near:
				_los_t = 0.12 + world.rng.randf() * 0.08
				_los_target = near
				_los_ok = world.grid.line_clear_thick(position, near.position, r, Grid.MODE_BUG)
			if _los_ok:
				direct = near
		var gen = world.generator
		if gen != null and not gen.dead and position.distance_to(gen.position) < 80.0:
			if direct == null or position.distance_to(gen.position) < position.distance_to(direct.position):
				if world.grid.line_clear_thick(position, gen.position, r, Grid.MODE_BUG):
					direct = gen
		if direct != null:
			var to2: Vector2 = direct.position - position
			var d := to2.length()
			dir = to2 / maxf(d, 0.001)
			if spitter and direct == near:
				# cuspidor: mantém distância de tiro e anda de lado
				var hold: float = B.spit_hold
				if d < hold * 0.7:
					dir = -dir * 0.8 + dir.orthogonal() * signf(flank) * 0.6
				elif d < hold * 1.1:
					dir = dir.orthogonal() * signf(flank) + dir * 0.1
					_spd = speed * 0.55
			elif d < B.lunge_dist and lunge_cd <= 0.0:
				lunge_t = B.lunge_time
				lunge_cd = B.lunge_cd / world.diff.aggro
				attacking = 0.3
		else:
			dir = _flow_dir(true)
	if lunge_t > 0.0:
		_spd *= B.lunge_boost
	if _dodge_t > 0.0:
		dir = (dir * 0.25 + _dodge).normalized()
		_spd = maxf(_spd, speed * 1.3)
	return dir


## Desce o campo de fluxo até os humanos; longe do alvo, abre pelo flanco preferido.
func _flow_dir(flanking: bool) -> Vector2:
	var fdir := world.ff_bug.dir_from(position)
	if fdir == Vector2.ZERO:
		return Vector2(cos(wob + world.time * 0.5), sin(wob + world.time * 0.5))
	if not flanking:
		return fdir
	var far := world.ff_bug.at(position)
	var k: float = clampf((far - 3.0) / 6.0, 0.0, 1.0) * Bal.BUG.flank
	return (fdir + fdir.orthogonal() * flank * k).normalized()


func _mother_intent() -> Vector2:
	var M: Dictionary = Bal.MOTHER
	_spd = speed
	threatened = false
	var near = _near
	if near == null:
		return _flow_dir(false)
	var to: Vector2 = near.position - position
	var d := to.length()
	var nd := to / maxf(d, 0.001)
	threatened = d < M.keep_dist * 1.6
	# investida em curso
	if charge_t > 0.0:
		_spd = speed * M.charge_boost
		return charge_dir
	# pouca vida: recua para longe dos humanos, puxando para o ninho mais próximo
	if hp < max_hp * M.retreat_hp:
		var away := -nd
		var nest = world.nearest_nest(position)
		if nest != null:
			away = (away + (nest.position - position).normalized() * 0.8).normalized()
		_spd = speed * 1.35
		return away
	# alguém chegou perto demais: investida com empurrão
	if d < M.charge_dist and charge_cd <= 0.0:
		charge_t = M.charge_time
		charge_cd = M.charge_cd / world.diff.aggro
		charge_dir = nd
		attacking = 0.4
		world.sfx("burst", position.x)
		_spd = speed * M.charge_boost
		return charge_dir
	# mantém distância e circula atrás da ninhada
	if d < M.keep_dist:
		_spd = speed * 0.85
		return (-nd * 0.7 + nd.orthogonal() * signf(flank) * 0.5).normalized()
	if d < M.keep_dist * 1.6:
		_spd = speed * 0.5
		return nd.orthogonal() * signf(flank)
	return _flow_dir(false)


func _move(dir: Vector2, spd: float, dt: float) -> void:
	# zigue-zague orgânico (a matriarca anda mais "pesada")
	var amp := 0.12 if kind == "mother" else 0.3
	var w := sin(world.time * 7.0 + wob) * amp
	var o := Vector2(dir.x - dir.y * w, dir.y + dir.x * w)
	var v := o.normalized() * spd if o.length() > 0.001 else Vector2.ZERO

	# separação entre insetos (quadros alternados por uid: metade do custo)
	if (world.frame + uid) % 2 == 0:
		_push = Vector2.ZERO
		var cnt := 0
		var others: Array = world.tmp_b
		world.bug_hash.query(position, r * 2.0 + 4.0, others)
		for b in others:
			if b == self or b.dead:
				continue
			var e: Vector2 = position - b.position
			var mn: float = r + b.r
			var l2 := e.length_squared()
			if l2 < mn * mn and l2 > 0.0001:
				var l := sqrt(l2)
				_push += e / l * (mn - l)
				cnt += 1
				if cnt > 6:
					break
	v += _push * (1.5 if kind == "mother" else 4.0)

	# impulso inicial (filhotes saindo da mãe)
	if impulse != Vector2.ZERO:
		v += impulse
		impulse *= maxf(0.0, 1.0 - dt * 5.0)
		if absf(impulse.x) + absf(impulse.y) < 4.0:
			impulse = Vector2.ZERO

	var blocked := world.grid.move_circle(self, v * dt, r, Grid.MODE_BUG)
	if blocked >= 0:
		world.bite_tile(self, blocked)
	if absf(v.x) + absf(v.y) > 2.0:
		face = lerp_angle(face, v.angle(), minf(1.0, dt * (6.0 if kind == "mother" else 12.0)))
		moving = true
	else:
		moving = false
	walk_t += dt * (spd / 22.0)

	# empurrado para fora do gerador
	var g = world.generator
	if g != null and not g.dead:
		var ex: Vector2 = position - g.position
		var l3 := ex.length()
		var mn3: float = g.r + r - 1.0
		if l3 < mn3 and l3 > 0.01:
			position = g.position + ex / l3 * mn3


func _try_bite() -> void:
	if bite_cd > 0.0:
		return
	var t = world.human_hash.nearest(position, r + 24.0)
	var g = world.generator
	if g != null and not g.dead:
		var dg: float = position.distance_to(g.position) - g.r
		if dg < r + 6.0 and (t == null or dg < position.distance_to(t.position) - t.r):
			t = g
	if t == null:
		return
	if position.distance_to(t.position) < r + t.r + 4.0:
		var cd: float = Bal.BUG.bite_interval * (0.8 if kind == "larva" else 1.0)
		if frenzy:
			cd *= Bal.MOTHER.aura_bite
		bite_cd = cd
		attacking = 0.25
		world.damage_human(t, damage)
		if kind == "mother" and charge_t > 0.0 and t is Unit:
			world.knockback(t, charge_dir, Bal.MOTHER.knockback)
			charge_t = 0.0
		world.sfx("bite", position.x)


func _touch_flower() -> void:
	for f in world.flowers:
		if f.dead or f.grow > 0.0:
			continue
		if position.distance_to(f.position) < f.r + r:
			world.flower_to_mother(f, self)
			return


func _try_spit(dt: float) -> void:
	var B: Dictionary = Bal.BUG
	spit_cd -= dt
	if spit_cd > 0.0:
		return
	spit_cd = world.rng.randf_range(B.spit_cd_min, B.spit_cd_max) / world.diff.aggro
	var t = world.human_hash.nearest(position, B.spit_max)
	if t == null:
		return
	var d: float = position.distance_to(t.position)
	if d < B.spit_min or not world.grid.line_clear(position, t.position, Grid.MODE_SPIT):
		return
	# mira com antecipação
	var lead: float = d / B.spit_speed
	var tp: Vector2 = t.position
	if t.moving:
		tp += Vector2(cos(t.face), sin(t.face)) * 80.0 * lead
	var a := (tp - position).angle() + world.rng.randf_range(-0.08, 0.08)
	world.projectiles.spit(position + Vector2(cos(a), sin(a)) * 10.0, a)
	face = a
	attacking = 0.3
	world.sfx("spit", position.x)


## Morteiro de ácido: arco por cima de muros, com aviso no chão; mira onde o alvo VAI estar.
func _try_mortar(dt: float) -> void:
	var M: Dictionary = Bal.MOTHER
	mortar_cd -= dt
	if mortar_cd > 0.0 or charge_t > 0.0:
		return
	var t = world.mortar_target(position)
	if t == null:
		mortar_cd = 0.5 # ninguém no alcance: tenta de novo logo
		return
	mortar_cd = M.mortar_cd * world.rng.randf_range(0.8, 1.2) / world.diff.aggro
	var tp: Vector2 = t.position
	if t.moving:
		tp += Vector2(cos(t.face), sin(t.face)) * 60.0 * M.mortar_flight
	tp += Vector2(world.rng.randf_range(-14, 14), world.rng.randf_range(-14, 14))
	tp.x = clampf(tp.x, 8.0, Bal.WORLD_W - 8.0)
	tp.y = clampf(tp.y, 8.0, Bal.WORLD_H - 8.0)
	world.projectiles.lob_acid(position + Vector2(0, -12), tp, M.mortar_flight)
	face = (tp - position).angle()
	attacking = 0.4
	world.sfx("spit", position.x)


func _tick_birth(dt: float) -> void:
	birth_cd -= dt
	if birth_cd > 0.0:
		return
	var interval: float = Bal.MOTHER.birth_interval / world.diff.spawn
	if threatened:
		interval *= Bal.MOTHER.threat_birth
	birth_cd = interval
	if world.bugs.size() >= Bal.LIMITS.max_bugs:
		return
	var a := face + PI + world.rng.randf_range(-0.6, 0.6)
	var p := position + Vector2(cos(a), sin(a)) * 20.0
	var nb: Bug = world.spawn_bug("bug", p, 0.25)
	if nb != null:
		nb.impulse = Vector2(cos(a), sin(a)) * 80.0
	world.fx.goo(p, 4)
	world.sfx("birth", position.x)


func sync_visual() -> void:
	visual.rotation = face
	var frames := 2 if kind != "bug" else 4
	var f := int(walk_t) % frames if moving else 0
	if kind == "bug" and attacking > 0.0:
		f = 4 + (int(attacking * 10.0) % 2) # linha 2: bote
	if kind == "mother":
		f = 1 if (attacking > 0.0 or int(world.time * 3.0 + wob) % 2 == 1) else 0
	visual.frame = f
	var s := 1.0
	if kind == "mother" and charge_t > 0.0:
		s = 1.08
	if emerge > 0.0:
		s *= clampf(1.0 - emerge / 0.5, 0.2, 1.0)
	visual.scale = Vector2(s, s)
	if not spitter:
		visual.modulate = Color(1.0, 0.86, 0.82) if frenzy else Color.WHITE
	apply_flash()
