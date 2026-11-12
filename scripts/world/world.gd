class_name World
extends Node2D
## WORLD — estado completo de uma missão + loop de simulação em passo fixo.
## Porte de src/game/world.js do MVP, agora com até 4 comandantes (co-op local).
## Comunicação com HUD/Main por sinais (toast, shake) e pelo estado público (troops, outcome...).

signal toast_requested(text: String, color: Color)
signal shake_requested(amount: float)

const TILE_KIND := {
	".": Grid.GROUND, ",": Grid.GROUND, ":": Grid.GROUND, "_": Grid.GROUND, "f": Grid.GROUND, "x": Grid.GROUND,
	"#": Grid.ROCK, "^": Grid.ROCK, "~": Grid.ACID, "=": Grid.WALL, "+": Grid.GATE,
}
const PICKUP_INFO := {
	reinforce = { label = "REFORÇOS!", color = Color("ffd166") },
	airstrike = { label = "ATAQUE AÉREO!", color = Color("ff9f43") },
	robot = { label = "APOIO BLINDADO!", color = Color("9fe8ff") },
	flame = { label = "LANÇA-CHAMAS", color = Color("ff7b39") },
	plasma = { label = "CANHÃO DE PLASMA", color = Color("7af5ff") },
	grenades = { label = "+3 GRANADAS", color = Color("c3ff6b") },
}

var mission: Dictionary
var diff: Dictionary
var diff_key := "normal"
var rng := RandomNumberGenerator.new()
var grid: Grid
var time := 0.0
var frame := 0
var next_uid := 1

var commanders: Array = []
var soldiers: Array = []
var robots: Array = []
var bugs: Array = []
var nests: Array = []
var flowers: Array = []
var pickups: Array = []
var vehicles: Array = []
var walls := {} # índice da célula -> Prop
var switches: Array = []
var ambushes: Array = [] # Dictionary: p, t, n, done
var generator: Prop = null
var crystal = null # Dictionary: p, carried, carrier
var extraction := Vector2.INF
var lz := Vector2.ZERO
var nest_cells: Array = []
var fertile_cells: Array = []
var acid_cells: Array = [] # Vector2 (centro) — bolhas animadas

var troops := 10
var merit := 0
var stats := { kills = 0, mothers = 0, nests = 0, flowers = 0, troops_lost = 0, commander_deaths = 0, pickups = 0 }
var outcome := ""
var outcome_reason := ""
var outcome_timer := 0.0
var settings := {}
var flower_timer := 0.0
var pickup_timer := 0.0
var ambush_timer := 0.0
var flow_index := 0
var total_nests := 0
var wall_toast_at := -99.0

var bug_hash: SpatialHash
var human_hash: SpatialHash
var ff_bug: FlowField
var ff_flower: FlowField
var ff_enemy: FlowField
var ff_cmd: Array = []
var tmp_a: Array = []
var tmp_b: Array = []

var ground: Sprite2D
var decal_layer: WorldLayer
var shadow_layer: WorldLayer
var entities: Node2D
var projectiles: Projectiles
var fx: Fx
var overlay: WorldLayer
var air: Node2D


# =============================================================================
# carregamento
# =============================================================================

func setup(mission_index: int, difficulty: String, players: int, seed_v: int = 1337) -> void:
	mission = Missions.get_mission(mission_index)
	diff_key = difficulty
	diff = Bal.DIFFICULTY[difficulty]
	rng.seed = seed_v
	grid = Grid.new()
	troops = diff.troops
	settings = { max_flowers = Bal.FLOWER.max_on_map, ambush = true, pickup_interval = 1.0 }
	settings.merge(mission.get("settings", {}), true)
	flower_timer = Bal.FLOWER.respawn_interval
	pickup_timer = rng.randf_range(Bal.PICKUPS.spawn_min, Bal.PICKUPS.spawn_max) * settings.pickup_interval * 0.6
	ambush_timer = Bal.AMBUSH.start_after

	bug_hash = SpatialHash.new(Bal.WORLD_W, Bal.WORLD_H, 32.0)
	human_hash = SpatialHash.new(Bal.WORLD_W, Bal.WORLD_H, 32.0)
	ff_bug = FlowField.new(grid, Grid.MODE_BUG)
	ff_flower = FlowField.new(grid, Grid.MODE_BUG)
	ff_enemy = FlowField.new(grid, Grid.MODE_HUMAN)

	_make_layers()
	_load_map(players)
	ground.texture = GroundBuilder.build(grid, mission.theme, nest_cells, seed_v)
	total_nests = 0
	for n in nests:
		if n.kind == "nest":
			total_nests += 1
	_recompute_all_flows()


func _make_layers() -> void:
	ground = Sprite2D.new()
	ground.name = "Ground"
	ground.centered = false
	add_child(ground)
	decal_layer = WorldLayer.new()
	decal_layer.name = "Decals"
	decal_layer.world = self
	decal_layer.mode = WorldLayer.Mode.DECALS
	add_child(decal_layer)
	shadow_layer = WorldLayer.new()
	shadow_layer.name = "Shadows"
	shadow_layer.world = self
	shadow_layer.mode = WorldLayer.Mode.SHADOWS
	add_child(shadow_layer)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	projectiles = Projectiles.new()
	projectiles.name = "Projectiles"
	projectiles.world = self
	add_child(projectiles)
	fx = Fx.new()
	fx.name = "Fx"
	fx.world = self
	add_child(fx)
	air = Node2D.new()
	air.name = "Air"
	add_child(air)
	overlay = WorldLayer.new()
	overlay.name = "Overlay"
	overlay.world = self
	overlay.mode = WorldLayer.Mode.OVERLAY
	add_child(overlay)


