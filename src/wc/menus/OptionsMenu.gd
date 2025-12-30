class_name OptionsMenu
extends Node2D

onready var v_box_container = $PanelContainer/MarginContainer/VBoxContainer
onready var file_dialog = get_node("%FileDialog")
onready var h_box_container = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer

# warning-ignore:unused_signal
signal exit_options_menu

func _ready():
	for option_button in v_box_container.get_children():
		if option_button.has_signal('pressed'):			
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
			option_button.connect('mouse_entered', option_button, 'grab_focus')
			
	for option_button in h_box_container.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
			option_button.connect('mouse_entered', option_button, 'grab_focus')
		if option_button.name in ["ForceResyncButton"]:
			if !cfc.is_game_master():
				option_button.hide()	

	
	file_dialog.connect("file_selected", self, "_on_file_selected")	
	resize()
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
		"DebugButton":
			var debug_button:CheckButton = get_node("%DebugButton")
			var value = debug_button.pressed
			gameData.phaseContainer.toggle_display_debug(value)
			close_me()			
		"SaveButton":
			save_game()	
		"ForceResyncButton":
			var json = gameData.save_gamedata()
			gameData.load_gamedata(json)
			close_me()				
		"LoadButton":
			load_game()	
		"MainMenuButton":
			back_to_main_menu()
		"RestartButton":
			restart_game()	
		"Controls":
			show_controls()

func show_controls():
	var overlay = get_node("%Overlay")
	var overlay_texture = overlay.get_children()[0]
	if !overlay_texture.texture:
		overlay_texture.texture = load("res://assets/other/controls_switch.png")
	if !overlay.visible:			
		overlay.visible = true
		hide_menu()
		
func hide_controls():
	var overlay = get_node("%Overlay")	
	if overlay.visible:			
		overlay.visible = false
		show_menu()

func hide_menu():
	$PanelContainer.hide()
	
func show_menu():
	$PanelContainer.show()
	
	#doing a pause here to not react to a previous button press
	yield(get_tree().create_timer(0.1), "timeout")
	cfc.default_button_focus($PanelContainer)
	
func _input(event):
	if event.is_pressed() and !event.is_echo():
		hide_controls()
		
func close_me():
	set_process(false)
	cfc.set_game_paused(false)
	visible = false
	#doing a pause here to not react to a previous button press
	yield(get_tree().create_timer(0.1), "timeout")	
	get_parent().enable_focus_mode()

func show_me():
	set_process(true)
	if gamepadHandler.is_controller_input():
		get_node("%Controls").visible = true
	else:
		get_node("%Controls").visible = false
	visible = true
	cfc.set_game_paused(true)
	get_parent().disable_focus_mode()
	cfc.default_button_focus(v_box_container)	

func restart_game():
	var path = "user://Saves/_restart.json"
	var json = WCUtils.read_json_file(path)
	if (json):
		gameData.load_gamedata(json)
	close_me()		

func back_to_main_menu():
	cfc.quit_game()
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

func save_game():
	hide_menu()
	file_dialog.set_current_path("user://Saves/")
	file_dialog.mode = FileDialog.MODE_SAVE_FILE
	file_dialog.popup_centered()
	
func load_game():
	hide_menu()	
	file_dialog.set_current_path("user://Saves/")
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.popup_centered()

func _on_file_selected(path):
	show_menu()	
	print("Selected file: ", path)
	if (FileDialog.MODE_OPEN_FILE == file_dialog.mode):
		var json = WCUtils.read_json_file(path)
		gameData.load_gamedata(json)
		close_me()	
	else:
		gameData.save_gamedata_to_file(path)


func _on_FileDialog_popup_hide():
	show_menu()
	pass # Replace with function body.


func resize():
	self.scale = cfc.screen_scale
