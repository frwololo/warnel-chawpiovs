class_name OptionsMenu
extends Control

onready var v_box_container = $MarginContainer/VBoxContainer
onready var file_dialog = $FileDialog

signal exit_options_menu

func _ready():
	for option_button in v_box_container.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
	
	file_dialog.connect("file_selected", self, "_on_file_selected")		
	set_process(false)
			
func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"BackButton":
			# warning-ignore:return_value_discarded
			close_me()
		"TestsButton":
			# warning-ignore:return_value_discarded
			gameData.start_tests()
			close_me()
		"SaveButton":
			save_game()		
		"LoadButton":
			load_game()	
		"MainMenuButton":
			back_to_main_menu()
		"RestartButton":
			restart_game()	
			
			
func close_me():
	set_process(false)
	cfc.set_game_paused(false)
	visible = false

func restart_game():
	var path = "user://Saves/_restart.json"
	var json = WCUtils.read_json_file(path)
	if (json):
		gameData.load_gamedata(json)
	close_me()		

func back_to_main_menu():
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

func save_game():
	file_dialog.mode = FileDialog.MODE_SAVE_FILE
	file_dialog.popup()
	
func load_game():
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.popup()	

func _on_file_selected(path):
	print("Selected file: ", path)
	if (FileDialog.MODE_OPEN_FILE == file_dialog.mode):
		var json = WCUtils.read_json_file(path)
		gameData.load_gamedata(json)
		close_me()	
	else:
		gameData.save_gamedata_to_file(path)
