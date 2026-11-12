class_name Robot
extends Human
## Robô blindado de apoio: autônomo, caça inimigos pelo campo de fluxo e esmaga filhotes ao passar.

var target: Unit = null
var fire_cd := 0.0
var retarget_cd := 0.0
var turret := 0.0
var turret_sprite: Sprite2D


func setup(w: World, x: Vector2) -> void:
	world = w
	kind = "robot"
	position = x
	r = Bal.VEHICLES.robot_radius
	max_hp = Bal.VEHICLES.robot_hp
	hp = max_hp
	Art.apply(visual, "robot")
	visual.frame = 0
	turret_sprite = Sprite2D.new()
	Art.apply(turret_sprite, "robot")
	turret_sprite.frame = 1
	turret_sprite.position = Vector2(0, -6)
	add_child(turret_sprite)


func tick(dt: float) -> void:
	if flash > 0.0:
		flash -= dt
	fire_cd -= dt
	retarget_cd -= dt
	moving = false
	var reach: float = Bal.WEAPONS.cannon.reach
	if retarget_cd <= 0.0 or not Unit.ok(target):
		retarget_cd = 0.3
		target = world.pick_target(self, reach)
	var t: Unit = target if Unit.ok(target) else null
	var dist := position.distance_to(t.position) if t != null else INF
	if t == null or dist > 180.0:
		var dir := world.ff_enemy.dir_from(position)
		if dir != Vector2.ZERO and world.ff_enemy.at(position) > 2.0:
			world.grid.move_circle(self, dir * Bal.VEHICLES.robot_speed * dt, r, Grid.MODE_HUMAN)
			walk_t += dt * 4.0
			moving = true
			face = lerp_angle(face, dir.angle(), minf(1.0, dt * 6.0))
	push_out_of_structures()
	trample_flowers()
	# esmaga filhotes e aracnídeos ao passar
	var near: Array = world.tmp_b
	world.bug_hash.query(position, r + 12.0, near)
	for b in near:
		if not b.dead and b.kind != "mother" and position.distance_to(b.position) < r + b.r - 2.0:
			world.damage_enemy(b, 0.5)
	if t != null and dist <= reach + t.r:
		turret = lerp_angle(turret, (t.position - position).angle(), minf(1.0, dt * 10.0))
		if fire_cd <= 0.0:
			fire_cd = Bal.WEAPONS.cannon.interval
			fire_weapon(turret, "cannon", Bal.WEAPONS.cannon.spread, t)
			Sfx.play("cannon", position.x)
	else:
		turret = lerp_angle(turret, face, minf(1.0, dt * 4.0))


func sync_visual() -> void:
	visual.rotation = face
	turret_sprite.rotation = turret
	apply_flash()
	turret_sprite.self_modulate = visual.self_modulate
