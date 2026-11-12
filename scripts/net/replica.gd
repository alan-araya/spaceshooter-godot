class_name Replica
extends RefCounted
## Cliente: desenha o mundo a partir dos snapshots do host, um pouco no passado (DELAY_TICKS),
## interpolando posições entre dois snapshots e disparando os eventos (som, partículas, decalques,
## mensagens) quando o relógio de desenho passa pelo quadro em que aconteceram.
## O World do cliente é montado com a mesma missão e semente do host (mesmos uids iniciais)
## e NÃO roda update(): só recebe estado.

## Atraso de interpolação em quadros do host (60 Hz). Com snapshots a 30 Hz, 6 quadros = 2 snapshots.
const DELAY_TICKS := 6.0

var world: World
var buf: Array = [] # snapshots decodificados, em ordem de tick
var events: Array = [] # [tick, tipo, args]
var nodes := {} # uid -> Node2D
var render_tick := -1.0
var snapshots_received := 0
var last_snapshot: Dictionary = {}


func _init(w: World) -> void:
	world = w
	w.replica = true
	for arr in [w.soldiers, w.robots, w.bugs, w.nests, w.flowers, w.pickups, w.vehicles]:
		for u in arr:
			nodes[u.uid] = u


func push_snapshot(bytes: PackedByteArray) -> void:
	var s := Snapshot.decode(bytes)
	snapshots_received += 1
	if not buf.is_empty() and s.tick <= buf[-1].tick:
		return # fora de ordem / repetido
	buf.append(s)
	last_snapshot = s


func push_events(evs: Array) -> void:
	events.append_array(evs)


func render(dt: float) -> void:
	if buf.is_empty():
		return
	var latest: float = buf[-1].tick
	var target := latest - DELAY_TICKS
	if render_tick < 0.0:
		render_tick = target
	render_tick += dt * 60.0
	# segue o alvo suavemente (corrige deriva de relógio e variação de chegada)
	if absf(render_tick - target) > 30.0:
		render_tick = target
	else:
		render_tick += (target - render_tick) * 0.05
	render_tick = minf(render_tick, latest)
	while buf.size() >= 2 and buf[1].tick <= render_tick:
		buf.pop_front()
	var s0: Dictionary = buf[0]
	var s1: Dictionary = buf[1] if buf.size() >= 2 else s0
	var alpha := 0.0
	if s1.tick > s0.tick:
		alpha = clampf((render_tick - s0.tick) / float(s1.tick - s0.tick), 0.0, 1.0)
	_fire_events()
	_apply(s0, s1, alpha, maxf(0.0, render_tick - s0.tick) / 60.0, dt)


## Consome todos os snapshots e eventos pendentes de uma vez (testes).
func catch_up() -> void:
	if buf.is_empty():
		return
	render_tick = buf[-1].tick
	while buf.size() >= 2:
		buf.pop_front()
	_fire_events()
	_apply(buf[0], buf[0], 0.0, 0.0, 0.0)


func _fire_events() -> void:
	var w := world
	while not events.is_empty() and float(events[0][0]) <= render_tick:
		var ev: Array = events.pop_front()
		var args: Array = ev[2]
		match ev[1]:
			"sfx":
				Sfx.play(args[0], args[1])
			"toast":
				w.toast_requested.emit(args[0], args[1])
			"shake":
				w.shake_requested.emit(args[0])
			"fx":
				w.fx.callv(args[0], args[1])
			"decal":
				w.decal_layer.add_decal(args[0], args[1], args[2])
			"corpse":
				w.decal_layer.add_corpse(args[0], args[1], args[2], args[3])


