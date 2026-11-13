extends Node
## MAIN — máquina de estados: menu → missões → briefing → jogo ↔ pausa → resultado,
## e o fluxo em rede: menu de rede → lobby → jogo (host simula / cliente desenha a réplica).
## Simulação em passo fixo de 60 Hz (_physics_process).
## Argumentos de depuração (depois de "--"):
##   --mission=N --players=N --difficulty=facil|normal|dificil --autostart --unlockall
##   --gfx=alto|medio|baixo   qualidade gráfica só nesta execução
##   --lang=pt_BR|en_US|es|pt_PT|de|ja|zh_CN   idioma só nesta execução
##   --manual[=PÁGINA]   abre direto o manual de campo (screenshots)
##   --seed=N   semente fixa da missão (screenshots e medições repetíveis)
##   --fx-demo=SEG   aos SEG segundos dispara efeitos de explosão ao lado do P1 (só visual, para screenshot)
##   --hurt-demo=SEG   aos SEG segundos dispara o aviso de dano na tela
##   --test [--probe] [--timeline=m3]   testes headless
##   --shot=arquivo.png --shot-after=SEG --quit-after-shot   screenshot
##   --shot-all=PASTA [--shot-after=SEG]   uma janela só: joga cada missão SEG segundos e salva mN.png
##   --stress   mede um frame renderizado com 180 insetos
##   --loopback   jogo local desenhado por um mundo-réplica alimentado por snapshots (fase 0)
##   --net-host [--net-start-when=N]   hospeda e começa sozinho quando houver N jogadores
##   --net-join=IP [--net-bot]   entra; --net-bot manda comandos sintéticos (andar em círculo e atirar)
##   --net-port=N   porta UDP (testes com outro jogo aberto na máquina) · --net-version=X finge outra versão
##   --net-log   imprime estatísticas de rede a cada 2 s · --quit-after=SEG

enum Screen { MENU, SELECT, BRIEFING, PLAYING, PAUSED, RESULT, NET_MENU, LOBBY }

const STEP := 1.0 / 60.0