func _load_map(players: int) -> void:
	var map: Array = mission.map
	var floor_ch := "_" if mission.theme == "hive" else "."
	for y in grid.rows:
		var row: String = map[y]
		for x in grid.cols:
			var ch := row[x]
			var i := grid.idx(x, y)
			if TILE_KIND.has(ch):
				grid.kind[i] = TILE_KIND[ch]
				grid.deco[i] = ch.unicode_at(0)
				if ch == "=":
					grid.hp[i] = Bal.STRUCTURES.wall_hp
					grid.max_hp[i] = Bal.STRUCTURES.wall_hp
				elif ch == "+":
					grid.hp[i] = Bal.STRUCTURES.gate_hp
					grid.max_hp[i] = Bal.STRUCTURES.gate_hp
			else:
				grid.kind[i] = Grid.GROUND
				var fl := "f" if ch == "F" else _floor_from_neighbors(map, x, y, floor_ch)
				grid.deco[i] = fl.unicode_at(0)
			if grid.deco[i] == 102:
				fertile_cells.append(i)
			if grid.kind[i] == Grid.ACID:
				acid_cells.append(grid.center(x, y))
	var initial_soldiers := 0
	for y in grid.rows:
		var row2: String = map[y]
		for x in grid.cols:
			var ch2 := row2[x]
			var p := grid.center(x, y)
			match ch2:
				"C":
					lz = p
				"s":
					spawn_soldier(p, initial_soldiers % players, 0.0)
					initial_soldiers += 1
				"b":
					spawn_bug("bug", p, 0.0)
				"M":
					spawn_bug("mother", p, 0.0)
				"N":
					spawn_nest("nest", p)
					nest_cells.append(Vector2i(x, y))
				"H":
					spawn_nest("heart", p)
					nest_cells.append(Vector2i(x, y))
				"F":
					_add_flower(p, 0.0)
				"S":
					var sw := Prop.new()
					sw.setup_switch(self, p)
					switches.append(sw)
					entities.add_child(sw)
				"G":
					generator = Prop.new()
					generator.setup_generator(self, p + Vector2(16, 0))
					entities.add_child(generator)
				"E":
					extraction = p
				"1", "2", "3", "4", "5", "6":
					var which: String = ["reinforce", "airstrike", "robot", "flame", "plasma", "grenades"][int(ch2) - 1]
					_add_pickup(p, which, -1.0)
				"=", "+":
					var wl := Prop.new()
					wl.setup_wall(self, p, grid.idx(x, y), ch2 == "+")
					walls[grid.idx(x, y)] = wl
					entities.add_child(wl)
	for pid in players:
		var c := Commander.new()
		c.setup(self, pid)
		c.uid = _uid()
		c.position = lz + Vector2((pid % 2) * 28 - 14 if players > 1 else 0, (pid / 2) * 24)
		commanders.append(c)
		entities.add_child(c)
		ff_cmd.append(FlowField.new(grid, Grid.MODE_HUMAN))
	# soldiers já criados antes dos comandantes: reindexar a formação
	_reslot()


func _floor_from_neighbors(map: Array, x: int, y: int, fallback: String) -> String:
	var counts := {}
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var yy: int = y + o.y
		var xx: int = x + o.x
		if yy < 0 or yy >= map.size() or xx < 0 or xx >= Bal.COLS:
			continue
		var ch: String = map[yy][xx]
		if ".,:_x".contains(ch):
			counts[ch] = counts.get(ch, 0) + 1
	var best := fallback
	var bc := 0
	for k in counts:
		if counts[k] > bc:
			bc = counts[k]
			best = k
	return best


func _uid() -> int:
	next_uid += 1
	return next_uid


# =============================================================================
# spawns
# =============================================================================

func spawn_soldier(p: Vector2, pid: int, drop: float) -> Soldier:
	if soldiers.size() >= Bal.TROOPS.max_in_field:
		return null
	var s := Soldier.new()
	s.setup(self, p, pid)
	s.uid = _uid()
	s.drop_t = drop
	soldiers.append(s)
	entities.add_child(s)
	_reslot()
	return s


func drop_soldier(p: Vector2, pid: int, drop: float) -> Soldier:
	var c := grid.nearest_walkable(grid.cell_of(p), Grid.MODE_HUMAN)
	var q := grid.center(c.x, c.y) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
	# a tropa entra na contagem mesmo se o campo estiver cheio (reserva)
	troops += 1
	return spawn_soldier(q, pid, drop)


func spawn_robot(p: Vector2) -> Robot:
	var r := Robot.new()
	r.setup(self, p)
	r.uid = _uid()
	robots.append(r)
	entities.add_child(r)
	return r


func spawn_bug(type: String, p: Vector2, emerge_time: float) -> Bug:
	if type != "mother" and bugs.size() >= Bal.LIMITS.max_bugs:
		return null
	var b := Bug.new()
	b.setup(self, type, p, emerge_time)
	b.uid = _uid()
	bugs.append(b)
	entities.add_child(b)
	return b


func spawn_nest(type: String, p: Vector2) -> Nest:
	var n := Nest.new()
	n.setup(self, type, p)
	n.uid = _uid()
	nests.append(n)
	entities.add_child(n)
	return n


func _add_flower(p: Vector2, bloom: float) -> void:
	var f := Prop.new()
	f.setup_flower(self, p, bloom)
	flowers.append(f)
	entities.add_child(f)


