extends Node
## ART — contrato de sprites por nome (ver docs/GDD.md §7).
## Carrega res://assets/sprites/<nome>.png; se não existir, gera um placeholder procedural
## com a mesma grade de frames. Trocar a arte = trocar o PNG, sem tocar no código.

const DEFS := {
	soldier = { h = 5, v = 4, size = Vector2i(32, 40), offset = Vector2(0, -15) },
	bug = { h = 4, v = 2, size = Vector2i(42, 42), offset = Vector2.ZERO },
	larva = { h = 2, v = 1, size = Vector2i(20, 20), offset = Vector2.ZERO },
	mother = { h = 2, v = 1, size = Vector2i(72, 72), offset = Vector2.ZERO },
	nest = { h = 2, v = 1, size = Vector2i(56, 48), offset = Vector2(0, -10) },
	heart = { h = 2, v = 1, size = Vector2i(96, 80), offset = Vector2(0, -18) },
	flower = { h = 2, v = 1, size = Vector2i(20, 20), offset = Vector2.ZERO },
	pickups = { h = 6, v = 1, size = Vector2i(37, 37), offset = Vector2.ZERO },
	buggy = { h = 1, v = 1, size = Vector2i(64, 40), offset = Vector2.ZERO },
	dropship = { h = 1, v = 1, size = Vector2i(112, 72), offset = Vector2.ZERO },
	robot = { h = 2, v = 1, size = Vector2i(48, 48), offset = Vector2.ZERO },
}

## Texturas de terreno (sem grade de frames).
const TERRAIN := ["ground_sand", "rock_top", "cliff", "creep_ground"]

var _tex := {}
var _img := {}


func tex(key: String) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var t: Texture2D = null
	var path := "res://assets/sprites/%s.png" % key
	if ResourceLoader.exists(path):
		t = load(path)
	if t == null:
		t = ImageTexture.create_from_image(image(key))
	_tex[key] = t
	return t


## Imagem (RGBA8) do asset; usada pelo construtor de terreno. Procedural se o PNG não existir.
func image(key: String) -> Image:
	if _img.has(key):
		return _img[key]
	var img: Image = null
	var path := "res://assets/sprites/%s.png" % key
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		if t != null:
			img = t.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RGBA8)
	if img == null:
		img = _placeholder(key)
	_img[key] = img
	return img


func has_file(key: String) -> bool:
	return ResourceLoader.exists("res://assets/sprites/%s.png" % key)


func apply(s: Sprite2D, key: String) -> void:
	var d: Dictionary = DEFS[key]
	s.texture = tex(key)
	s.hframes = d.h
	s.vframes = d.v
	s.offset = d.offset
	s.frame = 0


# =============================================================================
# Placeholders procedurais (mesma grade do contrato). Só servem até a arte chegar.
# =============================================================================

func _placeholder(key: String) -> Image:
	match key:
		"ground_sand":
			return _noise_tex(128, Color("d9a24a"), Color("e8b860"), Color("c98c3a"), 7)
		"rock_top":
			return _noise_tex(128, Color("8c7e6e"), Color("a39582"), Color("6f6255"), 11)
		"creep_ground":
			return _noise_tex(128, Color("6b3a8c"), Color("8e4fb0"), Color("4a2660"), 13)
		"cliff":
			return _cliff_tex()
	if not DEFS.has(key):
		return Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var d: Dictionary = DEFS[key]
	var fs: Vector2i = d.size
	var img := Image.create(fs.x * d.h, fs.y * d.v, false, Image.FORMAT_RGBA8)
	for fy in d.v:
		for fx in d.h:
			var o := Vector2(fx * fs.x, fy * fs.y)
			_paint(img, key, o, fs, fx, fy)
	_outline(img)
	return img


