class_name WorldLayer
extends Node2D
## Camadas desenhadas em lote pelo World: decalques (chão), sombras e sobreposição (marcadores, barras).

enum Mode { DECALS, SHADOWS, OVERLAY }

var world: World
var mode := Mode.DECALS
var dirty := true

## Decalques ficam em blocos de CHUNK itens, cada um num CanvasItem próprio:
## um abate novo só redesenha o bloco mais recente (e não os ~450 do mapa).
const CHUNK := 48
var chunks: Array = []


class DecalChunk extends Node2D:
	var items: Array = []

	func _draw() -> void:
		var rnd := RandomNumberGenerator.new()
		for d in items:
			WorldLayer.draw_decal(self, d, rnd)


func add_decal(kind: String, p: Vector2, size: float) -> void:
	var col := Color(0, 0, 0, 0.3)
	match kind:
		"goo":
			col = Color(0.72, 0.8, 0.3, 0.55)
		"blood":
			col = Color(0.5, 0.05, 0.05, 0.6)
		"scorch":
			col = Color(0.16, 0.11, 0.07, 0.22)
		"crater":
			col = Color(0.18, 0.12, 0.1, 0.65)
		"rubble":
			col = Color(0.45, 0.38, 0.3, 0.8)
		"petals":
			col = Color(0.85, 0.35, 0.7, 0.6)
	_push({ kind = kind, p = p, size = size, seed = world.rng.randi(), col = col })


## Carcaça: frame da folha de sprites desenhado girado no chão (ex.: aracnídeo esmagado).
func add_corpse(sheet: String, frame: int, p: Vector2, rot: float) -> void:
	_push({ kind = "corpse", p = p, size = 0.0, seed = 0, col = Color(0.78, 0.72, 0.62, 0.75), sheet = sheet, frame = frame, rot = rot })


func _push(d: Dictionary) -> void:
	if chunks.is_empty() or chunks[-1].items.size() >= CHUNK:
		var ch := DecalChunk.new()
		add_child(ch)
		chunks.append(ch)
	var cur: DecalChunk = chunks[-1]
	cur.items.append(d)
	cur.queue_redraw()
	if chunks.size() * CHUNK > Bal.LIMITS.max_decals:
		var old: DecalChunk = chunks.pop_front()
		old.queue_free()


func decal_count() -> int:
	var total := 0
	for ch in chunks:
		total += ch.items.size()
	return total


func tick() -> void:
	if mode == Mode.DECALS:
		if dirty:
			dirty = false
			queue_redraw()
	else:
		queue_redraw()


func _draw() -> void:
	match mode:
		Mode.DECALS:
			_draw_marks()
		Mode.SHADOWS:
			_draw_shadows()
		Mode.OVERLAY:
			_draw_overlay()


## Zonas de pouso / extração (estáticas; desenhadas uma vez, abaixo dos blocos de decalques).
func _draw_marks() -> void:
	draw_arc(world.lz, 26.0, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 2.0)
	if world.extraction != Vector2.INF:
		draw_circle(world.extraction, 32.0, Color(0.3, 0.9, 1.0, 0.12))
		draw_arc(world.extraction, 32.0, 0.0, TAU, 40, Color(0.3, 0.9, 1.0, 0.6), 2.0)


static func draw_decal(ci: CanvasItem, d: Dictionary, rnd: RandomNumberGenerator) -> void:
	rnd.seed = d.seed
	var p: Vector2 = d.p
	var s: float = d.size
	var c: Color = d.col
	match d.kind:
		"corpse":
			var def: Dictionary = Art.DEFS[d.sheet]
			var fs := Vector2(def.size)
			var fr: int = d.frame
			var region := Rect2(Vector2((fr % def.h) * fs.x, (fr / def.h) * fs.y), fs)
			ci.draw_set_transform(p, d.rot, Vector2.ONE)
			ci.draw_texture_rect_region(Art.tex(d.sheet), Rect2(-fs * 0.5, fs), region, c)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"crater":
			ci.draw_circle(p, s, c)
			ci.draw_circle(p + Vector2(-2, -2), s * 0.6, Color(0.1, 0.07, 0.05, 0.5))
		"rubble":
			for i in 7:
				var q := p + Vector2(rnd.randf_range(-s, s), rnd.randf_range(-s, s))
				ci.draw_rect(Rect2(q, Vector2(4, 3)), c)
		_:
			ci.draw_circle(p, s, c)
			for i in 4:
				var q2 := p + Vector2(rnd.randf_range(-s, s), rnd.randf_range(-s, s)) * 1.4
				ci.draw_circle(q2, s * rnd.randf_range(0.25, 0.5), c)