func _apply(s0: Dictionary, s1: Dictionary, a: float, since: float, dt: float) -> void:
	var w := world
	w.time = lerpf(s0.time, s1.time, a)
	w.troops = s0.troops
	w.merit = s0.merit
	w.outcome = s0.outcome
	w.outcome_reason = s0.reason
	w.replica_objective = s0.objective
	w.stats = s0.stats.duplicate()

	# comandantes
	for i in mini(w.commanders.size(), s0.cmds.size()):
		var c: Commander = w.commanders[i]
		var r0: Dictionary = s0.cmds[i]
		var p: Vector2 = r0.p
		var f: float = r0.face
		if i < s1.cmds.size() and not r0.dead and not s1.cmds[i].dead:
			p = p.lerp(s1.cmds[i].p, a)
			f = lerp_angle(f, s1.cmds[i].face, a)
		c.position = p
		c.face = f
		c.dead = r0.dead
		c.disconnected = r0.disconnected
		c.moving = r0.moving
		c.carrying = r0.carrying
		c.flash = 0.1 if r0.flash else 0.0
		c.walk_t = r0.walk
		c.hp = r0.hp
		c.invuln = r0.invuln
		c.respawn_timer = r0.respawn
		c.drop_t = r0.drop
		c.weapon = r0.weapon
		c.ammo = r0.ammo
		c.grenades = r0.grenades
		c.order = r0.order

	# entidades: cria, atualiza (interpolando) e remove por uid
	var nxt: Dictionary = s1.by_uid
	var seen := {}
	for e in s0.ents:
		var uid: int = e.uid
		var n = nodes.get(uid)
		if n == null or not is_instance_valid(n):
			n = _create(e)
			nodes[uid] = n
		seen[uid] = true
		var p2: Vector2 = e.p
		var f2: float = e.face
		var e1 = nxt.get(uid)
		if e1 != null and e1.t == e.t:
			p2 = p2.lerp(e1.p, a)
			f2 = lerp_angle(f2, e1.face, a)
		n.position = p2
		_apply_ent(n, e, f2, dt)
	for uid in nodes.keys():
		if not seen.has(uid):
			var gone = nodes[uid]
			if is_instance_valid(gone):
				gone.queue_free()
			nodes.erase(uid)
	_rebuild_lists()

	# cenário
	if w.generator != null and s0.gen != null:
		w.generator.hp = s0.gen.hp
		w.generator.dead = s0.gen.dead
		w.generator.flash = 0.1 if s0.gen.flash else 0.0
		w.generator.t += dt
	w.crystal = s0.crystal
	for i in mini(w.switches.size(), s0.switches.size()):
		w.switches[i].progress = s0.switches[i].progress
		w.switches[i].active = s0.switches[i].active
		w.switches[i].t += dt
	for i in mini(w.turrets.size(), s0.turrets.size()):
		var tu: Prop = w.turrets[i]
		var aim: float = s0.turrets[i].aim
		if i < s1.turrets.size():
			aim = lerp_angle(aim, s1.turrets[i].aim, a)
		tu.aim = aim
		tu.operator = tu if s0.turrets[i].manned else null
		tu.t += dt
	for cell in w.walls.keys():
		if not s0.walls.has(cell):
			# muro/portão destruído no host
			w.grid.kind[cell] = Grid.GROUND
			w.grid.deco[cell] = 120
			w.walls[cell].queue_free()
			w.walls.erase(cell)
			w.walls_version += 1
		else:
			w.grid.hp[cell] = s0.walls[cell] * w.grid.max_hp[cell]
	w.hazards = s0.hazards
	w.ambushes = s0.ambushes

	# projéteis: posição do snapshot + avanço pelo tempo decorrido
	var pl: Array = []
	for pr in s0.proj:
		var q: Dictionary = pr.duplicate()
		q.p = pr.p + pr.v * since
		pl.append(q)
	w.projectiles.list = pl
	var gl: Array = []
	for gr in s0.gren:
		var T: float = maxf(gr.T, 0.01)
		gl.append({ a = gr.a, b = gr.b, T = T, t = minf(gr.frac * T + since, T * 0.999), bomb = gr.bomb, acid = gr.acid })
	w.projectiles.grenades = gl
	w.projectiles.queue_redraw()

	w._sync_visuals()
	w.fx.tick(dt)
	w.lights.update(dt)


