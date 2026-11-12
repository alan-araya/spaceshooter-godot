class_name Human
extends Unit
## Base dos humanos: comandante, soldado e robô. Funções comuns de movimento, tiro e flores.

## Colunas da folha do soldado: S, SE, L, NE, N. As direções do lado esquerdo são espelhadas.
const DIR_TO_COL: Array[int] = [2, 1, 0, 1, 2, 3, 4, 3]
const DIR_FLIP: Array[bool] = [false, false, false, true, true, true, false, false]

var pid := 0 # comandante dono (0..3)


func _init() -> void:
	super._init()
	is_human = true


## Pisa em flores próximas (qualquer humano arranca).
func trample_flowers() -> void:
	for f in world.flowers:
		if f.dead:
			continue
		if position.distance_to(f.position) < f.r + r:
			world.trample_flower(f, self)


## Empurra para fora de estruturas sólidas (ninhos, gerador).
func push_out_of_structures() -> void:
	for n in world.nests:
		if n.dead:
			continue
		var d: Vector2 = position - n.position
		var l := d.length()
		var mn: float = n.r + r - 4.0
		if l < mn and l > 0.01:
			position = n.position + d / l * mn
	var g = world.generator
	if g != null and not g.dead:
		var d2: Vector2 = position - g.position
		var l2 := d2.length()
		var mn2: float = g.r + r - 4.0
		if l2 < mn2 and l2 > 0.01:
			position = g.position + d2 / l2 * mn2


func separate(dt: float) -> void:
	var push := Vector2.ZERO
	var near: Array = world.tmp_a
	world.human_hash.query(position, 22.0, near)
	for o in near:
		if o == self:
			continue
		var d: Vector2 = position - o.position
		var l2 := d.length_squared()
		if l2 < 400.0 and l2 > 0.0001:
			var l := sqrt(l2)
			push += d / l * (20.0 - l)
	if push != Vector2.ZERO:
		world.grid.move_circle(self, push * dt * 6.0, r, Grid.MODE_HUMAN)


var _route_t := 0.0
var _route_goal := Vector2.INF
var _route_wp := Vector2.INF


## Anda em direção a um ponto. Com `pathfind`, contorna obstáculos por BFS na grade
## (rota em cache por ~0,4 s) quando não há linha livre até o destino.
func move_toward_point(target: Vector2, speed: float, dt: float, pathfind: bool) -> bool:
	var to := target - position
	var d := to.length()
	if d < 3.0:
		return false
	var v: Vector2 = to / d
	if pathfind and d > 24.0 and not world.grid.line_clear_thick(position, target, r, Grid.MODE_HUMAN):
		_route_t -= dt
		if _route_t <= 0.0 or _route_goal.distance_to(target) > 24.0 or position.distance_to(_route_wp) < 6.0:
			_route_t = 0.4 + world.rng.randf() * 0.2
			_route_goal = target
			_route_wp = world.grid.path_next(position, target, Grid.MODE_HUMAN)
		if _route_wp != Vector2.INF:
			var tw := _route_wp - position
			if tw.length() > 0.5:
				v = tw.normalized()
	var step := minf(speed * dt, d)
	world.grid.move_circle(self, v * step, r, Grid.MODE_HUMAN)
	walk_t += dt * 7.0
	moving = true
	return true


func fire_weapon(angle: float, weapon_key: String, spread: float, target: Unit = null) -> void:
	var wp: Dictionary = Bal.WEAPONS[weapon_key]
	var a := angle + (world.rng.randf_range(-spread, spread) if spread > 0.0 else 0.0)
	var muzzle := position + Vector2(cos(angle), sin(angle)) * 14.0 + Vector2(0, -12)
	world.projectiles.fire(weapon_key, muzzle, a, target)
	if weapon_key != "flame":
		world.fx.muzzle(muzzle, angle)


## Atualiza o Sprite2D do soldado (folha 5 direções × 4 passos).
func sync_soldier_visual() -> void:
	var d := Unit.dir8(face)
	var col := DIR_TO_COL[d]
	var row := 1
	if moving:
		row = int(walk_t) % 4
	visual.frame = row * 5 + col
	visual.flip_h = DIR_FLIP[d]
	if drop_t > 0.0:
		visual.position.y = -drop_t * 260.0
		visual.modulate.a = clampf(1.0 - drop_t * 1.5, 0.3, 1.0)
	else:
		visual.position.y = 0.0
		visual.modulate.a = 1.0
	apply_flash()
