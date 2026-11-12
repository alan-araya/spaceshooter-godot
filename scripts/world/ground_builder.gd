class_name GroundBuilder
extends RefCounted
## Monta a textura do chão da missão (1280×640) a partir da grade, em vista 3/4:
## areia em mosaico, platôs com topo + paredão voltado para baixo, ácido, piso metálico,
## trilhas, solo fértil e "território alienígena" (trepadeiras roxas) em volta dos ninhos.
## Usa as texturas do Art (PNG ou placeholder procedural).
## Sai em duas imagens: `base` (chão, ácido, manchas) e `top` (platôs de rocha, transparente no
## resto). As sombras projetadas ficam ENTRE as duas, para não caírem em cima das rochas.

const T := 32


static func build(grid: Grid, theme: String, nest_cells: Array, seed_v: int) -> Dictionary:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = seed_v
	var W := grid.cols * T
	var H := grid.rows * T
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var top := Image.create(W, H, false, Image.FORMAT_RGBA8) # platôs (camada de cima)
	var faces: Array = [] # Rect2i dos paredões em `top` (recebem relevo de face vertical)
	var sand := Art.image("ground_sand")
	var rock := Art.image("rock_top")
	var cliff := Art.image("cliff")
	var creep := Art.image("creep_ground")

	# 1) base: areia em mosaico (ou piso metálico na colmeia/instalação)
	if theme == "hive":
		var metal := _metal_tile(rnd)
		for y in range(0, H, T):
			for x in range(0, W, T):
				img.blit_rect(metal, Rect2i(0, 0, T, T), Vector2i(x, y))
	else:
		_tile_fill(img, sand, Rect2i(0, 0, W, H))
		if theme == "swamp":
			img.blend_rect(_solid(W, H, Color(0.25, 0.35, 0.1, 0.12)), Rect2i(0, 0, W, H), Vector2i.ZERO)

	# 1b) variação larga de tom: quebra o aspecto de "tapete" da areia
	if theme != "hive":
		var shade_d := _patch(sand, rnd, Color(0.80, 0.74, 0.70), 0.30, 150)
		var shade_l := _patch(sand, rnd, Color(1.12, 1.08, 1.0), 0.28, 130)
		for n in 18:
			_blend_centered(img, shade_d if n % 2 == 0 else shade_l, Vector2i(rnd.randi_range(0, W), rnd.randi_range(0, H)))

	var dark := _patch(sand, rnd, Color(0.82, 0.7, 0.55), 0.45, 56)
	var trail := _patch(sand, rnd, Color(1.25, 1.18, 1.05), 0.6, 48)
	var fertile := _fertile_patch(sand, rnd)
	var metal2 := _metal_tile(rnd)
	var creep_patch := _patch(creep, rnd, Color(0.62, 0.38, 0.72) if theme == "hive" else Color(1, 1, 1), 0.8, 56)

	# 2) variações de chão por célula (manchas suaves que vazam para os vizinhos, sem "quadrados")
	for cy in grid.rows:
		for cx in grid.cols:
			var ch := grid.deco_at(cx, cy)
			var pos := Vector2i(cx * T, cy * T)
			match ch:
				44: # ','
					if theme == "hive":
						_blend_centered(img, creep_patch, pos + Vector2i(T / 2, T / 2))
					else:
						_blend_centered(img, dark, pos + Vector2i(T / 2, T / 2))
				58: # ':'
					_blend_centered(img, trail, pos + Vector2i(T / 2, T / 2))
				95: # '_'
					if theme != "hive":
						img.blit_rect(metal2, Rect2i(0, 0, T, T), pos)
				102: # 'f'
					_blend_centered(img, fertile, pos + Vector2i(T / 2, T / 2))

	# 2b) pedrinhas soltas no chão de terra
	if theme != "hive":
		for n in 150:
			var px := rnd.randi_range(0, grid.cols - 1)
			var py := rnd.randi_range(0, grid.rows - 1)
			var pi := grid.idx(px, py)
			if grid.kind[pi] != Grid.GROUND or grid.deco[pi] == 95: # 95 = piso metálico
				continue
			_boulder(img, Vector2(px * T + rnd.randi_range(3, T - 3), py * T + rnd.randi_range(3, T - 3)), rnd.randf_range(1.0, 2.4))

	# 3) território alienígena em volta dos ninhos (trepadeiras roxas e casulos)
	var blob := Art.image("creep_blob")
	for nc in nest_cells:
		var c: Vector2i = nc
		var center := Vector2i(c.x * T + T / 2, c.y * T + T / 2)
		_blend_centered(img, blob, center)
		for k in 2:
			var off := Vector2i(rnd.randi_range(-70, 70), rnd.randi_range(-50, 50))
			_blend_centered(img, creep_patch, center + off)

	# 4) ácido, rocha (platôs) e formações alienígenas
	for cy in grid.rows:
		for cx in grid.cols:
			var k := grid.kind[grid.idx(cx, cy)]
			var pos2 := Vector2i(cx * T, cy * T)
			if k == Grid.ACID:
				_acid_cell(img, grid, cx, cy, rnd)
			elif k == Grid.ROCK:
				var alien := grid.deco_at(cx, cy) == 94 # '^'
				_rock_cell(top, grid, cx, cy, rock, cliff, alien, theme == "hive", rnd, faces)

	# 4b) oclusão: o chão escurece junto à base das rochas
	var ao_below := _fade(T, 14, Vector2i(0, 1), 0.46)
	var ao_above := _fade(T, 5, Vector2i(0, -1), 0.24)
	var ao_right := _fade(5, T, Vector2i(1, 0), 0.24)
	var ao_left := _fade(5, T, Vector2i(-1, 0), 0.24)
	for cy in grid.rows:
		for cx in grid.cols:
			if grid.kind[grid.idx(cx, cy)] == Grid.ROCK:
				continue
			var p0 := Vector2i(cx * T, cy * T)
			if _rock_at(grid, cx, cy - 1): # paredão logo acima: sombra de contato
				img.blend_rect(ao_below, Rect2i(0, 0, T, 14), p0 + Vector2i(0, 4))
			if _rock_at(grid, cx, cy + 1):
				img.blend_rect(ao_above, Rect2i(0, 0, T, 5), p0 + Vector2i(0, T - 5))
			if _rock_at(grid, cx - 1, cy):
				img.blend_rect(ao_right, Rect2i(0, 0, 5, T), p0)
			if _rock_at(grid, cx + 1, cy):
				img.blend_rect(ao_left, Rect2i(0, 0, 5, T), p0 + Vector2i(T - 5, 0))

	# 5) pedregulhos na base dos paredões
	if theme != "hive":
		for cy in range(0, grid.rows - 1):
			for cx in grid.cols:
				if grid.kind[grid.idx(cx, cy)] == Grid.ROCK and grid.kind[grid.idx(cx, cy + 1)] == Grid.GROUND and rnd.randf() < 0.45:
					var bx := cx * T + rnd.randi_range(4, T - 4)
					var by := (cy + 1) * T + rnd.randi_range(7, 12)
					_boulder(img, Vector2(bx, by), rnd.randf_range(3.0, 6.0))
	return { base = img, top = top, faces = faces }


