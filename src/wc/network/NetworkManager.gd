# warning-ignore-all:RETURN_VALUE_DISCARDED
extends Node

# Network transport for multiplayer games (autoload "networkManager").
#
# Two transports behind one interface:
#  - ENET: direct IP connection (desktop only), as before
#  - WEBRTC: room codes through the signaling server (tools/signaling),
#    works between browsers and desktop builds (desktop needs the
#    webrtc-native plugin)
#
# With both, the host is peer 1 (get_tree().is_network_server(), the game
# master) and the high-level multiplayer API (rpc, rpc_id, remotesync...) is
# used unchanged. WebRTC players are connected in a full mesh, since Godot 3's
# WebRTCMultiplayer does not relay client-to-client RPCs through peer 1.
#
# All game RPCs go through send_rpc() (cfc._rpc and cfc._rpc_id). With WebRTC,
# a message bigger than MAX_MESSAGE_BYTES is split into chunks: larger messages
# are silently dropped between desktop and browsers, and make browsers throw
# out of the engine (see the WebRTC plan, step 1 results).

signal room_hosted(code)        # WebRTC host: the room code to give other players
signal room_joined(code)        # WebRTC client: joined, connections are being made
signal peer_ready(network_id)   # it is now safe to send RPCs to this peer
signal network_error(message)   # could not host or join
signal public_rooms_received(rooms)  # fetch_public_rooms(): Array of {room, name, players, max_players}
signal public_rooms_failed(message)  # fetch_public_rooms() could not reach the server

enum Transport { NONE, ENET, WEBRTC }

const DEFAULT_SIGNALING_URL := "wss://wololo.net/signal"
const ICE_SERVERS := [{"urls": ["stun:stun.l.google.com:19302"]}]
# 32 KB is the largest message that reached every peer in every direction
# during the step 1 tests; chunks stay well below, with room for the RPC header
const MAX_MESSAGE_BYTES := 12 * 1024
const ENET_RETRIES := 10

var transport: int = Transport.NONE
var room_code := ""

var _signaling: WebSocketClient = null
var _signaling_request := {}
var _rtc: WebRTCMultiplayer = null
# client side: peers that connected before connected_to_server fired
var _pending_ready_peers := []
var _server_reachable := false

var _next_transfer_id := 1
var _incoming_transfers := {}

# Peers released by close(), kept alive until the next frame: close() can be
# called while one of them is being polled (from one of its own signals), and
# freeing or closing it there crashes the engine
var _closed_peers := []

# fetch_public_rooms(): a short-lived connection to the signaling server,
# separate from the one used to host or join
const ROOM_LIST_TIMEOUT := 10.0
var _room_list_client: WebSocketClient = null
var _room_list_timer := 0.0

# WebRTC: how often the connections to the other players are checked
const PEER_CHECK_INTERVAL := 0.5
var _peer_check_timer := 0.0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().connect("network_peer_connected", self, "_on_network_peer_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_network_peer_disconnected")
	get_tree().connect("connected_to_server", self, "_on_connected_to_server")
	get_tree().connect("server_disconnected", self, "_on_server_disconnected")


func _process(delta: float) -> void:
	if _closed_peers:
		_release_closed_peers()
	if _signaling and _signaling.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_signaling.poll()
	if _room_list_client:
		_room_list_timer += delta
		if _room_list_timer > ROOM_LIST_TIMEOUT:
			call_deferred("_room_list_done", null, "The online server did not answer")
		else:
			_room_list_client.poll()
	if _rtc:
		_peer_check_timer += delta
		if _peer_check_timer >= PEER_CHECK_INTERVAL:
			_peer_check_timer = 0.0
			_remove_dead_rtc_peers()


