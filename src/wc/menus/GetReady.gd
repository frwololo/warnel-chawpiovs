# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_folder_label := $CenterContainer/VBox/Margin2/Label

var ready = false
var clients_ready = {}
var game
var loader = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")

	resize()

func _process(delta):
	if (not ready):
		if (not loader):
			loader = ResourceLoader.load_interactive(CFConst.PATH_CUSTOM + "Main.tscn")
		if loader.poll() == ERR_FILE_EOF:
			game = loader.get_resource()
			#I'm ready, tell myself then tell the server
			clients_ready[cfc.get_network_unique_id()] = true;
			ready = true;
			cfc._rpc_id(self, 1, "client_ready")
	
remotesync func client_ready():
	var client_id = cfc.get_rpc_sender_id()
	clients_ready[client_id] = true;
	if (cfc.is_game_master()):
		if (clients_ready.size() == gameData.network_players.size()):
			_launch_server_game()


func _launch_server_game():
	cfc._rpc(self, "launch_client_game")	
	
remotesync func launch_client_game():
	_launch_game() 	
	
func _launch_game():	
	# server said start the game!
	get_tree().change_scene_to(game)
	
func resize():
	var stretch_mode = cfc.get_screen_stretch_mode()
	if stretch_mode != SceneTree.STRETCH_MODE_VIEWPORT:
		return	
			
	var target_size = get_viewport().size
	var label = get_node("%Label")
	label.rect_min_size = Vector2(target_size.x,label.rect_min_size.y) 
	label.rect_size = label.rect_min_size
	rect_min_size = target_size	

func _on_Menu_resized() -> void:
	resize()
