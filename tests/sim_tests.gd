class_name SimTests
extends Node
## Testes headless da simulação. Rodar:
##   godot --headless --path . -- --test
## Sai com código 0 se tudo passou, 1 se algo falhou. Imprime desempenho por missão.

var main: Node
var failures: Array = []
var passes := 0


func run(m: Node) -> void:
	main = m
	if main.args.has("timeline"):
		_timeline(main.args.timeline)
		get_tree().quit(0)
		return
	print("=== ENXAME 2199 — testes da simulação ===")
	_test_missions_valid()
	_test_flowfield()
	for i in Missions.count():
		_test_mission_runs(i)
	_test_pickups()
	_test_flower_to_mother()
	_test_retrieve()
	_test_commander_respawn()
	_test_survive_ends()
	_test_hold_quota()
	_test_hordes_spawn()
	_test_area_secure()
	_test_turret_manned()
	_test_mother_mortar_and_brood()
	_test_cmd_input_roundtrip()
	_test_snapshot_roundtrip()
	_test_loopback_replica()
	_test_visuals()
	if main.args.has("probe"):
		# --probe (m3, m4, m5) ou --probe=m5; --probe-diff=facil|normal|dificil; --probe-seeds=3
		var ids: Array = ["m3", "m4", "m5"] if main.args.probe == "1" else String(main.args.probe).split(",")
		var dk: String = main.args.get("probe-diff", "normal")
		var seeds := int(main.args.get("probe-seeds", "1"))
		for id in ids:
			for k in seeds:
				_probe_defense(id, dk, 21 + k)
	_test_stress()
	print("=== %d ok, %d falhas ===" % [passes, failures.size()])
	for f in failures:
		print("FALHA: ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures.append(msg)


func _new_world(i: int, players: int = 1, diff: String = "normal", seed_v: int = 7) -> World:
	var w := World.new()
	add_child(w)
	w.setup(i, diff, players, seed_v)
	return w


## Bot simples: anda até o inimigo mais próximo mantendo distância e atira sem parar.
func _bot(w: World) -> void:
	if w.frame % 12 == 0:
		w._flow_enemy() # o bot navega pelo campo de inimigos (jogadores reais não precisam)
	for c in w.commanders:
		if c.dead:
			continue
		var t = w.pick_target(c, 400.0)
		var dir := Vector2.ZERO
		if t != null:
			var to: Vector2 = t.position - c.position
			if to.length() > 200.0:
				dir = w.ff_enemy.dir_from(c.position)
			elif to.length() < 110.0:
				dir = -to.normalized()
			c.face = to.angle()
			c.in_strafe = true
		else:
			dir = w.ff_enemy.dir_from(c.position)
			c.in_strafe = false
		c.in_move = dir
		c.in_fire = true
		c.in_grenade = w.rng.randf() < 0.01


func _run(w: World, seconds: float, bot: bool = true) -> float:
	var frames := int(seconds * 60.0)
	var t0 := Time.get_ticks_usec()
	for f in frames:
		if bot:
			_bot(w)
		w.update(1.0 / 60.0)
		if w.outcome != "" and w.outcome_timer > 0.5:
			break
	return float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, frames)


func _test_missions_valid() -> void:
	for i in Missions.count():
		var m := Missions.get_mission(i)
		var errs := Missions.validate(m)
		check(errs.is_empty(), "missão %s inválida: %s" % [m.id, str(errs)])


func _test_flowfield() -> void:
	var g := Grid.new()
	g.kind[g.idx(5, 5)] = Grid.ROCK
	var ff := FlowField.new(g, Grid.MODE_HUMAN)
	ff.compute([g.center(0, 0)])
	check(ff.at(g.center(0, 0)) == 0.0, "flowfield: fonte com custo 0")
	check(ff.at(g.center(5, 5)) == INF, "flowfield: rocha inalcançável")
	check(ff.dir_from(g.center(3, 3)).length() > 0.9, "flowfield: direção normalizada")


func _print_profile(w: World, label: String) -> void:
	var total := 0
	for k in w.profile:
		total += w.profile[k]
	var parts: Array = []
	var keys := w.profile.keys()
	keys.sort_custom(func(a, b): return w.profile[a] > w.profile[b])
	for k in keys:
		parts.append("%s %d%%" % [k, roundi(100.0 * w.profile[k] / maxf(1.0, total))])
	print("   perfil %s: %s" % [label, ", ".join(parts)])


