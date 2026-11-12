class_name Bug
extends Unit
## Aracnídeo: comum ("bug"), filhote ("larva") ou matriarca ("mother").
## IA (melhorias sobre o MVP):
## - BANDO: os que nascem do ninho se juntam em volta dele e partem juntos (ondas visíveis);
## - CERCO: cada inseto tem um lado preferido e se abre pelo flanco quando ainda está longe;
## - BOTE: perto do alvo dá uma arrancada curta;
## - CUSPIDOR: mantém distância de tiro, anda de lado e cospe com antecipação;
## - COLETOR: procura flores para virar matriarca.

enum State { HUNT, GATHER }

var speed := 160.0
var damage := 1.0
var bite_cd := 0.0
var forager := false
var spitter := false
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
var _los_t := 0.0 # cache da linha de visão até o humano mais próximo (custo alto)
var _los_target = null
var _los_ok := false
var _push := Vector2.ZERO # separação (recalculada em quadros alternados)
var _near = null # humano percebido (recalculado a cada 3 quadros)


func setup(w: World, type: String, x: Vector2, emerge_time: float) -> void:
	world = w
	kind = type
	position = x
	add_to_group("bugs")
	var d: Dictionary = w.diff
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
		spitter = w.rng.randf() < Bal.BUG.spitter_chance
	spit_cd = w.rng.randf_range(Bal.BUG.spit_cd_min, Bal.BUG.spit_cd_max)
	birth_cd = Bal.MOTHER.birth_interval * w.rng.randf_range(0.5, 1.0)
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
	if emerge > 0.0:
		emerge -= dt
		return
	_steer(dt)
	if kind == "bug":
		_touch_flower()
	if dead:
		return
	_try_bite()
	if spitter:
		_try_spit(dt)
	if kind == "mother":
		_tick_birth(dt)


func _steer(dt: float) -> void:
	var B: Dictionary = Bal.BUG
	var dir := Vector2.ZERO
	var spd := speed
	if (world.frame + uid) % 3 == 0:
		_near = world.human_hash.nearest(position, B.sense)
	elif _near != null and (not is_instance_valid(_near) or _near.dead):
		_near = null
	var near = _near

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
				spd = speed * 0.45
			else:
				dir = Vector2(cos(wob + world.time), sin(wob + world.time)) * 0.2
				spd = speed * 0.2

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
					spd = speed * 0.55
			elif d < B.lunge_dist and lunge_cd <= 0.0 and kind != "mother":
				lunge_t = B.lunge_time
				lunge_cd = B.lunge_cd
				attacking = 0.3
		else:
			var fdir := world.ff_bug.dir_from(position)
			if fdir != Vector2.ZERO:
				# cerco: longe do alvo, abre pelo flanco preferido
				var far := world.ff_bug.at(position)
				var k: float = clampf((far - 3.0) / 6.0, 0.0, 1.0) * B.flank
				dir = (fdir + fdir.orthogonal() * flank * k).normalized()
			else:
				dir = Vector2(cos(wob + world.time * 0.5), sin(wob + world.time * 0.5))
	if lunge_t > 0.0:
		spd *= B.lunge_boost

	# zigue-zague orgânico
	var w := sin(world.time * 7.0 + wob) * 0.3
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
	v += _push * 4.0

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
		face = lerp_angle(face, v.angle(), minf(1.0, dt * 12.0))
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
		bite_cd = Bal.BUG.bite_interval * (0.8 if kind == "larva" else 1.0)
		attacking = 0.25
		world.damage_human(t, damage)
		Sfx.play("bite", position.x)


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
	spit_cd = world.rng.randf_range(B.spit_cd_min, B.spit_cd_max)
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
	Sfx.play("spit", position.x)


func _tick_birth(dt: float) -> void:
	birth_cd -= dt
	if birth_cd > 0.0:
		return
	birth_cd = Bal.MOTHER.birth_interval / world.diff.spawn
	if world.bugs.size() >= Bal.LIMITS.max_bugs:
		return
	var a := face + PI + world.rng.randf_range(-0.6, 0.6)
	var p := position + Vector2(cos(a), sin(a)) * 20.0
	var nb: Bug = world.spawn_bug("bug", p, 0.25)
	if nb != null:
		nb.impulse = Vector2(cos(a), sin(a)) * 80.0
	world.fx.goo(p, 4)
	Sfx.play("birth", position.x)


func sync_visual() -> void:
	visual.rotation = face
	var frames := 2 if kind != "bug" else 4
	var f := int(walk_t) % frames if moving else 0
	if kind == "bug" and attacking > 0.0:
		f = 4 + (int(attacking * 10.0) % 2) # linha 2: bote
	if kind == "mother":
		f = int(world.time * 3.0 + wob) % 2
	visual.frame = f
	if emerge > 0.0:
		var k := clampf(1.0 - emerge / 0.5, 0.2, 1.0)
		visual.scale = Vector2(k, k)
	else:
		visual.scale = Vector2.ONE
	apply_flash()