func _add_pickup(p: Vector2, which: String, lifetime: float) -> Prop:
	var pk := Prop.new()
	pk.setup_pickup(self, p, which, lifetime)
	pickups.append(pk)
	entities.add_child(pk)
	return pk


func _reslot() -> void:
	var counts := [0, 0, 0, 0]
	for s in soldiers:
		if s.dead:
			continue
		s.slot = counts[s.pid]
		counts[s.pid] += 1


# =============================================================================
# eventos de jogo
# =============================================================================

func toast(text: String, color: Color = Color("ffe066")) -> void:
	toast_requested.emit(text, color)


func shake(amount: float) -> void:
	shake_requested.emit(amount)


func humans_alive() -> Array:
	var list: Array = []
	for c in commanders:
		if not c.dead:
			list.append(c)
	for s in soldiers:
		if not s.dead and s.drop_t <= 0.0:
			list.append(s)
	for r in robots:
		if not r.dead:
			list.append(r)
	return list


func alive_commanders() -> Array:
	var list: Array = []
	for c in commanders:
		if not c.dead:
			list.append(c)
	return list


func set_order(cmd: Commander, order: String) -> void:
	if not Bal.ORDERS.has(order):
		return
	cmd.order = order
	for s in soldiers:
		if s.pid == cmd.pid:
			s.anchor = s.position
			s.wander = s.position
	var label: String = Bal.ORDER_LABELS[order]
	toast("P%d · ORDEM: %s" % [cmd.pid + 1, label.to_upper()], Bal.PLAYER_COLORS[cmd.pid])
	Sfx.play("order", cmd.position.x)


## Escolha de alvo por AMEAÇA (melhoria sobre o MVP, que só pegava o mais próximo).
func pick_target(h, reach: float) -> Unit:
	var cands: Array = []
	var near: Array = tmp_a
	bug_hash.query(h.position, reach + 24.0, near)
	var cmd = null
	if h is Human and h.pid < commanders.size():
		cmd = commanders[h.pid]
		if cmd.dead:
			cmd = null
	for b in near:
		if b.dead or b.emerge > 0.2:
			continue
		var d: float = h.position.distance_to(b.position)
		if d > reach + b.r:
			continue
		var score := d
		if b.kind == "mother":
			score -= 90.0
		if d < 70.0:
			score -= 50.0 # colado em mim
		if cmd != null:
			var dc: float = cmd.position.distance_to(b.position)
			if dc < 110.0:
				score -= (110.0 - dc) * 0.8 # ameaça ao comandante
		if b.pending >= b.hp:
			score += 260.0 # já vai morrer com os tiros a caminho
		cands.append([score, b])
	for n in nests:
		if n.dead:
			continue
		var dn: float = h.position.distance_to(n.position) - n.r
		if dn <= reach:
			cands.append([dn + 60.0, n])
	if cands.is_empty():
		return null
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var checks := 0
	for cd in cands:
		var u: Unit = cd[1]
		if grid.line_clear(h.position, u.position, Grid.MODE_SHOT):
			return u
		checks += 1
		if checks >= 5:
			break
	return null


func damage_enemy(e: Unit, dmg: float) -> void:
	if e.dead:
		return
	e.hp -= dmg
	e.flash = 0.08
	if e.hp <= 0.0:
		kill_enemy(e)


func kill_enemy(e) -> void:
	if e.dead:
		return
	e.dead = true
	var p: Vector2 = e.position
	if e.kind == "bug" or e.kind == "larva":
		stats.kills += 1
		merit += Bal.MERIT.bug if e.kind == "bug" else Bal.MERIT.larva
		fx.goo(p, 5 if e.kind == "larva" else 9)
		if e.kind == "bug":
			decal_layer.add_corpse("bug", 7, p, e.face)
		else:
			decal_layer.add_decal("goo", p, 4.0)
		Sfx.play("squish", p.x)
	elif e.kind == "mother":
		stats.kills += 1
		stats.mothers += 1
		merit += Bal.MERIT.mother
		fx.goo(p, 26)
		fx.explosion(p, 0.7)
		decal_layer.add_decal("goo", p, 20.0)
		for i in Bal.MOTHER.death_larvae:
			var a: float = TAU * i / Bal.MOTHER.death_larvae
			var l := spawn_bug("larva", p + Vector2(cos(a), sin(a)) * 12.0, 0.15)
			if l != null:
				l.impulse = Vector2(cos(a), sin(a)) * 180.0
		Sfx.play("burst", p.x)
		shake(4.0)
	elif e.kind == "nest" or e.kind == "heart":
		stats.nests += 1
		merit += Bal.MERIT.heart if e.kind == "heart" else Bal.MERIT.nest
		fx.explosion(p, 2.2 if e.kind == "heart" else 1.4)
		fx.goo(p, 30)
		decal_layer.add_decal("crater", p, 40.0 if e.kind == "heart" else 26.0)
		Sfx.play("bigboom", p.x)
		shake(10.0 if e.kind == "heart" else 7.0)
		e.release_pack()
		if e.kind == "heart":
			toast("CORAÇÃO DA COLMEIA DESTRUÍDO! PEGUE O CRISTAL", Color("ff7ae0"))
			crystal = { p = p, carried = false, carrier = null }
		else:
			toast("NINHO DESTRUÍDO", Color("ffb347"))
			if rng.randf() < Bal.NEST.pickup_drop_chance:
				spawn_random_pickup(p)


