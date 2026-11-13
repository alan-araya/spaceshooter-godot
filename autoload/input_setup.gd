extends Node
## Entrada: cria as ações em tempo de execução, remapeáveis via InputMap.
## Esquemas: 0 = teclado WASD, 1 = teclado setas, 2..5 = controles 1..4 (na ordem em que conectaram).
## Os controles são presos ao aparelho real (id do Godot) e refeitos quando um controle liga ou desliga.
##
## Quem usa o quê (assignments):
## - 1 jogador no PC (local ou em rede): tudo — os dois teclados e qualquer controle.
## - Vários jogadores no PC: P1 = WASD, P2 = setas, P3/P4 = controles. Controles que sobram vão
##   primeiro para o P1 e depois para o P2, então o jogador principal pode usar teclado OU controle.

const SNAP8 := PI / 4.0
const MAX_PADS := 4
const KB_WASD := 0
const KB_ARROWS := 1
const PAD0 := 2

## Comando atual de cada jogador LOCAL (slot 0..3) e o último aplicado ao comandante.
## O mesmo formato (CmdInput) é o que viaja pela rede.
var _cur: Array = []
var _applied: Array = []
var pads: Array = [] # ids dos controles conectados, em ordem de conexão


func _ready() -> void:
	for i in 4:
		_cur.append(CmdInput.new())
		_applied.append(null)
	_kb(KB_WASD, { up = [KEY_W], down = [KEY_S], left = [KEY_A], right = [KEY_D],
		fire = [KEY_SPACE, KEY_J], order = [KEY_Q, KEY_K], grenade = [KEY_E, KEY_L], strafe = [KEY_SHIFT] })
	_kb(KB_ARROWS, { up = [KEY_UP], down = [KEY_DOWN], left = [KEY_LEFT], right = [KEY_RIGHT],
		fire = [KEY_KP_0, KEY_SLASH], order = [KEY_KP_1, KEY_PERIOD], grenade = [KEY_KP_2, KEY_COMMA], strafe = [KEY_KP_3, KEY_CTRL] })
	for i in 4:
		_add("order_%d" % (i + 1), [_key(KEY_1 + i)])
	_add("pause", [_key(KEY_ESCAPE), _key(KEY_P), _joy_btn(JOY_BUTTON_START, -1)])
	_add("debug_win", [_key(KEY_F9)])
	# menus pelo controle: analógico esquerdo também navega (o direcional e o A já vêm do Godot)
	for pair in [["ui_up", JOY_AXIS_LEFT_Y, -1.0], ["ui_down", JOY_AXIS_LEFT_Y, 1.0], ["ui_left", JOY_AXIS_LEFT_X, -1.0], ["ui_right", JOY_AXIS_LEFT_X, 1.0]]:
		InputMap.action_add_event(pair[0], _joy_axis(pair[1], pair[2], -1))
	_rebuild_pads()
	Input.joy_connection_changed.connect(_on_joy_changed)


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_rebuild_pads()


## Refaz as ações dos controles 1..4 com os aparelhos conectados agora (mantendo a ordem de chegada).
func _rebuild_pads() -> void:
	var now := Input.get_connected_joypads()
	var keep: Array = []
	for d in pads:
		if now.has(d):
			keep.append(d)
	for d in now:
		if not keep.has(d):
			keep.append(d)
	pads = keep
	for k in MAX_PADS:
		_pad(PAD0 + k, pads[k] if k < pads.size() else 999) # 999 = nenhum aparelho


func _add(action: String, events: Array, deadzone: float = 0.3) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, deadzone)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _joy_btn(btn: JoyButton, device: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.device = device
	return e


func _joy_axis(axis: JoyAxis, value: float, device: int) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = device
	return e


func _kb(s: int, map: Dictionary) -> void:
	for k in map:
		var evs: Array = []
		for code in map[k]:
			evs.append(_key(code))
		_add("s%d_%s" % [s, k], evs)


func _pad(s: int, device: int) -> void:
	_add("s%d_up" % s, [_joy_axis(JOY_AXIS_LEFT_Y, -1.0, device), _joy_btn(JOY_BUTTON_DPAD_UP, device)], 0.35)
	_add("s%d_down" % s, [_joy_axis(JOY_AXIS_LEFT_Y, 1.0, device), _joy_btn(JOY_BUTTON_DPAD_DOWN, device)], 0.35)
	_add("s%d_left" % s, [_joy_axis(JOY_AXIS_LEFT_X, -1.0, device), _joy_btn(JOY_BUTTON_DPAD_LEFT, device)], 0.35)
	_add("s%d_right" % s, [_joy_axis(JOY_AXIS_LEFT_X, 1.0, device), _joy_btn(JOY_BUTTON_DPAD_RIGHT, device)], 0.35)
	_add("s%d_fire" % s, [_joy_btn(JOY_BUTTON_A, device), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0, device)], 0.5)
	_add("s%d_order" % s, [_joy_btn(JOY_BUTTON_X, device), _joy_btn(JOY_BUTTON_Y, device)])
	_add("s%d_grenade" % s, [_joy_btn(JOY_BUTTON_B, device), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0, device)], 0.5)
	_add("s%d_strafe" % s, [_joy_btn(JOY_BUTTON_LEFT_SHOULDER, device), _joy_btn(JOY_BUTTON_RIGHT_SHOULDER, device)])


