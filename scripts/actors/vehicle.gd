class_name Vehicle
extends Node2D
## Veículos de apoio: buggy de reforço (atropela insetos e desembarca soldados) e nave (soldados/bombas).

var world: World
var kind := ""
var dead := false
var r := 18.0
var delay := 0.0
var face := 0.0
# buggy
var path: Array = []
var path_i := 0
var phase := "in"
var wait := 0.0
var carry := 2
var hit_cd := 0.0
var owner_pid := 0
# nave
var vx := 0.0
var drops: Array = [] # Dictionary: p, soldier, done
var sprite: Sprite2D


func setup_buggy(w: World, p: Array, d: float, n: int, pid: int) -> void:
	world = w
	kind = "buggy"
	path = p
	position = p[0]
	delay = d
	carry = n
	owner_pid = pid
	r = Bal.VEHICLES.buggy_radius
	sprite = Sprite2D.new()
	add_child(sprite)
	Art.apply(sprite, "buggy")
	visible = false


func setup_dropship(w: World, start: Vector2, speed: float, d: float, drop_list: Array, pid: int) -> void:
	world = w
	kind = "dropship"
	position = start
	vx = speed
	delay = d
	drops = drop_list
	owner_pid = pid
	sprite = Sprite2D.new()
	add_child(sprite)
	Art.apply(sprite, "dropship")
	sprite.flip_h = speed < 0.0
	visible = false


func tick(dt: float) -> void:
	if delay > 0.0:
		delay -= dt
		return
	visible = true
	if kind == "buggy":
		_tick_buggy(dt)
	else:
		_tick_dropship(dt)


func _tick_buggy(dt: float) -> void:
	hit_cd -= dt
	if phase == "drop":
		wait -= dt
		if wait <= 0.0:
			phase = "out"
			path.reverse()
			path_i = 0
		return
	if path_i >= path.size():
		if phase == "in":
			phase = "drop"
			wait = 0.9
			for i in carry:
				var a := face + PI / 2.0 + (i - (carry - 1) * 0.5) * 0.9
				world.drop_soldier(position + Vector2(cos(a), sin(a)) * 24.0, owner_pid, 0.0)
			Sfx.play("brake", position.x)
		else:
			dead = true
		return
	var target: Vector2 = path[path_i]
	var to := target - position
	var d := to.length()
	var slow := 0.6 if (phase == "in" and path_i >= path.size() - 2) else 1.0
	var step: float = Bal.VEHICLES.buggy_speed * dt * slow
	if d <= step:
		position = target
		path_i += 1
	else:
		position += to / d * step
	if d > 0.5:
		face = lerp_angle(face, to.angle(), minf(1.0, dt * 10.0))
	# atropela insetos
	var near: Array = world.tmp_b
	world.bug_hash.query(position, r + 16.0, near)
	for b in near:
		if b.dead:
			continue
		if position.distance_to(b.position) < r + b.r:
			if b.kind == "mother":
				if hit_cd <= 0.0:
					hit_cd = 0.3
					world.damage_enemy(b, 8.0)
			else:
				world.kill_enemy(b)
				Sfx.play("splat", b.position.x)
	if world.rng.randf() < dt * 12.0:
		world.fx.dust(position - Vector2(cos(face), sin(face)) * 20.0, 1)


func _tick_dropship(dt: float) -> void:
	position.x += vx * dt
	for d in drops:
		if d.done:
			continue
		var dp: Vector2 = d.p
		if (vx > 0.0 and position.x >= dp.x) or (vx < 0.0 and position.x <= dp.x):
			d.done = true
			if d.soldier:
				world.drop_soldier(dp, owner_pid, 0.45)
			else:
				world.projectiles.throw_grenade(dp + Vector2(0, -8), dp, 0.35, true)
	if position.x < -160.0 or position.x > Bal.WORLD_W + 160.0:
		dead = true


func sync_visual() -> void:
	if kind == "buggy":
		sprite.rotation = face