## Dano em humano (comandante, soldado, robô) ou no gerador.
func damage_human(h, dmg: float) -> void:
	if h.dead:
		return
	if h is Commander and (h.invuln > 0.0 or h.god):
		return
	h.flash = 0.12
	h.hp -= dmg
	if h is Prop:
		if h.hp <= 0.0:
			h.dead = true
			h.hp = 0.0
			fx.explosion(h.position, 2.0)
			shake(12.0)
			Sfx.play("bigboom", h.position.x)
		return
	if h is Commander:
		h.invuln = Bal.COMMANDER.hit_invuln
		Sfx.play("hurt", h.position.x)
	if h.hp <= 0.0:
		kill_human(h)


func kill_human(h) -> void:
	if h.dead:
		return
	h.dead = true
	fx.blood(h.position, 12)
	decal_layer.add_decal("blood", h.position, 6.0)
	if h is Robot:
		fx.explosion(h.position, 1.1)
		toast("BLINDADO DESTRUÍDO", Color("ff6b6b"))
		Sfx.play("boom", h.position.x)
		return
	troops = maxi(0, troops - 1)
	stats.troops_lost += 1
	if h is Commander:
		stats.commander_deaths += 1
		Sfx.play("death", h.position.x)
		if h.carrying and crystal != null:
			h.carrying = false
			crystal.carried = false
			crystal.carrier = null
			crystal.p = h.position
		h.respawn_timer = Bal.TROOPS.commander_respawn
		if troops > 0:
			toast("P%d ABATIDO — VOLTA EM 10 s" % (h.pid + 1), Color("ff6b6b"))
		else:
			toast("P%d ABATIDO — SEM TROPAS!" % (h.pid + 1), Color("ff3b3b"))
	else:
		Sfx.play("scream", h.position.x)


func explode(p: Vector2, radius: float, damage: float, scale_k: float) -> void:
	bug_hash.query(p, radius + 24.0, tmp_b)
	var hits := tmp_b.duplicate()
	for b in hits:
		if b.dead:
			continue
		var d: float = b.position.distance_to(p)
		if d < radius + b.r:
			damage_enemy(b, damage * (1.0 if d < radius * 0.5 else 0.6))
	for n in nests:
		if not n.dead and n.position.distance_to(p) < radius + n.r:
			damage_enemy(n, damage * 0.8)
	fx.explosion(p, scale_k)
	decal_layer.add_decal("scorch", p, radius * 0.35)
	shake(2.0 + scale_k * 3.0)
	Sfx.play("boom", p.x)


func splash(p: Vector2, radius: float, dmg: float) -> void:
	bug_hash.query(p, radius + 20.0, tmp_b)
	var hits := tmp_b.duplicate()
	for b in hits:
		if not b.dead and b.position.distance_to(p) < radius + b.r:
			damage_enemy(b, dmg)
	fx.plasma_pop(p)
	Sfx.play("zap", p.x)


## Inseto travado num muro/portão: morde o tile.
func bite_tile(b: Bug, tile_idx: int) -> void:
	if b.bite_cd > 0.0:
		return
	b.bite_cd = Bal.BUG.bite_interval
	var k := grid.kind[tile_idx]
	if k != Grid.WALL and k != Grid.GATE:
		return
	var cx := tile_idx % grid.cols
	var cy := tile_idx / grid.cols
	var c := grid.center(cx, cy)
	b.attacking = 0.25
	fx.dust(c + (b.position - c) * 0.4, 2)
	if walls.has(tile_idx):
		walls[tile_idx].flash = 0.08
	if grid.damage_tile(cx, cy, Bal.BUG.wall_damage * (3.0 if b.kind == "mother" else 1.0)):
		fx.dust(c, 16)
		decal_layer.add_decal("rubble", c, 12.0)
		Sfx.play("wallbreak", c.x)
		shake(3.0)
		if walls.has(tile_idx):
			walls[tile_idx].queue_free()
			walls.erase(tile_idx)
		if time - wall_toast_at > 4.0:
			wall_toast_at = time
			toast("PORTÃO ROMPIDO!" if k == Grid.GATE else "MURO ROMPIDO!", Color("ff6b6b"))
	elif rng.randf() < 0.3:
		Sfx.play("scratch", c.x)


func trample_flower(f: Prop, h) -> void:
	if f.dead:
		return
	f.dead = true
	stats.flowers += 1
	merit += Bal.MERIT.flower
	fx.petals(f.position)
	decal_layer.add_decal("petals", f.position, 4.0)
	Sfx.play("trample", f.position.x)
	if h is Commander:
		toast("FLOR ARRANCADA", Color("c3ff6b"))


func flower_to_mother(f: Prop, b: Bug) -> void:
	f.dead = true
	b.dead = true
	var m := spawn_bug("mother", f.position, 0.6)
	fx.goo(f.position, 14)
	fx.petals(f.position)
	decal_layer.add_decal("goo", f.position, 12.0)
	if m != null:
		toast("UM ARACNÍDEO TOCOU UMA FLOR — MATRIARCA!", Color("ff7ae0"))
		Sfx.play("alarm", f.position.x)


# =============================================================================
# apoio: pickups, buggies, nave, robô
# =============================================================================

