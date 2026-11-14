extends Node
## REDE (fase 1): partida hospedada por um jogador, via ENet (UDP).
## - O HOST roda a simulação. Cada cliente manda só os comandos (CmdInput, ~6 bytes, 60×/s).
## - O host devolve o estado (Snapshot, 30×/s, não confiável) e os eventos de som/efeito
##   (lista, confiável), que o cliente desenha com o Replica.
## Um jogador por máquina nesta fase. P1 = host; P2..P4 = clientes, na ordem de entrada.
## As chamadas @rpc ficam neste autoload porque o caminho (/root/Net) é igual em todas as máquinas.

signal lobby_changed
signal status_changed(text: String)
signal start_requested(mission_index: int, difficulty: String, players: int, seed_v: int)
signal lobby_requested
signal host_left(reason: String)
signal peer_left(pid: int)
signal snapshot_received(bytes: PackedByteArray)
signal events_received(events: Array)
signal netinfo_changed

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4
const SNAPSHOT_EVERY := 2 # quadros de física entre snapshots (60/2 = 30 Hz)
## Sobe quando o formato de comandos, snapshots ou eventos muda.
const PROTOCOL := 4
const PING_EVERY := 0.5 # s entre pings do host
const INFO_EVERY := 1.0 # s entre envios da tabela de rede (Tab)
const INPUT_REDUNDANCY := 4 # cada pacote de comandos leva os 4 últimos (perda de 1–3 pacotes não custa nada)
const INPUT_QUEUE_MAX := 4 # host: fila de comandos por jogador; acima disso descarta os mais velhos

enum Mode { OFFLINE, HOST, CLIENT }

var mode := Mode.OFFLINE
var roster := {} # peer_id -> pid (0..3)
var my_pid := 0
var in_game := false
var lobby_mission := 0
var lobby_difficulty := "normal"
var remote_inputs := {} # pid -> CmdInput mais recente (host)
var _applied := {} # pid -> último CmdInput aplicado (host)
var stats := { snapshots_out = 0, snapshots_in = 0, bytes_out = 0, inputs_in = 0 }
## Versão para a conferência na entrada: protocolo + impressão digital dos mapas e dados das missões.
## O cliente monta o mundo com o próprio missions.gd; se o do host for outro, muros e unidades não batem
## (ex.: muros sumindo). Host e cliente precisam do mesmo valor.
var version := ""
var _pending := {} # peer_id conectado que ainda não mandou a versão (host)

## Tabela de rede (Tab): pid -> { rtt (ms), loss (0..1), host (bool) }. O host mede e envia a todos.
var netinfo := {}
var _ping_t := 0.0
var _info_t := 0.0
var _rtt := {} # peer_id -> ms (média móvel; ping próprio, passa pelo mesmo caminho dos dados do jogo)
## Comandos recebidos pelo host: pid -> { seq -> CmdInput } e o último seq aplicado.
var _queue := {}
var acked := {} # pid -> último seq aplicado (vai no snapshot; o cliente usa para a previsão)

## Simulador de rede ruim (-- --net-lag=MS --net-jitter=MS --net-loss=0.02): atrasa o que chega e o que sai
## desta máquina e descarta pacotes não confiáveis. Só para testes.
var sim_lag := 0.0 # ms de ida e volta acrescentados (metade na saída, metade na chegada)
var sim_jitter := 0.0
var sim_loss := 0.0
var _sim_q: Array = [] # [quando (ms), Callable]
var _sim_last_reliable := 0.0
var _sim_rng := RandomNumberGenerator.new()


func _ready() -> void:
	version = "%d-%x" % [PROTOCOL, hash(var_to_str(Missions.LIST))]
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


func player_count() -> int:
	return roster.size()


## Endereços IPv4 desta máquina na rede local (para mostrar ao host).
func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# =============================================================================
# conexão
# =============================================================================

