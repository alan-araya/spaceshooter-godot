class_name SpatialHash
extends RefCounted
## Hash espacial uniforme para consultas de vizinhança (separação, alvos, colisão de projéteis).

var cell: float
var cols: int
var rows: int
var buckets: Array = []


func _init(w: float, h: float, cell_size: float = 32.0) -> void:
	cell = cell_size
	cols = ceili(w / cell_size)
	rows = ceili(h / cell_size)
	buckets.resize(cols * rows)
	for i in buckets.size():
		buckets[i] = []


func clear() -> void:
	for b in buckets:
		b.clear()


func insert(u: Node2D) -> void:
	var cx := clampi(floori(u.position.x / cell), 0, cols - 1)
	var cy := clampi(floori(u.position.y / cell), 0, rows - 1)
	buckets[cy * cols + cx].append(u)


## Preenche `out` com os candidatos das células que cobrem o círculo (sem filtrar distância).
func query(p: Vector2, radius: float, out: Array) -> void:
	out.clear()
	var x0 := clampi(floori((p.x - radius) / cell), 0, cols - 1)
	var x1 := clampi(floori((p.x + radius) / cell), 0, cols - 1)
	var y0 := clampi(floori((p.y - radius) / cell), 0, rows - 1)
	var y1 := clampi(floori((p.y + radius) / cell), 0, rows - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			out.append_array(buckets[cy * cols + cx])


var _tmp: Array = []


## Unidade viva mais próxima (pelo centro) dentro do raio, ou null.
func nearest(p: Vector2, radius: float, exclude: Node2D = null):
	query(p, radius, _tmp)
	var best = null
	var bd := radius * radius
	for u in _tmp:
		if u == exclude or not is_instance_valid(u) or u.dead:
			continue
		var d := p.distance_squared_to(u.position)
		if d < bd:
			bd = d
			best = u
	return best
