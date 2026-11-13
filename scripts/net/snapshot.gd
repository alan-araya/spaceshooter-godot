class_name Snapshot
extends RefCounted
## Estado do mundo para a rede (host → clientes), em binário compacto (StreamPeerBuffer).
## Posições em meio pixel (int16), ângulos em 1/256 de volta, vida como razão 0..255.
## O cenário (terreno, muros iniciais, relés, torretas) é recriado pelo cliente a partir da
## missão + semente; o snapshot só leva o que muda.

enum T { SOLDIER = 1, ROBOT, BUG, LARVA, MOTHER, NEST, HEART, FLOWER, PICKUP, BUGGY, DROPSHIP }

const BUG_T := { "bug": T.BUG, "larva": T.LARVA, "mother": T.MOTHER }
const KIND_OF := { T.BUG: "bug", T.LARVA: "larva", T.MOTHER: "mother", T.NEST: "nest", T.HEART: "heart" }
const PICKS := ["reinforce", "airstrike", "robot", "flame", "plasma", "grenades"]
const WEAPONS := ["mg", "flame", "plasma"]
const PROJ := ["bullet", "shell", "flame", "plasma", "spit"]
const STATS := ["kills", "mothers", "nests", "flowers", "troops_lost", "commander_deaths", "pickups"]
const MAX_PROJ := 400


static func _a8(a: float) -> int:
	return posmod(roundi(a / TAU * 256.0), 256)


static func _ang(v: int) -> float:
	return v * TAU / 256.0


static func _u8(v: float) -> int:
	return clampi(roundi(v), 0, 255)


static func _ratio(hp: float, mx: float) -> int:
	return _u8(hp / maxf(mx, 0.001) * 255.0)


static func _put_pos(b: StreamPeerBuffer, p: Vector2) -> void:
	b.put_16(clampi(roundi(p.x * 2.0), -32768, 32767))
	b.put_16(clampi(roundi(p.y * 2.0), -32768, 32767))


static func _get_pos(b: StreamPeerBuffer) -> Vector2:
	var x := b.get_16()
	var y := b.get_16()
	return Vector2(x, y) * 0.5


# =============================================================================
# codificação (host)
# =============================================================================