var screen := Screen.MENU
var world: World
var replica: Replica
var stage: Stage # palco: mundo num SubViewport + pós-processamento
var game_root: Node2D # raiz do mundo, dentro do palco
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
	stage = Stage.new()
	add_child(stage)
	game_root = stage.content
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
	if args.has("gfx") and Game.GFX_KEYS.has(args.gfx):
		Game.gfx = Game.GFX_KEYS[args.gfx]
	if args.has("lang"): # só nesta execução (screenshots e testes); não grava
		Game.set_language(args.lang)
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
	if args.has("net-version"): # depuração: finge outra versão para testar a recusa
		Net.version = args["net-version"]
	if args.has("net-host"):
		_host()
		return
	if args.has("shot-all"):
		_shot_all(args["shot-all"])
		return
	if args.has("net-join"):
		_join(args["net-join"])
		return
	if args.has("manual"):
		var m := show_manual(show_menu, L.t("MANUAL_BACK_TO_MENU"))
		if args["manual"] != "1":
			m._go(int(args["manual"]) - 1)
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
	var logo := UiKit.label(L.t("GAME_TITLE"), 84, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	logo.add_theme_constant_override("outline_size", 14)
	logo.position = Vector2(0, 70)
	logo.size = Vector2(1280, 100)
	root.add_child(logo)
	var sub := UiKit.label(L.t("MENU_TAGLINE"), 20, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 170)
	sub.size = Vector2(1280, 30)
	root.add_child(sub)
	var box := _center_box(root, 170)
	var play := UiKit.button(L.t("MENU_PLAY"), show_select)
	box.add_child(play)
	box.add_child(UiKit.button(L.t("MENU_NET"), show_net_menu.bind("")))
	var cycle_players := func() -> void:
		Game.players = Game.players % 4 + 1
		Game.save()
		show_menu()
		_focus_index(2)
	box.add_child(UiKit.button(L.t("MENU_PLAYERS", {n = Game.players}), cycle_players))
	var dl := L.t(Bal.DIFFICULTY[Game.difficulty].label)
	var cycle_diff := func() -> void:
		var i := Bal.DIFFICULTY_ORDER.find(Game.difficulty)
		Game.difficulty = Bal.DIFFICULTY_ORDER[(i + 1) % Bal.DIFFICULTY_ORDER.size()]
		Game.save()
		show_menu()
		_focus_index(3)
	box.add_child(UiKit.button(L.t("MENU_DIFFICULTY", {d = dl.to_upper()}), cycle_diff))
	var cycle_gfx := func() -> void:
		Game.gfx = (Game.gfx + 2) % 3 # alto → médio → baixo → alto
		Game.save()
		show_menu()
		_focus_index(4)
	box.add_child(UiKit.button(L.t("MENU_GFX", {g = "@" + Game.GFX_LABELS[Game.gfx]}), cycle_gfx))
	box.add_child(UiKit.button(L.t("MENU_MANUAL"), show_manual.bind(show_menu, L.t("MANUAL_BACK_TO_MENU"))))
	var cycle_lang := func() -> void:
		Game.cycle_language()
		show_menu()
		_focus_index(6)
	box.add_child(UiKit.button(L.t("MENU_LANGUAGE", {name = Game.LANGUAGE_NAMES[Game.language]}), cycle_lang))
	box.add_child(UiKit.button(L.t("MENU_QUIT"), func(): get_tree().quit()))
	var foot := UiKit.label(L.t("MENU_FOOTER", {m = Game.merit_total}), 13, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	foot.position = Vector2(0, 690)
	foot.size = Vector2(1280, 20)
	root.add_child(foot)
	play.grab_focus.call_deferred()


func _focus_index(i: int) -> void:
	var btns := ui.find_children("*", "Button", true, false)
	if i < btns.size():
		(btns[i] as Button).grab_focus.call_deferred()


## Manual de campo (tutorial ilustrado). `then` roda ao fechar.
func show_manual(then: Callable, finish_text: String) -> FieldManual:
	var root := _screen_root()
	_background(root)
	var m := FieldManual.new(finish_text)
	m.closed.connect(then)
	root.add_child(m)
	return m


## COMEÇAR no briefing: na primeira vez da missão 1, o manual vem antes.
func _begin_from_briefing() -> void:
	if Game.mission_index == 0 and not Game.tutorial_seen:
		Game.tutorial_seen = true
		Game.save()
		show_manual(start_mission.bind(-1, -1), L.t("MANUAL_START_MISSION"))
		return
	start_mission()


func show_select() -> void:
	screen = Screen.SELECT
	Sfx.play("ui_ok")
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	box.add_child(UiKit.label(L.t("SELECT_TITLE"), 34, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(L.t("SELECT_MERIT", {m = Game.merit_total}), 16, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var first: Button = null
	for i in Missions.count():
		var m := Missions.get_mission(i)
		var done := " ✓" if Game.completed.has(i) else ""
		var pick := func() -> void:
			Game.mission_index = i
			show_briefing()
		var b := UiKit.button(L.t("SELECT_ITEM", {n = i + 1, name = "@" + m.name}) + done, pick, 520)
		b.disabled = i >= Game.unlocked and not args.has("unlockall")
		box.add_child(b)
		if first == null and not b.disabled:
			first = b
	box.add_child(UiKit.button(L.t("BACK"), show_menu, 520))
	if first != null:
		first.grab_focus.call_deferred()


func _briefing_lines(v: VBoxContainer, mission_index: int, difficulty: String, players: int) -> void:
	var m := Missions.get_mission(mission_index)
	v.add_child(UiKit.label(L.t("BRIEF_TITLE", {n = mission_index + 1, name = L.t(m.name).to_upper()}), 28, UiKit.AMBER))
	for line in m.briefing:
		v.add_child(UiKit.label(L.t(line), 17))
	v.add_child(UiKit.label(L.t("BRIEF_OBJECTIVE", {text = "@" + m.objective.text}), 17, Color("9fe8ff")))
	var d: Dictionary = Bal.DIFFICULTY[difficulty]
	v.add_child(UiKit.label(L.t("BRIEF_FOOTER", {t = d.troops, d = "@" + d.label, p = players}), 15, UiKit.DIM))


func show_briefing() -> void:
	screen = Screen.BRIEFING
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	var v := _panel(box, 820)
	_briefing_lines(v, Game.mission_index, Game.difficulty, Game.players)
	var go := UiKit.button(L.t("BRIEF_START"), _begin_from_briefing, 820)
	box.add_child(go)
	box.add_child(UiKit.button(L.t("BACK"), show_select, 820))
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
	v.add_child(UiKit.label(L.t("NET_TITLE"), 32, UiKit.AMBER))
	v.add_child(UiKit.label(L.t("NET_HELP_1"), 15, UiKit.DIM))
	v.add_child(UiKit.label(L.t("NET_HELP_2", {port = Net.DEFAULT_PORT}), 15, UiKit.DIM))
	if message != "":
		v.add_child(UiKit.label(message, 17, Color("ff9f43")))
	var host_btn := UiKit.button(L.t("NET_HOST"), _host, 640)
	box.add_child(host_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var ip := LineEdit.new()
	ip.text = _last_ip
	ip.placeholder_text = L.t("NET_IP_HINT")
	ip.custom_minimum_size = Vector2(380, 46)
	ip.add_theme_font_size_override("font_size", 20)
	row.add_child(ip)
	var join_btn := UiKit.button(L.t("NET_JOIN"), func(): _join(ip.text.strip_edges()), 250)
	row.add_child(join_btn)
	ip.text_submitted.connect(func(t: String): _join(t.strip_edges()))
	box.add_child(UiKit.button(L.t("BACK"), show_menu, 640))
	host_btn.grab_focus.call_deferred()


func _host() -> void:
	var err := Net.host_game(int(args.get("net-port", Net.DEFAULT_PORT)))
	if err != OK:
		show_net_menu(L.t("NET_HOST_FAILED", {err = err, port = Net.DEFAULT_PORT}))
		return
	Net.set_lobby(Game.mission_index, Game.difficulty)
	show_lobby()


func _join(address: String) -> void:
	if address == "":
		return
	_last_ip = address
	var err := Net.join_game(address, int(args.get("net-port", Net.DEFAULT_PORT)))
	if err != OK:
		show_net_menu(L.t("NET_BAD_ADDRESS", {err = err}))
		return
	show_lobby()


func show_lobby() -> void:
	screen = Screen.LOBBY
	_end_world()
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	var v := _panel(box, 860)
	var title := L.t("LOBBY_TITLE_HOST") if Net.is_host() else L.t("LOBBY_TITLE")
	v.add_child(UiKit.label(title, 30, UiKit.AMBER))
	if Net.is_host():
		var ips := Net.local_addresses()
		var ip_txt := ", ".join(ips) if not ips.is_empty() else L.t("LOBBY_NO_LAN")
		v.add_child(UiKit.label(L.t("LOBBY_MY_IP", {ip = ip_txt, port = Net.DEFAULT_PORT}), 16, Color("9fe8ff")))
	# jogadores
	var by_pid := {}
	for id in Net.roster:
		by_pid[int(Net.roster[id])] = int(id)
	for pid in Bal.MAX_PLAYERS:
		var txt := L.t("LOBBY_SLOT", {p = pid + 1})
		if by_pid.has(pid):
			txt += L.t("LOBBY_HOST") if by_pid[pid] == 1 else L.t("LOBBY_PLAYER")
			if pid == Net.my_pid and Net.roster.has(multiplayer.get_unique_id()):
				txt += L.t("LOBBY_YOU")
			v.add_child(UiKit.label(txt, 18, Bal.PLAYER_COLORS[pid]))
		else:
			v.add_child(UiKit.label(txt + L.t("LOBBY_FREE"), 18, UiKit.DIM))
	if Net.is_client() and Net.roster.is_empty():
		v.add_child(UiKit.label(L.t("LOBBY_CONNECTING"), 16, UiKit.DIM))
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
		row.add_child(UiKit.button(L.t("LOBBY_NEXT_MISSION"), next_mission, 425))
		row.add_child(UiKit.button(L.t("LOBBY_NEXT_DIFF"), next_diff, 425))
		first = UiKit.button(L.t("LOBBY_START_MANY", {n = Net.player_count()}) if Net.player_count() > 1 else L.t("LOBBY_START_ONE"), func(): Net.start_game(randi()), 860)
		box.add_child(first)
	else:
		box.add_child(UiKit.label(L.t("LOBBY_WAIT_HOST"), 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var leave := UiKit.button(L.t("LOBBY_LEAVE"), show_net_menu.bind(""), 860)
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
		seed_v = int(args.seed) if args.has("seed") else randi()
	if players < 0:
		players = Game.players
	InputSetup.reset()
	world = World.new()
	world.name = "World"
	game_root.add_child(world)
	world.setup(Game.mission_index, Game.difficulty, players, seed_v)
	world.shake_requested.connect(func(a: float): shake = maxf(shake, a))
	world.shock_requested.connect(stage.add_shock)
	_hp_seen = {}
	stage.apply(world.amb.grade, Game.gfx)
	stage.set_active(true)
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
	world.toast(world.mission.name, UiKit.AMBER)
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
	stage.set_active(false)
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
	box.add_child(UiKit.label(L.t("PAUSE_TITLE"), 40, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	var cont := UiKit.button(L.t("PAUSE_RESUME"), _resume)
	box.add_child(cont)
	box.add_child(UiKit.button(L.t("PAUSE_RESTART"), start_mission.bind(-1, -1)))
	box.add_child(UiKit.button(L.t("PAUSE_MAIN_MENU"), show_menu))
	cont.grab_focus.call_deferred()


## Em rede a partida não pausa: só abre um menu por cima.
func _show_net_overlay() -> void:
	var root := _screen_root(0.35)
	_overlay = true
	var box := _center_box(root)
	box.add_child(UiKit.label(L.t("NETPAUSE_TITLE"), 28, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	var back := UiKit.button(L.t("NETPAUSE_BACK"), _clear_ui)
	box.add_child(back)
	if Net.is_host():
		box.add_child(UiKit.button(L.t("NETPAUSE_END"), Net.back_to_lobby))
	box.add_child(UiKit.button(L.t("NETPAUSE_LEAVE"), show_net_menu.bind("")))
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
	v.add_child(UiKit.label(L.t("RESULT_WIN") if win else L.t("RESULT_LOSE"), 36, Color("7dff6b") if win else Color("ff5a5a"), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(L.t(world.outcome_reason), 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var s: Dictionary = world.stats
	var t := int(world.time)
	for line in [
		L.t("RESULT_TIME", {time = "%d:%02d" % [t / 60, t % 60]}),
		L.t("RESULT_KILLS", {k = s.kills, m = s.mothers}),
		L.t("RESULT_NESTS", {n = s.nests, f = s.flowers}),
		L.t("RESULT_LOSSES", {t = s.troops_lost, c = s.commander_deaths}),
		L.t("RESULT_MERIT_WIN" if win else "RESULT_MERIT_LOSE", {m = world.merit if win else world.merit / 2, total = Game.merit_total}),
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
		first = UiKit.button(L.t("RESULT_NEXT"), next_m, 620)
		box.add_child(first)
	if not win:
		var cost: int = Bal.MERIT.continue_cost
		var cont_m := func() -> void:
			if Game.spend_merit(cost):
				_continue_mission()
		var cb := UiKit.button(L.t("RESULT_CONTINUE", {c = cost}), cont_m, 620)
		cb.disabled = Game.merit_total < cost
		box.add_child(cb)
		if not cb.disabled:
			first = cb
	var retry := UiKit.button(L.t("RESULT_RETRY"), start_mission.bind(-1, -1), 620)
	box.add_child(retry)
	box.add_child(UiKit.button(L.t("PAUSE_MAIN_MENU"), show_menu, 620))
	(first if first != null else retry).grab_focus.call_deferred()


func _result_buttons_net(box: VBoxContainer, win: bool) -> void:
	var first: Button = null
	if Net.is_host():
		if win and Net.lobby_mission + 1 < Missions.count():
			var next_m := func() -> void:
				Net.set_lobby(Net.lobby_mission + 1, Net.lobby_difficulty)
				Net.start_game(randi())
			first = UiKit.button(L.t("RESULT_NEXT_ALL"), next_m, 620)
			box.add_child(first)
		var retry := UiKit.button(L.t("RESULT_RETRY_ALL"), func(): Net.start_game(randi()), 620)
		box.add_child(retry)
		if first == null:
			first = retry
		box.add_child(UiKit.button(L.t("RESULT_BACK_LOBBY"), Net.back_to_lobby, 620))
	else:
		box.add_child(UiKit.label(L.t("RESULT_WAIT_HOST"), 17, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var leave := UiKit.button(L.t("NETPAUSE_LEAVE"), show_net_menu.bind(""), 620)
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
	world.toast("TOAST_CONTINUE", UiKit.AMBER)
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


var _hp_seen := {} # pid -> [vida, morto] no quadro anterior


## Depuração visual: dispara efeitos num instante marcado, sem mexer na simulação.
func _fx_demo() -> void:
	if args.has("fx-demo") and world.time >= float(args["fx-demo"]):
		args.erase("fx-demo")
		var p: Vector2 = world.commanders[0].position + Vector2(130, -20)
		world.fx.explosion(p, 1.0)
		world.fx.spark(p + Vector2(-70, 40), 8)
		world.fx.smoke(p + Vector2(60, 50))
		world.fx.muzzle(world.commanders[0].position + Vector2(14, -14), 0.0)
	if args.has("hurt-demo") and world.time >= float(args["hurt-demo"]):
		args.erase("hurt-demo")
		stage.add_hurt(1.0)


## Pulso vermelho na tela quando um comandante DESTE jogador perde vida (só leitura do estado).
func _watch_damage() -> void:
	for c in world.commanders:
		if Net.is_online() and c.pid != Net.my_pid:
			continue
		var prev: Array = _hp_seen.get(c.pid, [c.hp, c.dead])
		if c.dead and not prev[1]:
			stage.add_hurt(1.0)
		elif not c.dead and c.hp < float(prev[0]) - 0.01:
			stage.add_hurt(clampf((float(prev[0]) - c.hp) / maxf(1.0, c.max_hp) * 4.0, 0.35, 1.0))
		_hp_seen[c.pid] = [c.hp, c.dead]


func _process(delta: float) -> void:
	if replica != null and world != null and screen in [Screen.PLAYING, Screen.RESULT]:
		replica.render(delta)
	if world != null and screen == Screen.PLAYING:
		_watch_damage()
		_fx_demo()
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 30.0)
		stage.set_shake(Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake)
	else:
		stage.set_shake(Vector2.ZERO)
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


## Screenshot de todas as missões numa execução só (comparar antes/depois sem abrir seis janelas).
func _shot_all(dir: String) -> void:
	var wait := float(args.get("shot-after", "8"))
	for i in Missions.count():
		Game.mission_index = i
		start_mission()
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/m%d.png" % [dir, i + 1])
	print("SCREENSHOTS salvos em ", dir)
	get_tree().quit()


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SCREENSHOT salvo em ", path)
	if args.has("quit-after-shot"):
		Net.leave()
		get_tree().quit()