# A player whose game crashed or whose tab was closed: its data channels close
# right away, but Godot 3's WebRTCMultiplayer only notices when the whole
# connection times out (about 30 s). Until then every send to that player
# fails ("_put_packet: DataChannel is closed") and the game still waits for it.
# Removing the peer emits network_peer_disconnected, as with ENet.
func _remove_dead_rtc_peers() -> void:
	var rtc = _rtc
	for id in rtc.get_peers().keys():
		if _rtc != rtc:
			return # closed by a peer_disconnected / server_disconnected handler
		var peer: Dictionary = rtc.get_peer(id)
		if not peer.get("connected", false):
			continue # still connecting
		var reason := ""
		var state = peer.connection.get_connection_state()
		if state in [WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED]:
			reason = "connection state %d" % state
		else:
			for channel in peer.get("channels", []):
				if channel and channel.get_ready_state() == WebRTCDataChannel.STATE_CLOSED:
					reason = "data channel closed"
					break
		if reason:
			cfc.LOG("{network} lost peer %d (%s)" % [int(id), reason], true)
			rtc.remove_peer(int(id))


# ---------------------------------------------------------------- status

# null until the first check: the plugin is loaded (or not) when the engine starts
var _webrtc_available = null

func is_webrtc_available() -> bool:
	if _webrtc_available == null:
		_webrtc_available = _check_webrtc_available()
	return _webrtc_available


static func _check_webrtc_available() -> bool:
	if OS.has_feature("JavaScript"):
		return true
	# desktop: needs the webrtc-native GDNative plugin, without it new() returns null
	var probe = WebRTCPeerConnection.new()
	if probe == null:
		return false
	var available: bool = probe.initialize({}) == OK
	probe.close()
	return available


static func is_enet_available() -> bool:
	return not OS.has_feature("JavaScript")


func signaling_url() -> String:
	return cfc.game_settings.get("lobby_server", {}).get("signaling_url", DEFAULT_SIGNALING_URL)


func uses_enet() -> bool:
	return transport == Transport.ENET


func uses_webrtc() -> bool:
	return transport == Transport.WEBRTC


# false while a client is connecting: rpc() is refused before connected_to_server
func can_send() -> bool:
	var peer = get_tree().network_peer
	if not peer:
		return false
	if peer.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return get_tree().is_network_server() or _server_reachable


# ---------------------------------------------------------------- ENet

func host_enet(port: int = 0) -> int:
	close()
	var peer = NetworkedMultiplayerENet.new()
	peer.set_compression_mode(NetworkedMultiplayerENet.COMPRESS_RANGE_CODER)
	var err = peer.create_server(port if port else CFConst.MULTIPLAYER_PORT, 4) # Maximum of 4 peers. TODO make this a config
	if err != OK:
		return err
	transport = Transport.ENET
	get_tree().set_network_peer(peer)
	return OK


func join_enet(ip: String, port: int = 0, own_port: int = 0):
	close()
	if not ip.is_valid_ip_address():
		emit_signal("network_error", "IP address is invalid")
		return
	for _attempt in ENET_RETRIES:
		var peer = NetworkedMultiplayerENet.new()
		peer.set_compression_mode(NetworkedMultiplayerENet.COMPRESS_RANGE_CODER)
		var err = peer.create_client(ip, port if port else CFConst.MULTIPLAYER_PORT, 0, 0, own_port)
		if err == OK:
			transport = Transport.ENET
			get_tree().set_network_peer(peer)
			return
		cfc.LOG("could not join, ERRNO:" + str(err))
		yield(get_tree().create_timer(1.0), "timeout")
	emit_signal("network_error", "Could not join after %d attempts" % ENET_RETRIES)


func set_peer_timeout(network_id: int, limit_ms: int, min_ms: int, max_ms: int) -> void:
	var peer = get_tree().network_peer
	if transport == Transport.ENET and peer is NetworkedMultiplayerENet:
		peer.set_peer_timeout(network_id, limit_ms, min_ms, max_ms)


# ---------------------------------------------------------------- WebRTC

# public: listed by fetch_public_rooms() until the game starts (see set_room_joinable)
# room_name: shown in that list
func host_webrtc(url: String = "", public: bool = false, room_name: String = "") -> void:
	_open_signaling(url, {"type": "host", "public": public, "name": room_name})


# host: false once the game starts. The room disappears from the public list
# and the server refuses new players
func set_room_joinable(joinable: bool) -> void:
	if transport == Transport.WEBRTC and get_tree().is_network_server():
		_send_signal({"type": "room_state", "joinable": joinable})


