extends Control

# WebRTC prototype ("step 1" of the web multiplayer plan).
#
# Connects 2 to 4 game instances (HTML5 and/or desktop) through the room-code
# signaling server in tools/signaling, using WebRTCMultiplayer as the
# SceneTree's network peer, exactly as the game would. Then it checks:
#  - that the host is peer 1 and is_network_server() (game master)
#  - that a client's broadcast rpc() reaches the other clients (full mesh)
#  - round trip times
#  - the largest reliable message that gets through, in both directions
#
# Desktop builds need the webrtc-native GDNative plugin (godot-gdnative-webrtc.zip,
# release 1.0.3-stable, built for Godot 3.5) extracted at the project root.
#
# Launch: desktop  --webrtc-probe [ws://host:port]  on the command line
#         HTML5    add ?webrtc_probe to the page URL (&signaling=wss://... optional)

const DEFAULT_SIGNALING_URL := "ws://localhost:9080"
const ICE_SERVERS := [{"urls": ["stun:stun.l.google.com:19302"]}]
const BLOB_SIZES_KB := [1, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
const BLOB_TIMEOUT := 8.0

var signaling := WebSocketClient.new()
var rtc: WebRTCMultiplayer = null
var my_id := 0
var room_code := ""
var pending_request := {}
var blob_acks := {}
var test_running := false
var log_text := ""

var url_edit: LineEdit
var code_edit: LineEdit
var host_button: Button
var join_button: Button
var test_button: Button
var log_box: RichTextLabel


func _ready() -> void:
	_build_ui()
	signaling.connect("connection_established", self, "_on_signaling_open")
	signaling.connect("connection_closed", self, "_on_signaling_closed")
	signaling.connect("connection_error", self, "_on_signaling_error")
	signaling.connect("data_received", self, "_on_signaling_data")
	get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_peer_disconnected")
	get_tree().connect("connected_to_server", self, "_on_connected_to_server")
	get_tree().connect("server_disconnected", self, "_on_server_disconnected")
	url_edit.text = _initial_signaling_url()
	_log("Platform: %s, Godot %s" % [OS.get_name(), Engine.get_version_info().string])
	_check_webrtc_available()


func _process(_delta: float) -> void:
	if signaling.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		signaling.poll()


func _exit_tree() -> void:
	signaling.disconnect_from_host()
	if get_tree().network_peer == rtc:
		get_tree().network_peer = null


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.anchor_right = 1
	margin.anchor_bottom = 1
	for side in ["left", "top", "right", "bottom"]:
		margin.add_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)

	var title := Label.new()
	title.text = "WebRTC probe"
	box.add_child(title)

	var row1 := HBoxContainer.new()
	box.add_child(row1)
	row1.add_child(_label("Signaling server"))
	url_edit = LineEdit.new()
	url_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	row1.add_child(url_edit)

	var row2 := HBoxContainer.new()
	box.add_child(row2)
	host_button = _button("Host a room", "_on_host_pressed")
	row2.add_child(host_button)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "Room code"
	code_edit.rect_min_size.x = 120
	row2.add_child(code_edit)
	join_button = _button("Join", "_on_join_pressed")
	row2.add_child(join_button)
	test_button = _button("Run tests", "_on_test_pressed")
	test_button.disabled = true
	row2.add_child(test_button)
	row2.add_child(_button("Copy log", "_on_copy_pressed"))
	row2.add_child(_button("Back", "_on_back_pressed"))

	log_box = RichTextLabel.new()
	log_box.size_flags_vertical = SIZE_EXPAND_FILL
	log_box.scroll_following = true
	log_box.selection_enabled = true
	box.add_child(log_box)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, method: String) -> Button:
	var b := Button.new()
	b.text = text
	b.connect("pressed", self, method)
	return b


func _log(text: String) -> void:
	var line := "[%.1f] %s" % [OS.get_ticks_msec() / 1000.0, text]
	print("WebRTCProbe: " + line)
	log_text += line + "\n"
	log_box.add_text(line + "\n")


func _initial_signaling_url() -> String:
	var args := Array(OS.get_cmdline_args())
	var i := args.find("--webrtc-probe")
	if i >= 0 and i + 1 < args.size() and args[i + 1].begins_with("ws"):
		return args[i + 1]
	if OS.has_feature("JavaScript"):
		var from_page = JavaScript.eval("new URLSearchParams(window.location.search).get('signaling') || ''", true)
		if from_page:
			return str(from_page)
	return DEFAULT_SIGNALING_URL