## Mapa de relevo a partir do brilho da imagem (claro = alto). `faces` = retângulos que são
## paredes verticais voltadas para a câmera: ganham a normal "para baixo na tela".
static func normal_map(img: Image, strength: float, faces: Array) -> Image:
	var n: Image = img.duplicate()
	n.convert(Image.FORMAT_L8)
	n.bump_map_to_normal_map(strength)
	if n.get_format() != Image.FORMAT_RGBA8:
		n.convert(Image.FORMAT_RGBA8)
	var face := Color(0.5, 0.5 - 0.5 * 0.85, 0.5 + 0.5 * 0.53, 0.8)
	for r in faces:
		var rect: Rect2i = r
		n.blend_rect(_solid(rect.size.x, rect.size.y, face), Rect2i(Vector2i.ZERO, rect.size), rect.position)
	return n


## Ondulação larga da areia (dunas baixas, esticadas pelo vento) somada ao relevo fino: aparece
## como faixas suaves de luz e sombra quando o sol está baixo. Não mexe em piso metálico, ácido
## nem rocha. Feita em 1/4 da resolução (o laço por pixel em GDScript é lento) e ampliada.
static func add_dunes(n_img: Image, grid: Grid, seed_v: int) -> void:
	var q := 4
	var w := n_img.get_width() / q
	var h := n_img.get_height() / q
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 2
	var hm := noise.get_image(w / 3, h, false, false, true)
	hm.resize(w, h, Image.INTERPOLATE_CUBIC) # estica 3× na horizontal
	hm.bump_map_to_normal_map(6.0)
	if hm.get_format() != Image.FORMAT_RGBA8:
		hm.convert(Image.FORMAT_RGBA8)
	for y in h:
		var cy := mini(y * q / T, grid.rows - 1)
		for x in w:
			var i := grid.idx(mini(x * q / T, grid.cols - 1), cy)
			var c := hm.get_pixel(x, y)
			c.a = 0.5 if (grid.kind[i] == Grid.GROUND and grid.deco[i] != 95) else 0.0
			hm.set_pixel(x, y, c)
	hm.resize(n_img.get_width(), n_img.get_height(), Image.INTERPOLATE_BILINEAR)
	n_img.blend_rect(hm, Rect2i(0, 0, hm.get_width(), hm.get_height()), Vector2i.ZERO)


