class_name Commander
extends Human
## Comandante controlado por um jogador. Mesmas regras de um soldado + ordens, pickups e granadas.

const SNAP8 := PI / 4.0

var weapon := "mg"
var ammo := -1 # -1 = infinita
var grenades := 3
var fire_cd := 0.0
var grenade_cd := 0.0
var invuln := 0.0
var carrying := false
var order := "normal"
var respawn_timer := 0.0
var god := false
var disconnected := false # rede: jogador saiu

# entrada do frame (preenchida pelo World a partir do InputSetup)
var in_move := Vector2.ZERO
var in_fire := false
var in_strafe := false
var in_grenade := false
var in_order_next := false
var in_order_set := ""


func setup(w: World, player_id: int) -> void:
	world = w
	pid = player_id
	kind = "commander"
	r = Bal.COMMANDER.radius
	max_hp = Bal.COMMANDER.hp
	hp = max_hp
	grenades = Bal.COMMANDER.start_grenades
	invuln = Bal.TROOPS.respawn_invuln
	face = -PI / 2.0
	Art.apply(visual, "soldier")


func tick(dt: float) -> void:
	if invuln > 0.0:
		invuln -= dt
	if flash > 0.0:
		flash -= dt
	if drop_t > 0.0:
		drop_t -= dt
	fire_cd -= dt
	grenade_cd -= dt

	# movimento em 8 direções
	moving = in_move.length() > 0.2
	face = step_move(world, self, face, in_move, in_strafe, carrying, r, dt)
	if moving:
		walk_t += dt * 7.0
	trample_flowers()

	# ordens (só para os soldados deste comandante)
	if in_order_next:
		var i := Bal.ORDERS.find(order)
		world.set_order(self, Bal.ORDERS[(i + 1) % Bal.ORDERS.size()])
	elif in_order_set != "" and in_order_set != order:
		world.set_order(self, in_order_set)

	# tiro na direção em que está virado
	if in_fire and fire_cd <= 0.0 and not carrying:
		var wp: Dictionary = Bal.WEAPONS[weapon]
		fire_cd = wp.interval
		world.event_owner = pid
		fire_weapon(face, weapon, wp.spread)
		world.sfx(shot_sound(weapon), position.x)
		world.event_owner = -1
		if ammo > 0:
			ammo -= 1
			if ammo <= 0:
				weapon = "mg"
				ammo = -1
				world.toast("TOAST_AMMO_OUT", Color("cccccc"))

	# granada em arco
	if in_grenade and grenade_cd <= 0.0 and grenades > 0:
		grenade_cd = Bal.GRENADE.cooldown
		grenades -= 1
		var dest := position + Vector2(cos(face), sin(face)) * Bal.GRENADE.throw_dist
		dest.x = clampf(dest.x, 8.0, Bal.WORLD_W - 8.0)
		dest.y = clampf(dest.y, 8.0, Bal.WORLD_H - 8.0)
		world.projectiles.throw_grenade(position + Vector2(0, -14), dest, Bal.GRENADE.flight_time, false)
		world.sfx("throw", position.x)

	in_order_next = false
	in_order_set = ""
	in_grenade = false


static func shot_sound(weapon_key: String) -> String:
	if weapon_key == "flame":
		return "flame"
	if weapon_key == "plasma":
		return "plasma"
	return "shot"


## Movimento de um quadro (o mesmo no host e na previsão do cliente): anda pelo grid, desvia de ninhos e do
## gerador. Move `u` (só a posição dele é usada) e devolve a nova direção.
static func step_move(w: World, u: Node2D, face_in: float, mv: Vector2, strafe: bool, carrying_now: bool, radius: float, dt: float) -> float:
	var f := face_in
	if mv.length() > 0.2:
		mv = mv.limit_length(1.0)
		var speed: float = Bal.COMMANDER.speed * (Bal.COMMANDER.carry_slow if carrying_now else 1.0)
		w.grid.move_circle(u, mv * speed * dt, radius, Grid.MODE_HUMAN)
		if not strafe:
			f = roundf(mv.angle() / SNAP8) * SNAP8
	u.position = Human.push_out_of(w, u.position, radius)
	return f


func sync_visual() -> void:
	visible = not dead
	sync_soldier_visual()
	if invuln > 0.0 and not dead:
		visual.modulate.a = 0.45 if int(invuln * 12.0) % 2 == 0 else 1.0