func _test_mission_runs(i: int) -> void:
	var w := _new_world(i, 2)
	w.profiling = true
	var ms := _run(w, 45.0)
	_print_profile(w, "missão %d" % (i + 1))
	var s := w.summary()
	print("missão %d (%s): %.2f ms/frame · t=%.0fs bugs=%d ninhos=%d tropas=%d abates=%d resultado=%s" % [
		i + 1, w.mission.name, ms, s.time, s.bugs, s.nests, s.troops, s.stats.kills, s.outcome])
	check(s.stats.kills > 0 or s.outcome != "", "missão %d: nenhum abate em 45 s" % (i + 1))
	check(ms < 12.0, "missão %d: lenta demais (%.1f ms/frame)" % [i + 1, ms])
	w.queue_free()


func _test_pickups() -> void:
	for kind in ["reinforce", "airstrike", "robot", "flame", "plasma", "grenades"]:
		var w := _new_world(0)
		var c: Commander = w.commanders[0]
		var before := w.troops
		var g_before := c.grenades
		w.apply_pickup(kind, c)
		if kind == "grenades":
			check(c.grenades == mini(Bal.COMMANDER.max_grenades, g_before + Bal.PICKUPS.grenade_pack), "granadas não somaram")
		_run(w, 8.0)
		match kind:
			"reinforce":
				check(w.troops > before, "reforço: tropas não subiram (%d -> %d)" % [before, w.troops])
			"airstrike":
				check(w.troops > before, "ataque aéreo: soldados não desceram")
			"robot":
				check(w.stats.pickups == 1, "robô: pickup não contou")
			"flame", "plasma":
				check(c.weapon == kind or c.weapon == "mg", "arma %s não equipou" % kind)
		w.queue_free()


func _test_flower_to_mother() -> void:
	var w := _new_world(1)
	var f = null
	for fl in w.flowers:
		f = fl
		break
	check(f != null, "missão 2 sem flores")
	if f == null:
		return
	f.grow = 0.0
	var b := w.spawn_bug("bug", f.position + Vector2(4, 0), 0.0)
	var mothers_before := 0
	for x in w.bugs:
		if x.kind == "mother":
			mothers_before += 1
	w.update(1.0 / 60.0)
	var mothers := 0
	for x in w.bugs:
		if x.kind == "mother":
			mothers += 1
	check(mothers == mothers_before + 1, "flor não virou matriarca (%d -> %d)" % [mothers_before, mothers])
	w.queue_free()


func _test_retrieve() -> void:
	var w := _new_world(5)
	w.debug_kill_nests()
	w.update(1.0 / 60.0)
	check(w.crystal != null, "coração destruído não liberou cristal")
	if w.crystal == null:
		return
	var c: Commander = w.commanders[0]
	c.position = w.crystal.p
	c.invuln = 99.0
	w.update(1.0 / 60.0)
	check(w.crystal.carried, "comandante não pegou o cristal")
	c.position = w.extraction
	w.update(1.0 / 60.0)
	check(w.outcome == "victory", "extração não deu vitória (outcome=%s)" % w.outcome)
	w.queue_free()


func _test_commander_respawn() -> void:
	var w := _new_world(0)
	var c: Commander = w.commanders[0]
	var before := w.troops
	c.invuln = 0.0
	w.damage_human(c, 99.0)
	check(c.dead and w.troops == before - 1, "morte do comandante não custou 1 tropa")
	for i in int((Bal.TROOPS.commander_respawn + 0.5) * 60.0):
		w.update(1.0 / 60.0)
	check(not c.dead, "comandante não renasceu em 10 s")
	w.queue_free()


func _test_stress() -> void:
	var w := _new_world(0, 4)
	for i in 230:
		var b := w.spawn_bug("bug", Vector2(900 + (i % 15) * 18, 60 + (i / 15) * 34), 0.0)
		if b != null:
			b.hp = 9999.0 # vivos o teste inteiro: mede carga sustentada
			b.max_hp = 9999.0
	for i in 36:
		w.spawn_soldier(Vector2(200 + (i % 6) * 24, 200 + (i / 6) * 24), i % 4, 0.0)
	for c in w.commanders:
		c.god = true
	w.profiling = true
	var ms := _run(w, 6.0)
	_print_profile(w, "estresse")
	print("estresse: %d insetos, %d soldados: %.2f ms/frame" % [w.bugs.size(), w.soldiers.size(), ms])
	# 200 insetos amontoados sobre 4 comandantes imortais: pior caso artificial (o jogo real fica em 1–3 ms)
	check(ms < 20.0, "estresse: %.1f ms/frame (meta < 20)" % ms)
	w.queue_free()


func _idx(id: String) -> int:
	for i in Missions.count():
		if Missions.get_mission(i).id == id:
			return i
	return -1


