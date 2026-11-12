class_name Shadows
extends CanvasGroup
## SOMBRAS projetadas pelo sol no chão: prismas dos muros, rochas e estruturas (estáticos) e
## silhuetas inclinadas das unidades (a cada quadro).
## Tudo é desenhado em preto opaco dentro de um CanvasGroup e composto com UMA transparência,
## para que sombras sobrepostas não escureçam em dobro. Fica acima dos decalques e abaixo das
## rochas e das entidades (que escondem a parte da sombra que cairia sobre elas).
## Só aparência: lê posições e sprites, não altera nada.

const ROCK_H := 22.0

var world: World
var dir := Vector2(0.5, 0.87) # para onde a sombra cai, na tela
var length := 0.65 # comprimento por unidade de altura
var statics: Node2D
var units: Node2D
var _version := -1


func setup(w: World) -> void:
	world = w
	var amb: Dictionary = w.amb
	var d: Vector2 = amb.sun_dir
	dir = d.normalized()
	length = amb.shadow_len
	self_modulate = Color(1, 1, 1, float(amb.shadow_alpha))
	fit_margin = 4.0
	clear_margin = 4.0
	statics = Node2D.new()
	statics.name = "Static"
	add_child(statics)
	statics.draw.connect(_draw_statics)
	units = Node2D.new()
	units.name = "Units"
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/silhouette.gdshader")
	units.material = m
	add_child(units)
	units.draw.connect(_draw_units)


func tick() -> void:
	if _version != world.walls_version:
		_version = world.walls_version
		statics.queue_redraw()
	units.queue_redraw()


## Sombra de um bloco de base `r` (no chão) e altura `h`: a base, a base deslocada e o que há entre elas.
func _prism(r: Rect2, h: float) -> void:
	var s := dir * (length * h)
	var pts := PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
		r.position + s, Vector2(r.end.x, r.position.y) + s, r.end + s, Vector2(r.position.x, r.end.y) + s])
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 3:
		hull.resize(hull.size() - 1) # o último ponto repete o primeiro
		statics.draw_colored_polygon(hull, Color.BLACK)


func _draw_statics() -> void:
	var g := world.grid
	var ts := float(Bal.TILE)
	for cy in g.rows:
		# trechos contínuos de rocha e de muro na mesma linha viram um prisma só
		var cx := 0
		while cx < g.cols:
			var k := _kind(cx, cy)
			if k == 0:
				cx += 1
				continue
			var x0 := cx
			while cx < g.cols and _kind(cx, cy) == k:
				cx += 1
			var r := Rect2(x0 * ts, cy * ts, (cx - x0) * ts, ts)
			_prism(r, ROCK_H if k == 1 else Prop.WALL_H)
			if k == 2:
				_contact(r, cy)
	var gen = world.generator
	if gen != null and not gen.dead:
		_prism(Rect2(gen.position + Vector2(-26, -8), Vector2(52, 22)), 30.0)
	for tu in world.turrets:
		_prism(Rect2(tu.position + Vector2(-15, -6), Vector2(30, 16)), 9.0)
	for sw in world.switches:
		_prism(Rect2(sw.position + Vector2(-3, -3), Vector2(6, 6)), 32.0)
		_prism(Rect2(sw.position + Vector2(-12, -8), Vector2(24, 16)), 3.0)


## 0 = nada, 1 = rocha, 2 = muro/portão de pé.
func _kind(cx: int, cy: int) -> int:
	var g := world.grid
	var i := g.idx(cx, cy)
	if g.kind[i] == Grid.ROCK:
		return 1
	if world.walls.has(i):
		return 2
	return 0


## Escurecimento de contato na base da face frontal dos muros (só onde não há muro logo abaixo).
func _contact(r: Rect2, cy: int) -> void:
	var g := world.grid
	var ts := float(Bal.TILE)
	var x := r.position.x
	while x < r.end.x:
		var cx := int(x / ts)
		if cy + 1 >= g.rows or _kind(cx, cy + 1) == 0:
			var y := r.end.y
			statics.draw_polygon(
				PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x + ts, y + 9.0), Vector2(x, y + 9.0)]),
				PackedColorArray([Color(0, 0, 0, 0.75), Color(0, 0, 0, 0.75), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0)]))
		x += ts


func _draw_units() -> void:
	var d := dir * length
	for c in world.commanders:
		_upright(c, d)
	for s in world.soldiers:
		_upright(s, d)
	for n in world.nests:
		_upright(n, d * 0.8)
	for rb in world.robots:
		_flat(rb, d * 12.0)
	for b in world.bugs:
		_flat(b, d * (14.0 if b.kind == "mother" else 6.0))
	units.draw_set_transform_matrix(Transform2D.IDENTITY)


## Sprite "em pé" (soldado, ninho): a silhueta deita no chão a partir dos pés, na direção da sombra.
func _upright(u, d: Vector2) -> void:
	if not is_instance_valid(u) or u.dead or not u.visible:
		return
	var v: Sprite2D = u.visual
	var ct := v.texture as CanvasTexture
	if ct == null:
		return
	var fs := Vector2(ct.get_width() / v.hframes, ct.get_height() / v.vframes)
	var fc := v.frame_coords
	var region := Rect2(Vector2(fc) * fs, fs)
	var feet := v.offset.y + fs.y * 0.5 - 2.0 # y local do contato com o chão
	var sx := -1.0 if v.flip_h else 1.0
	var origin: Vector2 = u.position + Vector2(0, feet) + d * feet
	units.draw_set_transform_matrix(Transform2D(Vector2(sx * v.scale.x, 0), -d * v.scale.y, origin))
	units.draw_texture_rect_region(ct.diffuse_texture, Rect2(v.offset - fs * 0.5, fs), region)


## Sprite visto de cima (aranha, robô): a mesma silhueta, deslocada conforme a altura do corpo.
func _flat(u, off: Vector2) -> void:
	if not is_instance_valid(u) or u.dead or not u.visible:
		return
	var v: Sprite2D = u.visual
	var ct := v.texture as CanvasTexture
	if ct == null:
		return
	var fs := Vector2(ct.get_width() / v.hframes, ct.get_height() / v.vframes)
	var fc := v.frame_coords
	var region := Rect2(Vector2(fc) * fs, fs)
	var p: Vector2 = u.position + off
	units.draw_set_transform_matrix(Transform2D(v.rotation, v.scale, 0.0, p))
	units.draw_texture_rect_region(ct.diffuse_texture, Rect2(v.offset - fs * 0.5, fs), region)
