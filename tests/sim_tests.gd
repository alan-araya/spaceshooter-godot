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
	print("=== ENXAME 2199 — testes da simulação ===")
	_test_missions_valid()
	_test_flowfield()
	for i in Missions.count():
		_test_mission_runs(i)
	_test_pickups()
	_test_flower_to_mother()
	_test_retrieve()
	_test_commander_respawn()
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
	var w := _new_world(4)
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
	check(ms < 16.0, "estresse: %.1f ms/frame (meta < 16)" % ms)
	w.queue_free()