# Public rooms that can be joined, from the signaling server.
# Answers with public_rooms_received(rooms) or public_rooms_failed(message)
func fetch_public_rooms(url: String = "") -> void:
	if _room_list_client:
		return # already fetching
	if not url:
		url = signaling_url()
	_room_list_client = WebSocketClient.new()
	_room_list_timer = 0.0
	_room_list_client.connect("connection_established", self, "_on_room_list_open")
	_room_list_client.connect("connection_error", self, "_on_room_list_error")
	_room_list_client.connect("connection_closed", self, "_on_room_list_error")
	_room_list_client.connect("data_received", self, "_on_room_list_data")
	var err = _room_list_client.connect_to_url(url)
	if err != OK:
		_room_list_done(null, "Could not reach the online server (error %d)" % err)


func _on_room_list_open(_protocol: String) -> void:
	var peer = _room_list_client.get_peer(1)
	peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	peer.put_packet(JSON.print({"type": "list"}).to_utf8())


func _on_room_list_error(_was_clean := false) -> void:
	call_deferred("_room_list_done", null, "Could not reach the online server")


func _on_room_list_data() -> void:
	var parsed = JSON.parse(_room_list_client.get_peer(1).get_packet().get_string_from_utf8())
	if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY and parsed.result.get("type", "") == "rooms":
		call_deferred("_room_list_done", parsed.result.get("rooms", []), "")


# deferred: called from the client's own signals, while it is being polled
func _room_list_done(rooms, error_message: String) -> void:
	if not _room_list_client:
		return # already answered
	_closed_peers.append(_room_list_client)
	_room_list_client = null
	if rooms == null:
		emit_signal("public_rooms_failed", error_message)
		return
	var result := []
	for room in rooms:
		if typeof(room) == TYPE_DICTIONARY and looks_like_room_code(str(room.get("room", ""))):
			result.append({
				"room": str(room.room),
				"name": str(room.get("name", "")),
				"players": int(room.get("players", 0)),
				"max_players": int(room.get("max_players", 4)),
			})
	emit_signal("public_rooms_received", result)


func join_webrtc(code: String, url: String = "") -> void:
	code = code.strip_edges().to_upper()
	if code.empty():
		emit_signal("network_error", "Enter a room code")
		return
	_open_signaling(url, {"type": "join", "room": code})


static func looks_like_room_code(text: String) -> bool:
	var code = text.strip_edges().to_upper()
	if code.length() != 5:
		return false
	for c in code:
		if not c in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789":
			return false
	return true


func _open_signaling(url: String, request: Dictionary) -> void:
	close()
	if not is_webrtc_available():
		emit_signal("network_error", "WebRTC is not available (the webrtc-native plugin is missing)")
		return
	if not url:
		url = signaling_url()
	_signaling = WebSocketClient.new()
	_signaling.connect("connection_established", self, "_on_signaling_open")
	_signaling.connect("connection_closed", self, "_on_signaling_closed")
	_signaling.connect("connection_error", self, "_on_signaling_error")
	_signaling.connect("data_received", self, "_on_signaling_data")
	_signaling_request = request
	transport = Transport.WEBRTC
	cfc.LOG("{network} connecting to signaling server " + url, true)
	var err = _signaling.connect_to_url(url)
	if err != OK:
		_fail("Could not reach the online server (error %d)" % err)


func _on_signaling_open(_protocol: String) -> void:
	_send_signal(_signaling_request)


# failures reported from inside _signaling.poll() are handled on the next
# frame: close() releases the WebSocketClient, which must not happen while it runs
func _on_signaling_error() -> void:
	call_deferred("_fail", "Could not reach the online server")


func _on_signaling_closed(_was_clean := false) -> void:
	# the WebRTC connections outlive the signaling server: only a problem
	# while we are still waiting for our room
	if transport == Transport.WEBRTC and not _rtc:
		call_deferred("_fail", "The online server closed the connection")


func _send_signal(msg: Dictionary) -> void:
	if not _signaling:
		return
	var peer = _signaling.get_peer(1)
	peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	peer.put_packet(JSON.print(msg).to_utf8())


