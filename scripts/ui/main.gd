extends Node
## MAIN — máquina de estados: menu → missões → briefing → jogo ↔ pausa → resultado,
## e o fluxo em rede: menu de rede → lobby → jogo (host simula / cliente desenha a réplica).
## Simulação em passo fixo de 60 Hz (_physics_process).
## Argumentos de depuração (depois de "--"):
##   --mission=N --players=N --difficulty=facil|normal|dificil --autostart --unlockall
##   --test [--probe] [--timeline=m3]   testes headless
##   --shot=arquivo.png --shot-after=SEG --quit-after-shot   screenshot
##   --stress   mede um frame renderizado com 180 insetos
##   --loopback   jogo local desenhado por um mundo-réplica alimentado por snapshots (fase 0)
##   --net-host [--net-start-when=N]   hospeda e começa sozinho quando houver N jogadores
##   --net-join=IP [--net-bot]   entra; --net-bot manda comandos sintéticos (andar em círculo e atirar)
##   --net-log   imprime estatísticas de rede a cada 2 s · --quit-after=SEG

enum Screen { MENU, SELECT, BRIEFING, PLAYING, PAUSED, RESULT, NET_MENU, LOBBY }

const STEP := 1.0 / 60.0

var screen := Screen.MENU
var world: World
var replica: Replica
var game_root: Node2D
var hud: Hud
var hud_layer: CanvasLayer
var ui_layer: CanvasLayer
var ui: Control
var shake := 0.0
var args := {}
var _shot_timer := -1.0
var _quit_timer := -1.0
var _net_frame := 0
var _client_outcome_t := 0.0
var _overlay := false # menu de rede aberto sobre o jogo (a partida continua)
var _last_ip := "127.0.0.1"
var _loop_sim: World # --loopback: mundo-fantasma que simula
var _log_t := 0.0


func _ready() -> void:
	_parse_args()
	game_root = Node2D.new()
	game_root.name = "GameRoot"
	game_root.position = Vector2(0, Bal.HUD_TOP)
	add_child(game_root)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.status_changed.connect(_on_net_status)
	Net.start_requested.connect(_on_net_start)
	Net.lobby_requested.connect(show_lobby)
	Net.host_left.connect(_on_host_left)
	Net.peer_left.connect(_on_peer_left)
	Net.snapshot_received.connect(_on_snapshot)
	Net.events_received.connect(_on_events)
	if args.has("players"):
		Game.players = clampi(int(args.players), 1, 4)
	if args.has("difficulty") and Bal.DIFFICULTY.has(args.difficulty):
		Game.difficulty = args.difficulty
	if args.has("shot"):
		_shot_timer = float(args.get("shot-after", "4"))
	if args.has("quit-after"):
		_quit_timer = float(args["quit-after"])
	if args.has("mission"):
		Game.mission_index = clampi(int(args.mission) - 1, 0, Missions.count() - 1)
	if args.has("test"):
		var tests := SimTests.new()
		add_child(tests)
		tests.run.call_deferred(self)
		return
	if args.has("net-host"):
		_host()
		return
	if args.has("net-join"):
		_join(args["net-join"])
		return
	if args.has("mission"):
		if args.has("autostart"):
			start_mission()
		else:
			show_briefing()
	else:
		show_menu()


func _on_host_left(reason: String) -> void:
	_end_world()
	show_net_menu(reason)


func _on_peer_left(pid: int) -> void:
	if world != null and not world.replica:
		world.disconnect_commander(pid)


func _on_snapshot(bytes: PackedByteArray) -> void:
	if replica != null:
		replica.push_snapshot(bytes)


func _on_events(evs: Array) -> void:
	if replica != null:
		replica.push_events(evs)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"


# =============================================================================
# telas
# =============================================================================

func _clear_ui() -> void:
	if ui != null:
		ui.queue_free()
		ui = null
	_overlay = false


func _screen_root(dim: float = 0.0) -> Control:
	_clear_ui()
	var root := Control.new()
	root.theme = UiKit.theme()
	UiKit.full_rect(root)
	ui_layer.add_child(root)
	ui = root
	if dim > 0.0:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, dim)
		UiKit.full_rect(shade)
		root.add_child(shade)
	return root