func _noise_tex(size: int, base: Color, light: Color, dark: Color, seed_v: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = seed_v
	img.fill(base)
	for i in size * size / 6:
		var x := rnd.randi_range(0, size - 1)
		var y := rnd.randi_range(0, size - 1)
		img.set_pixel(x, y, light if rnd.randf() < 0.5 else dark)
	return img


func _cliff_tex() -> Image:
	var img := Image.create(128, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color("8e5427"))
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 5
	for row in 4:
		for i in 10:
			var cx := i * 14 + (7 if row % 2 else 0)
			var cy := row * 8 + 4
			_ellipse(img, Vector2(cx, cy), 7.0, 5.0, Color("b9773a").darkened(row * 0.08))
			_ellipse(img, Vector2(cx - 2, cy - 2), 3.0, 2.0, Color("d0904c").darkened(row * 0.08))
	return img


func _ellipse(img: Image, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var x0 := maxi(0, floori(c.x - rx))
	var x1 := mini(img.get_width() - 1, ceili(c.x + rx))
	var y0 := maxi(0, floori(c.y - ry))
	var y1 := mini(img.get_height() - 1, ceili(c.y + ry))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := (x + 0.5 - c.x) / rx
			var dy := (y + 0.5 - c.y) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, col)


func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := maxi(1, ceili(a.distance_to(b)))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var x := floori(p.x)
		var y := floori(p.y)
		if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
			img.set_pixel(x, y, col)


func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate()
	var dark := Color(0.08, 0.06, 0.06, 1.0)
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.5:
					img.set_pixel(x, y, dark)
					break


func _paint(img: Image, key: String, o: Vector2, fs: Vector2i, fx: int, fy: int) -> void:
	var c := o + Vector2(fs) * 0.5
	match key:
		"soldier":
			# coluna = direção (S, SE, L, NE, N); linha = passo
			var dirs := [Vector2(0, 1), Vector2(0.7, 0.7), Vector2(1, 0), Vector2(0.7, -0.7), Vector2(0, -1)]
			var dv: Vector2 = dirs[fx]
			var step := 3.0 if fy % 2 == 0 else 0.0
			var sgn := 1.0 if fy < 2 else -1.0
			var feet := o + Vector2(fs.x * 0.5, fs.y - 4)
			_ellipse(img, feet + Vector2(-4, -2 + step * sgn * 0.5), 2.5, 3.0, Color("c9a46a"))
			_ellipse(img, feet + Vector2(4, -2 - step * sgn * 0.5), 2.5, 3.0, Color("c9a46a"))
			_ellipse(img, feet + Vector2(0, -12), 7.0, 9.0, Color("6c8a3c"))
			_ellipse(img, feet + Vector2(0, -13), 5.0, 6.0, Color("3f5a26"))
			_ellipse(img, feet + Vector2(0, -25), 5.0, 5.0, Color("e0b088"))
			if fx < 4:
				_ellipse(img, feet + Vector2(-dv.x * 1.5, -27), 5.0, 3.0, Color("6b4423"))
			else:
				_ellipse(img, feet + Vector2(0, -25), 5.0, 5.0, Color("6b4423"))
			var gun_from := feet + Vector2(0, -14)
			_line(img, gun_from, gun_from + Vector2(dv.x, dv.y * 0.6) * 13.0, Color("2a2a2e"))
			_line(img, gun_from + Vector2(0, 1), gun_from + Vector2(dv.x, dv.y * 0.6) * 13.0 + Vector2(0, 1), Color("2a2a2e"))
		"bug", "larva":
			var k := 1.0 if key == "bug" else 0.5
			var leg := 3.0 * k if fx % 2 == 0 else -3.0 * k
			if key == "bug" and fy == 1 and fx >= 2:
				_ellipse(img, c, 14.0 * k, 9.0 * k, Color("b8c060") if fx == 3 else Color("c9a97a"))
				return
			for i in 4:
				var lx := (i - 1.5) * 6.0 * k + (leg if i % 2 == 0 else -leg)
				_line(img, c + Vector2(lx, 0), c + Vector2(lx * 1.3, -16.0 * k), Color("8a6a44"))
				_line(img, c + Vector2(lx, 0), c + Vector2(lx * 1.3, 16.0 * k), Color("8a6a44"))
			_ellipse(img, c + Vector2(-3 * k, 0), 11.0 * k, 9.0 * k, Color("e8d2a6"))
			_ellipse(img, c + Vector2(-5 * k, -2 * k), 6.0 * k, 4.0 * k, Color("f4e6c4"))
			_ellipse(img, c + Vector2(9 * k, 0), 5.0 * k, 5.0 * k, Color("c9a97a"))
			img.set_pixelv(Vector2i(c + Vector2(11 * k, -2 * k)), Color("e05ac8"))
			img.set_pixelv(Vector2i(c + Vector2(11 * k, 2 * k)), Color("e05ac8"))
		"mother":
			var swell := 1.0 + fx * 0.08
			for i in 4:
				var lx := (i - 1.5) * 9.0
				_line(img, c + Vector2(lx, 0), c + Vector2(lx * 1.2, -26), Color("8a6a44"))
				_line(img, c + Vector2(lx, 0), c + Vector2(lx * 1.2, 26), Color("8a6a44"))
			_ellipse(img, c + Vector2(-6, 0), 24.0 * swell, 20.0 * swell, Color("e8a8b8"))
			_ellipse(img, c + Vector2(-10, -6), 10.0, 7.0, Color("f6d0dc"))
			_ellipse(img, c + Vector2(22, 0), 9.0, 8.0, Color("c9a97a"))
			_line(img, c + Vector2(-20, 4), c + Vector2(4, 10), Color("8e4fb0"))
		"nest", "heart":
			var big := 1.0 if key == "nest" else 1.7
			var p := 1.0 + fx * 0.06
			_ellipse(img, c + Vector2(0, 8 * big), 24.0 * big, 10.0 * big, Color("6b3a8c"))
			_ellipse(img, c + Vector2(0, 2), 20.0 * big * p, 16.0 * big * p, Color("7a5236") if key == "nest" else Color("8a2f6a"))
			_ellipse(img, c + Vector2(-5, -4), 8.0 * big, 6.0 * big, Color("9a6e4a") if key == "nest" else Color("c0508f"))
			_ellipse(img, c + Vector2(0, -4 * big), 5.0 * big, 3.0 * big, Color("ff5ad8") if fx == 1 else Color("c03ca8"))
			if key == "heart":
				_ellipse(img, c + Vector2(0, -2), 6.0, 9.0, Color("ff3b5c"))
		"flower":
			if fx == 0:
				_ellipse(img, c + Vector2(0, 2), 3.0, 5.0, Color("5f9a3a"))
				_ellipse(img, c + Vector2(0, -2), 2.0, 2.0, Color("8e4fb0"))
			else:
				for i in 5:
					var a := TAU * i / 5.0
					_ellipse(img, c + Vector2(cos(a), sin(a)) * 5.0, 3.5, 3.5, Color("e05ac8"))
				_ellipse(img, c, 2.5, 2.5, Color("fff2a0"))
		"pickups":
			var cols := [Color("e8c040"), Color("a8c4dc"), Color("c07a3a"), Color("d23c2c"), Color("3c7ad2"), Color("5a6a2c")]
			_ellipse(img, c, 12.0, 12.0, cols[fx])
			_ellipse(img, c + Vector2(-3, -3), 5.0, 5.0, Color(cols[fx]).lightened(0.4))
		"buggy":
			img.fill_rect(Rect2i(Vector2i(o + Vector2(8, 10)), Vector2i(48, 20)), Color("5a6e30"))
			for wp in [Vector2(14, 6), Vector2(14, 30), Vector2(48, 6), Vector2(48, 30)]:
				img.fill_rect(Rect2i(Vector2i(o + wp - Vector2(5, 3)), Vector2i(10, 6)), Color("1e1e1e"))
			img.fill_rect(Rect2i(Vector2i(o + Vector2(30, 12)), Vector2i(4, 16)), Color("2e3a1a"))
		"dropship":
			_ellipse(img, c, 50.0, 14.0, Color("7d858f"))
			_ellipse(img, c + Vector2(-10, -24), 22.0, 8.0, Color("5d646d"))
			_ellipse(img, c + Vector2(-10, 24), 22.0, 8.0, Color("5d646d"))
			_ellipse(img, c + Vector2(-30, -24), 6.0, 5.0, Color("d23c2c"))
			_ellipse(img, c + Vector2(-30, 24), 6.0, 5.0, Color("d23c2c"))
			_ellipse(img, c + Vector2(36, 0), 8.0, 6.0, Color("9fe8ff"))
		"robot":
			if fx == 0:
				img.fill_rect(Rect2i(Vector2i(o + Vector2(8, 10)), Vector2i(32, 28)), Color("5b636e"))
				img.fill_rect(Rect2i(Vector2i(o + Vector2(6, 6)), Vector2i(36, 6)), Color("2a2f36"))
				img.fill_rect(Rect2i(Vector2i(o + Vector2(6, 36)), Vector2i(36, 6)), Color("2a2f36"))
			else:
				_ellipse(img, c, 10.0, 10.0, Color("6c8a3c"))
				img.fill_rect(Rect2i(Vector2i(c + Vector2(4, -4)), Vector2i(16, 3)), Color("2a2a2e"))
				img.fill_rect(Rect2i(Vector2i(c + Vector2(4, 1)), Vector2i(16, 3)), Color("2a2a2e"))
