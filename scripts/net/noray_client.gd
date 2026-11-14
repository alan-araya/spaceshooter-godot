class_name NorayClient
extends Node
## Cliente do noray (github.com/foxssake/noray, MIT): servidor que junta jogadores pela internet sem VPN.
## Protocolo (TCP, linhas de texto): "register-host" → "set-oid CÓDIGO" + "set-pid SEGREDO";
## "connect CÓDIGO" → os DOIS lados recebem "connect ip:porta" do outro (furar o NAT);
## "connect-relay CÓDIGO" → os dois recebem "connect-relay PORTA" (o noray repassa o tráfego UDP).
## O endereço externo de cada um é registrado mandando o SEGREDO por UDP para a porta 8809, da mesma porta
## local que o ENet vai usar depois. Baseado no addon netfox.noray (MIT), reescrito sem dependências.

signal command(cmd: String, data: String)
signal oid_received(oid: String)
signal pid_received(pid: String)
signal connect_nat(address: String, port: int)
signal connect_relay(address: String, port: int)
signal failed(message: String) # "connect <erro>" do servidor (ex.: código de sala que não existe)
signal disconnected

const DEFAULT_PORT := 8890
const REGISTRAR_PORT := 8809

var address := "" # IP do servidor noray
var oid := "" # código da sala (público)
var pid := "" # segredo (privado)
var local_port := -1 # porta local registrada: o servidor ENet escuta nela / o cliente ENet sai dela
var _tcp := StreamPeerTCP.new()
var _buf := ""
var _was_connected := false


func is_connected_to_server() -> bool:
	return _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


## Conecta ao servidor ("host" ou "host:porta"). Espera até 5 s.
func connect_to_server(server: String) -> Error:
	close()
	var host := server.strip_edges()
	var port := DEFAULT_PORT
	if host.contains(":"):
		port = host.get_slice(":", 1).to_int()
		host = host.get_slice(":", 0)
	var ip := IP.resolve_hostname(host, IP.TYPE_IPV4)
	if ip == "":
		return ERR_CANT_RESOLVE
	var err := _tcp.connect_to_host(ip, port)
	if err != OK:
		return err
	_tcp.set_no_delay(true)
	var t := 0.0
	while _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and t < 5.0:
		_tcp.poll()
		await get_tree().process_frame
		t += get_process_delta_time()
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		close()
		return ERR_CANT_CONNECT
	address = ip
	_was_connected = true
	return OK


func close() -> void:
	if _tcp.get_status() != StreamPeerTCP.STATUS_NONE:
		_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_buf = ""
	oid = ""
	pid = ""
	local_port = -1
	_was_connected = false


## Pede código + segredo (todo mundo se registra, também quem só vai entrar) e registra a porta UDP externa.
func register() -> Error:
	if not is_connected_to_server():
		return ERR_CONNECTION_ERROR
	_send("register-host")
	var t := 0.0
	while pid == "" and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if pid == "":
		return ERR_TIMEOUT
	return await _register_remote()


func _register_remote(timeout: float = 6.0, interval: float = 0.1) -> Error:
	var udp := PacketPeerUDP.new()
	udp.bind(0)
	udp.set_dest_address(address, REGISTRAR_PORT)
	var result := ERR_TIMEOUT
	var t := timeout
	while t > 0.0:
		udp.put_packet(pid.to_utf8_buffer())
		await get_tree().create_timer(interval).timeout
		t -= interval
		if udp.get_available_packet_count() > 0:
			var r := udp.get_packet().get_string_from_utf8()
			result = OK if r == "OK" else FAILED
			if result == OK:
				local_port = udp.get_local_port()
			break
	udp.close()
	return result


func request_nat(room: String) -> void:
	_send("connect " + room)


func request_relay(room: String) -> void:
	_send("connect-relay " + room)


func _send(line: String) -> void:
	if is_connected_to_server():
		_tcp.put_data((line + "\n").to_utf8_buffer())


func _process(_dt: float) -> void:
	if _tcp.get_status() == StreamPeerTCP.STATUS_NONE:
		return
	_tcp.poll()
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if _was_connected:
			_was_connected = false
			disconnected.emit()
		return
	var n := _tcp.get_available_bytes()
	if n <= 0:
		return
	_buf += _tcp.get_utf8_string(n)
	while _buf.contains("\n"):
		var i := _buf.find("\n")
		var line := _buf.substr(0, i).strip_edges()
		_buf = _buf.substr(i + 1)
		if line == "":
			continue
		var sp := line.find(" ")
		var cmd := line if sp < 0 else line.substr(0, sp)
		var data := "" if sp < 0 else line.substr(sp + 1)
		_handle(cmd, data)


func _handle(cmd: String, data: String) -> void:
	command.emit(cmd, data)
	match cmd:
		"set-oid":
			oid = data
			oid_received.emit(data)
		"set-pid":
			pid = data
			pid_received.emit(data)
		"connect":
			var parts := data.split(":")
			if parts.size() != 2 or not parts[1].is_valid_int():
				failed.emit(data) # o servidor responde com o mesmo comando + mensagem de erro
				return
			connect_nat.emit(parts[0], parts[1].to_int())
		"connect-relay":
			if not data.is_valid_int():
				failed.emit(data)
				return
			connect_relay.emit(address, data.to_int())


## Aperto de mão UDP antes do ENet (cliente): os dois lados mandam o estado até ambos se lerem.
## Abre o buraco no NAT. OK = completo; ERR_BUSY = só um lado ouviu (dá para tentar mesmo assim).
static func handshake_udp(tree: SceneTree, udp: PacketPeerUDP, timeout: float = 6.0, interval: float = 0.1) -> Error:
	var did_read := false
	var did_handshake := false
	var result := ERR_TIMEOUT
	var t := timeout
	while t >= 0.0:
		while udp.get_available_packet_count() > 0:
			var st := udp.get_packet().get_string_from_ascii()
			if not st.begins_with("$"):
				continue
			did_read = true
			if st.contains("r"):
				did_handshake = true
			if st.contains("x") and did_handshake:
				result = OK
				t = -1.0
		var me := "$" + ("r" if did_read else "-") + "w" + ("x" if did_handshake else "-")
		udp.put_packet(me.to_ascii_buffer())
		if t < 0.0:
			break
		await tree.create_timer(interval).timeout
		t -= interval
	if result != OK and did_read:
		result = ERR_BUSY
	return result


## Host: não dá para ler pelo socket do ENet, então só "grita" que leu e completou por alguns segundos.
static func handshake_enet(tree: SceneTree, peer: ENetMultiplayerPeer, address: String, port: int, timeout: float = 6.0, interval: float = 0.1) -> void:
	var t := timeout
	while t >= 0.0:
		if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		peer.host.socket_send(address, port, "$rwx".to_ascii_buffer())
		await tree.create_timer(interval).timeout
		t -= interval