func _on_signaling_data() -> void:
	var text = _signaling.get_peer(1).get_packet().get_string_from_utf8()
	var parsed = JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed.result
	match msg.get("type", ""):
		"hosted":
			room_code = msg.room
			_start_rtc(int(msg.id))
			emit_signal("room_hosted", room_code)
		"joined":
			room_code = msg.room
			_start_rtc(int(msg.id))
			# players already in the room send us their offers
			for id in msg.get("peers", []):
				_add_rtc_peer(int(id), false)
			emit_signal("room_joined", room_code)
		"peer_joined":
			_add_rtc_peer(int(msg.id), true)
		"peer_left":
			var id := int(msg.id)
			if _rtc and _rtc.has_peer(id):
				_rtc.remove_peer(id)
		"room_closed":
			cfc.LOG("{network} the host closed the room", true)
		"offer", "answer":
			var from := int(msg.from)
			if _rtc and _rtc.has_peer(from):
				_rtc.get_peer(from).connection.set_remote_description(msg.type, msg.sdp)
		"candidate":
			var from := int(msg.from)
			if _rtc and _rtc.has_peer(from):
				_rtc.get_peer(from).connection.add_ice_candidate(msg.mid, int(msg.index), msg.sdp)
		"error":
			if not _rtc:
				call_deferred("_fail", _signaling_error_text(str(msg.get("message", ""))))
			else:
				cfc.LOG("{network} signaling error: " + str(msg.get("message", "")), true)


func _signaling_error_text(message: String) -> String:
	match message:
		"no such room":
			return "No room with this code"
		"room is full":
			return "This room is full"
		"game already started":
			return "The game in this room has already started"
	return "Online server error: " + message


func _start_rtc(my_id: int) -> void:
	_rtc = WebRTCMultiplayer.new()
	# server compatibility: peer 1 is the network server and clients get
	# connected_to_server once peer 1 is reachable, as with ENet
	_rtc.initialize(my_id, true)
	get_tree().set_network_peer(_rtc)
	cfc.LOG("{network} WebRTC peer %d in room %s" % [my_id, room_code], true)


func _add_rtc_peer(id: int, send_offer: bool) -> void:
	if not _rtc or _rtc.has_peer(id):
		return
	var peer = WebRTCPeerConnection.new()
	if peer == null or peer.initialize({"iceServers": ICE_SERVERS}) != OK:
		cfc.LOG("{network} could not create a WebRTC connection to " + str(id), true)
		return
	peer.connect("session_description_created", self, "_on_description_created", [id])
	peer.connect("ice_candidate_created", self, "_on_ice_candidate", [id])
	_rtc.add_peer(peer, id)
	if send_offer:
		peer.create_offer()


func _on_description_created(type: String, sdp: String, id: int) -> void:
	if not _rtc or not _rtc.has_peer(id):
		return
	_rtc.get_peer(id).connection.set_local_description(type, sdp)
	_send_signal({"type": type, "to": id, "sdp": sdp})


func _on_ice_candidate(mid: String, index: int, sdp: String, id: int) -> void:
	_send_signal({"type": "candidate", "to": id, "mid": mid, "index": index, "sdp": sdp})


func _fail(message: String) -> void:
	if transport != Transport.WEBRTC:
		return # already closed
	cfc.LOG("{network} " + message, true)
	close()
	emit_signal("network_error", message)


# ---------------------------------------------------------------- connection events

func _on_network_peer_connected(id: int) -> void:
	if get_tree().is_network_server() or _server_reachable:
		emit_signal("peer_ready", id)
	else:
		# a client cannot send anything before connected_to_server
		_pending_ready_peers.append(id)


func _on_connected_to_server() -> void:
	_server_reachable = true
	var ready_peers = _pending_ready_peers
	_pending_ready_peers = []
	for id in ready_peers:
		if get_tree().network_peer and id in Array(get_tree().get_network_connected_peers()):
			emit_signal("peer_ready", id)


