class_name Projectiles
extends Node2D
## Projéteis e granadas em lote (sem um nó por bala). Sem fogo amigo.

var world: World
var list: Array = [] # Dictionary: kind, p, v, life, max, dmg, pierce, splash, hit, target, bug
var grenades: Array = [] # Dictionary: a, b, t, T, bomb
var _near: Array = []


func fire(weapon_key: String, from: Vector2, angle: float, target: Unit = null) -> void:
	var wp: Dictionary = Bal.WEAPONS[weapon_key]
	var spd: float = wp.speed
	if weapon_key == "flame":
		spd *= world.rng.randf_range(0.75, 1.15)
	var kind := "bullet"
	if weapon_key == "flame" or weapon_key == "plasma":
		kind = weapon_key
	elif weapon_key == "cannon":
		kind = "shell"
	var dmg: float = wp.damage
	var hit = null
	if kind == "flame" or wp.pierce > 0:
		hit = {}
	var pr := {
		kind = kind, p = from, v = Vector2(cos(angle), sin(angle)) * spd,
		life = wp.reach / spd, max = wp.reach / spd, dmg = dmg, pierce = wp.pierce,
		splash = wp.splash, hit = hit, target = target, bug = false,
	}
	if target != null:
		target.pending += dmg
	list.append(pr)


func spit(from: Vector2, angle: float) -> void:
	var B: Dictionary = Bal.BUG
	var life: float = (B.spit_max + 60.0) / B.spit_speed
	list.append({
		kind = "spit", p = from, v = Vector2(cos(angle), sin(angle)) * B.spit_speed,
		life = life, max = life, dmg = B.spit_damage, pierce = 0, splash = 0.0, hit = null, target = null, bug = true,
	})


func throw_grenade(a: Vector2, b: Vector2, flight: float, bomb: bool) -> void:
	grenades.append({ a = a, b = b, t = 0.0, T = flight, bomb = bomb })


func _release(pr: Dictionary) -> void:
	var tg = pr.target
	if tg != null and is_instance_valid(tg):
		tg.pending = maxf(0.0, tg.pending - pr.dmg)
	pr.target = null


func tick(dt: float) -> void:
	var g := world.grid
	var w := float(Bal.WORLD_W)
	var h := float(Bal.WORLD_H)
	var keep: Array = []
	for pr in list:
		pr.life -= dt
		if pr.life <= 0.0:
			if pr.kind == "plasma":
				world.fx.plasma_pop(pr.p)
			_release(pr)
			continue
		var prev: Vector2 = pr.p
		pr.p += pr.v * dt
		if pr.kind == "flame":
			pr.v *= 1.0 - dt * 1.5
		var p: Vector2 = pr.p
		if p.x < -16.0 or p.y < -16.0 or p.x > w + 16.0 or p.y > h + 16.0:
			_release(pr)
			continue
		if g.kind_at(p) == Grid.ROCK:
			if pr.kind != "flame":
				world.fx.spark(prev, 3)
			_release(pr)
			continue
		if pr.bug:
			var kw := g.kind_at(p)
			if kw == Grid.WALL or kw == Grid.GATE:
				world.fx.goo(prev, 3) # muros e portões protegem do cuspe
				continue
			if _hit_humans(pr):
				continue
			keep.append(pr)
			continue
		if _hit_enemies(pr):
			continue
		keep.append(pr)
	list = keep

	var gkeep: Array = []
	for gr in grenades:
		gr.t += dt
		if gr.t >= gr.T:
			if gr.bomb:
				world.explode(gr.b, Bal.PICKUPS.bomb_radius, Bal.PICKUPS.bomb_damage, 1.1)
			else:
				world.explode(gr.b, Bal.GRENADE.radius, Bal.GRENADE.damage, 1.2)
		else:
			gkeep.append(gr)
	grenades = gkeep
	queue_redraw()


## Cuspe: atinge humanos e o gerador. Retorna true se o projétil acabou.
func _hit_humans(pr: Dictionary) -> bool:
	var p: Vector2 = pr.p
	var hm = world.human_hash.nearest(p, 20.0)
	if hm != null and hm.position.distance_to(p) < hm.r + 5.0:
		world.damage_human(hm, pr.dmg)
		world.fx.goo(p, 4)
		return true
	var gen = world.generator
	if gen != null and not gen.dead and gen.position.distance_to(p) < gen.r + 5.0:
		world.damage_human(gen, pr.dmg)
		world.fx.goo(p, 4)
		return true
	return false


