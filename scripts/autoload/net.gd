extends Node
## Netværk: solo, host eller join. Bruger ENet (UDP) til co-op.
## Solo bruger OfflineMultiplayerPeer, så spillet altid kører gennem den samme kode.

signal started            ## Verden er klar til at modtage spillere.
signal status(msg: String)
signal stopped(msg: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4

var local_name := "Pilot"
var chosen_ship := "falk"      ## Startskib valgt på titelskærmen (bruges kun for nye piloter)
var is_online := false


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func start_solo(pname: String) -> void:
	local_name = pname
	is_online = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_begin_as_server()


func host(pname: String, port: int = DEFAULT_PORT) -> bool:
	local_name = pname
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		status.emit("Kunne ikke starte server på port %d (fejl %d)" % [port, err])
		return false
	multiplayer.multiplayer_peer = peer
	is_online = true
	_begin_as_server()
	status.emit("Server kører på port %d. Venner joiner med din IP." % port)
	return true


func join(pname: String, address: String, port: int = DEFAULT_PORT) -> bool:
	local_name = pname
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status.emit("Kunne ikke forbinde til %s:%d (fejl %d)" % [address, port, err])
		return false
	multiplayer.multiplayer_peer = peer
	is_online = true
	status.emit("Forbinder til %s:%d …" % [address, port])
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.server_save()


func leave() -> void:
	Game.server_save()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_online = false


func _begin_as_server() -> void:
	Game.reset_session()
	Game.server_load()
	started.emit()
	Game.server_add_player(multiplayer.get_unique_id(), local_name, chosen_ship)


func _on_connected() -> void:
	Game.reset_session()
	started.emit()
	Game.srv_register.rpc_id(1, local_name, chosen_ship)


func _on_failed() -> void:
	status.emit("Forbindelsen mislykkedes")
	leave()


func _on_server_gone() -> void:
	leave()
	stopped.emit("Forbindelsen til værten blev afbrudt")


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		Game.server_remove_player(id)