## Faixa preta que some na direção `dir` (para a oclusão na base das rochas).
static func _fade(w: int, h: int, dir: Vector2i, alpha: float) -> Image:
	var i := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var k := 0.0
			if dir.y > 0:
				k = 1.0 - float(y) / h
			elif dir.y < 0:
				k = float(y + 1) / h
			elif dir.x > 0:
				k = 1.0 - float(x) / w
			else:
				k = float(x + 1) / w
			i.set_pixel(x, y, Color(0, 0, 0, alpha * k * k))
	return i


static func _rock_at(grid: Grid, cx: int, cy: int) -> bool:
	return grid.in_bounds(cx, cy) and grid.kind[grid.idx(cx, cy)] == Grid.ROCK


static func _tile_fill(img: Image, src: Image, area: Rect2i) -> void:
	var sw := src.get_width()
	var sh := src.get_height()
	for y in range(area.position.y, area.end.y, sh):
		for x in range(area.position.x, area.end.x, sw):
			img.blit_rect(src, Rect2i(0, 0, mini(sw, area.end.x - x), mini(sh, area.end.y - y)), Vector2i(x, y))


static func _solid(w: int, h: int, c: Color) -> Image:
	var i := Image.create(w, h, false, Image.FORMAT_RGBA8)
	i.fill(c)
	return i


static func _blend_centered(img: Image, src: Image, center: Vector2i) -> void:
	var w := src.get_width()
	var h := src.get_height()
	var dst := center - Vector2i(w / 2, h / 2)
	var src_rect := Rect2i(0, 0, w, h)
	# recorta nas bordas da imagem
	if dst.x < 0:
		src_rect.position.x -= dst.x
		src_rect.size.x += dst.x
		dst.x = 0
	if dst.y < 0:
		src_rect.position.y -= dst.y
		src_rect.size.y += dst.y
		dst.y = 0
	src_rect.size.x = mini(src_rect.size.x, img.get_width() - dst.x)
	src_rect.size.y = mini(src_rect.size.y, img.get_height() - dst.y)
	if src_rect.size.x > 0 and src_rect.size.y > 0:
		img.blend_rect(src, src_rect, dst)


## Mancha circular com borda irregular, tirada de `tex` e tingida por `tint`.
static func _patch(tex: Image, rnd: RandomNumberGenerator, tint: Color, strength: float, size: int) -> Image:
	var i := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var tw := tex.get_width()
	var th := tex.get_height()
	var ox := rnd.randi_range(0, tw - 1)
	var oy := rnd.randi_range(0, th - 1)
	var ph := rnd.randf() * TAU
	for y in size:
		for x in size:
			var dx := (x + 0.5) / size - 0.5
			var dy := (y + 0.5) / size - 0.5
			var ang := atan2(dy, dx)
			var rad := 0.5 * (0.8 + 0.12 * sin(ang * 3.0 + ph) + 0.08 * sin(ang * 7.0 + ph * 2.0))
			var d := sqrt(dx * dx + dy * dy) / rad
			if d >= 1.0:
				i.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c := tex.get_pixel((x + ox) % tw, (y + oy) % th)
			c = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, 1.0)
			var a := clampf((1.0 - d) * 2.5, 0.0, 1.0) * strength
			if rnd.randf() < 0.15:
				a *= 0.5
			c.a = a
			i.set_pixel(x, y, c)
	return i


static func _fertile_patch(tex: Image, rnd: RandomNumberGenerator) -> Image:
	# mancha larga e suave: as vizinhas se fundem num canteiro só (antes formavam um xadrez)
	var i := _patch(tex, rnd, Color(0.62, 0.5, 0.3), 0.5, 80)
	for n in 14:
		var x := rnd.randi_range(26, 54)
		var y := rnd.randi_range(26, 54)
		i.set_pixel(x, y, Color(0.38, 0.6, 0.18, 1.0))
		i.set_pixel(x, y - 1, Color(0.5, 0.75, 0.25, 1.0))
		if rnd.randf() < 0.4:
			i.set_pixel(x + 1, y - 1, Color(0.5, 0.75, 0.25, 1.0))
	return i