static func encode(w: World) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(w.frame)
	b.put_float(w.time)
	b.put_u16(clampi(w.troops, 0, 65535))
	b.put_32(w.merit)
	b.put_u8(0 if w.outcome == "" else (1 if w.outcome == "victory" else 2))
	b.put_utf8_string(w.outcome_reason)
	b.put_utf8_string(JSON.stringify(w.objective_parts())) # [chave, valores]: o cliente traduz
	for k in STATS:
		b.put_u16(clampi(int(w.stats[k]), 0, 65535))

	# comandantes
	b.put_u8(w.commanders.size())
	for c in w.commanders:
		_put_pos(b, c.position)
		b.put_u8(_a8(c.face))
		var fl := 0
		if c.dead:
			fl |= 1
		if c.moving:
			fl |= 2
		if c.carrying:
			fl |= 4
		if c.flash > 0.0:
			fl |= 8
		if c.disconnected:
			fl |= 16
		b.put_u8(fl)
		b.put_u8(int(c.walk_t * 4.0) % 256)
		b.put_u8(_u8(c.hp * 10.0))
		b.put_u8(_u8(c.invuln * 20.0))
		b.put_u8(_u8(c.respawn_timer * 10.0))
		b.put_u8(_u8(c.drop_t * 100.0))
		b.put_u8(maxi(0, WEAPONS.find(c.weapon)))
		b.put_16(clampi(c.ammo, -1, 32767))
		b.put_u8(c.grenades)
		b.put_u8(maxi(0, Bal.ORDERS.find(c.order)))

	# entidades com uid
	var n := 0
	for arr in [w.soldiers, w.robots, w.bugs, w.nests, w.flowers, w.pickups, w.vehicles]:
		for u in arr:
			if not u.dead:
				n += 1
	b.put_u16(n)
	for s in w.soldiers:
		if s.dead:
			continue
		_head(b, s.uid, T.SOLDIER, s.position)
		b.put_u8(_a8(s.face))
		b.put_u8((1 if s.moving else 0) | (2 if s.flash > 0.0 else 0))
		b.put_u8(int(s.walk_t * 4.0) % 256)
		b.put_u8(_u8(s.drop_t * 100.0))
		b.put_u8(s.pid)
	for r in w.robots:
		if r.dead:
			continue
		_head(b, r.uid, T.ROBOT, r.position)
		b.put_u8(_a8(r.face))
		b.put_u8(_a8(r.turret))
		b.put_u8(1 if r.flash > 0.0 else 0)
		b.put_u8(_ratio(r.hp, r.max_hp))
	for g in w.bugs:
		if g.dead:
			continue
		_head(b, g.uid, BUG_T[g.kind], g.position)
		b.put_u8(_a8(g.face))
		var bf := 0
		if g.moving:
			bf |= 1
		if g.flash > 0.0:
			bf |= 2
		if g.frenzy:
			bf |= 4
		if g.spitter:
			bf |= 8
		if g.charge_t > 0.0:
			bf |= 16
		b.put_u8(bf)
		b.put_u8(int(g.walk_t * 4.0) % 256)
		b.put_u8(_u8(g.attacking * 100.0))
		b.put_u8(_u8(g.emerge * 100.0))
		b.put_u8(_ratio(g.hp, g.max_hp))
	for ne in w.nests:
		if ne.dead:
			continue
		_head(b, ne.uid, T.HEART if ne.kind == "heart" else T.NEST, ne.position)
		b.put_u8(1 if ne.flash > 0.0 else 0)
		b.put_u8(_ratio(ne.hp, ne.max_hp))
	for f in w.flowers:
		if f.dead:
			continue
		_head(b, f.uid, T.FLOWER, f.position)
		b.put_u8(_u8(f.grow * 10.0))
	for pk in w.pickups:
		if pk.dead:
			continue
		_head(b, pk.uid, T.PICKUP, pk.position)
		b.put_u8(maxi(0, PICKS.find(pk.pick)))
		b.put_u8(255 if pk.life < 0.0 else _u8(pk.life * 10.0))
	for v in w.vehicles:
		if v.dead:
			continue
		if v.kind == "buggy":
			_head(b, v.uid, T.BUGGY, v.position)
			b.put_u8(_a8(v.face))
			b.put_u8(1 if v.visible else 0)
		else:
			_head(b, v.uid, T.DROPSHIP, v.position)
			b.put_u8((1 if v.visible else 0) | (2 if v.vx < 0.0 else 0))

	# cenário que muda
	var gen = w.generator
	b.put_u8(1 if gen != null else 0)
	if gen != null:
		b.put_u16(clampi(roundi(gen.hp * 10.0), 0, 65535))
		b.put_u8((1 if gen.dead else 0) | (2 if gen.flash > 0.0 else 0))
	b.put_u8(1 if w.crystal != null else 0)
	if w.crystal != null:
		_put_pos(b, w.crystal.p)
		b.put_u8(1 if w.crystal.carried else 0)
	b.put_u8(w.switches.size())
	for sw in w.switches:
		b.put_u8(_u8(sw.progress * 255.0))
		b.put_u8(1 if sw.active else 0)
	b.put_u8(w.turrets.size())
	for tu in w.turrets:
		b.put_u8(_a8(tu.aim))
		b.put_u8(1 if tu.operator != null else 0)
	b.put_u16(w.walls.size())
	for cell in w.walls:
		b.put_u16(cell)
		b.put_u8(_ratio(w.grid.hp[cell], w.grid.max_hp[cell]))
	b.put_u8(mini(255, w.hazards.size()))
	for i in mini(255, w.hazards.size()):
		var hz: Dictionary = w.hazards[i]
		_put_pos(b, hz.p)
		b.put_u8(_u8(hz.r))
		b.put_u8(_u8(hz.t * 10.0))
	var amb: Array = []
	for a in w.ambushes:
		if not a.done:
			amb.append(a)
	b.put_u8(mini(255, amb.size()))
	for i in mini(255, amb.size()):
		var am: Dictionary = amb[i]
		_put_pos(b, am.p)
		b.put_u8(_u8(am.t * 100.0))
		b.put_u8(1 if am.get("edge", false) else 0)

	# projéteis e granadas (o cliente os move entre snapshots)
	var pl: Array = w.projectiles.list
	var np := mini(MAX_PROJ, pl.size())
	b.put_u16(np)
	for i in np:
		var pr: Dictionary = pl[i]
		b.put_u8(maxi(0, PROJ.find(pr.kind)))
		_put_pos(b, pr.p)
		var v: Vector2 = pr.v
		b.put_16(clampi(roundi(v.x), -32768, 32767))
		b.put_16(clampi(roundi(v.y), -32768, 32767))
		b.put_u8(_u8(pr.life / maxf(pr.max, 0.001) * 255.0))
	var gl: Array = w.projectiles.grenades
	b.put_u8(mini(255, gl.size()))
	for i in mini(255, gl.size()):
		var gr: Dictionary = gl[i]
		_put_pos(b, gr.a)
		_put_pos(b, gr.b)
		b.put_u8(_u8(gr.t / maxf(gr.T, 0.001) * 255.0))
		b.put_u8(_u8(gr.T * 50.0))
		b.put_u8((1 if gr.bomb else 0) | (2 if gr.acid else 0))
	return b.data_array


