class_name CmdInput
extends RefCounted
## Comandos de UM comandante num quadro (o que o cliente manda ao host, ~6 bytes).
## Mover, atirar e travar mira são ESTADO. Granada e ordem são CONTADORES de apertos:
## se um pacote se perder, o próximo ainda carrega o aperto (nada de "apertei e não foi").

var move := Vector2.ZERO
var fire := false
var strafe := false
var grenade_n := 0 # contador cíclico 0..255
var order_n := 0
var order_set := -1 # índice em Bal.ORDERS do último aperto direto (teclas 1–4), -1 = nenhum
var order_set_n := 0


func copy() -> CmdInput:
	var c := CmdInput.new()
	c.move = move
	c.fire = fire
	c.strafe = strafe
	c.grenade_n = grenade_n
	c.order_n = order_n
	c.order_set = order_set
	c.order_set_n = order_set_n
	return c


func encode() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(6)
	var dir := 8 # 8 = parado
	if move.length() > 0.2:
		dir = posmod(roundi(move.angle() / (PI / 4.0)), 8)
	var mag := clampi(roundi(move.length() * 15.0), 0, 15)
	b[0] = dir | (mag << 4)
	b[1] = (1 if fire else 0) | (2 if strafe else 0)
	b[2] = grenade_n & 255
	b[3] = order_n & 255
	b[4] = (order_set + 1) & 255
	b[5] = order_set_n & 255
	return b


static func decode(b: PackedByteArray) -> CmdInput:
	var c := CmdInput.new()
	if b.size() < 6:
		return c
	var dir := b[0] & 15
	var mag := (b[0] >> 4) / 15.0
	if dir < 8:
		var a := dir * PI / 4.0
		c.move = Vector2(cos(a), sin(a)) * mag
	c.fire = (b[1] & 1) != 0
	c.strafe = (b[1] & 2) != 0
	c.grenade_n = b[2]
	c.order_n = b[3]
	c.order_set = b[4] - 1
	c.order_set_n = b[5]
	return c


## Aplica ao comandante. Apertos disparam quando o contador mudou desde `prev` (o último aplicado).
func apply_to(c: Commander, prev: CmdInput) -> void:
	c.in_move = move
	c.in_fire = fire
	c.in_strafe = strafe
	if prev == null:
		return
	if grenade_n != prev.grenade_n:
		c.in_grenade = true
	if order_n != prev.order_n:
		c.in_order_next = true
	if order_set_n != prev.order_set_n and order_set >= 0 and order_set < Bal.ORDERS.size():
		c.in_order_set = Bal.ORDERS[order_set]