func _god(w: World) -> void:
	for c in w.commanders:
		c.god = true


## Bug relatado: defesa com tudo limpo ficava com o relógio correndo sem fim.
func _test_survive_ends() -> void:
	var w := _new_world(_idx("m3"))
	_god(w)
	w.time = w.mission.objective.time - 0.01
	w.update(1.0 / 60.0)
	check(w.outcome == "victory", "defesa por tempo não terminou (outcome=%s)" % w.outcome)
	w.queue_free()


func _test_hold_quota() -> void:
	var w := _new_world(_idx("m4"))
	_god(w)
	w.update(1.0 / 60.0)
	check(w.outcome == "", "defesa por abates terminou cedo")
	w.stats.kills = int(w.mission.objective.kills * w.diff.spawn)
	w.update(1.0 / 60.0)
	check(w.outcome == "victory", "cota de abates não deu vitória")
	w.queue_free()


func _test_hordes_spawn() -> void:
	var w := _new_world(_idx("m3"))
	_god(w)
	var before := w.bugs.size()
	_run(w, float(w.settings.hordes.start) + 5.0, false)
	check(w.horde_count > 0, "nenhuma horda depois do início configurado")
	check(w.stats.kills + w.bugs.size() > before, "hordas não trouxeram aracnídeos")
	w.queue_free()


func _test_area_secure() -> void:
	var w := _new_world(_idx("m3"))
	_god(w)
	w.settings.erase("hordes")
	w.debug_kill_nests()
	for b in w.bugs:
		w.kill_enemy(b)
	_run(w, 4.0, false)
	check(w.outcome == "victory", "defesa sem inimigos e sem hordas não terminou (área segura)")
	w.queue_free()


func _test_turret_manned() -> void:
	var w := _new_world(_idx("m4"))
	_god(w)
	var manned := false
	for f in 300:
		w.update(1.0 / 60.0)
		for tu in w.turrets:
			if tu.operator != null:
				manned = true
		if manned:
			break
	check(not w.turrets.is_empty(), "missão de trincheiras sem metralhadoras")
	check(manned, "nenhum soldado assumiu uma metralhadora de ponto em 5 s")
	w.queue_free()


func _test_mother_mortar_and_brood() -> void:
	var w := _new_world(0)
	_god(w)
	var c: Commander = w.commanders[0]
	var m := w.spawn_bug("mother", c.position + Vector2(0, 250), 0.0)
	m.mortar_cd = 0.1
	var saw_pool := false
	for f in 240:
		w.update(1.0 / 60.0)
		if not w.hazards.is_empty():
			saw_pool = true
			break
	check(saw_pool, "matriarca não lançou morteiro de ácido em 4 s")
	var larvae_before := 0
	for b in w.bugs:
		if b.kind == "larva":
			larvae_before += 1
	if not m.dead:
		w.damage_enemy(m, m.max_hp * 0.4)
		var larvae := 0
		for b in w.bugs:
			if b.kind == "larva":
				larvae += 1
		check(larvae >= larvae_before + Bal.MOTHER.brood_burst, "matriarca ferida não soltou ninhada")
	w.queue_free()


## Sonda de balanceamento (só com --probe): bot que defende o gerador, 1 jogador, Soldado.
func _probe_defense(id: String, dk: String = "normal", seed_v: int = 21) -> void:
	var w := _new_world(_idx(id), 1, dk, seed_v)
	var c: Commander = w.commanders[0]
	var limit: float = float(w.mission.objective.get("time", 400.0)) + 5.0
	var frames := int(limit * 60.0)
	for f in frames:
		if not c.dead:
			var home := w.lz
			var to_home := home - c.position
			c.in_move = to_home.normalized() if to_home.length() > 60.0 else Vector2.ZERO
			var t = w.pick_target(c, 400.0)
			c.in_strafe = true
			c.in_fire = t != null
			if t != null:
				c.face = (t.position - c.position).angle()
				w.bug_hash.query(t.position, 80.0, w.tmp_b)
				c.in_grenade = w.tmp_b.size() >= 4 and c.grenade_cd <= 0.0
		w.update(1.0 / 60.0)
		if w.outcome != "":
			break
	var gp := 0
	if w.generator != null:
		gp = roundi(w.generator.hp / w.generator.max_hp * 100.0)
	print("SONDA %s %s semente %d (%s): %s em %ds · %s · gerador %d%% · abates %d · tropas %d · matriarcas %d" % [
		id, dk, seed_v, w.mission.name, w.outcome if w.outcome != "" else "sem fim", int(w.time), w.outcome_reason, gp,
		w.stats.kills, w.troops, w.stats.mothers])
	w.queue_free()