func _check_webrtc_available() -> void:
	# without a WebRTC implementation (desktop build without webrtc-native)
	# new() returns null
	var probe = WebRTCPeerConnection.new()
	if probe == null:
		_log("WebRTC is NOT available. Desktop builds need the webrtc-native plugin.")
		host_button.disabled = true
		join_button.disabled = true
		return
	var err: int = probe.initialize({"iceServers": ICE_SERVERS})
	if err == OK:
		_log("WebRTC is available.")
	else:
		_log("WebRTC is NOT available (error %d). Desktop builds need the webrtc-native plugin." % err)
	probe.close()


func _on_copy_pressed() -> void:
	OS.clipboard = log_text
	_log("Log copied to the clipboard.")


func _on_back_pressed() -> void:
	get_tree().change_scene("res://src/wc/MainMenu.tscn")


# ---------------------------------------------------------------- signaling

func _on_host_pressed() -> void:
	_open_signaling({"type": "host"})


func _on_join_pressed() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.empty():
		_log("Enter a room code first.")
		return
	_open_signaling({"type": "join", "room": code})


func _open_signaling(request: Dictionary) -> void:
	if signaling.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_log("Already connected to the signaling server.")
		return
	pending_request = request
	host_button.disabled = true
	join_button.disabled = true
	_log("Connecting to %s ..." % url_edit.text)
	var err := signaling.connect_to_url(url_edit.text)
	if err != OK:
		_log("connect_to_url failed: %d" % err)
		_reset_buttons()


func _reset_buttons() -> void:
	host_button.disabled = false
	join_button.disabled = false


func _on_signaling_open(_protocol: String) -> void:
	_log("Signaling connected.")
	_send_signal(pending_request)


func _on_signaling_closed(_was_clean := false) -> void:
	_log("Signaling closed.")
	if my_id == 0:
		_reset_buttons()


func _on_signaling_error() -> void:
	_log("Could not reach the signaling server.")
	_reset_buttons()


func _send_signal(msg: Dictionary) -> void:
	var peer := signaling.get_peer(1)
	peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	peer.put_packet(JSON.print(msg).to_utf8())


func _on_signaling_data() -> void:
	var text := signaling.get_peer(1).get_packet().get_string_from_utf8()
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		_log("Bad signaling message: " + text)
		return
	var msg: Dictionary = parsed.result
	match msg.get("type", ""):
		"hosted":
			room_code = msg.room
			_start_rtc(int(msg.id))
			_log("Hosting room %s. Other players join with this code." % room_code)
			code_edit.text = room_code
		"joined":
			room_code = msg.room
			_start_rtc(int(msg.id))
			_log("Joined room %s as peer %d." % [room_code, my_id])
			# peers already in the room send us their offers
			for id in msg.get("peers", []):
				_create_peer(int(id), false)
		"peer_joined":
			_create_peer(int(msg.id), true)
		"peer_left":
			var id := int(msg.id)
			if rtc and rtc.has_peer(id):
				rtc.remove_peer(id)
		"room_closed":
			_log("The host closed the room.")
		"offer", "answer":
			var from := int(msg.from)
			_log_max_message_size("Peer %d" % from, msg.sdp)
			if rtc and rtc.has_peer(from):
				rtc.get_peer(from).connection.set_remote_description(msg.type, msg.sdp)
		"candidate":
			var from := int(msg.from)
			if rtc and rtc.has_peer(from):
				rtc.get_peer(from).connection.add_ice_candidate(msg.mid, int(msg.index), msg.sdp)
		"error":
			_log("Signaling error: " + str(msg.get("message", "")))
			if my_id == 0:
				signaling.disconnect_from_host()
				_reset_buttons()


# ---------------------------------------------------------------- WebRTC

func _start_rtc(id: int) -> void:
	my_id = id
	rtc = WebRTCMultiplayer.new()
	# server compatibility: peer 1 is the network server, clients get
	# connected_to_server once peer 1 is reachable, like with ENet
	var err := rtc.initialize(id, true)
	if err != OK:
		_log("WebRTCMultiplayer.initialize failed: %d" % err)
	get_tree().network_peer = rtc
	_log("Network peer set: unique id %d, is_network_server = %s" % [get_tree().get_network_unique_id(), get_tree().is_network_server()])


func _create_peer(id: int, send_offer: bool) -> void:
	var peer = WebRTCPeerConnection.new()
	if peer == null:
		_log("WebRTC is not available.")
		return
	var err: int = peer.initialize({"iceServers": ICE_SERVERS})
	if err != OK:
		_log("WebRTCPeerConnection.initialize failed: %d" % err)
		return
	peer.connect("session_description_created", self, "_on_description_created", [id])
	peer.connect("ice_candidate_created", self, "_on_ice_candidate", [id])
	rtc.add_peer(peer, id)
	if send_offer:
		peer.create_offer()
	_log("Connecting to peer %d%s" % [id, " (sending offer)" if send_offer else ""])


