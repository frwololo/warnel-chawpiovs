extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $MainMenu/VBox/Center/VButtons
onready var main_menu := $MainMenu
onready var v_folder_label := $MainMenu/VBox/Margin2/Label

var ready = false
var clients_ready = {}
var game
var loader = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")

	#do loading related stuff

func _process(delta):
	if (not ready):
		if (not loader):
			loader = ResourceLoader.load_interactive(CFConst.PATH_CUSTOM + "Main.tscn")
		if loader.poll() == ERR_FILE_EOF:
			game = loader.get_resource()
			#I'm ready, tell myself then tell the server
			clients_ready[get_tree().get_network_unique_id()] = true;
			ready = true;
			rpc_id(1, "client_ready")
	
remotesync func client_ready():
	var client_id = get_tree().get_rpc_sender_id()
	clients_ready[client_id] = true;
	if (get_tree().is_network_server()):
		if (clients_ready.size() == gameData.network_players.size()):
			_launch_server_game()


func _launch_server_game():
	# Finalize Network players data
	#var i = 0
	#for player in players:
	#	rpc("set_network_player_index", player, i)
	#	i+=1
	rpc("launch_client_game")	
	_launch_game()
	
remote func launch_client_game():
	_launch_game() 	
	
func _launch_game():	
	# server said start the game!
	get_tree().change_scene_to(game)
	
func _on_Menu_resized() -> void:
	for tab in [main_menu]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x