func _create(e: Dictionary):
	var w := world
	var n = null
	match e.t:
		Snapshot.T.SOLDIER:
			var s := Soldier.new()
			s.setup(w, e.p, e.pid)
			n = s
		Snapshot.T.ROBOT:
			var r := Robot.new()
			r.setup(w, e.p)
			n = r
		Snapshot.T.BUG, Snapshot.T.LARVA, Snapshot.T.MOTHER:
			var b := Bug.new()
			b.setup(w, Snapshot.KIND_OF[e.t], e.p, 0.0)
			n = b
		Snapshot.T.NEST, Snapshot.T.HEART:
			var ne := Nest.new()
			ne.setup(w, Snapshot.KIND_OF[e.t], e.p)
			n = ne
		Snapshot.T.FLOWER:
			var f := Prop.new()
			f.setup_flower(w, e.p, e.grow)
			n = f
		Snapshot.T.PICKUP:
			var pk := Prop.new()
			pk.setup_pickup(w, e.p, e.pick, e.life)
			n = pk
		Snapshot.T.BUGGY:
			var v := Vehicle.new()
			v.setup_replica(w, "buggy", false)
			n = v
		_:
			var d := Vehicle.new()
			d.setup_replica(w, "dropship", e.get("flip", false))
			n = d
	n.uid = e.uid
	n.position = e.p
	if e.t == Snapshot.T.DROPSHIP:
		w.air.add_child(n)
	else:
		w.entities.add_child(n)
	return n


func _apply_ent(n, e: Dictionary, f: float, dt: float) -> void:
	match e.t:
		Snapshot.T.SOLDIER:
			n.face = f
			n.moving = e.moving
			n.walk_t = e.walk
			n.drop_t = e.drop
			n.flash = 0.1 if e.flash else 0.0
		Snapshot.T.ROBOT:
			n.face = f
			n.turret = e.turret
			n.flash = 0.1 if e.flash else 0.0
			n.hp = e.hp * n.max_hp
		Snapshot.T.BUG, Snapshot.T.LARVA, Snapshot.T.MOTHER:
			n.face = f
			n.moving = e.moving
			n.walk_t = e.walk
			n.attacking = e.attack
			n.emerge = e.emerge
			n.flash = 0.1 if e.flash else 0.0
			n.frenzy = e.frenzy
			n.charge_t = 0.2 if e.charge else 0.0
			n.hp = e.hp * n.max_hp
			if n.spitter != e.spitter:
				n.spitter = e.spitter
				n.visual.modulate = Color(0.85, 1.0, 0.8) if n.spitter else Color.WHITE
		Snapshot.T.NEST, Snapshot.T.HEART:
			n.flash = 0.1 if e.flash else 0.0
			n.hp = e.hp * n.max_hp
			n.pulse += dt
		Snapshot.T.FLOWER:
			n.grow = e.grow
			n.t += dt
		Snapshot.T.PICKUP:
			n.life = e.life
			n.t += dt
		Snapshot.T.BUGGY:
			n.face = f
			n.visible = e.visible
		Snapshot.T.DROPSHIP:
			n.visible = e.visible


func _rebuild_lists() -> void:
	var w := world
	var soldiers: Array = []
	var robots: Array = []
	var bugs: Array = []
	var nests: Array = []
	var flowers: Array = []
	var pickups: Array = []
	var vehicles: Array = []
	var mothers: Array = []
	for n in nodes.values():
		if n is Soldier:
			soldiers.append(n)
		elif n is Robot:
			robots.append(n)
		elif n is Bug:
			bugs.append(n)
			if n.kind == "mother":
				mothers.append(n)
		elif n is Nest:
			nests.append(n)
		elif n is Vehicle:
			vehicles.append(n)
		elif n is Prop:
			if n.kind == "flower":
				flowers.append(n)
			else:
				pickups.append(n)
	w.soldiers = soldiers
	w.robots = robots
	w.bugs = bugs
	w.nests = nests
	w.flowers = flowers
	w.pickups = pickups
	w.vehicles = vehicles
	w.mothers = mothers
