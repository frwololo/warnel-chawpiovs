# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Panel

const ENABLE_HOLE_PUNCHING = false

var ERROR_COLOR := 	Color(1,0.11,0.1)
var OK_COLOR := 	Color(0.1,11,0.1)
# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $MainMenu/HBox/VBox/Center/VButtons
onready var main_menu := $MainMenu
onready var v_folder_label := $MainMenu/HBox/VBox/Margin2/Label
onready var status_msg := $MainMenu/HBox/VBox/WaitingMsg
onready var players_container := $MainMenu/HBox/VBox/Players
onready var launch_button := $MainMenu/HBox/VBox/Center/VButtons/Launch
onready var status := $MainMenu/HBox/StatusLabel

var peer = null
# dictionary indexed by network_id for each player.
var players = {}
var my_info = {name = "Name Unset", tests = []}
var _multiplayer_desync = null

var person = preload("res://src/wc/lobby/Player.tscn")

var http_request: HTTPRequest = null
var is_master = false
var my_port = 0
var network_is_ready = false
var master_ip = ""
# WebRTC: hosting or joining a room code instead of a direct IP
var online_room = false
var room_code = ""

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	launch_button.disabled = true
	cfc.default_button_focus(v_buttons)
	resize()
	
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
			option_button.connect('mouse_entered', option_button, 'grab_focus')			
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	if cfc.game_settings.get("hide_folder_label", false):
		v_folder_label.text = " "
	else:
		v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")
	

	
# Network setup
	# peer_ready instead of network_peer_connected: a client cannot send
	# anything before connected_to_server (see NetworkManager)
	networkManager.connect("peer_ready", self, "_player_connected")
	networkManager.connect("room_hosted", self, "_room_hosted")
	networkManager.connect("room_joined", self, "_room_joined")
	networkManager.connect("network_error", self, "_network_error")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected_ok")
	# deferred: these are emitted while the network peer is being polled,
	# and _end_game closes it
	get_tree().connect("connection_failed", self, "_connected_fail", [], CONNECT_DEFERRED)
	get_tree().connect("server_disconnected", self, "_server_disconnected", [], CONNECT_DEFERRED)
	$HolePunch.connect("hole_punched", self, "_hole_punched")
	$HolePunch.connect("session_registered", self, "_nat_session_registered")	
	$HolePunch.connect("error", self, "_nat_error")	

	var params = cfc.get_next_scene_params()
	if params.has("room_code"):
		launch_button.hide()
		is_master = false
		online_room = true
		room_code = params["room_code"]
		add_log("joining room " + room_code)
	elif params.has("host_ip"):
		launch_button.hide()
		is_master = false
		master_ip = params["host_ip"]
		add_log("joining as client. Server is:" + str(master_ip))
	else:
		is_master = true
		online_room = params.get("online", false) or not networkManager.is_enet_available()
		add_log("joining as server")		

	if online_room:
		if is_master:
			_set_status("Creating an online room...", true)
			networkManager.host_webrtc("", params.get("public", false), params.get("room_name", ""))
		else:
			_set_status("Joining room " + room_code + "...", true)
			networkManager.join_webrtc(room_code)
	elif is_master:
		
		http_request = HTTPRequest.new()
		http_request.set_timeout(10.0)
		add_child(http_request)	
		http_request.connect("request_completed", self, "check_signal_server")
		var create_room_url = cfc.game_settings.get('lobby_server', {}).get('create_room_url', '')
		var server = cfc.game_settings.get('lobby_server', {}).get('server', '')
		if server and create_room_url:
			add_log("connecting lobby server:" + server + create_room_url)
			http_request.request(server + create_room_url)
		
		if ENABLE_HOLE_PUNCHING:	
			add_log("starting traversal as host")
			$HolePunch.start_traversal("wc7548", true, "Wololo")
		else:
			_join_as_server()
	else:
		if ENABLE_HOLE_PUNCHING:
			add_log("starting traversal as client")
			$HolePunch.start_traversal("wc7548", false, "Player2")
		else:
			_join_as_client(master_ip)


func add_log(value):
	status.text += value + "\n"

# WebRTC host: the room exists, other players join with its code
func _room_hosted(code):
	room_code = code
	network_is_ready = true
	v_folder_label.text = "Room code: " + code
	v_folder_label.add_color_override("font_color", OK_COLOR)
	my_info.name = "Player 1"
	my_info.tests = gameData.run_auto_tests
	_set_status("Room code: " + code + " - waiting for players...", true)
	register_self(my_info)