func _background(root: Control) -> void:
	if Art.has_file("title_bg"):
		var bg_tex := TextureRect.new()
		bg_tex.texture = Art.tex("title_bg")
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		UiKit.full_rect(bg_tex)
		root.add_child(bg_tex)
	else:
		var bg := ColorRect.new()
		bg.color = Color("2a1a2e")
		UiKit.full_rect(bg)
		root.add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	UiKit.full_rect(shade)
	root.add_child(shade)


func _center_box(root: Control, y: float = 0.0) -> VBoxContainer:
	var center := CenterContainer.new()
	UiKit.full_rect(center)
	center.offset_top = y
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	return box


func _panel(box: Control, width: float = 0.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	if width > 0.0:
		panel.custom_minimum_size = Vector2(width, 0)
	box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	return v


func show_menu() -> void:
	screen = Screen.MENU
	_end_world()
	if Net.is_online():
		Net.leave()
	var root := _screen_root()
	_background(root)
	var logo := UiKit.label("ENXAME 2199", 84, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	logo.add_theme_constant_override("outline_size", 14)
	logo.position = Vector2(0, 70)
	logo.size = Vector2(1280, 100)
	root.add_child(logo)
	var sub := UiKit.label("UM COMANDANTE, UM PELOTÃO, UM PLANETA INFESTADO", 20, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 170)
	sub.size = Vector2(1280, 30)
	root.add_child(sub)
	var box := _center_box(root, 170)
	var play := UiKit.button("JOGAR", show_select)
	box.add_child(play)
	box.add_child(UiKit.button("JOGAR EM REDE", show_net_menu.bind("")))
	var cycle_players := func() -> void:
		Game.players = Game.players % 4 + 1
		Game.save()
		show_menu()
		_focus_index(2)
	box.add_child(UiKit.button("JOGADORES NESTE PC: %d" % Game.players, cycle_players))
	var dl: String = Bal.DIFFICULTY[Game.difficulty].label
	var cycle_diff := func() -> void:
		var i := Bal.DIFFICULTY_ORDER.find(Game.difficulty)
		Game.difficulty = Bal.DIFFICULTY_ORDER[(i + 1) % Bal.DIFFICULTY_ORDER.size()]
		Game.save()
		show_menu()
		_focus_index(3)
	box.add_child(UiKit.button("DIFICULDADE: %s" % dl.to_upper(), cycle_diff))
	box.add_child(UiKit.button("CONTROLES", show_controls))
	box.add_child(UiKit.button("SAIR", func(): get_tree().quit()))
	var foot := UiKit.label("Méritos: %d   ·   Inspirado na jogabilidade de clássicos de ação tática dos anos 2000. Arte e nomes originais." % Game.merit_total, 13, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	foot.position = Vector2(0, 690)
	foot.size = Vector2(1280, 20)
	root.add_child(foot)
	play.grab_focus.call_deferred()


func _focus_index(i: int) -> void:
	var btns := ui.find_children("*", "Button", true, false)
	if i < btns.size():
		(btns[i] as Button).grab_focus.call_deferred()


func show_controls() -> void:
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	var v := _panel(box)
	v.add_child(UiKit.label("CONTROLES (%d JOGADOR%s)" % [Game.players, "ES" if Game.players > 1 else ""], 26, UiKit.AMBER))
	for pid in Game.players:
		v.add_child(UiKit.label("P%d" % (pid + 1), 18, Bal.PLAYER_COLORS[pid]))
		v.add_child(UiKit.label(InputSetup.help_for(pid, Game.players), 15))
	v.add_child(UiKit.label("Esc / Start: pausa. Ordens: Normal → Atacar → Defender → Seguir.", 15, UiKit.DIM))
	var back := UiKit.button("VOLTAR", show_menu)
	box.add_child(back)
	back.grab_focus.call_deferred()


func show_select() -> void:
	screen = Screen.SELECT
	Sfx.play("ui_ok")
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	box.add_child(UiKit.label("ESCOLHA A MISSÃO", 34, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("Méritos: %d" % Game.merit_total, 16, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var first: Button = null
	for i in Missions.count():
		var m := Missions.get_mission(i)
		var done := " ✓" if Game.completed.has(i) else ""
		var pick := func() -> void:
			Game.mission_index = i
			show_briefing()
		var b := UiKit.button("%d. %s%s" % [i + 1, m.name, done], pick, 520)
		b.disabled = i >= Game.unlocked and not args.has("unlockall")
		box.add_child(b)
		if first == null and not b.disabled:
			first = b
	box.add_child(UiKit.button("VOLTAR", show_menu, 520))
	if first != null:
		first.grab_focus.call_deferred()


func _briefing_lines(v: VBoxContainer, mission_index: int, difficulty: String, players: int) -> void:
	var m := Missions.get_mission(mission_index)
	v.add_child(UiKit.label("MISSÃO %d — %s" % [mission_index + 1, String(m.name).to_upper()], 28, UiKit.AMBER))
	for line in m.briefing:
		v.add_child(UiKit.label(line, 17))
	v.add_child(UiKit.label("OBJETIVO: " + String(m.objective.text), 17, Color("9fe8ff")))
	var d: Dictionary = Bal.DIFFICULTY[difficulty]
	v.add_child(UiKit.label("Tropas: %d   ·   Dificuldade: %s   ·   Jogadores: %d" % [d.troops, d.label, players], 15, UiKit.DIM))


func show_briefing() -> void:
	screen = Screen.BRIEFING
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	var v := _panel(box, 820)
	_briefing_lines(v, Game.mission_index, Game.difficulty, Game.players)
	var go := UiKit.button("COMEÇAR", start_mission, 820)
	box.add_child(go)
	box.add_child(UiKit.button("VOLTAR", show_select, 820))
	go.grab_focus.call_deferred()


# =============================================================================
# telas de rede
# =============================================================================

func show_net_menu(message: String = "") -> void:
	screen = Screen.NET_MENU
	_end_world()
	if Net.is_online():
		Net.leave()
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	var v := _panel(box, 640)
	v.add_child(UiKit.label("JOGAR EM REDE", 32, UiKit.AMBER))
	v.add_child(UiKit.label("Um jogador hospeda (o PC dele roda a partida); os outros entram pelo IP.", 15, UiKit.DIM))
	v.add_child(UiKit.label("Rede local ou internet via rede virtual (ex.: Tailscale). Porta UDP %d." % Net.DEFAULT_PORT, 15, UiKit.DIM))
	if message != "":
		v.add_child(UiKit.label(message, 17, Color("ff9f43")))
	var host_btn := UiKit.button("HOSPEDAR PARTIDA", _host, 640)
	box.add_child(host_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var ip := LineEdit.new()
	ip.text = _last_ip
	ip.placeholder_text = "IP do host (ex.: 192.168.0.10)"
	ip.custom_minimum_size = Vector2(380, 46)
	ip.add_theme_font_size_override("font_size", 20)
	row.add_child(ip)
	var join_btn := UiKit.button("ENTRAR", func(): _join(ip.text.strip_edges()), 250)
	row.add_child(join_btn)
	ip.text_submitted.connect(func(t: String): _join(t.strip_edges()))
	box.add_child(UiKit.button("VOLTAR", show_menu, 640))
	host_btn.grab_focus.call_deferred()


func _host() -> void:
	var err := Net.host_game()
	if err != OK:
		show_net_menu("Não foi possível hospedar (erro %d). A porta %d pode estar em uso." % [err, Net.DEFAULT_PORT])
		return
	Net.set_lobby(Game.mission_index, Game.difficulty)
	show_lobby()


func _join(address: String) -> void:
	if address == "":
		return
	_last_ip = address
	var err := Net.join_game(address)
	if err != OK:
		show_net_menu("Endereço inválido ou erro %d." % err)
		return
	show_lobby()


func show_lobby() -> void:
	screen = Screen.LOBBY
	_end_world()
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	var v := _panel(box, 860)
	var title := "LOBBY — VOCÊ HOSPEDA" if Net.is_host() else "LOBBY"
	v.add_child(UiKit.label(title, 30, UiKit.AMBER))
	if Net.is_host():
		var ips := Net.local_addresses()
		var ip_txt := ", ".join(ips) if not ips.is_empty() else "(sem rede local)"
		v.add_child(UiKit.label("Seu IP: %s   ·   porta %d" % [ip_txt, Net.DEFAULT_PORT], 16, Color("9fe8ff")))
	# jogadores
	var by_pid := {}
	for id in Net.roster:
		by_pid[int(Net.roster[id])] = int(id)
	for pid in Bal.MAX_PLAYERS:
		var txt := "P%d  —  " % (pid + 1)
		if by_pid.has(pid):
			txt += "host" if by_pid[pid] == 1 else "jogador conectado"
			if pid == Net.my_pid and Net.roster.has(multiplayer.get_unique_id()):
				txt += "  (você)"
			v.add_child(UiKit.label(txt, 18, Bal.PLAYER_COLORS[pid]))
		else:
			v.add_child(UiKit.label(txt + "vago", 18, UiKit.DIM))
	if Net.is_client() and Net.roster.is_empty():
		v.add_child(UiKit.label("Conectando…", 16, UiKit.DIM))
	v.add_child(UiKit.label(" ", 6))
	_briefing_lines(v, Net.lobby_mission, Net.lobby_difficulty, maxi(1, Net.player_count()))
	var first: Button = null
	if Net.is_host():
		var next_mission := func() -> void:
			Net.set_lobby((Net.lobby_mission + 1) % Missions.count(), Net.lobby_difficulty)
		var next_diff := func() -> void:
			var i := Bal.DIFFICULTY_ORDER.find(Net.lobby_difficulty)
			Net.set_lobby(Net.lobby_mission, Bal.DIFFICULTY_ORDER[(i + 1) % Bal.DIFFICULTY_ORDER.size()])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		row.add_child(UiKit.button("TROCAR MISSÃO", next_mission, 425))
		row.add_child(UiKit.button("TROCAR DIFICULDADE", next_diff, 425))
		first = UiKit.button("COMEÇAR (%d jogador%s)" % [Net.player_count(), "es" if Net.player_count() > 1 else ""], func(): Net.start_game(randi()), 860)
		box.add_child(first)
	else:
		box.add_child(UiKit.label("Aguardando o host começar a partida…", 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var leave := UiKit.button("SAIR DO LOBBY", show_net_menu.bind(""), 860)
	box.add_child(leave)
	(first if first != null else leave).grab_focus.call_deferred()


func _on_lobby_changed() -> void:
	if screen == Screen.LOBBY:
		var focused := get_viewport().gui_get_focus_owner()
		var focus_text := (focused as Button).text if focused is Button else ""
		show_lobby()
		if focus_text != "":
			for b in ui.find_children("*", "Button", true, false):
				if (b as Button).text.begins_with(focus_text.substr(0, 8)):
					(b as Button).grab_focus.call_deferred()
					break
	if args.has("net-start-when") and Net.is_host() and not Net.in_game:
		if Net.player_count() >= int(args["net-start-when"]):
			Net.start_game(randi())


func _on_net_status(text: String) -> void:
	if args.has("net-log"):
		print("NET ", text)


func _on_net_start(mission_index: int, difficulty: String, players: int, seed_v: int) -> void:
	Game.mission_index = mission_index
	Game.difficulty = difficulty
	start_mission(seed_v, players)


# =============================================================================
# partida
# =============================================================================

func start_mission(seed_v: int = -1, players: int = -1) -> void:
	_clear_ui()
	_end_world()
	Sfx.play("ui_ok")
	if seed_v < 0:
		seed_v = randi()
	if players < 0:
		players = Game.players
	InputSetup.reset()
	world = World.new()
	world.name = "World"
	game_root.add_child(world)
	world.setup(Game.mission_index, Game.difficulty, players, seed_v)
	world.shake_requested.connect(func(a: float): shake = maxf(shake, a))
	if Net.is_client():
		replica = Replica.new(world)
	elif Net.is_host():
		world.recording = true
	elif args.has("loopback"):
		# fase 0: um mundo-fantasma simula; o visível só desenha a partir de snapshots + eventos
		_loop_sim = World.new()
		_loop_sim.name = "LoopbackSim"
		_loop_sim.visible = false
		_loop_sim.present = false
		_loop_sim.recording = true
		game_root.add_child(_loop_sim)
		_loop_sim.setup(Game.mission_index, Game.difficulty, players, seed_v)
		replica = Replica.new(world)
	hud = Hud.new()
	hud.theme = UiKit.theme()
	hud_layer.add_child(hud)
	hud.bind(world, players)
	world.toast(String(world.mission.name).to_upper(), UiKit.AMBER)
	screen = Screen.PLAYING
	_net_frame = 0
	_client_outcome_t = 0.0
	if args.has("stress"):
		_start_stress()


## --stress: 180 insetos imortais + 40 soldados; mede o frame RENDERIZADO após 6 s e sai.
func _start_stress() -> void:
	for i in 180:
		var b := world.spawn_bug("bug", Vector2(760 + (i % 15) * 30, 40 + (i / 15) * 48), 0.0)
		if b != null:
			b.hp = 99999.0
			b.max_hp = 99999.0
	for i in 40:
		world.spawn_soldier(Vector2(120 + (i % 8) * 28, 180 + (i / 8) * 40), 0, 0.0)
	for c in world.commanders:
		c.god = true
	await get_tree().create_timer(6.0).timeout
	var fps := Engine.get_frames_per_second()
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("STRESS fps=%d process=%.2fms physics=%.2fms bugs=%d soldiers=%d decals=%d particles=%d draw_calls=%d" % [
		fps, proc, phys, world.bugs.size(), world.soldiers.size(), world.decal_layer.decal_count(), world.fx.parts.size(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()


func _end_world() -> void:
	if world != null:
		world.queue_free()
		world = null
	if _loop_sim != null:
		_loop_sim.queue_free()
		_loop_sim = null
	replica = null
	if hud != null:
		hud.queue_free()
		hud = null


func show_pause() -> void:
	if Net.is_online():
		_show_net_overlay()
		return
	screen = Screen.PAUSED
	var root := _screen_root(0.55)
	var box := _center_box(root)
	box.add_child(UiKit.label("PAUSA", 40, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	var cont := UiKit.button("CONTINUAR", _resume)
	box.add_child(cont)
	box.add_child(UiKit.button("REINICIAR MISSÃO", start_mission.bind(-1, -1)))
	box.add_child(UiKit.button("MENU PRINCIPAL", show_menu))
	cont.grab_focus.call_deferred()


## Em rede a partida não pausa: só abre um menu por cima.
func _show_net_overlay() -> void:
	var root := _screen_root(0.35)
	_overlay = true
	var box := _center_box(root)
	box.add_child(UiKit.label("A PARTIDA CONTINUA (REDE)", 28, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	var back := UiKit.button("VOLTAR AO JOGO", _clear_ui)
	box.add_child(back)
	if Net.is_host():
		box.add_child(UiKit.button("ENCERRAR E VOLTAR AO LOBBY", Net.back_to_lobby))
	box.add_child(UiKit.button("SAIR DA PARTIDA", show_net_menu.bind("")))
	back.grab_focus.call_deferred()


func show_result() -> void:
	screen = Screen.RESULT
	var win := world.outcome == "victory"
	if win:
		Game.mission_won(Game.mission_index, world.merit)
	else:
		Game.add_merit(world.merit / 2)
	var root := _screen_root(0.6)
	var box := _center_box(root)
	var v := _panel(box, 620)
	v.add_child(UiKit.label("MISSÃO CUMPRIDA!" if win else "MISSÃO FRACASSADA", 36, Color("7dff6b") if win else Color("ff5a5a"), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(world.outcome_reason, 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var s: Dictionary = world.stats
	var t := int(world.time)
	for line in [
		"Tempo: %d:%02d" % [t / 60, t % 60],
		"Aracnídeos abatidos: %d   ·   Matriarcas: %d" % [s.kills, s.mothers],
		"Ninhos destruídos: %d   ·   Flores arrancadas: %d" % [s.nests, s.flowers],
		"Tropas perdidas: %d   ·   Comandantes abatidos: %d" % [s.troops_lost, s.commander_deaths],
		"Mérito ganho: %d%s   ·   Total: %d" % [world.merit if win else world.merit / 2, "" if win else " (metade)", Game.merit_total],
	]:
		v.add_child(UiKit.label(line, 17, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if Net.is_online():
		_result_buttons_net(box, win)
		return
	var first: Button
	if win and Game.mission_index + 1 < Missions.count():
		var next_m := func() -> void:
			Game.mission_index += 1
			show_briefing()
		first = UiKit.button("PRÓXIMA MISSÃO", next_m, 620)
		box.add_child(first)
	if not win:
		var cost: int = Bal.MERIT.continue_cost
		var cont_m := func() -> void:
			if Game.spend_merit(cost):
				_continue_mission()
		var cb := UiKit.button("CONTINUAR (%d méritos)" % cost, cont_m, 620)
		cb.disabled = Game.merit_total < cost
		box.add_child(cb)
		if not cb.disabled:
			first = cb
	var retry := UiKit.button("TENTAR DE NOVO", start_mission.bind(-1, -1), 620)
	box.add_child(retry)
	box.add_child(UiKit.button("MENU PRINCIPAL", show_menu, 620))
	(first if first != null else retry).grab_focus.call_deferred()


func _result_buttons_net(box: VBoxContainer, win: bool) -> void:
	var first: Button = null
	if Net.is_host():
		if win and Net.lobby_mission + 1 < Missions.count():
			var next_m := func() -> void:
				Net.set_lobby(Net.lobby_mission + 1, Net.lobby_difficulty)
				Net.start_game(randi())
			first = UiKit.button("PRÓXIMA MISSÃO (TODOS)", next_m, 620)
			box.add_child(first)
		var retry := UiKit.button("TENTAR DE NOVO (TODOS)", func(): Net.start_game(randi()), 620)
		box.add_child(retry)
		if first == null:
			first = retry
		box.add_child(UiKit.button("VOLTAR AO LOBBY", Net.back_to_lobby, 620))
	else:
		box.add_child(UiKit.label("Aguardando o host escolher a próxima missão…", 17, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var leave := UiKit.button("SAIR DA PARTIDA", show_net_menu.bind(""), 620)
	box.add_child(leave)
	(first if first != null else leave).grab_focus.call_deferred()


## Continue: mesma missão, mesmo estado, com tropas repostas.
func _continue_mission() -> void:
	_clear_ui()
	world.outcome = ""
	world.outcome_timer = 0.0
	world.troops = Bal.DIFFICULTY[Game.difficulty].troops
	if world.generator != null and world.generator.dead:
		world.generator.dead = false
		world.generator.hp = world.generator.max_hp * 0.5
	for c in world.commanders:
		c.respawn_timer = 0.0
	world.toast("REFORÇOS ORBITAIS — CONTINUE A MISSÃO!", UiKit.AMBER)
	screen = Screen.PLAYING


# =============================================================================
# loop
# =============================================================================

func _physics_process(_delta: float) -> void:
	if screen == Screen.PLAYING and world != null:
		if Net.is_client():
			_tick_client()
		elif _loop_sim != null:
			_tick_loopback()
		else:
			_tick_sim()
		if Input.is_action_just_pressed("pause") and not _overlay:
			show_pause()
		if Input.is_action_just_pressed("debug_win") and OS.is_debug_build() and not world.replica:
			world.debug_kill_nests()
	elif screen == Screen.PAUSED and Input.is_action_just_pressed("pause"):
		_resume()


## Jogo local ou HOST: lê comandos, simula e (host) envia estado + eventos.
func _tick_sim() -> void:
	for c in world.commanders:
		if not Net.is_online():
			InputSetup.read_into(c, Game.players)
		elif c.pid == Net.my_pid:
			InputSetup.read_into(c, 1, 0)
		else:
			Net.apply_remote(c)
	world.update(STEP)
	if Net.is_host():
		_net_frame += 1
		if _net_frame % Net.SNAPSHOT_EVERY == 0:
			Net.broadcast_state(Snapshot.encode(world), world.net_events)
			world.net_events = []
	if world.outcome != "" and world.outcome_timer > 2.5:
		show_result()


## CLIENTE: só manda os comandos; o desenho vem do Replica (em _process).
func _tick_client() -> void:
	var cmd: CmdInput
	if args.has("net-bot"):
		cmd = _bot_cmd()
	else:
		cmd = InputSetup.sample(0, 1)
	Net.send_input(cmd)
	if world.outcome != "":
		_client_outcome_t += STEP
		if _client_outcome_t > 2.5:
			show_result()


var _bot := CmdInput.new()


func _bot_cmd() -> CmdInput:
	var a := Time.get_ticks_msec() / 1500.0
	_bot.move = Vector2(cos(a), sin(a))
	_bot.fire = true
	if Engine.get_physics_frames() % 240 == 0:
		_bot.grenade_n = (_bot.grenade_n + 1) & 255
	return _bot


## --loopback: o mundo-fantasma simula com os comandos locais; o visível é uma réplica.
func _tick_loopback() -> void:
	for c in _loop_sim.commanders:
		InputSetup.read_into(c, Game.players)
	_loop_sim.update(STEP)
	_net_frame += 1
	if _net_frame % Net.SNAPSHOT_EVERY == 0:
		replica.push_snapshot(Snapshot.encode(_loop_sim))
		replica.push_events(_loop_sim.net_events)
		_loop_sim.net_events = []
	if world.outcome != "":
		_client_outcome_t += STEP
		if _client_outcome_t > 2.5:
			show_result()


func _resume() -> void:
	_clear_ui()
	screen = Screen.PLAYING


func _process(delta: float) -> void:
	if replica != null and world != null and screen in [Screen.PLAYING, Screen.RESULT]:
		replica.render(delta)
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 30.0)
		game_root.position = Vector2(0, Bal.HUD_TOP) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	else:
		game_root.position = Vector2(0, Bal.HUD_TOP)
	if _shot_timer >= 0.0:
		_shot_timer -= delta
		if _shot_timer < 0.0:
			_save_shot(args.shot)
	if _quit_timer >= 0.0:
		_quit_timer -= delta
		if _quit_timer < 0.0:
			_quit_timer = -1.0
			_net_log()
			Net.leave()
			get_tree().quit()
	if args.has("net-log"):
		_log_t += delta
		if _log_t >= 2.0:
			_log_t = 0.0
			_net_log()


func _net_log() -> void:
	if not args.has("net-log"):
		return
	var st: Dictionary = Net.stats
	var info := "mode=%s screen=%d players=%d" % [["offline", "host", "client"][Net.mode], screen, Net.player_count()]
	if world != null:
		var p2 := "-"
		if world.commanders.size() > 1:
			var c2: Commander = world.commanders[1]
			p2 = "(%d,%d)%s" % [c2.position.x, c2.position.y, " morto" if c2.dead else ""]
		info += " t=%.1f bugs=%d soldiers=%d P2=%s" % [world.time, world.bugs.size(), world.soldiers.size(), p2]
	if Net.is_host():
		var kb: float = st.bytes_out / 1024.0
		info += " snaps_out=%d kb_out=%.0f inputs_in=%d" % [st.snapshots_out, kb, st.inputs_in]
	elif Net.is_client() and replica != null:
		info += " snaps_in=%d render_tick=%.0f decals=%d" % [st.snapshots_in, replica.render_tick, world.decal_layer.decal_count()]
	print("NET ", info)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if screen in [Screen.SELECT, Screen.BRIEFING]:
			show_menu()
		elif screen == Screen.NET_MENU:
			show_menu()


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SCREENSHOT salvo em ", path)
	if args.has("quit-after-shot"):
		Net.leave()
		get_tree().quit()
