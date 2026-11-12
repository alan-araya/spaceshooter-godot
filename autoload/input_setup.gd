extends Node
## Entrada: cria as ações em tempo de execução, remapeáveis via InputMap.
## Esquemas: s0 = WASD, s1 = setas, s2 = controle 1, s3 = controle 2.
## Cada jogador usa um ou mais esquemas, conforme o número de jogadores.

const SCHEMES := 4
const SNAP8 := PI / 4.0

## jogadores -> lista de esquemas por jogador
const LAYOUTS := {
	1: [[0, 1, 2, 3]],
	2: [[0, 2], [1, 3]],
	3: [[0], [1], [2, 3]],
	4: [[0], [1], [2], [3]],
}

const SCHEME_NAMES := ["Teclado WASD", "Teclado Setas", "Controle 1", "Controle 2"]


func _ready() -> void:
	_kb(0, { up = [KEY_W], down = [KEY_S], left = [KEY_A], right = [KEY_D],
		fire = [KEY_SPACE, KEY_J], order = [KEY_Q, KEY_K], grenade = [KEY_E, KEY_L], strafe = [KEY_SHIFT] })
	_kb(1, { up = [KEY_UP], down = [KEY_DOWN], left = [KEY_LEFT], right = [KEY_RIGHT],
		fire = [KEY_KP_0, KEY_SLASH], order = [KEY_KP_1, KEY_PERIOD], grenade = [KEY_KP_2, KEY_COMMA], strafe = [KEY_KP_3, KEY_CTRL] })
	_pad(2, 0)
	_pad(3, 1)
	for i in 4:
		_add("order_%d" % (i + 1), [_key(KEY_1 + i)])
	_add("pause", [_key(KEY_ESCAPE), _key(KEY_P), _joy_btn(JOY_BUTTON_START, -1)])
	_add("debug_win", [_key(KEY_F9)])


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


func schemes_for(pid: int, players: int) -> Array:
	var layout: Array = LAYOUTS.get(clampi(players, 1, 4), LAYOUTS[1])
	if pid >= layout.size():
		return []
	return layout[pid]


## Preenche a entrada do comandante a partir dos esquemas do jogador.
func read_into(c: Commander, players: int) -> void:
	var best := Vector2.ZERO
	var fire := false
	var strafe := false
	for s in schemes_for(c.pid, players):
		var v := Input.get_vector("s%d_left" % s, "s%d_right" % s, "s%d_up" % s, "s%d_down" % s)
		if v.length() > best.length():
			best = v
		if Input.is_action_pressed("s%d_fire" % s):
			fire = true
		if Input.is_action_pressed("s%d_strafe" % s):
			strafe = true
		if Input.is_action_just_pressed("s%d_order" % s):
			c.in_order_next = true
		if Input.is_action_just_pressed("s%d_grenade" % s):
			c.in_grenade = true
	# 8 direções (como o original)
	if best.length() > 0.2:
		var a := roundf(best.angle() / SNAP8) * SNAP8
		best = Vector2(cos(a), sin(a)) * minf(1.0, best.length())
	else:
		best = Vector2.ZERO
	c.in_move = best
	c.in_fire = fire
	c.in_strafe = strafe
	if c.pid == 0:
		for i in 4:
			if Input.is_action_just_pressed("order_%d" % (i + 1)):
				c.in_order_set = Bal.ORDERS[i]


## Texto de ajuda dos controles de um jogador.
func help_for(pid: int, players: int) -> String:
	var parts: Array = []
	for s in schemes_for(pid, players):
		match s:
			0:
				parts.append("WASD · Espaço atira · Q ordem · E granada · Shift trava mira · 1-4 ordem direta")
			1:
				parts.append("Setas · / ou Num0 atira · . ou Num1 ordem · , ou Num2 granada")
			2, 3:
				parts.append("%s: analógico · A/RT atira · X ordem · B/LT granada · LB/RB trava mira" % SCHEME_NAMES[s])
	return "\n".join(parts)