func spawn_random_pickup(at: Vector2 = Vector2.INF) -> Prop:
	var weights: Dictionary = Bal.PICKUPS.weights
	var total := 0.0
	for k in weights:
		total += weights[k]
	var roll := rng.randf() * total
	var which := "grenades"
	for k in weights:
		roll -= weights[k]
		if roll <= 0.0:
			which = k
			break
	var p := at
	if p == Vector2.INF:
		var alive := alive_commanders()
		var ref: Vector2 = lz if alive.is_empty() else alive[rng.randi() % alive.size()].position
		var reach: FlowField = ff_cmd[0]
		reach.compute([ref]) # alcançável a pé a partir do comandante (sob demanda)
		for tries in 50:
			var cx := rng.randi_range(1, grid.cols - 2)
			var cy := rng.randi_range(1, grid.rows - 2)
			if grid.kind[grid.idx(cx, cy)] != Grid.GROUND:
				continue
			var q := grid.center(cx, cy)
			if reach.at(q) == INF:
				continue
			var d := q.distance_to(ref)
			if d < 100.0 or d > 520.0:
				continue
			var crowded := false
			for pk in pickups:
				if pk.position.distance_to(q) < 60.0:
					crowded = true
			if crowded:
				continue
			p = q
			break
		if p == Vector2.INF:
			return null
	return _add_pickup(p, which, Bal.PICKUPS.lifetime)


func _update_pickups(dt: float) -> void:
	pickup_timer -= dt
	if pickup_timer <= 0.0 and outcome == "":
		pickup_timer = rng.randf_range(Bal.PICKUPS.spawn_min, Bal.PICKUPS.spawn_max) * settings.pickup_interval
		if pickups.size() < 4:
			spawn_random_pickup()
	for pk in pickups:
		if pk.dead:
			continue
		if pk.life > 0.0:
			pk.life -= dt
			if pk.life <= 0.0:
				pk.dead = true
				continue
		for c in commanders:
			if not c.dead and c.position.distance_to(pk.position) < c.r + pk.r:
				pk.dead = true
				apply_pickup(pk.pick, c)
				break


func apply_pickup(which: String, c: Commander) -> void:
	var info: Dictionary = PICKUP_INFO[which]
	stats.pickups += 1
	toast("P%d · %s" % [c.pid + 1, info.label], info.color)
	Sfx.play("pickup", c.position.x)
	fx.sparkle(c.position, info.color)
	match which:
		"reinforce":
			call_reinforcements(c)
		"airstrike":
			call_airstrike(c)
		"robot":
			call_robot(c)
		"flame", "plasma":
			c.weapon = which
			c.ammo = Bal.WEAPONS[which].ammo
		"grenades":
			c.grenades = mini(Bal.COMMANDER.max_grenades, c.grenades + Bal.PICKUPS.grenade_pack)


## Caminho da borda do mapa até perto do comandante, seguindo o campo de fluxo dele.
func edge_path(c: Commander, stop_cells: float) -> Array:
	var ff: FlowField = ff_cmd[c.pid]
	ff.compute([c.position])
	var best := -1
	var bd := INF
	for x in grid.cols:
		for y in [0, grid.rows - 1]:
			var i := grid.idx(x, y)
			if ff.dist[i] < bd:
				bd = ff.dist[i]
				best = i
	for y in grid.rows:
		for x in [0, grid.cols - 1]:
			var i2 := grid.idx(x, y)
			if ff.dist[i2] < bd:
				bd = ff.dist[i2]
				best = i2
	if best < 0 or bd == INF:
		return []
	var cx := best % grid.cols
	var cy := best / grid.cols
	var s := grid.center(cx, cy)
	var off := Vector2.ZERO
	if cx == 0:
		off.x = -56
	elif cx == grid.cols - 1:
		off.x = 56
	if cy == 0:
		off.y = -56
	elif cy == grid.rows - 1:
		off.y = 56
	var out: Array = [s + off, s]
	for guard in 300:
		var i3 := grid.idx(cx, cy)
		if ff.dist[i3] <= stop_cells:
			break
		var nb := -1
		var nd: float = ff.dist[i3]
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := cx + ox
				var ny := cy + oy
				if not grid.in_bounds(nx, ny):
					continue
				if ox != 0 and oy != 0 and (not grid.is_walkable_cell(cx + ox, cy) or not grid.is_walkable_cell(cx, cy + oy)):
					continue
				var d: float = ff.dist[grid.idx(nx, ny)]
				if d < nd:
					nd = d
					nb = grid.idx(nx, ny)
		if nb < 0:
			break
		cx = nb % grid.cols
		cy = nb / grid.cols
		out.append(grid.center(cx, cy))
	return out


func call_reinforcements(c: Commander) -> void:
	var path := edge_path(c, 2.0)
	var n: int = Bal.PICKUPS.reinforce_buggies
	var per := ceili(float(Bal.PICKUPS.reinforce_soldiers) / n)
	if path.size() < 2:
		for i in Bal.PICKUPS.reinforce_soldiers:
			drop_soldier(lz + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40)), c.pid, 0.45)
		return
	for k in n:
		var my: Array = path.slice(0, maxi(2, path.size() - k))
		var v := Vehicle.new()
		v.setup_buggy(self, my, k * 0.45, per, c.pid)
		vehicles.append(v)
		entities.add_child(v)
	Sfx.play("engine", c.position.x)