## Depuração de balanceamento (--timeline=m3): estado da defesa segundo a segundo, bot parado no gerador.
func _timeline(id: String) -> void:
	var w := _new_world(_idx(id), 1, "normal", 21)
	var c: Commander = w.commanders[0]
	for f in 60 * 60:
		var t = w.pick_target(c, 400.0)
		c.in_move = Vector2.ZERO
		c.in_strafe = true
		c.in_fire = t != null
		if t != null:
			c.face = (t.position - c.position).angle()
		w.update(1.0 / 60.0)
		if f % 60 == 0 and w.generator != null:
			var near := 0
			for b in w.bugs:
				if b.position.distance_to(w.generator.position) < 100.0:
					near += 1
			print("t=%2d gerador=%3d muros=%d insetos=%d perto_do_gerador=%d matriarcas=%d soldados=%d" % [
				int(w.time), int(w.generator.hp), w.walls.size(), w.bugs.size(), near, w.mothers.size(), w.soldiers.size()])
		if w.outcome != "":
			print("FIM ", w.outcome, " — ", w.outcome_reason, " t=", int(w.time))
			break
	w.queue_free()


# =============================================================================
# rede — fase 0
# =============================================================================

func _test_cmd_input_roundtrip() -> void:
	var c := CmdInput.new()
	c.move = Vector2(cos(PI / 4.0), sin(PI / 4.0))
	c.fire = true
	c.strafe = true
	c.grenade_n = 200
	c.order_n = 7
	c.order_set = 2
	c.order_set_n = 9
	var d := CmdInput.decode(c.encode())
	check(c.encode().size() == 6, "CmdInput não tem 6 bytes")
	check(d.move.distance_to(c.move) < 0.08 and d.fire and d.strafe, "CmdInput: movimento/botões não sobreviveram")
	check(d.grenade_n == 200 and d.order_n == 7 and d.order_set == 2 and d.order_set_n == 9, "CmdInput: contadores não sobreviveram")
	# contador mudou => aperto aplicado uma vez
	var w := _new_world(0)
	var cm: Commander = w.commanders[0]
	var prev := d.copy()
	d.grenade_n = 201
	d.apply_to(cm, prev)
	check(cm.in_grenade, "CmdInput: aperto de granada não disparou")
	w.queue_free()


func _count_ents(w: World) -> int:
	var n := 0
	for arr in [w.soldiers, w.robots, w.bugs, w.nests, w.flowers, w.pickups, w.vehicles]:
		for u in arr:
			if not u.dead:
				n += 1
	return n


func _test_snapshot_roundtrip() -> void:
	var w := _new_world(_idx("m4"), 2)
	w.apply_pickup("airstrike", w.commanders[0])
	_run(w, 6.0)
	var bytes := Snapshot.encode(w)
	var s := Snapshot.decode(bytes)
	print("snapshot: %d bytes, %d entidades, %d projéteis" % [bytes.size(), s.ents.size(), s.proj.size()])
	check(s.tick == w.frame and is_equal_approx(s.time, w.time), "snapshot: tick/tempo")
	check(s.ents.size() == _count_ents(w), "snapshot: %d entidades (mundo tem %d)" % [s.ents.size(), _count_ents(w)])
	check(s.walls.size() == w.walls.size() and s.turrets.size() == w.turrets.size(), "snapshot: muros/torretas")
	check(s.cmds.size() == 2 and s.cmds[0].p.distance_to(w.commanders[0].position) <= 0.5, "snapshot: comandantes")
	check(s.objective == w.objective_text(), "snapshot: texto do objetivo")
	var ok_pos := true
	for e in s.ents:
		var found := false
		for arr in [w.soldiers, w.bugs, w.nests]:
			for u in arr:
				if u.uid == e.uid:
					found = true
					if u.position.distance_to(e.p) > 0.5:
						ok_pos = false
		if not found:
			continue
	check(ok_pos, "snapshot: posição com erro > 0,5 px")
	w.queue_free()


func _sim_hash(w: World) -> String:
	var acc := 0.0
	for b in w.bugs:
		acc += b.position.x * 1.3 + b.position.y * 0.7 + b.hp
	for s in w.soldiers:
		acc += s.position.x * 0.9 + s.position.y * 1.1 + s.hp
	return "%d|%d|%d|%d|%.2f|%.2f" % [w.frame, w.troops, w.stats.kills, w.bugs.size(), acc, w.commanders[0].position.x]


