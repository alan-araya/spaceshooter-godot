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

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4
const SNAPSHOT_EVERY := 2 # quadros de física entre snapshots (60/2 = 30 Hz)

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


func _ready() -> void:
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
	status_changed.emit("Hospedando na porta %d" % port)
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
	status_changed.emit("Conectando a %s:%d…" % [address, port])
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
	_reset_inputs()


func _reset_inputs() -> void:
	remote_inputs = {}
	_applied = {}


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
	var used := roster.values()
	var pid := 1
	while used.has(pid):
		pid += 1
	roster[id] = pid
	_broadcast_lobby()


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not roster.has(id):
		return
	var pid: int = roster[id]
	roster.erase(id)
	remote_inputs.erase(pid)
	_applied.erase(pid)
	if in_game:
		peer_left.emit(pid)
	else:
		_broadcast_lobby()


func _on_connected() -> void:
	status_changed.emit("Conectado. Aguardando o host…")


func _on_connection_failed() -> void:
	leave()
	host_left.emit("Não foi possível conectar.")


func _on_server_disconnected() -> void:
	leave()
	host_left.emit("A conexão com o host foi perdida.")


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

func send_input(cmd: CmdInput) -> void:
	if is_client() and in_game:
		_rpc_input.rpc_id(1, cmd.encode())


@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _rpc_input(bytes: PackedByteArray) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not roster.has(sender):
		return
	remote_inputs[int(roster[sender])] = CmdInput.decode(bytes)
	stats.inputs_in += 1


## Host: aplica ao comandante o comando mais recente do jogador remoto dono dele.
func apply_remote(c: Commander) -> void:
	var cmd: CmdInput = remote_inputs.get(c.pid)
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
	_rpc_snapshot.rpc(snapshot)
	if not events.is_empty():
		_rpc_events.rpc(events)
	stats.snapshots_out += 1
	stats.bytes_out += snapshot.size()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snapshot(bytes: PackedByteArray) -> void:
	stats.snapshots_in += 1
	snapshot_received.emit(bytes)


@rpc("authority", "call_remote", "reliable", 2)
func _rpc_events(events: Array) -> void:
	events_received.emit(events)