## Tiros humanos: atingem insetos e ninhos. Retorna true se o projétil acabou.
func _hit_enemies(pr: Dictionary) -> bool:
	var p: Vector2 = pr.p
	var kind: String = pr.kind
	var hit_r := 4.0
	if kind == "plasma":
		hit_r = 12.0
	elif kind == "flame":
		hit_r = 10.0
	world.bug_hash.query(p, hit_r + 24.0, _near)
	for b in _near:
		if b.dead or b.emerge > 0.25:
			continue
		if pr.hit != null and pr.hit.has(b.uid):
			continue
		var rr: float = b.r + hit_r
		if b.position.distance_squared_to(p) > rr * rr:
			continue
		if pr.target == b:
			_release(pr)
		world.damage_enemy(b, pr.dmg)
		if kind != "flame":
			world.fx.goo(p, 2)
		elif world.rng.randf() < 0.15:
			world.fx.burn(b.position)
		if pr.hit != null:
			pr.hit[b.uid] = true
		if pr.pierce > 0:
			pr.pierce -= 1
			continue
		if kind == "plasma" and pr.splash > 0.0:
			world.splash(p, pr.splash, pr.dmg * 0.4)
		_release(pr)
		return true
	for n in world.nests:
		if n.dead:
			continue
		if pr.hit != null and pr.hit.has(n.uid):
			continue
		var rn: float = n.r + hit_r
		if n.position.distance_squared_to(p) < rn * rn:
			world.damage_enemy(n, pr.dmg)
			world.fx.goo(p, 2)
			if pr.hit != null:
				pr.hit[n.uid] = true
			if kind == "flame":
				continue
			if kind == "plasma" and pr.splash > 0.0:
				world.splash(p, pr.splash, pr.dmg * 0.4)
			_release(pr)
			return true
	if kind == "flame" and world.rng.randf() < 0.1:
		world.fx.smoke(p)
	return false


func _draw() -> void:
	for pr in list:
		var p: Vector2 = pr.p
		var v: Vector2 = pr.v
		match pr.kind:
			"bullet":
				var tail := p - v.normalized() * 9.0
				draw_line(tail, p, Color(1.0, 0.85, 0.35, 0.9), 2.0)
				draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 0.8))
			"shell":
				var tail2 := p - v.normalized() * 12.0
				draw_line(tail2, p, Color(1.0, 0.6, 0.2, 0.9), 3.0)
			"flame":
				var k: float = 1.0 - pr.life / pr.max
				var col := Color(1.0, 0.9 - k * 0.6, 0.3 - k * 0.3, 0.85 - k * 0.6)
				draw_circle(p, 4.0 + k * 9.0, col)
			"plasma":
				draw_circle(p, 9.0, Color(0.3, 0.9, 1.0, 0.35))
				draw_circle(p, 5.0, Color(0.6, 1.0, 1.0))
				draw_circle(p, 2.5, Color(1, 1, 1))
			"spit":
				draw_circle(p, 4.5, Color(0.55, 0.9, 0.2, 0.9))
				draw_circle(p - v.normalized() * 4.0, 3.0, Color(0.55, 0.9, 0.2, 0.5))
	for gr in grenades:
		var k2: float = gr.t / gr.T
		var a: Vector2 = gr.a
		var b: Vector2 = gr.b
		var base := a.lerp(b, k2)
		var hgt := sin(k2 * PI) * (18.0 if gr.bomb else 46.0)
		draw_circle(base, 3.5, Color(0, 0, 0, 0.35))
		var pos := base - Vector2(0, hgt)
		if gr.bomb:
			draw_rect(Rect2(pos - Vector2(3, 5), Vector2(6, 10)), Color("3b3f2a"))
		else:
			draw_circle(pos, 4.0, Color("4e5a2c"))
			draw_circle(pos + Vector2(-1, -1), 1.5, Color("9fb060"))
