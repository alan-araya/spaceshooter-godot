class_name Atmosphere
extends Node2D
## ATMOSFERA — o ar da missão: sombras de nuvens passando, poeira/névoa que anda com o vento,
## partículas soltas (poeira, vaga-lumes, rajadas de areia) e esporos subindo dos ninhos.
## Configurada pelo clima (Ambience.PRESETS[...].atmo). Só aparência: tem o próprio sorteio e
## não toca na simulação. Desligada no nível gráfico baixo.

var world: World
var cfg: Dictionary
var active := false
var wind := Vector2(10, 4)
var t := 0.0
var rnd := RandomNumberGenerator.new()
var motes: Node2D
var spores: Node2D
var mp := PackedVector2Array() # posição de cada partícula solta
var mk := PackedFloat32Array() # fator de velocidade
var mph := PackedFloat32Array() # fase (pisca e balança)
var mote_color := Color(1, 1, 1, 0.5)
var mote_glow := false
var streak := false


func setup(w: World) -> void:
	world = w
	visibility_layer = Stage.LAYER_BOTH # contêiner: os filhos que brilham entram no buffer de brilho
	cfg = w.amb.get("atmo", {})
	active = w.visuals and Game.gfx >= 1
	if not active:
		return
	rnd.randomize()
	wind = cfg.get("wind", Vector2(10, 4))
	var area := Rect2(0, 0, Bal.WORLD_W, Bal.WORLD_H)
	var clouds: float = cfg.get("clouds", 0.0)
	if clouds > 0.0:
		_layer("Clouds", "res://shaders/clouds.gdshader", { strength = clouds, wind = wind }, area)
	var fog: float = cfg.get("fog", 0.0)
	if fog > 0.0:
		var fc: Color = cfg.get("fog_color", Color(0.8, 0.7, 0.6))
		_layer("Fog", "res://shaders/fog.gdshader", {
			density = fog, fog_color = Vector3(fc.r, fc.g, fc.b), wind = wind, streaks = float(cfg.get("streaks", 0.0)) }, area)
	var n: int = cfg.get("motes", 0)
	if Game.gfx == 1:
		n /= 2
	if n > 0:
		mote_color = cfg.get("mote_color", Color(1.0, 0.95, 0.8, 0.5))
		mote_glow = cfg.get("mote_glow", false)
		streak = float(cfg.get("streaks", 0.0)) > 0.0
		for i in n:
			mp.append(Vector2(rnd.randf() * area.size.x, rnd.randf() * area.size.y))
			mk.append(rnd.randf_range(0.6, 1.5))
			mph.append(rnd.randf() * TAU)
		motes = Node2D.new()
		motes.name = "Motes"
		motes.material = Art.unshaded(mote_glow)
		if mote_glow:
			motes.visibility_layer = Stage.LAYER_BOTH
		add_child(motes)
		motes.draw.connect(_draw_motes)
	spores = Node2D.new()
	spores.name = "Spores"
	spores.material = Art.unshaded(true)
	spores.visibility_layer = Stage.LAYER_BOTH
	add_child(spores)
	spores.draw.connect(_draw_spores)


func _layer(layer_name: String, shader_path: String, params: Dictionary, area: Rect2) -> void:
	var node := Node2D.new()
	node.name = layer_name
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	for key in params:
		m.set_shader_parameter(key, params[key])
	node.material = m
	add_child(node)
	node.draw.connect(_fill.bind(node, area))


func _fill(node: Node2D, area: Rect2) -> void:
	node.draw_rect(area, Color.WHITE)


func update(dt: float) -> void:
	if not active:
		return
	t += dt
	if motes != null:
		var w := float(Bal.WORLD_W)
		var h := float(Bal.WORLD_H)
		var wobble := 9.0 if mote_glow else 4.0
		for i in mp.size():
			var p := mp[i]
			var ph := mph[i]
			p += wind * (mk[i] * dt) + Vector2(sin(t * 0.9 + ph), cos(t * 0.7 + ph * 1.3)) * (wobble * dt)
			p.x = fposmod(p.x, w)
			p.y = fposmod(p.y, h)
			mp[i] = p
		motes.queue_redraw()
	spores.queue_redraw()


func _draw_motes() -> void:
	var dir := wind.normalized()
	for i in mp.size():
		var p := mp[i]
		var a := 0.45 + 0.4 * sin(t * 1.7 + mph[i] * 3.0)
		var c := Color(mote_color.r, mote_color.g, mote_color.b, mote_color.a * a)
		if streak:
			motes.draw_line(p, p - dir * (5.0 + 9.0 * mk[i]), c, 1.0)
		elif mote_glow:
			motes.draw_rect(Rect2(p, Vector2(2, 2)), c)
		else:
			motes.draw_rect(Rect2(p, Vector2(1.5, 1.5)), c)


## Esporos subindo dos ninhos vivos (posição calculada do tempo: não guarda estado).
func _draw_spores() -> void:
	for n in world.nests:
		if n.dead:
			continue
		var big: bool = n.kind == "heart"
		var base: Vector2 = n.position
		var count := 11 if big else 6
		var spread := 1.7 if big else 1.0
		for j in count:
			var ph := float(j) * 2.399 + base.x * 0.013
			var life := fmod(t * 0.2 + ph * 0.37, 1.0)
			var ang := ph + t * 0.35
			var rad := (16.0 + 26.0 * fmod(ph * 0.61, 1.0)) * spread
			var p := base + Vector2(cos(ang) * rad, sin(ang) * rad * 0.55 - life * 36.0)
			spores.draw_rect(Rect2(p, Vector2(2, 2)), Color(1.0, 0.45, 0.9, 0.75 * sin(life * PI)))
