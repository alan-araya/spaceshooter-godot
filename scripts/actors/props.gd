class_name Prop
extends Node2D
## Objetos de cenário e de missão que não são unidades com IA:
## flor, pickup, muro/portão, gerador, relé. Desenhados por sprite (Art) ou procedural (_draw).

var world: World
var kind := ""
var r := 10.0
var dead := false
var t := 0.0
var flash := 0.0
# flor
var grow := 0.0
# pickup
var pick := ""
var life := -1.0
# muro
var cell := -1
# gerador
var hp := 1.0
var max_hp := 1.0
# relé
var progress := 0.0
var active := false
# metralhadora de ponto
var claimed_by = null # Soldier que vai/está operando
var operator = null # quem opera neste quadro (soldado ou comandante)
var aim := -PI / 2.0
var fire_cd := 0.0
var retarget_cd := 0.0
var target = null

var sprite: Sprite2D


func setup_flower(w: World, x: Vector2, bloom: float) -> void:
	world = w
	kind = "flower"
	position = x
	r = Bal.FLOWER.radius
	grow = bloom
	t = w.rng.randf() * 6.0
	sprite = Sprite2D.new()
	add_child(sprite)
	Art.apply(sprite, "flower")


const PICK_FRAME := { reinforce = 0, airstrike = 1, robot = 2, flame = 3, plasma = 4, grenades = 5 }


func setup_pickup(w: World, x: Vector2, which: String, lifetime: float) -> void:
	world = w
	kind = "pickup"
	pick = which
	position = x
	r = Bal.PICKUPS.radius
	life = lifetime
	sprite = Sprite2D.new()
	add_child(sprite)
	Art.apply(sprite, "pickups")
	sprite.frame = PICK_FRAME.get(which, 0)


func setup_wall(w: World, x: Vector2, i: int, gate: bool) -> void:
	world = w
	kind = "gate" if gate else "wall"
	position = x
	cell = i


func setup_generator(w: World, x: Vector2) -> void:
	world = w
	kind = "generator"
	position = x
	r = 24.0
	max_hp = Bal.STRUCTURES.generator_hp
	hp = max_hp


func setup_turret(w: World, x: Vector2) -> void:
	world = w
	kind = "turret"
	position = x
	r = Bal.TURRET.radius
	aim = -PI / 2.0


func setup_switch(w: World, x: Vector2) -> void:
	world = w
	kind = "switch"
	position = x
	r = 14.0


func tick(dt: float) -> void:
	t += dt
	if flash > 0.0:
		flash -= dt
	if kind == "flower" and grow > 0.0:
		grow -= dt
	elif kind == "turret":
		_tick_turret(dt)


func _tick_turret(dt: float) -> void:
	fire_cd -= dt
	retarget_cd -= dt
	if claimed_by != null and not Unit.ok(claimed_by):
		claimed_by = null
	operator = null
	var man: float = Bal.TURRET.man_radius
	if claimed_by != null and claimed_by.position.distance_to(position) < man:
		operator = claimed_by
	else:
		for c in world.commanders:
			if not c.dead and not c.moving and c.position.distance_to(position) < man:
				operator = c
				break
	if operator == null:
		return
	var wp: Dictionary = Bal.WEAPONS.turret
	if retarget_cd <= 0.0 or not Unit.ok(target):
		retarget_cd = 0.2
		target = world.pick_target(self, wp.reach)
	if not Unit.ok(target):
		return
	var want: float = (target.position - position).angle()
	aim = lerp_angle(aim, want, minf(1.0, dt * 12.0))
	if fire_cd <= 0.0 and absf(angle_difference(aim, want)) < 0.3:
		fire_cd = wp.interval
		var muzzle := position + Vector2(cos(aim), sin(aim)) * 20.0 + Vector2(0, -10)
		world.projectiles.fire("turret", muzzle, aim + world.rng.randf_range(-wp.spread, wp.spread), target)
		world.fx.muzzle(muzzle, aim)
		Sfx.play("shot", position.x)


func sync_visual() -> void:
	match kind:
		"flower":
			sprite.frame = 0 if grow > 0.0 else 1
			var s := 0.6 + 0.4 * clampf(1.0 - grow / Bal.FLOWER.bloom_time, 0.0, 1.0)
			sprite.scale = Vector2(s, s)
			sprite.position.y = -6.0
		"pickup":
			sprite.position.y = -8.0 + sin(t * 4.0) * 3.0
			visible = life < 0.0 or life > 4.0 or int(life * 8.0) % 2 == 0
		_:
			queue_redraw()


func _draw() -> void:
	match kind:
		"wall", "gate":
			_draw_wall()
		"generator":
			_draw_generator()
		"switch":
			_draw_switch()
		"turret":
			_draw_turret()