func _on_description_created(type: String, sdp: String, id: int) -> void:
	if not rtc.has_peer(id):
		return
	_log_max_message_size("This instance (to peer %d)" % id, sdp)
	rtc.get_peer(id).connection.set_local_description(type, sdp)
	_send_signal({"type": type, "to": id, "sdp": sdp})


# the SCTP "max-message-size" each side accepts, from its session description
func _log_max_message_size(who: String, sdp: String) -> void:
	var value := "not stated (65536 by default)"
	for line in sdp.split("\n"):
		if line.begins_with("a=max-message-size:"):
			value = line.substr(19).strip_edges()
	_log("%s accepts messages up to: %s bytes" % [who, value])


func _on_ice_candidate(mid: String, index: int, sdp: String, id: int) -> void:
	_send_signal({"type": "candidate", "to": id, "mid": mid, "index": index, "sdp": sdp})


func _on_peer_connected(id: int) -> void:
	_log("network_peer_connected: %d" % id)
	if get_tree().is_network_server():
		test_button.disabled = false
	elif rtc.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		# a client's broadcast must reach every other client, as with ENet.
		# Before connected_to_server the peer is not CONNECTED yet and rpc() is refused:
		# the first hello is sent from _on_connected_to_server instead
		rpc("probe_hello", OS.get_name())


func _on_peer_disconnected(id: int) -> void:
	_log("network_peer_disconnected: %d" % id)


func _on_connected_to_server() -> void:
	_log("connected_to_server (peer 1 reachable).")
	test_button.disabled = false
	rpc("probe_hello", OS.get_name())


func _on_server_disconnected() -> void:
	_log("server_disconnected.")


# ---------------------------------------------------------------- tests

remote func probe_hello(platform: String) -> void:
	_log("Hello from peer %d (%s)" % [get_tree().get_rpc_sender_id(), platform])


remote func probe_ping(sent_msec: int) -> void:
	rpc_id(get_tree().get_rpc_sender_id(), "probe_pong", sent_msec)


remote func probe_pong(sent_msec: int) -> void:
	_log("Round trip to peer %d: %d ms" % [get_tree().get_rpc_sender_id(), OS.get_ticks_msec() - sent_msec])


remote func probe_blob(size: int, data: PoolByteArray) -> void:
	_log("Received %d KB from peer %d" % [data.size() / 1024, get_tree().get_rpc_sender_id()])
	rpc_id(get_tree().get_rpc_sender_id(), "probe_blob_ack", size, data.size())


remote func probe_blob_ack(size: int, received: int) -> void:
	var sender := get_tree().get_rpc_sender_id()
	blob_acks[sender] = received
	if received != size:
		_log("Peer %d received %d bytes instead of %d" % [sender, received, size])


func _on_test_pressed() -> void:
	if test_running:
		return
	test_running = true
	test_button.disabled = true
	_heartbeat()
	var peers := Array(get_tree().get_network_connected_peers())
	_log("Testing %d connected peer(s): %s" % [peers.size(), str(peers)])
	if peers.empty():
		test_running = false
		test_button.disabled = false
		return
	for id in peers:
		rpc_id(id, "probe_ping", OS.get_ticks_msec())
	yield(get_tree().create_timer(1.0), "timeout")
	yield(_blob_test(peers), "completed")
	_log("Tests finished. Run them from each instance to check both directions.")
	test_running = false
	test_button.disabled = false


func _heartbeat() -> void:
	var started := OS.get_ticks_msec()
	while test_running:
		yield(get_tree().create_timer(5.0), "timeout")
		if test_running:
			_log("(test still running, %d s)" % ((OS.get_ticks_msec() - started) / 1000))


func _blob_test(peers: Array):
	var crypto := Crypto.new()
	var largest := 0
	for kb in BLOB_SIZES_KB:
		var size: int = kb * 1024
		var data := crypto.generate_random_bytes(size)
		blob_acks = {}
		var started := OS.get_ticks_msec()
		_log("Sending %d KB ..." % kb)
		for id in peers:
			rpc_id(id, "probe_blob", size, data)
		_log("%d KB handed to the network" % kb)
		var waited := 0.0
		while waited < BLOB_TIMEOUT and blob_acks.size() < peers.size():
			yield(get_tree().create_timer(0.1), "timeout")
			waited += 0.1
		var ok := 0
		for id in peers:
			if blob_acks.get(id, -1) == size:
				ok += 1
		_log("%d KB: %d/%d peer(s) acknowledged in %d ms" % [kb, ok, peers.size(), OS.get_ticks_msec() - started])
		if ok < peers.size():
			_log("Stopping: the largest message that reached every peer is %d KB." % largest)
			return
		largest = kb
	_log("Every size up to %d KB got through." % largest)
