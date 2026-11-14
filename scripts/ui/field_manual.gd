class_name FieldManual
extends Control
## MANUAL DE CAMPO — tutorial ilustrado em páginas: missão, controles, jogo em grupo, inimigos e apoio.
## Abre sozinho antes da primeira partida da missão 1 e pelo botão MANUAL DE CAMPO do menu.
## Ícones = os próprios sprites do jogo ampliados (batem com o que aparece na partida);
## ilustrações em assets/ui/ (geradas no Codex, processadas por tools/process_art.py tutorial).

signal closed

const W := 1140.0
const H := 600.0
const PAGES := ["MANUAL_PAGE_1", "MANUAL_PAGE_2", "MANUAL_PAGE_3", "MANUAL_PAGE_4", "MANUAL_PAGE_5"] # chaves de i18n

var page := 0
var finish_label := ""
var _body: Control
var _title: Label
var _dots: HBoxContainer
var _prev: Button
var _next: Button
var _anim: Array = [] # TextureRect animados: [rect, folha, frames, fps]
var _t := 0.0


func _init(finish_text: String = "") -> void:
	finish_label = finish_text if finish_text != "" else L.t("MANUAL_CLOSE")


func _ready() -> void:
	UiKit.full_rect(self)
	theme = UiKit.theme()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.82)
	UiKit.full_rect(shade)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2((1280.0 - W) * 0.5, (720.0 - H) * 0.5)
	panel.size = Vector2(W, H)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var tag := UiKit.label(L.t("MANUAL_MANUAL_DE_CAMPO"), 15, UiKit.DIM)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tag)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 6)
	head.add_child(_dots)
	_title = UiKit.label("", 32, UiKit.AMBER)
	col.add_child(_title)
	_body = Control.new()
	_body.custom_minimum_size = Vector2(W - 52, 420)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	var skip := UiKit.button(L.t("MANUAL_PULAR"), _close, 180)
	foot.add_child(skip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	_prev = UiKit.button(L.t("MANUAL_ANTERIOR"), func(): _go(page - 1), 220)
	foot.add_child(_prev)
	_next = UiKit.button(L.t("MANUAL_PROXIMO"), _on_next, 260)
	foot.add_child(_next)
	_show()
	_next.grab_focus.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	for a in _anim:
		var tr: TextureRect = a[0]
		var at := tr.texture as AtlasTexture
		var frames: Array = a[2]
		var f: int = frames[int(_t * float(a[3])) % frames.size()]
		at.region = _frame_rect(a[1], f)


## Setas viram a página (antes da navegação de foco entre botões); Esc fecha.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
	elif event.is_action_pressed("ui_right") and page < PAGES.size() - 1:
		get_viewport().set_input_as_handled()
		_go(page + 1)
	elif event.is_action_pressed("ui_left") and page > 0:
		get_viewport().set_input_as_handled()
		_go(page - 1)


func _on_next() -> void:
	if page >= PAGES.size() - 1:
		_close()
	else:
		_go(page + 1)


func _go(p: int) -> void:
	page = clampi(p, 0, PAGES.size() - 1)
	Sfx.play("ui_move")
	_show()


func _close() -> void:
	Sfx.play("ui_ok")
	closed.emit()
	queue_free()


func _show() -> void:
	for c in _body.get_children():
		c.queue_free()
	_anim.clear()
	_title.text = L.t(PAGES[page])
	for c in _dots.get_children():
		c.queue_free()
	for i in PAGES.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(26 if i == page else 10, 10)
		d.color = UiKit.AMBER if i == page else UiKit.METAL_HI
		_dots.add_child(d)
	_prev.disabled = page == 0
	_next.text = finish_label if page == PAGES.size() - 1 else L.t("MANUAL_PROXIMO")
	match page:
		0:
			_page_welcome()
		1:
			_page_controls()
		2:
			_page_coop()
		3:
			_page_enemies()
		4:
			_page_support()


# =============================================================================
# páginas
# =============================================================================

func _page_welcome() -> void:
	_illustration("tutorial_welcome", Rect2(0, 0, 600, 338))
	var v := _column(Rect2(624, 0, W - 52 - 624, 420))
	_para(v, L.t("MANUAL_UM_PLANETA_DESERTICO_FOI"), 18)
	_point(v, L.t("MANUAL_TROPAS_VIDAS"), L.t("MANUAL_CADA_SOLDADO_OU_COMANDANTE"))
	_point(v, L.t("MANUAL_O_COMANDANTE_VOLTA"), L.t("MANUAL_SE_VOCE_CAIR_RENASCE"))
	_point(v, L.t("MANUAL_DERROTA"), L.t("MANUAL_SEM_TROPAS_E_SEM"))
	_point(v, L.t("MANUAL_OBJETIVO"), L.t("MANUAL_APARECE_NO_RODAPE_DESTRUIR"))
	var cap := UiKit.label(L.t("MANUAL_USE_AS_SETAS_OU"), 14, UiKit.DIM)
	cap.position = Vector2(0, 350)
	cap.size = Vector2(600, 24)
	_body.add_child(cap)


func _page_controls() -> void:
	var kb := _column(Rect2(0, 0, 520, 300))
	kb.add_child(UiKit.label(L.t("MANUAL_TECLADO"), 18, UiKit.AMBER))
	_key_row(kb, ["W", "A", "S", "D"], L.t("MANUAL_MOVER_EM_8_DIRECOES"))
	_key_row(kb, [L.t("MANUAL_ESPACO")], L.t("MANUAL_ATIRAR_PARA_ONDE_ESTA"))
	_key_row(kb, ["SHIFT"], L.t("MANUAL_TRAVAR_A_MIRA_RECUAR"))
	_key_row(kb, ["E"], L.t("MANUAL_GRANADA_COMECA_COM_3"))
	_key_row(kb, ["Q"], L.t("MANUAL_TROCAR_A_ORDEM_DO"))
	_key_row(kb, ["1", "2", "3", "4"], L.t("MANUAL_ORDEM_DIRETA"))
	_key_row(kb, ["ESC"], L.t("MANUAL_PAUSA"))
	var ph := UiKit.label(L.t("MANUAL_CONTROLE"), 18, UiKit.AMBER)
	ph.position = Vector2(560, 0)
	_body.add_child(ph)
	var pad := PadDiagram.new()
	pad.position = Vector2(530, 22)
	pad.size = Vector2(W - 52 - 530, 270)
	_body.add_child(pad)
	var oh := UiKit.label(L.t("MANUAL_ORDENS_DO_PELOTAO_Q"), 16, UiKit.AMBER)
	oh.position = Vector2(0, 296)
	_body.add_child(oh)
	var rh := UiKit.label(L.t("MANUAL_ORDER_RADIUS"), 14, UiKit.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	rh.position = Vector2(560, 298)
	rh.size = Vector2(W - 52 - 560, 20)
	_body.add_child(rh)
	var orders := HBoxContainer.new()
	orders.position = Vector2(0, 324)
	orders.size = Vector2(W - 52, 100)
	orders.add_theme_constant_override("separation", 10)
	_body.add_child(orders)
	var info := [
		[L.t("MANUAL_NORMAL"), L.t("MANUAL_PATRULHAM_POR_PERTO_E")],
		[L.t("MANUAL_ATACAR"), L.t("MANUAL_AVANCAM_ATE_OS_INSETOS")],
		[L.t("MANUAL_DEFENDER"), L.t("MANUAL_SEGURAM_O_PONTO_ONDE")],
		[L.t("MANUAL_SEGUIR"), L.t("MANUAL_ANDAM_EM_FORMACAO_EM")],
	]
	for o in info:
		var card := _card(orders, Vector2(262, 90))
		card.add_child(UiKit.label(o[0], 17, Color("9fe8ff")))
		card.add_child(_wrap(o[1], 14))


func _page_coop() -> void:
	_illustration("tutorial_coop", Rect2(0, 0, 520, 293))
	var v := _column(Rect2(544, 0, W - 52 - 544, 420))
	v.add_child(UiKit.label(L.t("MANUAL_ATE_4_JOGADORES_NO"), 18, UiKit.AMBER))
	_para(v, L.t("MANUAL_ESCOLHA_JOGADORES_NESTE_PC"), 15)
	var rows := [
		[0, "P1", L.t("MANUAL_TECLADO_WASD_OU_CONTROLE")],
		[1, "P2", L.t("MANUAL_SETAS_NUM0_ATIRA_NUM1")],
		[2, "P3", L.t("MANUAL_CONTROLE_1_COM_3")],
		[3, "P4", L.t("MANUAL_CONTROLE_2")],
	]
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		var chip := ColorRect.new()
		chip.color = Bal.PLAYER_COLORS[r[0]]
		chip.custom_minimum_size = Vector2(36, 26)
		h.add_child(chip)
		var who := UiKit.label(r[1], 18, Bal.PLAYER_COLORS[r[0]])
		who.custom_minimum_size = Vector2(34, 0)
		h.add_child(who)
		var l := _wrap(r[2], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	_para(v, L.t("MANUAL_COM_1_JOGADOR_QUALQUER"), 14, UiKit.DIM)
	var net := _card_at(Rect2(0, 306, 520, 112))
	net.add_child(UiKit.label(L.t("MANUAL_JOGAR_EM_REDE"), 17, Color("9fe8ff")))
	net.add_child(_wrap(L.t("MANUAL_ATE_4_PCS_NA"), 14))


func _page_enemies() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(0, 0)
	grid.size = Vector2(W - 52, 420)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	_enemy(grid, "bug", [0, 1, 2, 3], 8, Color.WHITE, L.t("MANUAL_ARACNIDEO"), L.t("MANUAL_CORRE_EM_BANDO_CERCA"),
		L.t("MANUAL_ATAQUE_MORDIDA_E_BOTE"))
	_enemy(grid, "bug", [0, 1, 2, 3], 6, Color(0.8, 1.0, 0.72), L.t("MANUAL_CUSPIDOR"), L.t("MANUAL_ESVERDEADO_FICA_LONGE_E"),
		L.t("MANUAL_ATAQUE_CUSPE_DE_ACIDO"))
	_enemy(grid, "mother", [0, 1], 2, Color.WHITE, L.t("MANUAL_MATRIARCA"), L.t("MANUAL_NASCE_QUANDO_UM_ARACNIDEO"),
		L.t("MANUAL_ATAQUE_ACIDO_EM_ARCO"))
	_enemy(grid, "larva", [0, 1], 6, Color.WHITE, L.t("MANUAL_FILHOTE"), L.t("MANUAL_PEQUENO_E_RAPIDO_MORRE"),
		L.t("MANUAL_ATAQUE_MORDIDA"))
	_enemy(grid, "nest", [0, 1], 2, Color.WHITE, L.t("MANUAL_NINHO"), L.t("MANUAL_GERA_ARACNIDEOS_SEM_PARAR"),
		L.t("MANUAL_NAO_ATACA_PRIORIDADE_NAS"))
	_enemy(grid, "flower", [0, 1], 1, Color.WHITE, L.t("MANUAL_FLOR"), L.t("MANUAL_ABRE_DEPOIS_DE_ALGUNS"),
		L.t("MANUAL_PERIGO_ARACNIDEO_FLOR_ABERTA"))


func _page_support() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size = Vector2(W - 52, 260)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	var items := [
		[0, L.t("MANUAL_REFORCOS"), L.t("MANUAL_BUGGIES_ATROPELAM_INSETOS_E")],
		[1, L.t("MANUAL_ATAQUE_AEREO"), L.t("MANUAL_NAVE_SOLTA_SOLDADOS_E")],
		[2, L.t("MANUAL_APOIO_BLINDADO"), L.t("MANUAL_UM_ROBO_ALIADO_COM")],
		[3, L.t("MANUAL_LANCA_CHAMAS"), L.t("MANUAL_CONE_CURTO_QUE_ATRAVESSA")],
		[4, L.t("MANUAL_CANHAO_DE_PLASMA"), L.t("MANUAL_TIROS_PERFURANTES_QUE_EXPLODEM")],
		[5, L.t("MANUAL_3_GRANADAS"), L.t("MANUAL_ATE_9_NO_TOTAL")],
	]
	for it in items:
		var card := _card(grid, Vector2(354, 78))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		card.add_child(h)
		h.add_child(_sprite_icon("pickups", it[0], 1.6, Color.WHITE))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UiKit.label(it[1], 16, UiKit.AMBER))
		v.add_child(_wrap(it[2], 13))
	_para_at(Rect2(0, 186, W - 52, 24), L.t("MANUAL_SO_O_COMANDANTE_PEGA"), 14, UiKit.DIM)
	var th := UiKit.label(L.t("MANUAL_DICAS_DE_CAMPO"), 18, UiKit.AMBER)
	th.position = Vector2(0, 222)
	_body.add_child(th)
	var half := (W - 52 - 24) * 0.5
	var t1 := _column(Rect2(0, 254, half, 170))
	_point(t1, L.t("MANUAL_METRALHADORA_DE_PONTO"), L.t("MANUAL_PARE_AO_LADO_DE"))
	_point(t1, L.t("MANUAL_MUROS_E_PORTOES"), L.t("MANUAL_SEGURAM_O_ENXAME_MAS"))
	var t2 := _column(Rect2(half + 24, 254, half, 170))
	_point(t2, L.t("MANUAL_ANEL_VERMELHO_NA_BORDA"), L.t("MANUAL_HORDA_CHEGANDO_POR_ALI"))
	_point(t2, L.t("MANUAL_REVER_ESTE_MANUAL"), L.t("MANUAL_ELE_FICA_NO_MENU"))


# =============================================================================
# peças
# =============================================================================

func _column(r: Rect2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = r.position
	v.size = r.size
	v.add_theme_constant_override("separation", 8)
	_body.add_child(v)
	return v


func _wrap(text: String, size: int, color: Color = UiKit.TEXT) -> Label:
	var l := UiKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


func _para(parent: Control, text: String, size: int, color: Color = UiKit.TEXT) -> void:
	parent.add_child(_wrap(text, size, color))


func _para_at(r: Rect2, text: String, size: int, color: Color) -> void:
	var l := _wrap(text, size, color)
	l.position = r.position
	l.size = r.size
	_body.add_child(l)


func _point(parent: Control, head: String, text: String) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	parent.add_child(v)
	v.add_child(UiKit.label(L.t("MANUAL_") + head, 15, Color("9fe8ff")))
	v.add_child(_wrap(text, 15))


func _box_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17, 0.95)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _card(parent: Control, min_size: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override("panel", _box_style(UiKit.METAL_HI))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v


func _card_at(r: Rect2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = r.position
	p.size = r.size
	p.add_theme_stylebox_override("panel", _box_style(UiKit.METAL_HI))
	_body.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v


## Tecla desenhada: caixa clara com sombra embaixo, como uma tecla de verdade.
func _key(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("e9e2d0")
	sb.border_color = Color("8e8676")
	sb.border_width_bottom = 4
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(30, 30)
	var l := UiKit.label(text, 15, Color("23211d"), HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("outline_size", 0)
	p.add_child(l)
	return p


func _key_row(parent: Control, keys: Array, what: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	parent.add_child(h)
	var ks := HBoxContainer.new()
	ks.add_theme_constant_override("separation", 4)
	ks.custom_minimum_size = Vector2(190, 0)
	h.add_child(ks)
	for k in keys:
		ks.add_child(_key(k))
	var l := UiKit.label(what, 16)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)


func _illustration(key: String, r: Rect2) -> void:
	var frame := PanelContainer.new()
	frame.position = r.position - Vector2(3, 3)
	frame.size = r.size + Vector2(6, 6)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.border_color = UiKit.AMBER.darkened(0.3)
	sb.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", sb)
	_body.add_child(frame)
	var tr := TextureRect.new()
	var path := "res://assets/ui/%s.png" % key
	tr.texture = load(path) if ResourceLoader.exists(path) else Art.tex("title_bg")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # ilustração reduzida: suavizar
	tr.position = r.position
	tr.size = r.size
	tr.clip_contents = true
	_body.add_child(tr)


func _frame_rect(sheet: String, f: int) -> Rect2:
	var d: Dictionary = Art.DEFS[sheet]
	var fs := Vector2(d.size)
	return Rect2(Vector2((f % int(d.h)) * fs.x, (f / int(d.h)) * fs.y), fs)


func _sprite_icon(sheet: String, frame: int, scale_k: float, tint: Color) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = Art.tex(sheet)
	at.region = _frame_rect(sheet, frame)
	var tr := TextureRect.new()
	tr.texture = at
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = at.region.size * scale_k
	tr.modulate = tint
	return tr


func _enemy(grid: GridContainer, sheet: String, frames: Array, fps: float, tint: Color, name_txt: String, text: String, attack: String) -> void:
	var card := _card(grid, Vector2(354, 200))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var stage := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("b98a55") # chão de areia atrás do bicho
	sb.set_corner_radius_all(4)
	stage.add_theme_stylebox_override("panel", sb)
	stage.custom_minimum_size = Vector2(112, 112)
	h.add_child(stage)
	var big: Vector2 = Vector2(Art.DEFS[sheet].size)
	var k := minf(104.0 / big.x, 104.0 / big.y)
	k = maxf(1.0, floorf(k)) if k >= 1.0 else k
	var icon := _sprite_icon(sheet, frames[0], k, tint)
	stage.add_child(icon)
	if frames.size() > 1:
		_anim.append([icon, sheet, frames, fps])
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiKit.label(name_txt, 18, Color("ff9fdc")))
	v.add_child(_wrap(text, 14))
	var at := _wrap(attack, 13, Color("ffb36b"))
	at.position = Vector2(0, 0)
	card.add_child(at)


## Controle no estilo Xbox desenhado por código, com cada botão ligado à sua ação (página CONTROLES).
class PadDiagram extends Control:
	const BODY := Color("2d3138")
	const EDGE := Color("5b616c")
	const PART := Color("1c1f24")
	const LINE := Color(1.0, 0.79, 0.29, 0.75)

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 150.0)
		# gatilhos e botões de ombro
		_rect(c + Vector2(-112, -86), Vector2(48, 20), PART)
		_rect(c + Vector2(64, -86), Vector2(48, 20), PART)
		_rect(c + Vector2(-122, -63), Vector2(70, 13), Color("3a3f47"))
		_rect(c + Vector2(52, -63), Vector2(70, 13), Color("3a3f47"))
		_tag(c + Vector2(-88, -76), "LT")
		_tag(c + Vector2(88, -76), "RT")
		_tag(c + Vector2(-87, -57), "LB")
		_tag(c + Vector2(87, -57), "RB")
		# corpo: duas empunhaduras + centro
		for sx in [-1.0, 1.0]:
			draw_circle(c + Vector2(sx * 86.0, 22.0), 60.0, EDGE)
			draw_circle(c + Vector2(sx * 86.0, 22.0), 57.0, BODY)
		draw_rect(Rect2(c + Vector2(-110, -50), Vector2(220, 88)), BODY)
		draw_rect(Rect2(c + Vector2(-110, -52), Vector2(220, 3)), EDGE)
		# analógicos, direcional, botões
		_stick(c + Vector2(-66, -14))
		_stick(c + Vector2(32, 30))
		var dp := c + Vector2(-30, 30)
		draw_rect(Rect2(dp - Vector2(17, 6), Vector2(34, 12)), PART)
		draw_rect(Rect2(dp - Vector2(6, 17), Vector2(12, 34)), PART)
		var bc := c + Vector2(68, -14)
		_btn(bc + Vector2(0, -20), Color("e5c03a"), "Y")
		_btn(bc + Vector2(-20, 0), Color("3f86d8"), "X")
		_btn(bc + Vector2(20, 0), Color("d84a3f"), "B")
		_btn(bc + Vector2(0, 20), Color("4caf50"), "A")
		draw_circle(c + Vector2(-16, -26), 5.0, PART)
		draw_circle(c + Vector2(16, -26), 5.0, PART)
		draw_circle(c + Vector2(0, -38), 8.0, Color("6a7280"))
		# legendas: botão em âmbar + ação
		var l := 4.0
		var r := size.x - 4.0
		_label(Vector2(l, c.y - 112), "LT", L.t("MANUAL_TRAVAR_A_MIRA"), c + Vector2(-100, -80), false)
		_label(Vector2(l, c.y - 64), "LB / X", L.t("MANUAL_TROCAR_A_ORDEM"), c + Vector2(-110, -57), false)
		_label(Vector2(l, c.y + 14), L.t("MANUAL_ANALOGICO"), L.t("MANUAL_MOVER"), c + Vector2(-80, -8), false)
		_label(Vector2(r, c.y - 112), "RT / A", L.t("MANUAL_ATIRAR"), c + Vector2(100, -80), true)
		_label(Vector2(r, c.y - 64), "RB / B", L.t("MANUAL_GRANADA"), c + Vector2(110, -57), true)
		_label_top(Vector2(c.x, c.y - 128), "START", L.t("MANUAL_PAUSA"), c + Vector2(16, -30))

	## Legenda centralizada acima do controle, com linha descendo até o botão.
	func _label_top(center: Vector2, head: String, what: String, target: Vector2) -> void:
		_text_center(center + Vector2(0, 0), head + "  ·  " + what, 14, UiKit.AMBER)
		draw_line(center + Vector2(0, 6), target, LINE, 1.5)
		draw_circle(target, 2.5, LINE)

	func _rect(p: Vector2, s: Vector2, col: Color) -> void:
		draw_rect(Rect2(p, s), col)
		draw_rect(Rect2(p, s), EDGE, false, 1.0)

	func _stick(p: Vector2) -> void:
		draw_circle(p, 16.0, PART)
		draw_circle(p, 11.0, Color("454b55"))
		draw_arc(p, 11.0, 0.0, TAU, 20, Color("6a7280"), 1.5)

	func _btn(p: Vector2, col: Color, t: String) -> void:
		draw_circle(p, 10.0, PART)
		draw_circle(p, 8.5, col.darkened(0.15))
		_text_center(p + Vector2(0, 5), t, 12, Color.WHITE)

	func _tag(p: Vector2, t: String) -> void:
		_text_center(p + Vector2(0, 5), t, 11, Color("c8ccd3"))

	func _text_center(p: Vector2, t: String, fs: int, col: Color) -> void:
		var f := get_theme_default_font()
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, p - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	## Legenda em duas linhas (botão / ação) presa à beirada; linha até a peça do controle.
	func _label(anchor: Vector2, head: String, what: String, target: Vector2, right: bool) -> void:
		var f := get_theme_default_font()
		var w1 := f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var w2 := f.get_string_size(what, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var w := maxf(w1, w2)
		var x := anchor.x - w if right else anchor.x
		draw_string(f, Vector2(x if not right else anchor.x - w1, anchor.y + 14), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.AMBER)
		draw_string_outline(f, Vector2(x if not right else anchor.x - w2, anchor.y + 32), what, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 3, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(x if not right else anchor.x - w2, anchor.y + 32), what, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.TEXT)
		var from := Vector2((anchor.x - w - 6.0) if right else (anchor.x + w + 6.0), anchor.y + 20)
		draw_line(from, target, LINE, 1.5)
		draw_circle(target, 2.5, LINE)
