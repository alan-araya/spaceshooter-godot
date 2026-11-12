class_name Grid
extends RefCounted
## Grade de tiles: colisão círculo × grade, linha de visão e dano em muros.
## Sem dependência de nós/render: roda em testes headless.

enum { GROUND, ROCK, ACID, WALL, GATE }

const MODE_HUMAN := 0
const MODE_BUG := 1
const MODE_SHOT := 2
const MODE_SPIT := 3 # cuspe: rocha, muros e portões bloqueiam

var cols: int
var rows: int
var tile: int
var n: int
var kind := PackedByteArray()
var deco := PackedByteArray() # código ASCII do caractere do mapa (variações de chão)
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var version := 0 # incrementa quando um tile muda


func _init(c: int = Bal.COLS, r: int = Bal.ROWS, t: int = Bal.TILE) -> void:
	cols = c
	rows = r
	tile = t
	n = c * r
	kind.resize(n)
	deco.resize(n)
	hp.resize(n)
	max_hp.resize(n)
	deco.fill(46) # '.'


func idx(cx: int, cy: int) -> int:
	return cy * cols + cx


func in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < cols and cy < rows


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(p.x / tile), 0, cols - 1), clampi(floori(p.y / tile), 0, rows - 1))


func center(cx: int, cy: int) -> Vector2:
	return Vector2(cx * tile + tile * 0.5, cy * tile + tile * 0.5)


func center_i(i: int) -> Vector2:
	return center(i % cols, i / cols)


func kind_at(p: Vector2) -> int:
	var cx := floori(p.x / tile)
	var cy := floori(p.y / tile)
	if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
		return GROUND
	return kind[cy * cols + cx]


func deco_at(cx: int, cy: int) -> int:
	if not in_bounds(cx, cy):
		return 0
	return deco[cy * cols + cx]


static func blocks_move(k: int, mode: int) -> bool:
	if k == GROUND:
		return false
	if k == GATE:
		return mode == MODE_BUG
	return true


static func blocks_shot(k: int) -> bool:
	return k == ROCK


func is_walkable_cell(cx: int, cy: int, mode: int = MODE_HUMAN) -> bool:
	if not in_bounds(cx, cy):
		return false
	return not blocks_move(kind[cy * cols + cx], mode)


## Aplica dano a muro/portão. Retorna true se o tile foi destruído.
func damage_tile(cx: int, cy: int, amount: float) -> bool:
	if not in_bounds(cx, cy):
		return false
	var i := idx(cx, cy)
	var k := kind[i]
	if k != WALL and k != GATE:
		return false
	hp[i] -= amount
	version += 1
	if hp[i] <= 0.0:
		kind[i] = GROUND
		deco[i] = 120 # 'x' escombros
		return true
	return false


## Move um círculo com colisão por eixo (desliza nas paredes).
## Retorna o índice do tile que bloqueou o movimento, ou -1.
func move_circle(u: Node2D, d: Vector2, r: float, mode: int) -> int:
	var blocked := -1
	var p := u.position
	if d.x != 0.0:
		var hit := _hit_tile(p.x + d.x, p.y, r, mode)
		if hit < 0:
			p.x += d.x
		else:
			blocked = hit
	if d.y != 0.0:
		var hit2 := _hit_tile(p.x, p.y + d.y, r, mode)
		if hit2 < 0:
			p.y += d.y
		else:
			blocked = hit2
	p.x = clampf(p.x, r, cols * tile - r)
	p.y = clampf(p.y, r, rows * tile - r)
	u.position = p
	return blocked


func _hit_tile(x: float, y: float, r: float, mode: int) -> int:
	var x0 := floori((x - r) / tile)
	var x1 := floori((x + r - 0.001) / tile)
	var y0 := floori((y - r) / tile)
	var y1 := floori((y + r - 0.001) / tile)
	for cy in range(y0, y1 + 1):
		if cy < 0 or cy >= rows:
			continue
		for cx in range(x0, x1 + 1):
			if cx < 0 or cx >= cols:
				continue
			var i := cy * cols + cx
			if blocks_move(kind[i], mode):
				return i
	return -1