static func _speckle(rnd: RandomNumberGenerator, c: Color, density: float) -> Image:
	var i := Image.create(T, T, false, Image.FORMAT_RGBA8)
	i.fill(Color(0, 0, 0, 0))
	for y in T:
		for x in T:
			var d := Vector2(x - T * 0.5, y - T * 0.5).length() / (T * 0.7)
			if rnd.randf() < density * (1.0 - d):
				i.set_pixel(x, y, c)
	return i


static func _fertile_tile(rnd: RandomNumberGenerator) -> Image:
	var i := _speckle(rnd, Color(0.32, 0.2, 0.08, 0.35), 0.9)
	for n in 10:
		var x := rnd.randi_range(2, T - 3)
		var y := rnd.randi_range(2, T - 3)
		i.set_pixel(x, y, Color(0.45, 0.65, 0.2, 0.9))
		i.set_pixel(x, y - 1, Color(0.55, 0.75, 0.25, 0.9))
	return i


static func _metal_tile(rnd: RandomNumberGenerator) -> Image:
	var i := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var base := Color("5d646d")
	i.fill(base)
	for n in 60:
		i.set_pixel(rnd.randi_range(0, T - 1), rnd.randi_range(0, T - 1), base.lightened(0.06) if rnd.randf() < 0.5 else base.darkened(0.06))
	i.fill_rect(Rect2i(0, 0, T, 1), base.lightened(0.18))
	i.fill_rect(Rect2i(0, 0, 1, T), base.lightened(0.12))
	i.fill_rect(Rect2i(0, T - 1, T, 1), base.darkened(0.35))
	i.fill_rect(Rect2i(T - 1, 0, 1, T), base.darkened(0.3))
	for p in [Vector2i(3, 3), Vector2i(T - 4, 3), Vector2i(3, T - 4), Vector2i(T - 4, T - 4)]:
		i.set_pixelv(p, base.darkened(0.45))
	return i


static func _creep_blob(creep: Image, rnd: RandomNumberGenerator) -> Image:
	# 3×3 tiles de trepadeira com bordas suaves (alfa por ruído)
	var s := T * 3
	var i := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var cw := creep.get_width()
	var chh := creep.get_height()
	for y in s:
		for x in s:
			var c := creep.get_pixel(x % cw, y % chh)
			var lx := float(x % T) / T - 0.5
			var ly := float(y % T) / T - 0.5
			var edge := 1.0 - clampf(Vector2(lx, ly).length() * 1.6, 0.0, 1.0)
			c.a = clampf(edge * 1.6 + rnd.randf_range(-0.3, 0.2), 0.0, 0.85)
			i.set_pixel(x, y, c)
	return i


static func _acid_cell(img: Image, grid: Grid, cx: int, cy: int, rnd: RandomNumberGenerator) -> void:
	var base := Color("3f8f2a")
	var x0 := cx * T
	var y0 := cy * T
	img.fill_rect(Rect2i(x0, y0, T, T), base)
	for n in 14:
		img.set_pixel(x0 + rnd.randi_range(0, T - 1), y0 + rnd.randi_range(0, T - 1), Color("8fe04a"))
	for n in 3:
		var bx := x0 + rnd.randi_range(4, T - 6)
		var by := y0 + rnd.randi_range(4, T - 6)
		img.fill_rect(Rect2i(bx, by, 3, 2), Color("c8ff7a"))
	# margem escura onde encosta em chão seco
	var dark := Color("23461a")
	if not _is_kind(grid, cx, cy - 1, Grid.ACID):
		img.fill_rect(Rect2i(x0, y0, T, 3), dark)
	if not _is_kind(grid, cx, cy + 1, Grid.ACID):
		img.fill_rect(Rect2i(x0, y0 + T - 2, T, 2), Color("6aa83a"))
	if not _is_kind(grid, cx - 1, cy, Grid.ACID):
		img.fill_rect(Rect2i(x0, y0, 2, T), dark)
	if not _is_kind(grid, cx + 1, cy, Grid.ACID):
		img.fill_rect(Rect2i(x0 + T - 2, y0, 2, T), dark)


static func _is_kind(grid: Grid, cx: int, cy: int, k: int) -> bool:
	if not grid.in_bounds(cx, cy):
		return true
	return grid.kind[grid.idx(cx, cy)] == k


