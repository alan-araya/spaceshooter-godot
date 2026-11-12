class_name Soldier
extends Human
## Soldado aliado com IA por ordens (Normal / Atacar / Defender / Seguir).
## Melhorias sobre o MVP:
## - alvo por ameaça (matriarca, insetos perto do comandante, quem está colado) e sem desperdício de tiro;
## - recuo (kiting) quando um inseto encosta, sem fugir da posição;
## - formação em fileiras ATRÁS do comandante (não bloqueia o caminho nem a linha de tiro);
## - em Atacar, avança em leque (desvio lateral próprio) e para a uma distância de tiro.

var anchor := Vector2.ZERO
var wander := Vector2.ZERO
var wander_t := 0.0
var target: Unit = null
var fire_cd := 0.0
var retarget_cd := 0.0
var slot := 0 # posição na formação (entre os soldados do mesmo comandante)
var lane := 0.0 # desvio lateral pessoal (-1..1) para avançar em leque


func setup(w: World, x: Vector2, owner_pid: int) -> void:
	world = w
	kind = "soldier"
	pid = owner_pid
	position = x
	r = Bal.SOLDIER.radius
	max_hp = Bal.SOLDIER.hp
	hp = max_hp
	face = w.rng.randf_range(-PI, PI)
	walk_t = w.rng.randf() * 4.0
	anchor = x
	wander = x
	fire_cd = w.rng.randf() * 0.5
	retarget_cd = w.rng.randf() * Bal.SOLDIER.retarget
	lane = w.rng.randf_range(-1.0, 1.0)
	Art.apply(visual, "soldier")


func tick(dt: float) -> void:
	if flash > 0.0:
		flash -= dt
	if drop_t > 0.0:
		drop_t -= dt
		return
	fire_cd -= dt
	retarget_cd -= dt
	moving = false

	var S: Dictionary = Bal.SOLDIER
	if retarget_cd <= 0.0 or not Unit.ok(target):
		retarget_cd = S.retarget * world.rng.randf_range(0.8, 1.2)
		target = world.pick_target(self, S.reach)
	var t: Unit = target if Unit.ok(target) else null
	var dist_t := position.distance_to(t.position) if t != null else INF

	var cmd: Commander = world.commanders[pid]
	var order: String = cmd.order
	var speed: float = S.speed

	# recuo: inseto colado → um passo para trás, puxando para a âncora / comandante
	if t != null and dist_t < S.kite_dist and t is Bug and order != "atacar":
		var away := (position - t.position).normalized()
		var home := anchor
		if order == "seguir" and not cmd.dead:
			home = cmd.position
		var pull := (home - position).normalized() * 0.35
		world.grid.move_circle(self, (away + pull).normalized() * speed * 0.75 * dt, r, Grid.MODE_HUMAN)
		walk_t += dt * 7.0
		moving = true
	elif order == "atacar":
		_tick_attack(t, dist_t, speed, dt)
	elif order == "defender":
		move_toward_point(anchor, speed, dt, true)
	elif order == "seguir" and not cmd.dead:
		var dest := _formation_point(cmd)
		var d := position.distance_to(dest)
		if d > 6.0:
			move_toward_point(dest, speed * (1.2 if d > 120.0 else 1.0), dt, true)
	else:
		_tick_patrol(t, dist_t, speed, dt)

	separate(dt)
	push_out_of_structures()
	trample_flowers()

	if t != null and dist_t <= S.reach + t.r:
		face = (t.position - position).angle()
		if fire_cd <= 0.0:
			if not world.grid.line_clear(position, t.position, Grid.MODE_SHOT):
				target = null # perdeu a linha livre: escolhe outro alvo no próximo tick
				retarget_cd = 0.0
			elif _ally_in_line(t, dist_t):
				# aliado na frente: dá um passo para o lado e tenta de novo logo
				fire_cd = 0.08
				var side := (t.position - position).normalized().orthogonal() * (1.0 if lane >= 0.0 else -1.0)
				world.grid.move_circle(self, side * speed * 0.6 * dt * 4.0, r, Grid.MODE_HUMAN)
				walk_t += dt * 7.0
				moving = true
			else:
				fire_cd = S.fire_interval * world.rng.randf_range(0.85, 1.2)
				fire_weapon(face, "rifle", S.spread, t)
				if world.rng.randf() < 0.3:
					Sfx.play("shot_far", position.x)


## Há um humano no corredor de tiro entre mim e o alvo?
func _ally_in_line(t: Unit, dist_t: float) -> bool:
	var dir := (t.position - position) / maxf(dist_t, 0.001)
	var reach := minf(dist_t, 160.0)
	var near: Array = world.tmp_a
	world.human_hash.query(position + dir * reach * 0.5, reach * 0.5 + 12.0, near)
	for o in near:
		if o == self or o.dead:
			continue
		var rel: Vector2 = o.position - position
		var along := rel.dot(dir)
		if along <= 6.0 or along >= dist_t - 8.0:
			continue
		if absf(rel.cross(dir)) < 11.0:
			return true
	return false


func _tick_attack(t: Unit, dist_t: float, speed: float, dt: float) -> void:
	var S: Dictionary = Bal.SOLDIER
	if t == null or dist_t > S.attack_hold:
		var dir := world.ff_enemy.dir_from(position)
		if dir != Vector2.ZERO and world.ff_enemy.at(position) > 1.5:
			# avança em leque: desvio lateral pessoal some perto do alvo
			var spread_k := clampf((world.ff_enemy.at(position) - 3.0) / 6.0, 0.0, 1.0) * 0.45
			var v := (dir + dir.orthogonal() * lane * spread_k).normalized()
			world.grid.move_circle(self, v * speed * dt, r, Grid.MODE_HUMAN)
			walk_t += dt * 7.0
			moving = true
			if t == null:
				face = v.angle()
	elif dist_t < S.kite_dist:
		var away := (position - t.position).normalized()
		world.grid.move_circle(self, away * speed * 0.6 * dt, r, Grid.MODE_HUMAN)
		walk_t += dt * 7.0
		moving = true


func _tick_patrol(t: Unit, dist_t: float, speed: float, dt: float) -> void:
	var S: Dictionary = Bal.SOLDIER
	if t == null or dist_t > S.chase_radius:
		wander_t -= dt
		if wander_t <= 0.0:
			wander_t = world.rng.randf_range(1.5, 4.0)
			var a := world.rng.randf_range(0.0, TAU)
			var rr := world.rng.randf_range(0.0, S.patrol_radius)
			wander = anchor + Vector2(cos(a), sin(a)) * rr
		if move_toward_point(wander, speed * 0.45, dt, false) and t == null:
			face = (wander - position).angle()


## Ponto na formação: fileiras de 4 atrás do comandante, viradas para onde ele olha.
func _formation_point(cmd: Commander) -> Vector2:
	var S: Dictionary = Bal.SOLDIER
	var fwd := Vector2(cos(cmd.face), sin(cmd.face))
	var right := fwd.orthogonal()
	var row := slot / 4
	var col := slot % 4
	var back: float = S.follow_back + row * S.follow_row
	var lat: float = (col - 1.5) * S.follow_spread + (row % 2) * S.follow_spread * 0.5
	var p := cmd.position - fwd * back + right * lat
	p.x = clampf(p.x, 12.0, Bal.WORLD_W - 12.0)
	p.y = clampf(p.y, 12.0, Bal.WORLD_H - 12.0)
	return p


func sync_visual() -> void:
	sync_soldier_visual()