# WebRTC client: in the room, the connections to the other players are being made
func _room_joined(code):
	network_is_ready = true
	v_folder_label.text = "Room code: " + code
	my_info.name = "Player " + str(cfc.get_network_unique_id())
	my_info.tests = gameData.run_auto_tests
	_set_status("Connecting...", true)
	register_self(my_info)

func _network_error(message):
	_set_status(message, false)

func _nat_error(error_text, error_id):
	add_log(error_text + " - ERRNO:" + str(error_id))

func _nat_session_registered():
	add_log("session registered")

func _hole_punched(own_port, host_port, host_address):
#	var result = {
#		"own_port": own_port,
#		"host_port": host_port,
#		"host_address": host_address,
#	}
	v_folder_label.text	= "registered to signal server with ip:" + str(host_address) + ", own_port:" +str(own_port) +", host_port:" + str(host_port)
	add_log(v_folder_label.text)
	yield(get_tree().create_timer(0.1), 'timeout')
	if is_master:
		_join_as_server(own_port)
#		_join_as_server(CFConst.MULTIPLAYER_PORT)
	else:
		_join_as_client(host_address, host_port, own_port)
#		_join_as_client(master_ip, CFConst.MULTIPLAYER_PORT)

	

func _get_data_from_signal_server(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		#TODO error handling
		return ""

	var content = body.get_string_from_utf8()

	var json_result:JSONParseResult = JSON.parse(content)
	if (json_result.error != OK):
		return ""
		

	var results = json_result.result
	if ! typeof(results) == TYPE_DICTIONARY:
		return ""
				
	return results
	
func check_signal_server(result, response_code, headers, body):
	var results =  _get_data_from_signal_server(result, response_code, headers, body)
	if results and typeof(results) == TYPE_DICTIONARY:
		var ip  = results.get("ip", "")
		var room_name =  results.get("room_name", "")
		v_folder_label.text	= "registered to signal server with ip:" + str(ip) + " and room name: " + str(room_name)
		v_folder_label.add_color_override("font_color", OK_COLOR)
	else:
		v_folder_label.text	=  "error registering with signal server"
		v_folder_label.add_color_override("font_color", ERROR_COLOR)		
		



func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"Launch":
			_launch_server_game()
		"Cancel":
			gameData.disconnect_from_network()
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

	
func _on_Menu_resized() -> void:
	resize()
	
func resize():
	self.rect_scale =  cfc.hardcoded_positions_modifier

func register_self(info):
	var id = cfc.get_network_unique_id()
	# Store the info
	players[id] = info

	# Call function to update lobby UI here
	var new_person = person.instance()
	players_container.add_child(new_person)
	new_person.set_network_master(id)
			
	new_person.set_name("Player_%s" % id)
	new_person.playerName.set_text(info.name)
	new_person.playerName.set_editable(true)
	
	new_person.kick.hide()

func _process(delta:float):
	launch_button.disabled = false
	
#we still allow launching the game in case of database desync. Player responsibility	
	if (_multiplayer_desync):
		launch_button.text = "Launch ? (Cards Desync)"
	if players_container.get_children().size()<2:
		launch_button.disabled = true
	


func find_player_by_network_id(network_id):
	for child in players_container.get_children():
		if child.my_network_id == network_id:
			return child
	return null

remote func register_player(info):
	# Get the id of the RPC sender.
	var id = cfc.get_rpc_sender_id()
	# Store the info
	players[id] = info

	# Call function to update lobby UI here
	var new_person = person.instance()
	players_container.add_child(new_person)
	new_person.set_network_master(id)
			
	new_person.set_name("Player_%s" % id)
	new_person.playerName.set_text(info.name)
	new_person.playerName.set_editable(false)
	

	
	if cfc.is_game_master():
		launch_button.disabled = true
		new_person.kick.show()
		cfc._rpc_id(self, id, "multiplayer_database_comparison")

		launch_button.disabled = false	
		if CFConst.DEBUG_AUTO_START_MULTIPLAYER or info.tests:
			if info.tests:
				gameData.run_auto_tests = info.tests	
			on_button_pressed(launch_button.name)
	else:
		new_person.kick.hide()

mastersync func master_multiplayer_database_comparison(other_status):
	var client_id = cfc.get_rpc_sender_id()
	var my_status = compute_database_hash()
	if !(WCUtils.json_equal(my_status, other_status)):
			_multiplayer_desync = other_status
			var bad_player = find_player_by_network_id(client_id)
			bad_player.set_desync_msg(to_json(_multiplayer_desync))
			return false
	return true

func compute_database_hash() -> Dictionary:
	var card_definitions_hash = WCUtils.ordered_hash(cfc.card_definitions)
	var card_scripts_hash = WCUtils.ordered_hash(cfc.set_scripts)

	var db_status = {
		"card_definitions": card_definitions_hash,
		"card_scripts": card_scripts_hash
	}
	return db_status
	
remotesync func multiplayer_database_comparison():
	var db_status = compute_database_hash()
	cfc._rpc_id(self,1, "master_multiplayer_database_comparison", db_status)



func set_my_info(info):
	my_info = info
	
	#update info locally
	var id = cfc.get_network_unique_id()
	players[id] = info
	
	#update my info on other clients/server
	cfc._rpc(self,"update_player", my_info)

# Update player names remotely	
remote func update_player(info):
	# Get the id of the RPC sender.
	var id = cfc.get_rpc_sender_id()
	players[id] = info
	if players_container.has_node("Player_%s" % str(id)):
		var the_player = players_container.get_node("Player_%s" % str(id))
		the_player.playerName.set_text(info.name)	
	
#### Network callbacks from SceneTree ####

# Callback from SceneTree.
func _player_connected(id):
	_set_status ("connected: " + str(id), false)
	cfc._rpc_id(self, id, "register_player", my_info)

func _launch_server_game():
	# online room: hidden from the public list, closed to new players
	networkManager.set_room_joinable(false)
	# Finalize Network players data
	var i = 1
	for player in players:
		cfc._rpc(self,"set_network_player_index", player, i)
		i+=1
	_launch_game()
	cfc._rpc(self,"launch_client_game")

remotesync func set_network_player_index(player, i):
	players[player].id = i
	
remote func launch_client_game():
	_launch_game() #TODO might not work?	
	
func _launch_game():	
	# server pressed on launch, start the game!
	gameData.init_network_players(players)
	var game = load(CFConst.PATH_CUSTOM + "lobby/TeamSelection.tscn").instance()
	# Connect deferred so we can safely erase it from the callback.
#	game.connect("game_finished", self, "_end_game", [], CONNECT_DEFERRED)

	get_tree().get_root().add_child(game)
	hide()


func _player_disconnected(_id):
	if cfc.is_game_master():
		#TODO remove player from list
		pass
	else:
		_end_game("Server disconnected")


# Callback from SceneTree, only for clients (not server).
func _connected_ok():
	pass # This function is not needed for this project.


# Callback from SceneTree, only for clients (not server).
func _connected_fail():
	_set_status("Couldn't connect", false)
	networkManager.close()
	#Go back to lobby
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MultiplayerLobby.tscn')
	


func _server_disconnected():
	_end_game("Server disconnected")

##### Game creation functions ######

func _end_game(with_error = ""):
	if has_node("/root/Main"):
		# Erase immediately, otherwise network might show
		# errors (this is why we connected deferred above).
		get_node("/root/Main").free()
		show()

	networkManager.close()
	_set_status(with_error, false)
	#Go back to lobby
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'lobby/MultiplayerLobby.tscn')