func host_game(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	roster = { 1: 0 }
	my_pid = 0
	in_game = false
	_reset_inputs()
	status_changed.emit(L.t("NET_STATUS_HOSTING", {port = port}))
	lobby_changed.emit()
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	roster = {}
	in_game = false
	status_changed.emit(L.t("NET_STATUS_CONNECTING", {addr = address, port = port}))
	return OK


func leave() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	roster = {}
	my_pid = 0
	in_game = false
	_pending = {}
	netinfo = {}
	_rtt = {}
	_sim_q = []
	_reset_inputs()


func _reset_inputs() -> void:
	remote_inputs = {}
	_applied = {}
	_queue = {}
	acked = {}


## O ENet, por padrão, descarta pacotes não confiáveis (os snapshots) quando o ping oscila — numa VPN isso
## congela e faz pular o mundo do cliente. Aqui o descarte fica desligado (desaceleração 0) e a queda da
## conexão fica mais tolerante.
func _tune_peer(id: int) -> void:
	var pp := _enet_peer(id)
	if pp == null:
		return
	pp.throttle_configure(5000, 32, 0)
	pp.set_timeout(0, 8000, 20000)


func _enet_peer(id: int) -> ENetPacketPeer:
	var mp := multiplayer.multiplayer_peer
	if not (mp is ENetMultiplayerPeer):
		return null
	return (mp as ENetMultiplayerPeer).get_peer(id)


func _enet_loss(id: int) -> float:
	var pp := _enet_peer(id)
	if pp == null:
		return 0.0
	return pp.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE)


func _set_refuse(refuse: bool) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.refuse_new_connections = refuse


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	if in_game or roster.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_tune_peer(id)
	_pending[id] = true # entra no lobby só depois de conferir a versão (_rpc_version)


## Cliente → host, logo ao conectar.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_version(v: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _pending.has(id):
		return
	_pending.erase(id)
	if v != version:
		_rpc_rejected.rpc_id(id, version)
		get_tree().create_timer(0.5).timeout.connect(_drop_peer.bind(id)) # dá tempo da recusa chegar
		return
	if in_game or roster.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var used := roster.values()
	var pid := 1
	while used.has(pid):
		pid += 1
	roster[id] = pid
	_broadcast_lobby()


func _drop_peer(id: int) -> void:
	var peer := multiplayer.multiplayer_peer
	if is_host() and peer != null and id in multiplayer.get_peers():
		peer.disconnect_peer(id)


## Host → cliente com versão diferente.
@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(host_version: String) -> void:
	leave()
	host_left.emit(L.t("NET_VERSION_MISMATCH", {mine = version, host = host_version}))


func _on_peer_disconnected(id: int) -> void:
	_pending.erase(id)
	if not is_host() or not roster.has(id):
		return
	var pid: int = roster[id]
	roster.erase(id)
	remote_inputs.erase(pid)
	_applied.erase(pid)
	_queue.erase(pid)
	_rtt.erase(id)
	if in_game:
		peer_left.emit(pid)
	else:
		_broadcast_lobby()


func _on_connected() -> void:
	_tune_peer(1)
	status_changed.emit(L.t("NET_STATUS_CONNECTED"))
	_rpc_version.rpc_id(1, version)


func _on_connection_failed() -> void:
	leave()
	host_left.emit(L.t("NET_CANT_CONNECT"))


func _on_server_disconnected() -> void:
	leave()
	host_left.emit(L.t("NET_HOST_LOST"))


# =============================================================================
# lobby e início (host decide)
# =============================================================================

func set_lobby(mission_index: int, difficulty: String) -> void:
	lobby_mission = mission_index
	lobby_difficulty = difficulty
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	if not is_host():
		return
	_rpc_lobby.rpc(roster, lobby_mission, lobby_difficulty)
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(r: Dictionary, mission_index: int, difficulty: String) -> void:
	roster = r
	lobby_mission = mission_index
	lobby_difficulty = difficulty
	my_pid = int(roster.get(multiplayer.get_unique_id(), -1))
	lobby_changed.emit()