func call_airstrike(c: Commander) -> void:
	var y := clampf(c.position.y, 40.0, Bal.WORLD_H - 40.0)
	var drops: Array = []
	var n: int = Bal.PICKUPS.airstrike_soldiers
	for i in n:
		var dx := (i - (n - 1) * 0.5) * 44.0
		drops.append({ p = Vector2(clampf(c.position.x + dx, 20.0, Bal.WORLD_W - 20.0), y), soldier = true, done = false })
	var ship := Vehicle.new()
	ship.setup_dropship(self, Vector2(-100, y), Bal.VEHICLES.dropship_speed, 0.2, drops, c.pid)
	vehicles.append(ship)
	air.add_child(ship)
	# segunda passagem: bombas na faixa com mais insetos
	var rows := []
	rows.resize(grid.rows)
	rows.fill(0)
	for b in bugs:
		if not b.dead:
			rows[clampi(int(b.position.y / Bal.TILE), 0, grid.rows - 1)] += 6 if b.kind == "mother" else 1
	for nst in nests:
		rows[clampi(int(nst.position.y / Bal.TILE), 0, grid.rows - 1)] += 8
	var br := 0
	for i in grid.rows:
		if rows[i] > rows[br]:
			br = i
	var by := br * Bal.TILE + Bal.TILE * 0.5 if rows[br] > 0 else y + 80.0
	var bombs: Array = []
	var x := 24.0
	while x < Bal.WORLD_W:
		bombs.append({ p = Vector2(x, by), soldier = false, done = false })
		x += Bal.PICKUPS.bomb_spacing
	var bomber := Vehicle.new()
	bomber.setup_dropship(self, Vector2(Bal.WORLD_W + 100, by), -Bal.VEHICLES.dropship_speed * 1.15, 1.6, bombs, c.pid)
	vehicles.append(bomber)
	air.add_child(bomber)
	Sfx.play("jet", c.position.x)


func call_robot(c: Commander) -> void:
	var path := edge_path(c, 3.0)
	var start := lz
	if path.size() > 1:
		start = path[1]
	var r := spawn_robot(start)
	fx.dust(r.position, 10)


# =============================================================================
# loop
# =============================================================================

## Perfil opcional (testes): soma de microssegundos por seção do update.
var profile := {}
var profiling := false
var _pt := 0


func _prof(section: String) -> void:
	if not profiling:
		return
	var now := Time.get_ticks_usec()
	profile[section] = profile.get(section, 0) + (now - _pt)
	_pt = now


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	_pt = Time.get_ticks_usec()
	time += dt
	frame += 1
	_update_respawns(dt)
	_rebuild_hashes()
	_prof("hashes")
	_step_flows()
	_prof("flows")

	for c in commanders:
		if not c.dead:
			c.tick(dt)
	for s in soldiers:
		if not s.dead:
			s.tick(dt)
	for r in robots:
		if not r.dead:
			r.tick(dt)
	_prof("humans")
	for b in bugs:
		if not b.dead:
			b.tick(dt)
	_prof("bugs")
	for n in nests:
		if not n.dead:
			n.tick(dt)
	for f in flowers:
		f.tick(dt)
	for pk in pickups:
		pk.tick(dt)
	for sw in switches:
		sw.tick(dt)
	for wl in walls.values():
		wl.tick(dt)
	if generator != null:
		generator.tick(dt)

	_prof("props")
	projectiles.tick(dt)
	_prof("projectiles")
	for v in vehicles:
		if not v.dead:
			v.tick(dt)
	_update_pickups(dt)
	_update_flowers(dt)
	_update_ambush(dt)
	_update_switches_and_crystal(dt)
	_prof("support")
	fx.tick(dt)
	_prof("fx")
	_compact()
	_prof("compact")

	if outcome == "":
		var res := _objective_update()
		if res == "failed":
			_finish("defeat", outcome_reason)
		elif res == "done":
			_finish("victory", "Objetivo cumprido")
		elif troops <= 0 and alive_commanders().is_empty():
			_finish("defeat", "Sem tropas e sem comandantes")
	else:
		outcome_timer += dt
	_sync_visuals()
	_prof("visuals")


func _update_respawns(dt: float) -> void:
	for c in commanders:
		if not c.dead:
			continue
		if c.respawn_timer > 0.0:
			c.respawn_timer -= dt
		if c.respawn_timer <= 0.0 and troops > 0 and outcome == "":
			_respawn_commander(c)


func _respawn_commander(c: Commander) -> void:
	var p := lz + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
	c.position = p
	c.dead = false
	c.hp = Bal.COMMANDER.hp
	c.invuln = Bal.TROOPS.respawn_invuln
	c.flash = 0.0
	c.weapon = "mg"
	c.ammo = -1
	c.fire_cd = 0.0
	c.drop_t = 0.5
	c.respawn_timer = 0.0
	c.grenades = maxi(c.grenades, 1)
	# cápsula de pouso: esmaga insetos colados
	for b in bugs:
		if not b.dead and b.kind != "mother" and b.position.distance_to(p) < Bal.TROOPS.pod_clear_radius:
			kill_enemy(b)
	fx.explosion(p, 0.6)
	decal_layer.add_decal("scorch", p, 18.0)
	toast("P%d DE VOLTA AO CAMPO" % (c.pid + 1), Color("7cff8a"))
	Sfx.play("respawn", p.x)


func _rebuild_hashes() -> void:
	bug_hash.clear()
	for b in bugs:
		if not b.dead:
			bug_hash.insert(b)
	human_hash.clear()
	for c in commanders:
		if not c.dead:
			human_hash.insert(c)
	for s in soldiers:
		if not s.dead and s.drop_t <= 0.0:
			human_hash.insert(s)
	for r in robots:
		if not r.dead:
			human_hash.insert(r)