static func _rock_cell(img: Image, grid: Grid, cx: int, cy: int, rock: Image, cliff: Image, alien: bool, hive: bool, rnd: RandomNumberGenerator, faces: Array) -> void:
	var x0 := cx * T
	var y0 := cy * T
	if hive:
		# parede de instalação: preta grossa com friso
		img.fill_rect(Rect2i(x0, y0, T, T), Color("15161a"))
		if not _is_kind(grid, cx, cy + 1, Grid.ROCK):
			img.fill_rect(Rect2i(x0, y0 + T - 10, T, 10), Color("3a3e46"))
			faces.append(Rect2i(x0, y0 + T - 10, T, 10))
			img.fill_rect(Rect2i(x0, y0 + T - 10, T, 2), Color("8a929c"))
		if not _is_kind(grid, cx, cy - 1, Grid.ROCK):
			img.fill_rect(Rect2i(x0, y0, T, 2), Color("8a929c"))
		return
	var face_below := not _is_kind(grid, cx, cy + 1, Grid.ROCK)
	var face_h := 0
	if face_below:
		face_h = 22 if _is_kind(grid, cx, cy - 1, Grid.ROCK) else 16
	var top_h := T - face_h
	# topo do platô
	var rw := rock.get_width()
	var rh := rock.get_height()
	var sx := (cx * T) % rw
	var sy := (cy * T) % rh
	img.blit_rect(rock, Rect2i(sx, sy, mini(T, rw - sx), mini(top_h, rh - sy)), Vector2i(x0, y0))
	if alien:
		img.blend_rect(_solid(T, top_h, Color(0.45, 0.15, 0.55, 0.45)), Rect2i(0, 0, T, top_h), Vector2i(x0, y0))
		for n in 6:
			img.set_pixel(x0 + rnd.randi_range(1, T - 2), y0 + rnd.randi_range(1, maxi(1, top_h - 2)), Color("e05ac8"))
	# bordas do topo: luz em cima/esquerda, sombra à direita
	var rim := Color(1, 1, 1, 0.35)
	var shade := Color(0, 0, 0, 0.35)
	if not _is_kind(grid, cx, cy - 1, Grid.ROCK):
		img.blend_rect(_solid(T, 2, rim), Rect2i(0, 0, T, 2), Vector2i(x0, y0))
	if not _is_kind(grid, cx - 1, cy, Grid.ROCK):
		img.blend_rect(_solid(2, top_h, rim), Rect2i(0, 0, 2, top_h), Vector2i(x0, y0))
	if not _is_kind(grid, cx + 1, cy, Grid.ROCK):
		img.blend_rect(_solid(3, T, shade), Rect2i(0, 0, 3, T), Vector2i(x0 + T - 3, y0))
	# paredão (face voltada para a câmera): usa o topo da textura (borda das escamas)
	# e "vaza" OVERHANG px para a célula de baixo, para o platô parecer mais alto
	if face_h > 0:
		var overhang := 8
		var total := mini(face_h + overhang, cliff.get_height())
		var cw := cliff.get_width()
		var csx := (cx * T) % cw
		var src := Rect2i(csx, 0, mini(T, cw - csx), total)
		var dst := Vector2i(x0, y0 + top_h)
		if dst.y + total > img.get_height():
			src.size.y = img.get_height() - dst.y
		img.blit_rect(cliff, src, dst)
		faces.append(Rect2i(dst, src.size))
		img.blend_rect(_solid(T, total, Color(0.25, 0.08, 0.02, 0.22)), Rect2i(0, 0, T, src.size.y), dst)
		if alien:
			img.blend_rect(_solid(T, total, Color(0.4, 0.1, 0.5, 0.35)), Rect2i(0, 0, T, src.size.y), dst)
		img.blend_rect(_solid(T, 2, Color(0, 0, 0, 0.45)), Rect2i(0, 0, T, 2), dst)
		if not _is_kind(grid, cx - 1, cy, Grid.ROCK):
			img.blend_rect(_solid(2, total, Color(0, 0, 0, 0.35)), Rect2i(0, 0, 2, src.size.y), dst)
		if not _is_kind(grid, cx + 1, cy, Grid.ROCK):
			img.blend_rect(_solid(3, total, Color(0, 0, 0, 0.35)), Rect2i(0, 0, 3, src.size.y), Vector2i(x0 + T - 3, dst.y))


static func _boulder(img: Image, c: Vector2, rad: float) -> void:
	var col := Color("a8703a")
	var hi := Color("d09a5a")
	var lo := Color("6e4422")
	var x0 := floori(c.x - rad - 1)
	var y0 := floori(c.y - rad - 1)
	for y in range(y0, ceili(c.y + rad) + 2):
		for x in range(x0, ceili(c.x + rad * 1.3) + 2):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := (x + 0.5 - c.x) / (rad * 1.3)
			var dy := (y + 0.5 - c.y) / rad
			var d := dx * dx + dy * dy
			if d <= 1.0:
				var p := lo if d > 0.7 else (hi if dx + dy < -0.6 else col)
				img.set_pixel(x, y, p)
			elif d <= 1.35 and dy > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.25))
