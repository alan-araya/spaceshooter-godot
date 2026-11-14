class_name Predictor
extends RefCounted
## Cliente: previsão do PRÓPRIO comandante. Sem ela, cada passo e cada tiro esperava ida e volta ao host
## mais o atraso de interpolação (~200 ms com ping de 60 ms).
##
## - A cada quadro de física o comando local ganha um número (seq), vai para o host e é aplicado AQUI na
##   hora, com a mesma regra de movimento do host (Commander.step_move).
## - Quando chega um snapshot, ele diz qual foi o último comando aplicado pelo host (ack) e onde o
##   comandante estava depois dele. A previsão volta para essa posição e refaz os comandos que o host ainda
##   não aplicou. A diferença para o que estava na tela vira um deslocamento que some em ~0,1 s
##   (sem tranco); diferença grande (renascer, empurrão) = pula direto.
## - Tiros: som, clarão e balas aparecem na hora (só visual). As balas do host com dono = este jogador
##   não são desenhadas; acertos e mortes continuam vindo do host.
## Só leitura do mundo-réplica: nada aqui escreve na simulação (o cliente não tem simulação).

const STEP := 1.0 / 60.0
const HISTORY := 120 # comandos guardados (2 s)
const SNAP_DIST := 64.0 # erro acima disso: pula em vez de suavizar
const SMOOTH := 12.0 # 1/s: rapidez com que a correção some

var world: World
var pid := 0
var seq := 0
var history: Array = [] # CmdInput já numerados, do mais velho ao mais novo
var ready := false # há posição do host para prever a partir dela
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO # posição do quadro de física anterior (desenho interpolado)
var face := -PI / 2.0
var moving := false
var walk_t := 0.0
var offset := Vector2.ZERO # correção visual pendente
var bullets: Array = [] # balas locais (só visual), no formato de Projectiles.list
var err_avg := 0.0 # média móvel do erro de previsão (px), para a tabela de rede
var _weapon := "mg"
var _carrying := false
var _fire_cd := 0.0
var _mover := Node2D.new()
var _rng := RandomNumberGenerator.new()


func _init(w: World, player_id: int) -> void:
	world = w
	pid = player_id


func free_nodes() -> void:
	if is_instance_valid(_mover):
		_mover.free()


## Numera o comando amostrado neste quadro, guarda, aplica localmente e devolve a cópia numerada.
func next_cmd(sampled: CmdInput) -> CmdInput:
	var cmd := sampled.copy()
	cmd.seq = seq
	seq = (seq + 1) & 0xffff
	history.append(cmd)
	while history.size() > HISTORY:
		history.pop_front()
	prev_pos = pos
	if ready:
		_step(cmd)
		_predict_fire(cmd)
	return cmd


## Snapshot novo (o mais recente que chegou): reconcilia com a posição do host.
func on_snapshot(s: Dictionary) -> void:
	if pid >= s.cmds.size():
		return
	var c: Dictionary = s.cmds[pid]
	_weapon = c.weapon
	_carrying = c.carrying
	if c.dead or c.drop > 0.0 or c.disconnected:
		ready = false
		pos = c.p
		prev_pos = pos
		face = c.face
		offset = Vector2.ZERO
		return
	var ack: int = c.ack
	while not history.is_empty() and not CmdInput.seq_newer(history[0].seq, ack):
		history.pop_front()
	var shown := pos + offset
	pos = c.p
	face = c.face
	for cmd in history:
		_step(cmd)
	if not ready:
		ready = true
		prev_pos = pos
		offset = Vector2.ZERO
		return
	var err := shown - pos
	err_avg = lerpf(err_avg, err.length(), 0.1)
	offset = Vector2.ZERO if err.length() > SNAP_DIST else err


## Posição para desenhar agora (entre dois quadros de física, mais a correção que ainda está sumindo).
func visual_pos(frac: float) -> Vector2:
	return prev_pos.lerp(pos, clampf(frac, 0.0, 1.0)) + offset


## Por quadro de desenho: some com a correção e move as balas locais.
func render(dt: float) -> void:
	offset *= exp(-SMOOTH * dt)
	if offset.length() < 0.05:
		offset = Vector2.ZERO
	var g := world.grid
	var keep: Array = []
	for pr in bullets:
		pr.life -= dt
		pr.p += pr.v * dt
		if pr.kind == "flame":
			pr.v *= 1.0 - dt * 1.5
		var p: Vector2 = pr.p
		if pr.life <= 0.0 or p.x < -16.0 or p.y < -16.0 or p.x > Bal.WORLD_W + 16.0 or p.y > Bal.WORLD_H + 16.0:
			continue
		if g.kind_at(p) == Grid.ROCK:
			continue
		if pr.kind == "bullet" and _touches_bug(p):
			continue # o acerto de verdade (gosma, dano) vem do host
		keep.append(pr)
	bullets = keep


func _touches_bug(p: Vector2) -> bool:
	for b in world.bugs:
		if is_instance_valid(b) and p.distance_squared_to(b.position) < (b.r + 3.0) * (b.r + 3.0):
			return true
	return false


func _step(cmd: CmdInput) -> void:
	_mover.position = pos
	moving = cmd.move.length() > 0.2
	face = Commander.step_move(world, _mover, face, cmd.move, cmd.strafe, _carrying, Bal.COMMANDER.radius, STEP)
	pos = _mover.position
	if moving:
		walk_t += STEP * 7.0


func _predict_fire(cmd: CmdInput) -> void:
	_fire_cd -= STEP
	if not cmd.fire or _fire_cd > 0.0 or _carrying:
		return
	var wp: Dictionary = Bal.WEAPONS.get(_weapon, Bal.WEAPONS.mg)
	_fire_cd = wp.interval
	var a := face + (_rng.randf_range(-wp.spread, wp.spread) if wp.spread > 0.0 else 0.0)
	var muzzle := pos + Vector2(cos(face), sin(face)) * 14.0 + Vector2(0, -12)
	var spd: float = wp.speed
	if _weapon == "flame":
		spd *= _rng.randf_range(0.75, 1.15)
	var kind := "bullet"
	if _weapon == "flame" or _weapon == "plasma":
		kind = _weapon
	bullets.append({ kind = kind, p = muzzle, v = Vector2(cos(a), sin(a)) * spd, life = wp.reach / spd, max = wp.reach / spd, pid = pid })
	if _weapon != "flame":
		world.fx.muzzle(muzzle, face)
	Sfx.play(Commander.shot_sound(_weapon), pos.x)
