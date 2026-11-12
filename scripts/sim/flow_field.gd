class_name FlowField
extends RefCounted
## Campo de fluxo: custo de cada célula até a fonte mais próxima (Dijkstra multi-fonte).
## mode BUG: muros e portões custam caro (o inseto vai até eles e os destrói).
## mode HUMAN: muros bloqueiam, portões passam.

const DX: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const DY: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]
const DW: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.41421356, 1.41421356, 1.41421356, 1.41421356]

var grid: Grid
var mode: int
var wall_cost: float
var dist := PackedFloat32Array()
var _cost := PackedFloat32Array()
var _hi := PackedInt32Array()
var _hd := PackedFloat32Array()
var _size := 0


func _init(g: Grid, m: int, wc: float = 12.0) -> void:
	grid = g
	mode = m
	wall_cost = wc
	dist.resize(g.n)
	dist.fill(INF)
	_cost.resize(g.n)
	_hi.resize(g.n * 8)
	_hd.resize(g.n * 8)


func _cell_cost(k: int) -> float:
	if k == Grid.GROUND:
		return 1.0
	if k == Grid.ROCK or k == Grid.ACID:
		return INF
	if mode == Grid.MODE_BUG:
		return wall_cost
	if k == Grid.GATE:
		return 1.0
	return INF


func _push(i: int, d: float) -> void:
	var k := _size
	_size += 1
	_hi[k] = i
	_hd[k] = d
	while k > 0:
		var p := (k - 1) >> 1
		if _hd[p] <= _hd[k]:
			break
		var ti := _hi[p]
		_hi[p] = _hi[k]
		_hi[k] = ti
		var td := _hd[p]
		_hd[p] = _hd[k]
		_hd[k] = td
		k = p


func _pop() -> int:
	var top := _hi[0]
	_size -= 1
	if _size > 0:
		_hi[0] = _hi[_size]
		_hd[0] = _hd[_size]
		var k := 0
		while true:
			var l := 2 * k + 1
			var r := l + 1
			var m := k
			if l < _size and _hd[l] < _hd[m]:
				m = l
			if r < _size and _hd[r] < _hd[m]:
				m = r
			if m == k:
				break
			var ti := _hi[m]
			_hi[m] = _hi[k]
			_hi[k] = ti
			var td := _hd[m]
			_hd[m] = _hd[k]
			_hd[k] = td
			k = m
	return top


## sources: Array de Vector2 (posições em px).
func compute(sources: Array) -> void:
	var g := grid
	var cols := g.cols
	var rows := g.rows
	dist.fill(INF)
	for i in g.n:
		_cost[i] = _cell_cost(g.kind[i])
	_size = 0
	for s in sources:
		var c := g.cell_of(s)
		var i := c.y * cols + c.x
		if dist[i] != 0.0:
			dist[i] = 0.0
			_push(i, 0.0)
	while _size > 0:
		var d0 := _hd[0]
		var i := _pop()
		if d0 > dist[i]:
			continue
		var cx := i % cols
		var cy := i / cols
		for k in 8:
			var nx := cx + DX[k]
			var ny := cy + DY[k]
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var ni := ny * cols + nx
			var c := _cost[ni]
			if c == INF:
				continue
			if k >= 4:
				# diagonal: sem cortar quina
				var ia := cy * cols + nx
				var ib := ny * cols + cx
				if _cost[ia] == INF or _cost[ib] == INF:
					continue
				if mode == Grid.MODE_BUG and (g.kind[ia] != Grid.GROUND or g.kind[ib] != Grid.GROUND):
					continue
			var nd := d0 + c * DW[k]
			if nd < dist[ni]:
				dist[ni] = nd
				_push(ni, nd)


func at(p: Vector2) -> float:
	var c := grid.cell_of(p)
	return dist[c.y * grid.cols + c.x]


## Direção normalizada descendo o gradiente a partir de p. Vector2.ZERO se não há caminho.
func dir_from(p: Vector2) -> Vector2:
	var g := grid
	var c := g.cell_of(p)
	var here := dist[c.y * g.cols + c.x]
	var best := here
	var bx := -1
	var by := -1
	for k in 8:
		var nx := c.x + DX[k]
		var ny := c.y + DY[k]
		if nx < 0 or ny < 0 or nx >= g.cols or ny >= g.rows:
			continue
		if k >= 4:
			if Grid.blocks_move(g.kind[c.y * g.cols + nx], mode) or Grid.blocks_move(g.kind[ny * g.cols + c.x], mode):
				continue
		var d := dist[ny * g.cols + nx]
		if d < best:
			best = d
			bx = nx
			by = ny
	if bx < 0:
		if here == INF:
			return Vector2.ZERO
		var to := g.center(c.x, c.y) - p
		return to.normalized() if to.length() > 0.5 else Vector2.ZERO
	return (g.center(bx, by) - p).normalized()