func _on_network_peer_disconnected(id: int) -> void:
	_pending_ready_peers.erase(id)
	for key in _incoming_transfers.keys():
		if _incoming_transfers[key].sender == id:
			_incoming_transfers.erase(key)


func _on_server_disconnected() -> void:
	_server_reachable = false


func close() -> void:
	if _signaling:
		_closed_peers.append(_signaling)
		_signaling = null
	if _rtc:
		_closed_peers.append(_rtc)
		_rtc = null
	if get_tree().network_peer:
		if not get_tree().network_peer in _closed_peers:
			_closed_peers.append(get_tree().network_peer)
		get_tree().set_network_peer(null)
	transport = Transport.NONE
	room_code = ""
	_server_reachable = false
	_pending_ready_peers = []
	_incoming_transfers = {}
	# the network id changes with every connection
	cfc._network_id = 0


func _release_closed_peers() -> void:
	var peers = _closed_peers
	_closed_peers = []
	for peer in peers:
		if peer is WebSocketClient:
			peer.disconnect_from_host()
		elif peer is WebRTCMultiplayer:
			peer.close()
		# ENet: releasing the last reference closes the connection, as before


# ---------------------------------------------------------------- RPCs

# target 0: every peer, like rpc(). Otherwise one peer, like rpc_id().
func send_rpc(object: Node, target: int, func_name: String, params: Array) -> void:
	if transport == Transport.WEBRTC:
		var payload := var2bytes([str(object.get_path()), func_name, params])
		if payload.size() > MAX_MESSAGE_BYTES:
			_send_chunked(object, target, func_name, params, payload)
			return
	if target:
		object.callv("rpc_id", [target, func_name] + params)
	else:
		object.callv("rpc", [func_name] + params)


func _send_chunked(object: Node, target: int, func_name: String, params: Array, payload: PoolByteArray) -> void:
	var my_id := get_tree().get_network_unique_id()
	var targets := []
	if target == 0:
		targets = Array(get_tree().get_network_connected_peers())
	elif target != my_id:
		targets = [target]
	var transfer_id := _next_transfer_id
	_next_transfer_id += 1
	var count := int(ceil(payload.size() / float(MAX_MESSAGE_BYTES)))
	cfc.LOG("{network} %s: %d bytes sent in %d chunks" % [func_name, payload.size(), count], true)
	for peer_id in targets:
		for i in count:
			var start: int = i * MAX_MESSAGE_BYTES
			var end: int = int(min(start + MAX_MESSAGE_BYTES, payload.size())) - 1
			rpc_id(peer_id, "_receive_chunk", transfer_id, i, count, payload.subarray(start, end))
	# local call, as rpc() and rpc_id() would do it: only for the sync modes
	# (remotesync, mastersync, puppetsync). A "remote" method prints an error
	# here and is not called, which is also what rpc() does locally.
	if target == 0 or target == my_id:
		object.callv("rpc_id", [my_id, func_name] + params)


remote func _receive_chunk(transfer_id: int, index: int, count: int, data: PoolByteArray) -> void:
	var sender := get_tree().get_rpc_sender_id()
	var key: String = "%d:%d" % [sender, transfer_id]
	if not _incoming_transfers.has(key):
		_incoming_transfers[key] = {"sender": sender, "parts": [], "received": 0}
		_incoming_transfers[key].parts.resize(count)
	var transfer: Dictionary = _incoming_transfers[key]
	if transfer.parts[index] == null:
		transfer.parts[index] = data
		transfer.received += 1
	if transfer.received < count:
		return
	_incoming_transfers.erase(key)
	var payload := PoolByteArray()
	for part in transfer.parts:
		payload.append_array(part)
	var message = bytes2var(payload, false)
	if typeof(message) != TYPE_ARRAY or message.size() != 3:
		cfc.LOG("{network} invalid chunked message from " + str(sender), true)
		return
	var node = get_node_or_null(NodePath(message[0]))
	if not node or not node.has_method(message[1]):
		cfc.LOG("{network} chunked message for a missing node or method: %s %s" % [message[0], message[1]], true)
		return
	# called while this RPC is running: get_rpc_sender_id() still returns
	# the sender, as for a regular RPC
	node.callv(message[1], message[2])
