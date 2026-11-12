extends Node
## MAIN — máquina de estados: menu → missões → briefing → jogo ↔ pausa → resultado.
## Simulação em passo fixo de 60 Hz (_physics_process).
## Argumentos de depuração (depois de "--"): --mission=N --players=N --difficulty=facil|normal|dificil
##   --autostart (pula o briefing) --test (testes headless e sai) --shot=arquivo.png --shot-after=SEG

enum Screen { MENU, SELECT, BRIEFING, PLAYING, PAUSED, RESULT }

const STEP := 1.0 / 60.0

var screen := Screen.MENU
var world: World
var game_root: Node2D
var hud: Hud
var hud_layer: CanvasLayer
var ui_layer: CanvasLayer
var ui: Control
var shake := 0.0
var args := {}
var _shot_timer := -1.0


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
	if args.has("players"):
		Game.players = clampi(int(args.players), 1, 4)
	if args.has("difficulty") and Bal.DIFFICULTY.has(args.difficulty):
		Game.difficulty = args.difficulty
	if args.has("shot"):
		_shot_timer = float(args.get("shot-after", "4"))
	if args.has("test"):
		var tests := SimTests.new()
		add_child(tests)
		tests.run.call_deferred(self)
		return
	if args.has("mission"):
		Game.mission_index = clampi(int(args.mission) - 1, 0, Missions.count() - 1)
		if args.has("autostart"):
			start_mission()
		else:
			show_briefing()
	else:
		show_menu()


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


func show_menu() -> void:
	screen = Screen.MENU
	_end_world()
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
	var box := _center_box(root, 160)
	var play := UiKit.button("JOGAR", show_select)
	box.add_child(play)
	var cycle_players := func() -> void:
		Game.players = Game.players % 4 + 1
		Game.save()
		show_menu()
		_focus_index(1)
	box.add_child(UiKit.button("JOGADORES: %d" % Game.players, cycle_players))
	var dl: String = Bal.DIFFICULTY[Game.difficulty].label
	var cycle_diff := func() -> void:
		var i := Bal.DIFFICULTY_ORDER.find(Game.difficulty)
		Game.difficulty = Bal.DIFFICULTY_ORDER[(i + 1) % Bal.DIFFICULTY_ORDER.size()]
		Game.save()
		show_menu()
		_focus_index(2)
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
	var panel := PanelContainer.new()
	box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
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


func show_briefing() -> void:
	screen = Screen.BRIEFING
	var m := Missions.get_mission(Game.mission_index)
	var root := _screen_root()
	_background(root)
	var box := _center_box(root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UiKit.label("MISSÃO %d — %s" % [Game.mission_index + 1, String(m.name).to_upper()], 30, UiKit.AMBER))
	for line in m.briefing:
		v.add_child(UiKit.label(line, 18))
	v.add_child(UiKit.label(" ", 8))
	v.add_child(UiKit.label("OBJETIVO: " + String(m.objective.text), 18, Color("9fe8ff")))
	var d: Dictionary = Bal.DIFFICULTY[Game.difficulty]
	v.add_child(UiKit.label("Tropas: %d   ·   Dificuldade: %s   ·   Jogadores: %d" % [d.troops, d.label, Game.players], 16, UiKit.DIM))
	var go := UiKit.button("COMEÇAR", start_mission, 820)
	box.add_child(go)
	box.add_child(UiKit.button("VOLTAR", show_select, 820))
	go.grab_focus.call_deferred()


func start_mission() -> void:
	_clear_ui()
	_end_world()
	Sfx.play("ui_ok")
	world = World.new()
	world.name = "World"
	game_root.add_child(world)
	world.setup(Game.mission_index, Game.difficulty, Game.players, randi())
	world.shake_requested.connect(func(a: float): shake = maxf(shake, a))
	hud = Hud.new()
	hud.theme = UiKit.theme()
	hud_layer.add_child(hud)
	hud.bind(world, Game.players)
	world.toast(String(world.mission.name).to_upper(), UiKit.AMBER)
	screen = Screen.PLAYING
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
	if hud != null:
		hud.queue_free()
		hud = null


func show_pause() -> void:
	screen = Screen.PAUSED
	var root := _screen_root(0.55)
	var box := _center_box(root)
	box.add_child(UiKit.label("PAUSA", 40, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
	var cont := UiKit.button("CONTINUAR", _resume)
	box.add_child(cont)
	box.add_child(UiKit.button("REINICIAR MISSÃO", start_mission))
	box.add_child(UiKit.button("MENU PRINCIPAL", show_menu))
	cont.grab_focus.call_deferred()


func show_result() -> void:
	screen = Screen.RESULT
	var win := world.outcome == "victory"
	if win:
		Game.mission_won(Game.mission_index, world.merit)
	else:
		Game.add_merit(world.merit / 2)
	var root := _screen_root(0.6)
	var box := _center_box(root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
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
	var retry := UiKit.button("TENTAR DE NOVO", start_mission, 620)
	box.add_child(retry)
	box.add_child(UiKit.button("MENU PRINCIPAL", show_menu, 620))
	(first if first != null else retry).grab_focus.call_deferred()


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
		for c in world.commanders:
			InputSetup.read_into(c, Game.players)
		world.update(STEP)
		if Input.is_action_just_pressed("pause"):
			show_pause()
		if Input.is_action_just_pressed("debug_win") and OS.is_debug_build():
			world.debug_kill_nests()
		if world.outcome != "" and world.outcome_timer > 2.5:
			show_result()
	elif screen == Screen.PAUSED and Input.is_action_just_pressed("pause"):
		_resume()


func _resume() -> void:
	_clear_ui()
	screen = Screen.PLAYING


func _process(delta: float) -> void:
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 30.0)
		game_root.position = Vector2(0, Bal.HUD_TOP) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	else:
		game_root.position = Vector2(0, Bal.HUD_TOP)
	if _shot_timer >= 0.0:
		_shot_timer -= delta
		if _shot_timer < 0.0:
			_save_shot(args.shot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and screen in [Screen.SELECT, Screen.BRIEFING]:
		show_menu()


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SCREENSHOT salvo em ", path)
	if args.has("quit-after-shot"):
		get_tree().quit()
