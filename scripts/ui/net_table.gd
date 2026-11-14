class_name NetTable
extends Control
## Tabela de jogadores (segurar Tab ou o botão Back/View do controle): quem está na partida, quem hospeda,
## ping até o host e perda de pacotes. No cliente, uma linha extra com a saúde da conexão (folga de
## desenho, variação, estados perdidos e correção da previsão). Os números vêm do Net (o host mede e envia).

const W := 640.0
const ROW := 30.0

var players := 1
var replica: Replica
var force := false # -- --nettable: sempre aberta (screenshot)
var _t := 0.0
var _font: Font


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	visible = false


func _process(dt: float) -> void:
	var want := force or Input.is_action_pressed("scoreboard")
	if want != visible:
		visible = want
		queue_redraw()
	if visible:
		_t += dt
		if _t > 0.25:
			_t = 0.0
			queue_redraw()


static func ping_color(ms: float) -> Color:
	if ms < 0.0:
		return UiKit.DIM
	if ms < 70.0:
		return Color("7dff6b")
	if ms < 140.0:
		return Color("ffd23f")
	return Color("ff5a5a")


func _draw() -> void:
	var lines := _footer()
	var h := 76.0 + ROW * players + 26.0 * lines.size() + 10.0
	var x0 := (Bal.WORLD_W - W) * 0.5
	var y0 := Bal.HUD_TOP + 40.0
	draw_rect(Rect2(x0, y0, W, h), Color(0.07, 0.08, 0.1, 0.92))
	draw_rect(Rect2(x0, y0, W, h), Color("4a505b"), false, 2.0)
	_text(Vector2(x0 + 20, y0 + 32), L.t("NETTAB_TITLE"), 22, UiKit.AMBER)
	var cols := [x0 + 20, x0 + 150, x0 + 400, x0 + 520]
	var hy := y0 + 60
	_text(Vector2(cols[0], hy), L.t("NETTAB_PLAYER"), 14, UiKit.DIM)
	_text(Vector2(cols[1], hy), L.t("NETTAB_ROLE"), 14, UiKit.DIM)
	_text(Vector2(cols[2], hy), L.t("NETTAB_PING"), 14, UiKit.DIM)
	_text(Vector2(cols[3], hy), L.t("NETTAB_LOSS"), 14, UiKit.DIM)
	for pid in players:
		var y := hy + ROW * (pid + 1)
		var col: Color = Bal.PLAYER_COLORS[pid % Bal.PLAYER_COLORS.size()]
		draw_rect(Rect2(cols[0], y - 14, 12, 12), col)
		_text(Vector2(cols[0] + 20, y), "P%d" % (pid + 1), 18, col)
		var role := L.t("NETTAB_LOCAL")
		var ping := "—"
		var loss := "—"
		var pcol := UiKit.DIM
		if Net.is_online():
			var info: Dictionary = Net.netinfo.get(pid, Net.netinfo.get(str(pid), {}))
			var host: bool = info.get("host", pid == 0)
			role = L.t("NETTAB_HOST") if host else L.t("NETTAB_CLIENT")
			if host:
				ping = "0 ms"
				loss = "0%"
				pcol = ping_color(0.0)
			elif not info.is_empty() and float(info.get("rtt", -1.0)) >= 0.0:
				var ms := float(info.rtt)
				ping = "%d ms" % roundi(ms)
				loss = "%.1f%%" % (float(info.get("loss", 0.0)) * 100.0)
				pcol = ping_color(ms)
		if Net.is_online() and pid == Net.my_pid:
			role += " " + L.t("NETTAB_YOU")
		_text(Vector2(cols[1], y), role, 16, Color("e8e8e8"))
		_text(Vector2(cols[2], y), ping, 16, pcol)
		_text(Vector2(cols[3], y), loss, 16, Color("e8e8e8"))
	var fy := hy + ROW * players + 30
	for ln in lines:
		_text(Vector2(cols[0], fy), ln, 14, UiKit.DIM)
		fy += 26.0


func _footer() -> Array:
	var out: Array = []
	if not Net.is_online():
		out.append(L.t("NETTAB_HINT_LOCAL"))
	elif Net.is_host():
		out.append(L.t("NETTAB_HINT_HOST"))
	elif replica != null:
		var err := replica.predictor.err_avg if replica.predictor != null else 0.0
		out.append(L.t("NETTAB_CLIENT_LINE", {
			delay = roundi(replica.delay_ticks * 1000.0 / 60.0), jitter = roundi(replica.jitter_ms),
			lost = "%.1f" % (replica.snap_loss * 100.0), err = "%.1f" % err }))
	if Net.is_client():
		var link := "@NETTAB_LINK_IP"
		if Net.online_link == "direct":
			link = "@NETTAB_LINK_DIRECT"
		elif Net.online_link == "relay":
			link = "@NETTAB_LINK_RELAY"
		out.append(L.t("NETTAB_LINK", {link = link}))
	if Net.sim_active():
		out.append(L.t("NETTAB_SIM", {lag = roundi(Net.sim_lag), loss = "%.1f" % (Net.sim_loss * 100.0)}))
	return out


func _text(p: Vector2, s: String, size: int, col: Color) -> void:
	draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