## Linha de visão em passos de 8 px. mode: MODE_SHOT (só rocha bloqueia), MODE_HUMAN ou MODE_BUG.
func line_clear(a: Vector2, b: Vector2, mode: int = MODE_SHOT) -> bool:
	var d := b - a
	var dist := d.length()
	var steps := maxi(1, ceili(dist / 8.0))
	for i in range(1, steps):
		var k := kind_at(a + d * (float(i) / steps))
		if mode == MODE_SHOT:
			if k == ROCK:
				return false
		elif mode == MODE_SPIT:
			if k == ROCK or k == WALL or k == GATE:
				return false
		elif blocks_move(k, mode):
			return false
	return true


## Linha de visão "grossa" para movimento: checa o centro e as duas bordas do corpo.
func line_clear_thick(a: Vector2, b: Vector2, r: float, mode: int = MODE_HUMAN) -> bool:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return true
	var nrm := Vector2(-d.y, d.x) / l * r
	return line_clear(a, b, mode) and line_clear(a + nrm, b + nrm, mode) and line_clear(a - nrm, b - nrm, mode)


var _stamp := PackedInt32Array()
var _stamp_id := 0
var _depth := PackedInt32Array()
var _queue := PackedInt32Array()


## Próximo ponto do caminho mais curto (BFS em 8 vizinhos, sem cortar quina) de `a` até `b`.
## Busca a partir do destino e para ao alcançar a origem. Vector2.INF se não houver caminho.
func path_next(a: Vector2, b: Vector2, mode: int, max_nodes: int = 600) -> Vector2:
	if _stamp.size() != n:
		_stamp.resize(n)
		_depth.resize(n)
		_queue.resize(n)
		_stamp.fill(0)
	_stamp_id += 1
	var ca := cell_of(a)
	var cb := cell_of(b)
	var ia := ca.y * cols + ca.x
	var ib := cb.y * cols + cb.x
	if ia == ib:
		return b
	var head := 0
	var tail := 0
	_queue[tail] = ib
	tail += 1
	_stamp[ib] = _stamp_id
	_depth[ib] = 0
	var found := false
	while head < tail and head < max_nodes:
		var i := _queue[head]
		head += 1
		if i == ia:
			found = true
			break
		var cx := i % cols
		var cy := i / cols
		for k in 8:
			var nx: int = cx + FlowField.DX[k]
			var ny: int = cy + FlowField.DY[k]
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var ni := ny * cols + nx
			if _stamp[ni] == _stamp_id:
				continue
			if ni != ia and blocks_move(kind[ni], mode):
				continue
			if k >= 4 and (blocks_move(kind[cy * cols + nx], mode) or blocks_move(kind[ny * cols + cx], mode)):
				continue
			_stamp[ni] = _stamp_id
			_depth[ni] = _depth[i] + 1
			_queue[tail] = ni
			tail += 1
	if not found:
		return Vector2.INF
	# da origem, anda para o vizinho visitado com menor profundidade
	var best := -1
	var bd := _depth[ia]
	for k in 8:
		var nx2: int = ca.x + FlowField.DX[k]
		var ny2: int = ca.y + FlowField.DY[k]
		if nx2 < 0 or ny2 < 0 or nx2 >= cols or ny2 >= rows:
			continue
		var ni2 := ny2 * cols + nx2
		if _stamp[ni2] != _stamp_id or _depth[ni2] >= bd:
			continue
		if k >= 4 and (blocks_move(kind[ca.y * cols + nx2], mode) or blocks_move(kind[ny2 * cols + ca.x], mode)):
			continue
		bd = _depth[ni2]
		best = ni2
	if best < 0:
		return Vector2.INF
	return center_i(best)


## Célula caminhável mais próxima (anéis crescentes). Útil para spawns.
func nearest_walkable(c: Vector2i, mode: int = MODE_HUMAN) -> Vector2i:
	if is_walkable_cell(c.x, c.y, mode):
		return c
	for rad in range(1, maxi(cols, rows)):
		for oy in range(-rad, rad + 1):
			for ox in range(-rad, rad + 1):
				if absi(ox) != rad and absi(oy) != rad:
					continue
				if is_walkable_cell(c.x + ox, c.y + oy, mode):
					return Vector2i(c.x + ox, c.y + oy)
	return c