## Recalcula UM campo de fluxo a cada FLOW_FRAMES quadros, em rodízio (cada campo é
## atualizado a cada ~0,2 s, como no MVP). Campos sem usuário no momento são pulados.
## Os campos por comandante (ff_cmd) são calculados sob demanda (rota dos buggies, pickups).
const FLOW_FRAMES := 4


func _step_flows() -> void:
	if frame % FLOW_FRAMES != 0:
		return
	match flow_index % 3:
		0:
			_flow_bug()
		1:
			if _needs_enemy_flow():
				_flow_enemy()
		2:
			if _needs_flower_flow():
				_flow_flower()
	flow_index += 1


func _needs_enemy_flow() -> bool:
	if not robots.is_empty():
		return true
	for c in commanders:
		if c.order == "atacar":
			return true
	return false


func _needs_flower_flow() -> bool:
	for f in flowers:
		if not f.dead and f.grow <= 0.0:
			return true
	return false


func _recompute_all_flows() -> void:
	_flow_bug()
	_flow_enemy()
	_flow_flower()
	for pid in ff_cmd.size():
		_flow_cmd(pid)


func _flow_bug() -> void:
	var targets: Array = []
	for h in humans_alive():
		targets.append(h.position)
	if generator != null and not generator.dead:
		targets.append(generator.position)
	ff_bug.compute(targets)


func _flow_enemy() -> void:
	var targets: Array = []
	for b in bugs:
		if not b.dead:
			targets.append(b.position)
	for n in nests:
		if not n.dead:
			targets.append(n.position)
	ff_enemy.compute(targets)


func _flow_flower() -> void:
	var targets: Array = []
	for f in flowers:
		if not f.dead and f.grow <= 0.0:
			targets.append(f.position)
	ff_flower.compute(targets)


func _flow_cmd(pid: int) -> void:
	var c: Commander = commanders[pid]
	ff_cmd[pid].compute([lz if c.dead else c.position])


func _update_flowers(dt: float) -> void:
	flower_timer -= dt
	if flower_timer > 0.0:
		return
	flower_timer = Bal.FLOWER.respawn_interval * rng.randf_range(0.7, 1.3)
	var alive := 0
	for f in flowers:
		if not f.dead:
			alive += 1
	if alive >= settings.max_flowers:
		return
	var humans := humans_alive()
	for tries in 30:
		var i: int
		if not fertile_cells.is_empty() and rng.randf() < 0.85:
			i = fertile_cells[rng.randi() % fertile_cells.size()]
		else:
			i = rng.randi_range(0, grid.n - 1)
		if grid.kind[i] != Grid.GROUND:
			continue
		var p := grid.center_i(i)
		var bad := false
		for f in flowers:
			if not f.dead and f.position.distance_to(p) < 28.0:
				bad = true
		for h in humans:
			if h.position.distance_to(p) < 80.0:
				bad = true
		if generator != null and generator.position.distance_to(p) < 120.0:
			bad = true
		if bad:
			continue
		_add_flower(p, Bal.FLOWER.bloom_time)
		return


func _update_ambush(dt: float) -> void:
	for a in ambushes:
		a.t -= dt
		if a.t <= 0.0 and not a.done:
			a.done = true
			for i in a.n:
				spawn_bug("bug", a.p + Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16)), 0.4)
			fx.dust(a.p, 16)
			Sfx.play("burrow", a.p.x)
		elif not a.done and rng.randf() < dt * 20.0:
			fx.dust(a.p + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12)), 1)
	if not settings.ambush or outcome != "":
		return
	if nests.is_empty() and mission.objective.type != "survive":
		return
	if time < Bal.AMBUSH.start_after:
		return
	ambush_timer -= dt
	if ambush_timer > 0.0:
		return
	var minutes := time / 60.0
	ambush_timer = maxf(Bal.AMBUSH.min_interval, Bal.AMBUSH.base_interval * diff.ambush / (1.0 + 0.25 * minutes))
	var humans := humans_alive()
	if humans.is_empty():
		return
	var cmds := alive_commanders()
	var target: Node2D = cmds[rng.randi() % cmds.size()] if not cmds.is_empty() else humans[rng.randi() % humans.size()]
	for tries in 20:
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(Bal.AMBUSH.min_dist, Bal.AMBUSH.max_dist)
		var p := target.position + Vector2(cos(a), sin(a)) * d
		if p.x < 24 or p.y < 24 or p.x > Bal.WORLD_W - 24 or p.y > Bal.WORLD_H - 24:
			continue
		if grid.kind_at(p) != Grid.GROUND:
			continue
		var close := false
		for h in humans:
			if h.position.distance_to(p) < Bal.AMBUSH.min_dist:
				close = true
		if close:
			continue
		var c := grid.cell_of(p)
		if grid.deco_at(c.x, c.y) == 95 and mission.objective.type == "survive":
			continue
		ambushes.append({ p = p, t = Bal.AMBUSH.warn_time, n = rng.randi_range(Bal.AMBUSH.size_min, Bal.AMBUSH.size_max), done = false })
		toast("EMBOSCADA! O CHÃO ESTÁ TREMENDO", Color("ff9f43"))
		return


