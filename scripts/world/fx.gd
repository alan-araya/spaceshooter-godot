class_name Fx
extends Node2D
## Partículas em lote. Duas camadas: normal (gosma, poeira, fumaça) e brilho aditivo (fogo, flashes).

const MAX := 1500

var world: World
var parts: Array = [] # Dictionary: p, v, life, max, col, size, drag, glow, grav, shrink
var glow_layer: Node2D


func _ready() -> void:
	glow_layer = Node2D.new()
	glow_layer.name = "Glow"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_layer.material = mat
	add_child(glow_layer)
	glow_layer.draw.connect(_draw_glow)


func _add(p: Vector2, v: Vector2, life: float, col: Color, size: float, drag: float = 3.0, glow: bool = false, grav: float = 0.0) -> void:
	if parts.size() >= MAX:
		return
	parts.append({ p = p, v = v, life = life, max = life, col = col, size = size, drag = drag, glow = glow, grav = grav })


func _rv(speed_min: float, speed_max: float) -> Vector2:
	var a := world.rng.randf_range(0.0, TAU)
	return Vector2(cos(a), sin(a)) * world.rng.randf_range(speed_min, speed_max)


func goo(p: Vector2, n: int) -> void:
	for i in n:
		var c := Color(0.85, 0.9, 0.45) if world.rng.randf() < 0.6 else Color(0.62, 0.78, 0.25)
		_add(p, _rv(30.0, 150.0), world.rng.randf_range(0.25, 0.6), c, world.rng.randf_range(2.0, 3.5), 5.0)


func blood(p: Vector2, n: int) -> void:
	for i in n:
		_add(p, _rv(30.0, 130.0), world.rng.randf_range(0.25, 0.55), Color(0.7, 0.08, 0.08), world.rng.randf_range(2.0, 3.0), 5.0)


func dust(p: Vector2, n: int) -> void:
	for i in n:
		_add(p, _rv(10.0, 70.0), world.rng.randf_range(0.4, 0.9), Color(0.85, 0.72, 0.5, 0.7), world.rng.randf_range(3.0, 6.0), 2.0)


func spark(p: Vector2, n: int) -> void:
	for i in n:
		_add(p, _rv(60.0, 200.0), world.rng.randf_range(0.08, 0.2), Color(1.0, 0.85, 0.4), 2.0, 6.0, true)


func muzzle(p: Vector2, angle: float) -> void:
	var d := Vector2(cos(angle), sin(angle))
	_add(p + d * 3.0, d * 40.0, 0.05, Color(1.0, 0.9, 0.5), 5.0, 0.0, true)


func smoke(p: Vector2) -> void:
	_add(p, Vector2(world.rng.randf_range(-10, 10), -25.0), world.rng.randf_range(0.6, 1.1), Color(0.25, 0.22, 0.2, 0.5), world.rng.randf_range(4.0, 8.0), 1.0)


func burn(p: Vector2) -> void:
	_add(p + _rv(0.0, 6.0), Vector2(0, -40), 0.35, Color(1.0, 0.55, 0.15), 4.0, 1.0, true)


func petals(p: Vector2) -> void:
	for i in 8:
		var c := Color(0.95, 0.4, 0.8) if i % 2 == 0 else Color(0.6, 0.85, 0.3)
		_add(p, _rv(20.0, 90.0), world.rng.randf_range(0.4, 0.8), c, 2.5, 3.0)


func sparkle(p: Vector2, col: Color) -> void:
	for i in 16:
		_add(p, _rv(40.0, 140.0), world.rng.randf_range(0.3, 0.7), col, 2.5, 3.0, true)


func plasma_pop(p: Vector2) -> void:
	for i in 10:
		_add(p, _rv(40.0, 160.0), world.rng.randf_range(0.15, 0.35), Color(0.4, 0.95, 1.0), 3.0, 4.0, true)


func explosion(p: Vector2, scale_k: float) -> void:
	_add(p, Vector2.ZERO, 0.18, Color(1.0, 0.95, 0.7), 26.0 * scale_k, 0.0, true)
	for i in int(22 * scale_k):
		var c := Color(1.0, world.rng.randf_range(0.4, 0.8), 0.15)
		_add(p, _rv(40.0, 220.0) * scale_k, world.rng.randf_range(0.2, 0.5), c, world.rng.randf_range(3.0, 6.0) * scale_k, 4.0, true)
	for i in int(10 * scale_k):
		_add(p + _rv(0.0, 10.0), _rv(10.0, 60.0) + Vector2(0, -20), world.rng.randf_range(0.6, 1.2), Color(0.2, 0.18, 0.16, 0.6), world.rng.randf_range(6.0, 12.0) * scale_k, 1.5)
	dust(p, int(8 * scale_k))


func tick(dt: float) -> void:
	var keep: Array = []
	for q in parts:
		q.life -= dt
		if q.life <= 0.0:
			continue
		q.p += q.v * dt
		q.v *= maxf(0.0, 1.0 - q.drag * dt)
		keep.append(q)
	parts = keep
	queue_redraw()
	glow_layer.queue_redraw()


func _draw() -> void:
	for q in parts:
		if q.glow:
			continue
		var k: float = q.life / q.max
		var c: Color = q.col
		c.a *= minf(1.0, k * 2.0)
		var s: float = q.size * (0.5 + 0.5 * k)
		draw_rect(Rect2(q.p - Vector2(s, s) * 0.5, Vector2(s, s)), c)


func _draw_glow() -> void:
	for q in parts:
		if not q.glow:
			continue
		var k: float = q.life / q.max
		var c: Color = q.col
		c.a *= k
		glow_layer.draw_circle(q.p, q.size * (0.4 + 0.6 * k), c)