## Host: P1..Pn contíguos, na ordem de entrada (o mundo cria um comandante por pid).
func _compact_pids() -> void:
	var ids := roster.keys()
	ids.sort_custom(func(a, b): return roster[a] < roster[b])
	var i := 0
	for id in ids:
		roster[id] = i
		i += 1


func start_game(seed_v: int) -> void:
	if not is_host():
		return
	_compact_pids()
	in_game = true
	_set_refuse(true)
	_reset_inputs()
	_rpc_lobby.rpc(roster, lobby_mission, lobby_difficulty)
	_rpc_start.rpc(lobby_mission, lobby_difficulty, roster.size(), seed_v)


@rpc("authority", "call_local", "reliable")
func _rpc_start(mission_index: int, difficulty: String, players: int, seed_v: int) -> void:
	in_game = true
	lobby_mission = mission_index
	lobby_difficulty = difficulty
	stats = { snapshots_out = 0, snapshots_in = 0, bytes_out = 0, inputs_in = 0 }
	start_requested.emit(mission_index, difficulty, players, seed_v)


func back_to_lobby() -> void:
	if not is_host():
		return
	in_game = false
	_set_refuse(false)
	_rpc_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_to_lobby() -> void:
	in_game = false
	lobby_requested.emit()
	if is_host():
		_broadcast_lobby()


# =============================================================================
# partida: comandos (cliente → host), estado e eventos (host → clientes)
# =============================================================================

## Cliente: manda os últimos comandos (o mais novo primeiro), cada um com o seu número de sequência.
func send_input(history: Array) -> void:
	if not (is_client() and in_game):
		return
	var b := PackedByteArray()
	for i in mini(INPUT_REDUNDANCY, history.size()):
		b.append_array((history[history.size() - 1 - i] as CmdInput).encode())
	_sim_push(_rpc_input.rpc_id.bind(1, b), false)


@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _rpc_input(bytes: PackedByteArray) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	_sim_push(on_input_bytes.bind(sender, bytes), false)


## Host: guarda na fila do jogador os comandos que ainda não foram aplicados (público para os testes).
func on_input_bytes(sender: int, bytes: PackedByteArray) -> void:
	if not roster.has(sender):
		return
	var pid := int(roster[sender])
	var q: Dictionary = _queue.get(pid, {})
	var last: int = acked.get(pid, -1)
	var i := 0
	while i + CmdInput.SIZE <= bytes.size():
		var cmd := CmdInput.decode(bytes.slice(i, i + CmdInput.SIZE))
		i += CmdInput.SIZE
		if last < 0 or CmdInput.seq_newer(cmd.seq, last):
			q[cmd.seq] = cmd
	_queue[pid] = q
	stats.inputs_in += 1


## Host: aplica ao comandante remoto o PRÓXIMO comando da fila dele (um por quadro, na ordem em que foram
## gerados). Fila vazia: repete o último (movimento e tiro), sem apertos novos. Fila longa demais: descarta os
## mais velhos, para o atraso não crescer (os apertos não se perdem: são contadores).
func apply_remote(c: Commander) -> void:
	var q: Dictionary = _queue.get(c.pid, {})
	var cmd: CmdInput = null
	if not q.is_empty():
		var keys := q.keys()
		keys.sort_custom(func(a, b): return CmdInput.seq_newer(b, a))
		while keys.size() > INPUT_QUEUE_MAX:
			q.erase(keys.pop_front())
		cmd = q[keys[0]]
		q.erase(keys[0])
		acked[c.pid] = cmd.seq
		remote_inputs[c.pid] = cmd
	else:
		cmd = remote_inputs.get(c.pid)
	if cmd == null:
		c.in_move = Vector2.ZERO
		c.in_fire = false
		c.in_strafe = false
		return
	cmd.apply_to(c, _applied.get(c.pid))
	_applied[c.pid] = cmd.copy()