func _draw_shadows() -> void:
	# bolhas nas poças de ácido
	var tt := world.time
	for i in world.acid_cells.size():
		var c: Vector2 = world.acid_cells[i]
		var ph := fmod(tt * 0.7 + i * 0.37, 1.0)
		var off := Vector2(sin(i * 12.9) * 9.0, cos(i * 7.3) * 9.0)
		var rr := 1.5 + ph * 3.5
		draw_arc(c + off, rr, 0.0, TAU, 10, Color(0.85, 1.0, 0.55, 0.7 * (1.0 - ph)), 1.0)
		if i % 3 == 0:
			draw_rect(Rect2(c + Vector2(-off.y, off.x) * 0.8, Vector2(2, 2)), Color(0.9, 1.0, 0.6, 0.5 + 0.5 * sin(tt * 3.0 + i)))
	for hz in world.hazards:
		var k: float = clampf(hz.t / Bal.MOTHER.pool_time, 0.0, 1.0)
		var pr: float = hz.r
		var hp2: Vector2 = hz.p
		draw_set_transform(hp2, 0.0, Vector2(1.0, 0.7))
		draw_circle(Vector2.ZERO, pr, Color(0.45, 0.8, 0.15, 0.35 * k))
		draw_circle(Vector2.ZERO, pr * 0.7, Color(0.6, 0.95, 0.25, 0.3 * k))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var bp := hp2 + Vector2(sin(tt * 3.0 + hp2.x) * pr * 0.5, cos(tt * 2.3 + hp2.y) * pr * 0.3)
		draw_arc(bp, 3.0 + fmod(tt * 4.0, 3.0), 0.0, TAU, 8, Color(0.85, 1.0, 0.5, 0.6 * k), 1.0)
	var sc := Color(0, 0, 0, 0.28)
	for u in world.shadow_casters():
		if not is_instance_valid(u) or u.dead or not u.visible:
			continue
		var rr: float = u.r
		var p: Vector2 = u.position + Vector2(3, 3)
		draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, rr * 1.15, sc)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	# marcadores dos comandantes
	for c in world.commanders:
		var col: Color = Bal.PLAYER_COLORS[c.pid]
		if c.dead:
			if c.respawn_timer > 0.0:
				var txt := "P%d  %ds" % [c.pid + 1, ceili(c.respawn_timer)]
				draw_string(font, world.lz + Vector2(-26, -40 - c.pid * 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
			continue
		var p: Vector2 = c.position
		draw_set_transform(p + Vector2(0, 2), 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, col, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var top := p + Vector2(0, -44 + sin(world.time * 5.0) * 2.0)
		draw_colored_polygon(PackedVector2Array([top + Vector2(-5, -6), top + Vector2(5, -6), top]), col)
		draw_string_outline(font, top + Vector2(-9, -9), "P%d" % (c.pid + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.8))
		draw_string(font, top + Vector2(-9, -9), "P%d" % (c.pid + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# barras de vida (ninhos, matriarcas, robôs, gerador)
	for n in world.nests:
		if not n.dead and n.hp < n.max_hp:
			_bar(n.position + Vector2(0, -n.r - 18), n.r * 1.6, n.hp / n.max_hp, Color("ff7ae0"))
	for b in world.bugs:
		if b.kind == "mother" and not b.dead:
			_bar(b.position + Vector2(0, -b.r - 10), 40.0, b.hp / b.max_hp, Color("ff7ae0"))
	for rb in world.robots:
		if not rb.dead:
			_bar(rb.position + Vector2(0, -30), 34.0, rb.hp / rb.max_hp, Color("9fe8ff"))
	var g = world.generator
	if g != null and not g.dead:
		_bar(g.position + Vector2(0, -38), 60.0, g.hp / g.max_hp, Color("7dff6b"))
	# avisos de emboscada
	for a in world.ambushes:
		if not a.done:
			var k: float = clampf(1.0 - a.t / Bal.AMBUSH.warn_time, 0.0, 1.0)
			var col_a := Color(1.0, 0.25, 0.2, 0.9) if a.get("edge", false) else Color(1.0, 0.5, 0.2, 0.8)
			draw_arc(a.p, 10.0 + k * 22.0, 0.0, TAU, 24, col_a, 2.0)
	# cristal
	if world.crystal != null:
		var cp: Vector2 = world.crystal.p
		var bob := sin(world.time * 4.0) * 3.0
		var tip := cp + Vector2(0, -26 + bob)
		var pts := PackedVector2Array([tip, cp + Vector2(9, -12 + bob), cp + Vector2(0, 2 + bob), cp + Vector2(-9, -12 + bob)])
		draw_circle(cp + Vector2(0, -12 + bob), 16.0, Color(1.0, 0.2, 0.3, 0.18))
		draw_colored_polygon(pts, Color("ff3b5c"))
		draw_polyline(pts + PackedVector2Array([tip]), Color("ffd0d8"), 1.0)


func _bar(center: Vector2, width: float, k: float, col: Color) -> void:
	var r := Rect2(center - Vector2(width * 0.5, 2), Vector2(width, 4))
	draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(r.position, Vector2(width * clampf(k, 0.0, 1.0), 4)), col)