static func _head(b: StreamPeerBuffer, uid: int, t: int, p: Vector2) -> void:
	b.put_u32(uid)
	b.put_u8(t)
	_put_pos(b, p)


# =============================================================================
# decodificação (cliente)
# =============================================================================

static func decode(bytes: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var s := {}
	s.tick = b.get_u32()
	s.time = b.get_float()
	s.troops = b.get_u16()
	s.merit = b.get_32()
	var oc := b.get_u8()
	s.outcome = "" if oc == 0 else ("victory" if oc == 1 else "defeat")
	s.reason = b.get_utf8_string()
	var obj = JSON.parse_string(b.get_utf8_string())
	s.objective = obj if obj is Array else ["", {}]
	var st := {}
	for k in STATS:
		st[k] = b.get_u16()
	s.stats = st

	var cmds: Array = []
	for i in b.get_u8():
		var c := {}
		c.p = _get_pos(b)
		c.face = _ang(b.get_u8())
		var fl := b.get_u8()
		c.dead = (fl & 1) != 0
		c.moving = (fl & 2) != 0
		c.carrying = (fl & 4) != 0
		c.flash = (fl & 8) != 0
		c.disconnected = (fl & 16) != 0
		c.walk = b.get_u8() / 4.0
		c.hp = b.get_u8() / 10.0
		c.invuln = b.get_u8() / 20.0
		c.respawn = b.get_u8() / 10.0
		c.drop = b.get_u8() / 100.0
		c.weapon = WEAPONS[mini(b.get_u8(), WEAPONS.size() - 1)]
		c.ammo = b.get_16()
		c.grenades = b.get_u8()
		c.order = Bal.ORDERS[mini(b.get_u8(), Bal.ORDERS.size() - 1)]
		cmds.append(c)
	s.cmds = cmds

	var ents: Array = []
	var by_uid := {}
	for i in b.get_u16():
		var e := {}
		e.uid = b.get_u32()
		e.t = b.get_u8()
		e.p = _get_pos(b)
		e.face = 0.0
		match e.t:
			T.SOLDIER:
				e.face = _ang(b.get_u8())
				var fl := b.get_u8()
				e.moving = (fl & 1) != 0
				e.flash = (fl & 2) != 0
				e.walk = b.get_u8() / 4.0
				e.drop = b.get_u8() / 100.0
				e.pid = b.get_u8()
			T.ROBOT:
				e.face = _ang(b.get_u8())
				e.turret = _ang(b.get_u8())
				e.flash = (b.get_u8() & 1) != 0
				e.hp = b.get_u8() / 255.0
			T.BUG, T.LARVA, T.MOTHER:
				e.face = _ang(b.get_u8())
				var bf := b.get_u8()
				e.moving = (bf & 1) != 0
				e.flash = (bf & 2) != 0
				e.frenzy = (bf & 4) != 0
				e.spitter = (bf & 8) != 0
				e.charge = (bf & 16) != 0
				e.walk = b.get_u8() / 4.0
				e.attack = b.get_u8() / 100.0
				e.emerge = b.get_u8() / 100.0
				e.hp = b.get_u8() / 255.0
			T.NEST, T.HEART:
				e.flash = (b.get_u8() & 1) != 0
				e.hp = b.get_u8() / 255.0
			T.FLOWER:
				e.grow = b.get_u8() / 10.0
			T.PICKUP:
				e.pick = PICKS[mini(b.get_u8(), PICKS.size() - 1)]
				var lf := b.get_u8()
				e.life = -1.0 if lf == 255 else lf / 10.0
			T.BUGGY:
				e.face = _ang(b.get_u8())
				e.visible = b.get_u8() != 0
			T.DROPSHIP:
				var df := b.get_u8()
				e.visible = (df & 1) != 0
				e.flip = (df & 2) != 0
		ents.append(e)
		by_uid[e.uid] = e
	s.ents = ents
	s.by_uid = by_uid

	s.gen = null
	if b.get_u8() == 1:
		var hp := b.get_u16() / 10.0
		var gf := b.get_u8()
		s.gen = { hp = hp, dead = (gf & 1) != 0, flash = (gf & 2) != 0 }
	s.crystal = null
	if b.get_u8() == 1:
		var cp := _get_pos(b)
		s.crystal = { p = cp, carried = b.get_u8() != 0, carrier = null }
	var sws: Array = []
	for i in b.get_u8():
		var pr := b.get_u8() / 255.0
		sws.append({ progress = pr, active = b.get_u8() != 0 })
	s.switches = sws
	var tus: Array = []
	for i in b.get_u8():
		var aim := _ang(b.get_u8())
		tus.append({ aim = aim, manned = b.get_u8() != 0 })
	s.turrets = tus
	var walls := {}
	for i in b.get_u16():
		var cell := b.get_u16()
		walls[cell] = b.get_u8() / 255.0
	s.walls = walls
	var hzs: Array = []
	for i in b.get_u8():
		var hp2 := _get_pos(b)
		var hr := float(b.get_u8())
		hzs.append({ p = hp2, r = hr, t = b.get_u8() / 10.0, tick = 0.0 })
	s.hazards = hzs
	var ams: Array = []
	for i in b.get_u8():
		var ap := _get_pos(b)
		var at := b.get_u8() / 100.0
		ams.append({ p = ap, t = at, n = 0, done = false, edge = b.get_u8() != 0 })
	s.ambushes = ams

	var proj: Array = []
	for i in b.get_u16():
		var k: String = PROJ[mini(b.get_u8(), PROJ.size() - 1)]
		var pp := _get_pos(b)
		var vx := b.get_16()
		var vy := b.get_16()
		var lf2 := b.get_u8() / 255.0
		proj.append({ kind = k, p = pp, v = Vector2(vx, vy), life = lf2, max = 1.0 })
	s.proj = proj
	var gren: Array = []
	for i in b.get_u8():
		var ga := _get_pos(b)
		var gb := _get_pos(b)
		var frac := b.get_u8() / 255.0
		var tt := b.get_u8() / 50.0
		var gf2 := b.get_u8()
		gren.append({ a = ga, b = gb, frac = frac, T = tt, bomb = (gf2 & 1) != 0, acid = (gf2 & 2) != 0 })
	s.gren = gren
	return s