func _update_switches_and_crystal(dt: float) -> void:
	for s in switches:
		if s.active:
			continue
		var on := false
		for c in commanders:
			if not c.dead and not c.moving and c.position.distance_to(s.position) < 24.0:
				on = true
		if on:
			s.progress += dt / Bal.STRUCTURES.switch_time
			if s.progress >= 1.0:
				s.active = true
				s.progress = 1.0
				merit += Bal.MERIT.switch
				toast("RELÉ RELIGADO", Color("7cff8a"))
				Sfx.play("switch", s.position.x)
		else:
			s.progress = maxf(0.0, s.progress - dt * 0.25)
	if crystal != null:
		if not crystal.carried:
			for c in commanders:
				if not c.dead and c.position.distance_to(crystal.p) < 24.0:
					crystal.carried = true
					crystal.carrier = c
					c.carrying = true
					toast("P%d PEGOU O CRISTAL — VÁ PARA A EXTRAÇÃO" % (c.pid + 1), Color("9fe8ff"))
					Sfx.play("pickup", c.position.x)
					break
		elif crystal.carrier != null and not crystal.carrier.dead:
			crystal.p = crystal.carrier.position + Vector2(0, -22)


func _compact() -> void:
	var n_soldiers := soldiers.size()
	soldiers = _keep(soldiers)
	robots = _keep(robots)
	bugs = _keep(bugs)
	nests = _keep(nests)
	flowers = _keep(flowers)
	pickups = _keep(pickups)
	vehicles = _keep(vehicles)
	var amb: Array = []
	for a in ambushes:
		if not a.done or a.t > -0.5:
			amb.append(a)
	ambushes = amb
	if soldiers.size() != n_soldiers:
		_reslot()


func _keep(arr: Array) -> Array:
	var any_dead := false
	for u in arr:
		if u.dead:
			any_dead = true
			break
	if not any_dead:
		return arr
	var out: Array = []
	for u in arr:
		if u.dead:
			u.queue_free()
		else:
			out.append(u)
	return out


func _sync_visuals() -> void:
	for c in commanders:
		c.sync_visual()
	for s in soldiers:
		s.sync_visual()
	for r in robots:
		r.sync_visual()
	for b in bugs:
		b.sync_visual()
	for n in nests:
		n.sync_visual()
	for f in flowers:
		f.sync_visual()
	for pk in pickups:
		pk.sync_visual()
	for sw in switches:
		sw.sync_visual()
	for wl in walls.values():
		wl.sync_visual()
	if generator != null:
		generator.sync_visual()
	for v in vehicles:
		v.sync_visual()
	decal_layer.tick()
	shadow_layer.tick()
	overlay.tick()


func shadow_casters() -> Array:
	var out: Array = []
	out.append_array(commanders)
	out.append_array(soldiers)
	out.append_array(robots)
	out.append_array(bugs)
	return out


# =============================================================================
# objetivos (data-driven por mission.objective.type)
# =============================================================================

func _objective_update() -> String:
	var def: Dictionary = mission.objective
	match def.type:
		"eliminate":
			return "done" if nests.is_empty() and bugs.is_empty() else ""
		"nests":
			for n in nests:
				if n.kind == "nest":
					return ""
			return "done"
		"switches":
			if switches.is_empty():
				return ""
			for s in switches:
				if not s.active:
					return ""
			return "done"
		"survive":
			if generator != null and generator.dead:
				outcome_reason = "O gerador foi destruído"
				return "failed"
			return "done" if time >= def.time else ""
		"retrieve":
			if crystal != null and crystal.carried and crystal.carrier != null and not crystal.carrier.dead:
				if crystal.carrier.position.distance_to(extraction) < 32.0:
					return "done"
			return ""
	return ""


func objective_text() -> String:
	var def: Dictionary = mission.objective
	match def.type:
		"eliminate":
			if not nests.is_empty():
				return "Ninhos restantes: %d/%d  ·  Aracnídeos: %d" % [nests.size(), total_nests, bugs.size()]
			return "Elimine os aracnídeos restantes: %d" % bugs.size()
		"nests":
			var alive := 0
			for n in nests:
				if n.kind == "nest":
					alive += 1
			return "Ninhos destruídos: %d/%d" % [total_nests - alive, total_nests]
		"switches":
			var on := 0
			for s in switches:
				if s.active:
					on += 1
			return "Relés religados: %d/%d  —  fique parado sobre o relé" % [on, switches.size()]
		"survive":
			var left := maxf(0.0, def.time - time)
			var gp := 0
			if generator != null:
				gp = roundi(generator.hp / generator.max_hp * 100.0)
			return "Evacuação em %d:%02d  ·  Gerador %d%%" % [int(left) / 60, int(left) % 60, gp]
		"retrieve":
			if crystal == null:
				for n in nests:
					if n.kind == "heart":
						return "Destrua o Coração da Colmeia (%d PV)" % roundi(n.hp)
				return "Destrua o Coração da Colmeia"
			if not crystal.carried:
				return "Pegue o Cristal Prisma"
			return "Leve o cristal até a EXTRAÇÃO"
	return def.text


func _finish(result: String, reason: String) -> void:
	outcome = result
	outcome_reason = reason
	outcome_timer = 0.0
	if result == "victory":
		merit += Bal.MERIT.objective + troops * Bal.MERIT.per_surviving_troop
		Sfx.play("victory", Bal.WORLD_W * 0.5)
	else:
		Sfx.play("defeat", Bal.WORLD_W * 0.5)


# =============================================================================
# depuração / testes
# =============================================================================

func debug_kill_nests() -> void:
	for n in nests.duplicate():
		kill_enemy(n)


func summary() -> Dictionary:
	return {
		time = time, troops = troops, soldiers = soldiers.size(), bugs = bugs.size(),
		nests = nests.size(), flowers = flowers.size(), pickups = pickups.size(), merit = merit,
		outcome = outcome, objective = objective_text(), stats = stats.duplicate(),
	}
