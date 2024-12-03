extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $MainMenu/VBox/Center/VButtons
onready var main_menu := $MainMenu
onready var v_folder_label := $MainMenu/VBox/Margin2/Label
onready var status_msg := $MainMenu/VBox/WaitingMsg
onready var players_container := $MainMenu/VBox/Players
onready var launch_button := $MainMenu/VBox/Center/VButtons/Launch

var peer = null
# dictionary indexed by network_id for each player.
var players = {}
var my_info = {name = "Name Unset"}

var person = preload("res://src/wc/lobby/Player.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")
	
# Network setup
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected_ok")
	get_tree().connect("connection_failed", self, "_connected_fail")
	get_tree().connect("server_disconnected", self, "_server_disconnected")	
	
	var params = cfc.get_next_scene_params()
	if params.has("host_ip"):
		launch_button.hide()
		_join_as_client(params["host_ip"])
	else:
		_join_as_server()	
	
	register_self(my_info)		


func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"Launch":
			_launch_server_game()
		"Cancel":
			#TODO disconnect?
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

	
func _on_Menu_resized() -> void:
	for tab in [main_menu]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x

func register_self(info):
	var id = get_tree().get_network_unique_id()
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


remote func register_player(info):
	# Get the id of the RPC sender.
	var id = get_tree().get_rpc_sender_id()
	# Store the info
	players[id] = info

	# Call function to update lobby UI here
	var new_person = person.instance()
	players_container.add_child(new_person)
	new_person.set_network_master(id)
			
	new_person.set_name("Player_%s" % id)
	new_person.playerName.set_text(info.name)
	new_person.playerName.set_editable(false)
	

	
	if get_tree().is_network_server():
		new_person.kick.show()
	else:
		new_person.kick.hide()

func set_my_info(info):
	my_info = info
	
	#update info locally
	var id = get_tree().get_network_unique_id()
	players[id] = info
	
	#update my info on other clients/server
	rpc("update_player", my_info)

# Update player names remotely	
remote func update_player(info):
	# Get the id of the RPC sender.
	var id = get_tree().get_rpc_sender_id()
	players[id] = info
	if players_container.has_node("Player_%s" % str(id)):
		var the_player = players_container.get_node("Player_%s" % str(id))
		the_player.playerName.set_text(info.name)	
	
#### Network callbacks from SceneTree ####

# Callback from SceneTree.
func _player_connected(id):
	_set_status ("connected: " + str(id), false)
	rpc_id(id, "register_player", my_info)

func _launch_server_game():
	# Finalize Network players data
	var i = 0
	for player in players:
		rpc("set_network_player_index", player, i)
		i+=1
	_launch_game()
	rpc("launch_client_game")

remotesync func set_network_player_index(player, i):
	players[player].id = i
	
remote func launch_client_game():
	_launch_game() #TODO might not work?	
	
func _launch_game():	
	# server pressed on launch, start the game!
	gameData.init_network_players(players)
	var game = load(CFConst.PATH_CUSTOM + "lobby/TeamSelection.tscn").instance()
	# Connect deferred so we can safely erase it from the callback.
	game.connect("game_finished", self, "_end_game", [], CONNECT_DEFERRED)

	get_tree().get_root().add_child(game)
	hide()


func _player_disconnected(_id):
	if get_tree().is_network_server():
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
	get_tree().set_network_peer(null) # Remove peer.
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

	get_tree().set_network_peer(null) # Remove peer.
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

func _join_as_server():
	var err = gameData.init_as_server()
	if err != OK:
		# Is another server running?
		_set_status("Can't host, address in use.",false)
		#Go back to lobby
		get_tree().change_scene(CFConst.PATH_CUSTOM + 'lobby/MultiplayerLobby.tscn')
		return #does this ever run?

	my_info.name = "Player 1"
	_set_status("Waiting for players...", true)



func _join_as_client(host_ip):
	var ip = host_ip
	if not ip.is_valid_ip_address():
		_set_status("IP address is invalid", false)
		#Go back to lobby
		get_tree().change_scene(CFConst.PATH_CUSTOM + 'lobby/MultiplayerLobby.tscn')		
		return

	peer = NetworkedMultiplayerENet.new()
	peer.set_compression_mode(NetworkedMultiplayerENet.COMPRESS_RANGE_CODER)
	peer.create_client(ip, CFConst.MULTIPLAYER_PORT)
	get_tree().set_network_peer(peer)
	my_info.name = "Player " + str(get_tree().get_network_unique_id())
	_set_status("Connecting...", true)