## A parte visual (luz, sombra, relevo) só lê o estado: com ela ligada, a simulação tem de dar
## exatamente o mesmo resultado. Também confere os limites do conjunto de luzes.
func _test_visuals() -> void:
	var i := _idx("m5")
	var plain := _new_world(i, 1, "normal", 31)
	World.headless_visuals = true
	var lit := _new_world(i, 1, "normal", 31)
	World.headless_visuals = false
	check(not plain.lights.active and plain.shadows == null, "visual: mundo sem janela não deveria criar luzes")
	check(lit.lights.active and lit.shadows != null, "visual: luzes e sombras não foram criadas")
	check(lit.lights.fixed.size() >= 10, "visual: poucas luzes fixas na fortaleza (%d)" % lit.lights.fixed.size())
	_run(plain, 30.0)
	_run(lit, 30.0)
	check(_sim_hash(plain) == _sim_hash(lit), "visual: ligar luz e sombra mudou a simulação (%s x %s)" % [_sim_hash(plain), _sim_hash(lit)])
	var L := lit.lights
	L.update(2.0) # apaga os clarões que sobraram do combate
	check(L.flashes.is_empty(), "visual: clarões não apagaram")
	for k in 3:
		L.flash(Vector2(300, 300), Color.WHITE, 60.0, 1.0, 5.0, "t")
	check(L.flashes.size() == 1, "visual: clarões próximos do mesmo tipo deveriam se fundir (%d)" % L.flashes.size())
	for k in 60:
		L.flash(Vector2(40 + k * 20, 500), Color.WHITE, 60.0, 1.0, 5.0)
	check(L.flashes.size() <= Lighting.MAX_FLASH, "visual: clarões passaram do limite (%d)" % L.flashes.size())
	var lamp = null
	for f in L.fixed:
		if f.kind == "lamp":
			lamp = f
			break
	check(lamp != null, "visual: fortaleza sem postes")
	if lamp != null:
		var wl: Prop = lamp.owner
		lit.walls.erase(wl.cell)
		wl.queue_free()
		lit.walls_version += 1
		L.update(1.0 / 60.0)
		check(not lamp.l.enabled, "visual: o poste continuou aceso depois de o muro cair")
	plain.queue_free()
	lit.queue_free()


## Mundo-fantasma simula e grava; mundo-réplica só recebe snapshots + eventos (como um cliente).
func _test_loopback_replica() -> void:
	var seed_v := 77
	var sim := World.new()
	add_child(sim)
	sim.present = false
	sim.recording = true
	sim.setup(_idx("m3"), "normal", 2, seed_v)
	var rep_world := World.new()
	add_child(rep_world)
	rep_world.setup(_idx("m3"), "normal", 2, seed_v)
	var rep := Replica.new(rep_world)
	check(rep.nodes.size() == _count_ents(sim), "loopback: uids iniciais diferem (%d x %d)" % [rep.nodes.size(), _count_ents(sim)])
	var events_seen := 0
	for f in 60 * 20:
		_bot(sim)
		sim.update(1.0 / 60.0)
		if f % 2 == 0:
			rep.push_snapshot(Snapshot.encode(sim))
			events_seen += sim.net_events.size()
			rep.push_events(sim.net_events.duplicate())
			sim.net_events.clear()
		rep.render(1.0 / 60.0)
	rep.push_snapshot(Snapshot.encode(sim))
	rep.push_events(sim.net_events.duplicate())
	rep.catch_up()
	check(events_seen > 50, "loopback: poucos eventos gravados (%d)" % events_seen)
	check(rep_world.bugs.size() == sim.bugs.size() and rep_world.soldiers.size() == sim.soldiers.size(),
		"loopback: réplica com %d insetos/%d soldados, host com %d/%d" % [rep_world.bugs.size(), rep_world.soldiers.size(), sim.bugs.size(), sim.soldiers.size()])
	check(rep_world.walls.size() == sim.walls.size(), "loopback: muros destruídos não replicados")
	check(rep_world.troops == sim.troops and rep_world.objective_text() == sim.objective_text(), "loopback: HUD (tropas/objetivo)")
	var maxd := 0.0
	for b in sim.bugs:
		var rb = rep.nodes.get(b.uid)
		if rb != null:
			maxd = maxf(maxd, rb.position.distance_to(b.position))
	check(maxd <= 0.5, "loopback: posição de inseto difere %.2f px" % maxd)
	check(rep_world.decal_layer.decal_count() > 0, "loopback: decalques não chegaram à réplica")
	print("loopback: %d eventos, réplica %d insetos, %d decalques" % [events_seen, rep_world.bugs.size(), rep_world.decal_layer.decal_count()])
	sim.queue_free()
	rep_world.queue_free()
