class_name Prop
extends Node2D
## Objetos de cenário e de missão que não são unidades com IA:
## flor, pickup, muro/portão, gerador, relé. Desenhados por sprite (Art) ou procedural (_draw).

## Altura do muro em px na tela (o topo é desenhado deslocado para cima; a face frontal tem essa altura).
const WALL_H := 18.0
## Regiões do atlas assets/sprites/walls.png (tools/build_structures.py).
const SRC_GATE_TOP := Rect2(128, 24, 32, 32)
const SRC_GATE_FRONT := Rect2(160, 24, 32, 18)

var world: World
var uid := 0
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
var lamp := false # poste de luz neste trecho (Lighting escolhe os cantos)
var _state := -1 # o muro só se redesenha quando isto muda
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
var gun: Sprite2D # metralhadora de ponto: a arma gira sobre a base
var glow_sprite: Sprite2D # partes que emitem luz (gerador, relé)


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
	sprite.material = Art.unshaded() # ícone sempre legível, mesmo no escuro
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
	sprite = Sprite2D.new()
	add_child(sprite)
	Art.apply(sprite, "generator")
	glow_sprite = Art.emissive("generator")
	add_child(glow_sprite)


func setup_turret(w: World, x: Vector2) -> void:
	world = w
	kind = "turret"
	position = x
	r = Bal.TURRET.radius
	aim = -PI / 2.0
	sprite = Sprite2D.new()
	add_child(sprite)
	Art.apply(sprite, "turret_base")
	gun = Sprite2D.new()
	gun.position = Vector2(0, -9)
	add_child(gun)
	Art.apply(gun, "turret_gun")


func setup_switch(w: World, x: Vector2) -> void:
	world = w
	kind = "switch"
	material = Art.flat_material()
	position = x
	r = 14.0
	sprite = Sprite2D.new()
	add_child(sprite)
	Art.apply(sprite, "relay")
	glow_sprite = Art.emissive("relay")
	add_child(glow_sprite)


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
		world.sfx("shot", position.x)


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
		"wall", "gate":
			var g := world.grid
			var st := world.walls_version * 8 + (4 if flash > 0.0 else 0)
			if g.max_hp[cell] > 0.0:
				var k: float = g.hp[cell] / g.max_hp[cell]
				st += 2 if k < 0.4 else (1 if k < 0.7 else 0)
			if st != _state:
				_state = st
				queue_redraw()
		"generator":
			var pulse := 0.75 + 0.25 * sin(t * 4.0)
			glow_sprite.visible = not dead
			glow_sprite.modulate = Color(pulse, pulse, pulse)
			if dead:
				sprite.self_modulate = Color(0.42, 0.42, 0.46)
			else:
				sprite.self_modulate = Color(1.9, 0.9, 0.85) if flash > 0.0 else Color.WHITE
		"turret":
			gun.rotation = aim
		"switch":
			glow_sprite.modulate = Color(0.45, 1.0, 0.4) if active else Color(1.0, 0.35, 0.28)
			queue_redraw()


func _draw() -> void:
	match kind:
		"wall", "gate":
			_draw_wall()
		"switch":
			_draw_switch()


func _wall_at(cx: int, cy: int) -> bool:
	var g := world.grid
	return g.in_bounds(cx, cy) and world.walls.has(g.idx(cx, cy))


## Muro/portão com volume: topo (deslocado WALL_H para cima) + face frontal, com mapa de relevo.
## O topo é amostrado pela posição no mundo, então as lajes continuam de um trecho para o outro.
## A face só aparece quando não há muro logo abaixo (senão o topo do vizinho a cobre).
func _draw_wall() -> void:
	var g := world.grid
	var cx := cell % g.cols
	var cy := cell / g.cols
	var hpk := 1.0
	if g.max_hp[cell] > 0.0:
		hpk = g.hp[cell] / g.max_hp[cell]
	var ts := float(Bal.TILE)
	var hs := ts * 0.5
	var tex := Art.lit("walls")
	var gate := kind == "gate"
	var top := Rect2(-hs, -hs - WALL_H, ts, ts)
	var front := Rect2(-hs, hs - WALL_H, ts, WALL_H)
	var n := _wall_at(cx, cy - 1)
	var s := _wall_at(cx, cy + 1)
	var w := _wall_at(cx - 1, cy)
	var e := _wall_at(cx + 1, cy)
	var ink := Color(0.09, 0.07, 0.07, 0.9)
	if not s:
		var fsrc: Rect2 = SRC_GATE_FRONT if gate else Rect2(128.0 + float((cx * 32) % 128), 0.0, 32.0, WALL_H)
		draw_texture_rect_region(tex, front, fsrc)
		if not w:
			draw_rect(Rect2(front.position.x, front.position.y, 1.0, WALL_H), ink)
		if not e:
			draw_rect(Rect2(front.end.x - 1.0, front.position.y, 1.0, WALL_H), ink)
	var tsrc: Rect2 = SRC_GATE_TOP if gate else Rect2(float((cx * 32) % 128), float((cy * 32) % 128), 32.0, 32.0)
	draw_texture_rect_region(tex, top, tsrc)
	# contorno e parapeito onde o topo termina
	var rim := Color(1.0, 0.95, 0.84, 0.30)
	var dip := Color(0, 0, 0, 0.26)
	if not n:
		draw_rect(Rect2(top.position.x, top.position.y, ts, 1.0), ink)
		draw_rect(Rect2(top.position.x, top.position.y + 1.0, ts, 2.0), rim)
		draw_rect(Rect2(top.position.x, top.position.y + 3.0, ts, 1.0), dip)
	if not w:
		draw_rect(Rect2(top.position.x, top.position.y, 1.0, ts), ink)
		draw_rect(Rect2(top.position.x + 1.0, top.position.y + 1.0, 2.0, ts - 1.0), rim)
		draw_rect(Rect2(top.position.x + 3.0, top.position.y + 1.0, 1.0, ts - 1.0), dip)
	if not e:
		draw_rect(Rect2(top.end.x - 1.0, top.position.y, 1.0, ts), ink)
		draw_rect(Rect2(top.end.x - 3.0, top.position.y + 1.0, 2.0, ts - 1.0), Color(0, 0, 0, 0.30))
	if lamp:
		# poste: o brilho da lâmpada é desenhado pelo Lighting
		draw_rect(Rect2(-1.0, -WALL_H - 14.0, 2.0, 14.0), Color("23262b"))
		draw_rect(Rect2(-4.0, -WALL_H - 17.0, 8.0, 3.0), Color("2f333a"))
		draw_rect(Rect2(-3.0, -WALL_H - 14.0, 6.0, 1.0), Color("ffe7b0"))
	# rachaduras conforme o dano
	var crack := Color(0, 0, 0, 0.75)
	if hpk < 0.7:
		draw_line(Vector2(-6, top.position.y + 8), Vector2(2, top.position.y + 20), crack, 1.5)
	if hpk < 0.4:
		draw_line(Vector2(8, top.position.y + 4), Vector2(0, top.position.y + 18), crack, 1.5)
		draw_line(Vector2(-10, front.end.y - 3), Vector2(-3, front.position.y + 3), crack, 1.5)
	if flash > 0.0:
		draw_rect(Rect2(top.position, Vector2(ts, ts + WALL_H)), Color(1.0, 0.95, 0.85, 0.3))


## O relé é sprite; aqui só o arco de progresso enquanto o comandante religa.
func _draw_switch() -> void:
	if not active and progress > 0.0:
		draw_arc(Vector2.ZERO, 18.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 24, Color("7dff6b"), 3.0)
