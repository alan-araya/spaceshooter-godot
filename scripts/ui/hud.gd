class_name Hud
extends Control
## HUD: faixa superior (tropas, tempo, painéis P1–P4, méritos), rodapé (objetivo) e mensagens.

var world: World
var players := 1
var _toasts: VBoxContainer
var _font: Font


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(0, Bal.HUD_TOP + 6)
	_toasts.size = Vector2(Bal.WORLD_W, 120)
	_toasts.add_theme_constant_override("separation", 0)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)


func bind(w: World, n_players: int) -> void:
	world = w
	players = n_players
	w.toast_requested.connect(show_toast)


func show_toast(text: String, color: Color) -> void:
	var l := UiKit.label(text, 19, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(Bal.WORLD_W, 24)
	l.add_theme_constant_override("outline_size", 6)
	_toasts.add_child(l)
	while _toasts.get_child_count() > 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var W := float(Bal.WORLD_W)
	# faixa superior
	draw_rect(Rect2(0, 0, W, Bal.HUD_TOP), Color("1b1d22"))
	draw_rect(Rect2(0, Bal.HUD_TOP - 3, W, 3), Color("4a505b"))
	_rivets(Rect2(0, 0, W, Bal.HUD_TOP))
	# tropas
	_panel(Rect2(8, 6, 196, 36))
	_draw_soldier_icon(Vector2(30, 24))
	var tc := Color("ffffff") if world.troops > 3 else Color("ff5a5a")
	_text(Vector2(52, 36), "%02d" % world.troops, 30, tc)
	_text(Vector2(106, 22), "TROPAS", 11, UiKit.DIM)
	var t := int(world.time)
	_text(Vector2(106, 38), "%d:%02d" % [t / 60, t % 60], 16, UiKit.TEXT)
	# painéis dos jogadores
	var pw := 214.0
	var x0 := 220.0
	for c in world.commanders:
		var r := Rect2(x0 + c.pid * (pw + 8), 6, pw, 36)
		var col: Color = Bal.PLAYER_COLORS[c.pid]
		_panel(r)
		draw_rect(Rect2(r.position, Vector2(26, r.size.y)), col.darkened(0.35))
		_text(r.position + Vector2(4, 24), "P%d" % (c.pid + 1), 14, Color.WHITE)
		if c.dead:
			var msg := "VOLTA EM %ds" % ceili(c.respawn_timer) if c.respawn_timer > 0.0 else "SEM TROPAS"
			if c.disconnected:
				msg = "DESCONECTADO"
			_text(r.position + Vector2(34, 23), msg, 14, Color("ff7b6b"))
			continue
		var wlabel: String = Bal.WEAPONS[c.weapon].label
		var ammo := "∞" if c.ammo < 0 else str(c.ammo)
		_text(r.position + Vector2(34, 16), "%s %s" % [wlabel, ammo], 12, UiKit.TEXT)
		# granadas: um ícone por granada, logo abaixo da linha da arma
		for gi in c.grenades:
			_draw_grenade(r.position + Vector2(38 + gi * 9, 26))
		if c.grenades == 0:
			_text(r.position + Vector2(34, 32), "sem granadas", 10, UiKit.DIM)
		var olabel := String(Bal.ORDER_LABELS[c.order]).to_upper()
		var ow := _font.get_string_size(olabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_text(Vector2(r.end.x - 8 - ow, r.position.y + 32), olabel, 12, col)
		# vida
		var hk: float = c.hp / c.max_hp
		draw_rect(Rect2(r.end.x - 52, r.position.y + 8, 44, 6), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(r.end.x - 52, r.position.y + 8, 44 * hk, 6), Color("7dff6b") if hk > 0.4 else Color("ff5a5a"))
	# méritos
	_panel(Rect2(W - 150, 6, 142, 36))
	_text(Vector2(W - 140, 22), "MÉRITO", 11, UiKit.DIM)
	_text(Vector2(W - 140, 38), str(world.merit), 18, UiKit.AMBER)
	# rodapé
	var by := float(Bal.HUD_TOP + Bal.WORLD_H)
	draw_rect(Rect2(0, by, W, Bal.HUD_BOTTOM), Color("1b1d22"))
	draw_rect(Rect2(0, by, W, 2), Color("4a505b"))
	_text(Vector2(14, by + 22), "OBJETIVO: " + world.objective_text(), 15, UiKit.AMBER)
	var mname: String = world.mission.name
	_text(Vector2(W - 14 - _font.get_string_size(mname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, by + 22), mname, 14, UiKit.DIM)


func _panel(r: Rect2) -> void:
	draw_rect(r, Color("2c3038"))
	draw_rect(r, Color("4a505b"), false, 1.0)


func _rivets(r: Rect2) -> void:
	for x in range(int(r.position.x) + 4, int(r.end.x), 64):
		draw_rect(Rect2(x, 2, 2, 2), Color("5b616c"))


func _text(p: Vector2, s: String, fsize: int, col: Color) -> void:
	draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## Granada pequena (ícone de HUD, desenhada em pixels).
func _draw_grenade(p: Vector2) -> void:
	var o := Color(0.08, 0.06, 0.07)
	draw_rect(Rect2(p + Vector2(-3, -3), Vector2(7, 9)), o)
	draw_rect(Rect2(p + Vector2(-2, -2), Vector2(5, 7)), Color("5a6a2c"))
	draw_rect(Rect2(p + Vector2(-2, 0), Vector2(5, 1)), Color("3e4a1e"))
	draw_rect(Rect2(p + Vector2(-2, 2), Vector2(5, 1)), Color("3e4a1e"))
	draw_rect(Rect2(p + Vector2(-1, -2), Vector2(1, 2)), Color("9fb060"))
	draw_rect(Rect2(p + Vector2(-1, -5), Vector2(3, 2)), Color("8a929c"))
	draw_rect(Rect2(p + Vector2(2, -5), Vector2(2, 1)), Color("c9ced4"))


func _draw_soldier_icon(c: Vector2) -> void:
	var tex := Art.tex("soldier")
	var fs: Vector2i = Art.DEFS.soldier.size
	draw_texture_rect_region(tex, Rect2(c - Vector2(fs) * 0.5, Vector2(fs)), Rect2(Vector2(fs.x * 0, fs.y * 1), Vector2(fs)))
