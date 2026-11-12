class_name Nest
extends Unit
## Ninho (gera aracnídeos sem parar, taxa crescente) ou Coração da colmeia (missão final).
## Os aracnídeos recém-nascidos juntam um BANDO em volta do ninho e partem juntos.

var spawn_cd := 1.0
var pulse := 0.0
var pack: Array = []


func setup(w: World, type: String, x: Vector2) -> void:
	world = w
	kind = type
	position = x
	add_to_group("nests")
	var base: Dictionary = Bal.HEART if type == "heart" else Bal.NEST
	r = base.radius
	max_hp = ceilf(base.hp * w.diff.bug_hp)
	hp = max_hp
	spawn_cd = w.rng.randf_range(0.5, base.spawn_interval)
	pulse = w.rng.randf() * 6.0
	Art.apply(visual, type)


func tick(dt: float) -> void:
	if flash > 0.0:
		flash -= dt
	pulse += dt
	spawn_cd -= dt
	if spawn_cd > 0.0:
		return
	var base: float = Bal.HEART.spawn_interval if kind == "heart" else Bal.NEST.spawn_interval
	var minutes := world.time / 60.0
	var rate: float = world.diff.spawn * (1.0 + world.diff.escalation * minutes)
	spawn_cd = maxf(Bal.NEST.min_interval, base / rate) * world.rng.randf_range(0.8, 1.2)
	if world.bugs.size() >= Bal.LIMITS.max_bugs:
		return
	var a := world.rng.randf_range(0.0, TAU)
	var p := position + Vector2(cos(a), sin(a)) * (r - 4.0)
	if world.grid.kind_at(p) != Grid.GROUND:
		return
	var b: Bug = world.spawn_bug("bug", p, 0.3)
	if b == null:
		return
	b.face = a
	b.impulse = Vector2(cos(a), sin(a)) * 60.0
	# bando: espera junto do ninho (o tempo de espera cai com a escalada)
	var wait: float = Bal.NEST.gather_time / (1.0 + minutes * 0.5)
	b.start_gather(self, wait)
	pack.append(b)
	if pack.size() >= Bal.NEST.pack_size:
		release_pack()


func release_pack() -> void:
	for b in pack:
		if Unit.ok(b):
			b.release()
	pack.clear()


func sync_visual() -> void:
	visual.frame = 1 if fmod(pulse, 1.2) < 0.25 else 0
	var s := 1.0 + sin(pulse * 3.0) * 0.03
	visual.scale = Vector2(s, s)
	apply_flash()