func _draw_wall() -> void:
	var g := world.grid
	var hpk := 1.0
	if g.max_hp[cell] > 0.0:
		hpk = g.hp[cell] / g.max_hp[cell]
	var ts := float(Bal.TILE)
	var top := Rect2(-ts * 0.5, -ts * 0.5 - 14.0, ts, ts * 0.5)
	var front := Rect2(-ts * 0.5, -ts * 0.5 - 14.0 + ts * 0.5, ts, ts * 0.5 + 14.0)
	if kind == "gate":
		draw_rect(front, Color("4a4f57"))
		draw_rect(top, Color("6f7782"))
		for i in 4:
			var x := -ts * 0.5 + 4.0 + i * 8.0
			draw_line(Vector2(x, front.position.y + 2.0), Vector2(x, front.end.y - 2.0), Color("2c3036"), 2.0)
		draw_rect(Rect2(-ts * 0.5, front.position.y + 4.0, ts, 3.0), Color("e0b040"))
	else:
		draw_rect(front, Color("7d6a52"))
		draw_rect(top, Color("a8916f"))
		# sacos de areia / blocos
		for row in 3:
			var y := front.position.y + 2.0 + row * 9.0
			var off := 0.0 if row % 2 == 0 else 5.0
			var x := -ts * 0.5 - off
			while x < ts * 0.5:
				draw_rect(Rect2(maxf(x, -ts * 0.5) + 1.0, y, minf(10.0, ts * 0.5 - x) - 2.0, 7.0), Color("917b5c"))
				x += 10.0
	draw_rect(Rect2(top.position, Vector2(ts, front.end.y - top.position.y)), Color(0, 0, 0, 0.6), false, 1.0)
	# rachaduras conforme o dano
	if hpk < 0.7:
		draw_line(Vector2(-6, front.position.y + 3), Vector2(2, front.position.y + 12), Color(0, 0, 0, 0.7), 1.5)
	if hpk < 0.4:
		draw_line(Vector2(8, top.position.y + 4), Vector2(0, front.position.y + 8), Color(0, 0, 0, 0.7), 1.5)
		draw_line(Vector2(-10, front.end.y - 4), Vector2(-2, front.position.y + 6), Color(0, 0, 0, 0.7), 1.5)
	if flash > 0.0:
		draw_rect(Rect2(top.position, Vector2(ts, front.end.y - top.position.y)), Color(1, 1, 1, 0.5))


func _draw_generator() -> void:
	var glow := 0.6 + 0.4 * sin(t * 4.0)
	draw_rect(Rect2(-26, -10, 52, 24), Color("3d434c"))
	draw_rect(Rect2(-26, -26, 52, 18), Color("5b636e"))
	draw_rect(Rect2(-26, -26, 52, 40), Color(0, 0, 0, 0.7), false, 1.0)
	draw_circle(Vector2(0, -17), 8.0, Color(0.3, 0.9, 1.0, glow))
	draw_circle(Vector2(0, -17), 4.0, Color(0.9, 1.0, 1.0))
	for i in 3:
		draw_rect(Rect2(-22 + i * 16, -4, 10, 12), Color("2a2f36"))
		draw_rect(Rect2(-20 + i * 16, -2, 6, 3), Color(0.3, 1.0, 0.5, glow))
	if flash > 0.0:
		draw_rect(Rect2(-26, -26, 52, 40), Color(1, 0.3, 0.3, 0.5))


func _draw_turret() -> void:
	# anel de sacos de areia + metralhadora girando sobre um pedestal
	for i in 10:
		var a := TAU * i / 10.0
		var p := Vector2(cos(a) * 15.0, sin(a) * 10.0 + 2.0)
		draw_rect(Rect2(p - Vector2(5, 3), Vector2(10, 7)), Color("a8916f"))
		draw_rect(Rect2(p - Vector2(5, 3), Vector2(10, 7)), Color(0, 0, 0, 0.45), false, 1.0)
	draw_circle(Vector2(0, -4), 7.0, Color("3a3f47"))
	var d := Vector2(cos(aim), sin(aim))
	var base := Vector2(0, -10)
	draw_line(base, base + d * 22.0, Color("1f2226"), 5.0)
	draw_line(base, base + d * 22.0, Color("5b636e"), 2.0)
	draw_circle(base, 5.0, Color("4a505b"))
	var col := Color("7dff6b") if operator != null else Color("ff6b4a")
	draw_circle(base + Vector2(0, -1), 2.0, col)


func _draw_switch() -> void:
	draw_circle(Vector2.ZERO, 14.0, Color("3a3f47"))
	draw_circle(Vector2.ZERO, 11.0, Color("59616c"))
	var c := Color("7dff6b") if active else Color("ff6b4a")
	draw_rect(Rect2(-2, -30, 4, 26), Color("8a929c"))
	draw_circle(Vector2(0, -32), 5.0, c)
	if not active and progress > 0.0:
		draw_arc(Vector2.ZERO, 18.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 24, Color("7dff6b"), 3.0)