func _set_status(text, isok):
	#TODO debug
	if not status_msg:
		return
	if isok:
		status_msg.set_text(text)
	else:
		status_msg.set_text(text)
	add_log(text)

func _join_as_server(port = 0):
	if network_is_ready:
		return
	if !port:
		port = CFConst.MULTIPLAYER_PORT	
	add_log("creating server on port:" + str(port))	
	my_port = port
	for attempt in 10:
		var err = gameData.init_as_server(my_port)
		if err == OK:
			network_is_ready = true
			break;
		else:
			# Is another server running?
			add_log("Can't start host, address might be in use? ERRNO:" +str(err))	
			_set_status("Can't host, address in use?",false)
			yield(get_tree().create_timer(1.0), 'timeout')
	
	if !network_is_ready:
		add_log("failed starting host after 10 attempts")
	
	my_info.name = "Player 1"	
	my_info.tests = gameData.run_auto_tests
	_set_status("Waiting for players...", true)
	register_self(my_info)		


func _join_as_client(host_ip, host_port = 0, own_port = 0):
	if network_is_ready:
		return
		
	add_log("joining as client:" + str(host_ip) +":" + str(host_port if host_port else CFConst.MULTIPLAYER_PORT) + " (my port: )" + str(own_port))	
	var state = networkManager.join_enet(host_ip, host_port, own_port)
	if state is GDScriptFunctionState:
		yield(state, "completed")
	if !networkManager.uses_enet():
		add_log("failed conection")
		return
		
	my_info.name = "Player " + str(cfc.get_network_unique_id())
	my_info.tests = gameData.run_auto_tests
	_set_status("Connecting...", true)
	network_is_ready = true
	register_self(my_info)		