func broadcast_state(snapshot: PackedByteArray, events: Array) -> void:
	if not is_host() or roster.size() < 2:
		return
	_sim_push(_rpc_snapshot.rpc.bind(snapshot), false)
	if not events.is_empty():
		_sim_push(_rpc_events.rpc.bind(events), true)
	stats.snapshots_out += 1
	stats.bytes_out += snapshot.size()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snapshot(bytes: PackedByteArray) -> void:
	_sim_push(_got_snapshot.bind(bytes), false)


func _got_snapshot(bytes: PackedByteArray) -> void:
	stats.snapshots_in += 1
	snapshot_received.emit(bytes)


@rpc("authority", "call_remote", "reliable", 2)
func _rpc_events(events: Array) -> void:
	_sim_push(events_received.emit.bind(events), true)


# =============================================================================
# ping, perda e tabela de rede (Tab)
# =============================================================================

func _process(delta: float) -> void:
	_sim_flush()
	if not is_host():
		return
	_ping_t += delta
	if _ping_t >= PING_EVERY:
		_ping_t = 0.0
		for id in roster:
			if int(id) != 1:
				_sim_push(_rpc_ping.rpc_id.bind(int(id), Time.get_ticks_msec()), false)
	_info_t += delta
	if _info_t >= INFO_EVERY:
		_info_t = 0.0
		_refresh_info()


@rpc("authority", "call_remote", "unreliable", 4)
func _rpc_ping(t: int) -> void:
	_sim_push(_answer_ping.bind(t), false)


func _answer_ping(t: int) -> void:
	_sim_push(_rpc_pong.rpc_id.bind(1, t), false)


@rpc("any_peer", "call_remote", "unreliable", 4)
func _rpc_pong(t: int) -> void:
	_sim_push(_got_pong.bind(multiplayer.get_remote_sender_id(), t), false)


func _got_pong(sender: int, t: int) -> void:
	var ms := float(Time.get_ticks_msec() - t)
	_rtt[sender] = ms if not _rtt.has(sender) else lerpf(_rtt[sender], ms, 0.3)


## Host: monta a tabela (pid -> ping, perda) e manda para todos.
func _refresh_info() -> void:
	var info := {}
	for id in roster:
		var pid := int(roster[id])
		if int(id) == 1:
			info[pid] = { rtt = 0.0, loss = 0.0, host = true }
		else:
			info[pid] = { rtt = float(_rtt.get(int(id), -1.0)), loss = _enet_loss(int(id)), host = false }
	netinfo = info
	netinfo_changed.emit()
	_rpc_info.rpc(info)


@rpc("authority", "call_remote", "reliable", 2)
func _rpc_info(info: Dictionary) -> void:
	netinfo = info
	netinfo_changed.emit()


# =============================================================================
# simulador de rede ruim (só testes): cada passagem (saída ou chegada) atrasa metade do lag
# =============================================================================

func sim_active() -> bool:
	return sim_lag > 0.0 or sim_jitter > 0.0 or sim_loss > 0.0


func _sim_push(call: Callable, reliable: bool) -> void:
	if not sim_active():
		call.call()
		return
	if not reliable and _sim_rng.randf() < sim_loss:
		return
	var due := Time.get_ticks_msec() + sim_lag * 0.5
	if reliable:
		due = maxf(due, _sim_last_reliable) # confiável: mantém a ordem
		_sim_last_reliable = due
	else:
		due += _sim_rng.randf() * sim_jitter
	_sim_q.append([due, call])


func _sim_flush() -> void:
	if _sim_q.is_empty():
		return
	var now := float(Time.get_ticks_msec())
	var keep: Array = []
	var run: Array = []
	for it in _sim_q:
		if float(it[0]) <= now:
			run.append(it)
		else:
			keep.append(it)
	_sim_q = keep
	run.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for it in run:
		(it[1] as Callable).call()