## Esquemas de cada jogador do PC, para `players` jogadores e `n_pads` controles conectados.
static func assignments(players: int, n_pads: int) -> Array:
	players = clampi(players, 1, 4)
	n_pads = clampi(n_pads, 0, MAX_PADS)
	if players == 1:
		var all: Array = [KB_WASD, KB_ARROWS]
		for k in MAX_PADS:
			all.append(PAD0 + k)
		return [all]
	var out: Array = []
	for i in players:
		out.append([])
	out[0].append(KB_WASD)
	out[1].append(KB_ARROWS)
	var next := 0
	# primeiro quem não tem teclado (P3, P4); depois o P1; depois o P2
	var order: Array = []
	for i in range(2, players):
		order.append(i)
	order.append(0)
	order.append(1)
	for i in order:
		if next < n_pads:
			out[i].append(PAD0 + next)
			next += 1
	return out


func schemes_for(pid: int, players: int) -> Array:
	var a := assignments(players, pads.size())
	return a[pid] if pid < a.size() else []


## Texto curto com os aparelhos de cada jogador (briefing), ex.: "P1: teclado WASD + controle 1".
func describe(players: int) -> Array:
	var out: Array = []
	var a := assignments(players, pads.size())
	for pid in a.size():
		var parts: Array = []
		for s in a[pid]:
			if s == KB_WASD:
				parts.append(L.t("INPUT_WASD") if players > 1 else L.t("INPUT_KEYBOARD"))
			elif s == KB_ARROWS:
				if players > 1:
					parts.append(L.t("INPUT_ARROWS"))
			elif s - PAD0 < pads.size():
				parts.append(L.t("INPUT_PAD", {n = s - PAD0 + 1}) if players > 1 else L.t("INPUT_ANY_PAD"))
		var seen := {}
		var uniq: Array = []
		for p in parts:
			if not seen.has(p):
				seen[p] = true
				uniq.append(p)
		out.append(" + ".join(PackedStringArray(uniq)) if not uniq.is_empty() else L.t("INPUT_NONE"))
	return out


## Zera os contadores (início de missão).
func reset() -> void:
	for i in 4:
		_cur[i] = CmdInput.new()
		_applied[i] = null


## Lê os esquemas do jogador local `slot` e atualiza o comando dele. Chamar 1× por quadro de física.
func sample(slot: int, players: int) -> CmdInput:
	var cmd: CmdInput = _cur[slot]
	var best := Vector2.ZERO
	var fire := false
	var strafe := false
	for s in schemes_for(slot, players):
		var v := Input.get_vector("s%d_left" % s, "s%d_right" % s, "s%d_up" % s, "s%d_down" % s)
		if v.length() > best.length():
			best = v
		if Input.is_action_pressed("s%d_fire" % s):
			fire = true
		if Input.is_action_pressed("s%d_strafe" % s):
			strafe = true
		if Input.is_action_just_pressed("s%d_order" % s):
			cmd.order_n = (cmd.order_n + 1) & 255
		if Input.is_action_just_pressed("s%d_grenade" % s):
			cmd.grenade_n = (cmd.grenade_n + 1) & 255
	# 8 direções (como o original)
	if best.length() > 0.2:
		var a := roundf(best.angle() / SNAP8) * SNAP8
		best = Vector2(cos(a), sin(a)) * minf(1.0, best.length())
	else:
		best = Vector2.ZERO
	cmd.move = best
	cmd.fire = fire
	cmd.strafe = strafe
	if slot == 0:
		for i in 4:
			if Input.is_action_just_pressed("order_%d" % (i + 1)):
				cmd.order_set = i
				cmd.order_set_n = (cmd.order_set_n + 1) & 255
	return cmd


## Jogo local: lê os esquemas do jogador `slot` e aplica ao comandante `c`.
func read_into(c: Commander, players: int, slot: int = -1) -> void:
	var s := c.pid if slot < 0 else slot
	var cmd := sample(s, players)
	cmd.apply_to(c, _applied[s])
	_applied[s] = cmd.copy()
