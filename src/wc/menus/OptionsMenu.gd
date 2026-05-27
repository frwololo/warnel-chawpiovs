class_name OptionsMenu
extends Node2D


onready var v_box_container = $PanelContainer/general/VBoxContainer
onready var file_dialog = get_node("%FileDialog")
onready var h_box_container = $PanelContainer/general/VBoxContainer/DebugContainer
onready var advanced_settings_container = get_node("%AdvancedSettingsContainer")
const NOTIFICATION_LEVELS := [
	"noob",
	"normal",
	"expert",
	"debug"
]

# warning-ignore:unused_signal
signal exit_options_menu

var board_mode = true

func init_button_signals(node):
	if node.has_signal('pressed'):			
		node.connect('pressed', self, 'on_button_pressed', [node.name])
		node.connect('mouse_entered', node, 'grab_focus')		

	for child in node.get_children():
		init_button_signals(child)

func _ready():	
	init_button_signals(self)
	
	file_dialog.connect("file_selected", self, "_on_file_selected")	
	resize()
	self.visible = false
	select_tab("general")
			
func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"BackButton":
			# warning-ignore:return_value_discarded
			close_me()
		"TestsButton":
			# warning-ignore:return_value_discarded
			var test_options:OptionButton = get_node("%TestOptions")
			var test_option = test_options.get_item_text(test_options.selected)
			gameData.start_tests(test_option.to_lower())
			close_me()
		"DebugButton":
			var debug_button:CheckButton = get_node("%DebugButton")
			var value = debug_button.pressed
			cfc._debug = value
			var piles = cfc.get_tree().get_nodes_in_group("piles")
			for pile in piles:
				pile.allow_facedown_popup = cfc._debug
				
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
		"GameplayBackButton":
			hide_gameplay_options()
		"GameplayOptionsButton":
			show_gameplay_options()
		"ClearCacheButton":
			clear_cache()	
		"AdvancedSettingsButton":
			show_advanced_settings()
		"AdvancedSettingsBackButton":
			hide_advanced_settings()
		"ResetSettingsButton":
			reset_settings()
		"DeleteResourcesButton":
			delete_resources()
		"DeleteImgButton":
			delete_images()			

func get_cancel_button(tab_name):
	match tab_name:
		"gameplay":
			return get_node("%GameplayBackButton")
		_:
			return get_node("%BackButton")

func select_tab(tab_name):
	for tab in $PanelContainer.get_children():
		tab.visible = false

	get_node("%" + tab_name).visible = true
	cfc.default_button_focus(get_node("%" + tab_name))
	#get_node("%" + tab_name).set_as_toplevel(true)	

func hide_gameplay_options():
	save_options()
	select_tab("general")

func show_gameplay_options():
	load_options()
	select_tab("gameplay")

func hide_advanced_settings():
	save_advanced_settings()
	select_tab("general")

func show_advanced_settings():
	load_advanced_settings()	
	select_tab("advanced")

func clear_cache():
	cfc.clear_cards_cache($PanelContainer)


func warning(title, message, action):
	var dialog:ConfirmationDialog = ConfirmationDialog.new()
	dialog.window_title = title
	dialog.set_text(message)		

	dialog.connect("confirmed", self, action)
	add_child(dialog)
	dialog.popup_centered()			

func reset_settings():
	warning ("reset settings", "Settings will be reset to default.\nYou might lose some game progress!!!", "confirm_reset_settings")
func delete_resources():
	warning ("delete resources", "This will delete all zip/pck resource files at next startup.\nYou might have to redownload them!!!", "confirm_delete_resources")
func delete_images():
	warning ("delete images", "This will delete all downloaded images, the game will re-create them at next launch", "confirm_delete_images")			

func confirm_reset_settings():
	cfc.reset_settings_to_default()
	load_advanced_settings()
		
func confirm_delete_resources():
	WCUtils.mark_all_pck_for_deletion()
	
func confirm_delete_images():
	cfc.delete_all_images()

	
func load_options():
	var notifications_level = cfc.game_settings.get("notifications_level", "normal").to_lower()
	var options_button:OptionButton = get_node("%NotificationsLevel")
	options_button.select(1) #normal
	
	for i in NOTIFICATION_LEVELS.size():
		if NOTIFICATION_LEVELS[i] == notifications_level: 
			options_button.select(i)
			break
			
	var adventure_mode = cfc.game_settings.get("adventure_mode", true)
	var adv_check:CheckBox = get_node("%AdventureMode")
	adv_check.set_pressed_no_signal(adventure_mode)		

	var music_vol_slider:HSlider = get_node("%MusicVol")
	var music_vol = cfc.game_settings["music_volume"]
	music_vol_slider.value = int (music_vol)
	
	var sfx_vol_slider:HSlider = get_node("%SfxVol")
	var sfx_vol = cfc.game_settings["sfx_volume"]
	sfx_vol_slider.value = int (sfx_vol)	

func save_options():
	var options_button:OptionButton = get_node("%NotificationsLevel")
	cfc.game_settings["notifications_level"] = NOTIFICATION_LEVELS[options_button.selected]
	gameData.theAnnouncer.init_notifications_level()
	
	var adv_check:CheckBox = get_node("%AdventureMode")
	cfc.game_settings["adventure_mode"] = adv_check.pressed

	var music_vol_slider:HSlider = get_node("%MusicVol")
	var music_vol = music_vol_slider.value
	cfc.game_settings["music_volume"] = music_vol
	
	var sfx_vol_slider:HSlider = get_node("%SfxVol")
	var sfx_vol = sfx_vol_slider.value
	cfc.game_settings["sfx_volume"] = sfx_vol	

	cfc.save_settings()

const NON_ADVANCED_OPTIONS = [
	"sfx_volume", 
	"music_volume", 
	"adventure_mode", 
	"notifications_level"]
	
func load_advanced_settings():
	for child in advanced_settings_container.get_children():
		advanced_settings_container.remove_child(child)
	
	var setting_keys = cfc.game_settings.keys() 
	setting_keys.sort()
	
	for setting_key in setting_keys:
		if setting_key in NON_ADVANCED_OPTIONS:
			continue
		var value = cfc.game_settings.get(setting_key, null)
		if value == null:
			continue		
		var element = null		
		match typeof(value):
			TYPE_STRING:
				element = LineEdit.new()
				element.rect_min_size.x = 700
				element.text = value
			TYPE_BOOL:
				element = CheckBox.new()
				element.pressed = value
			TYPE_INT, TYPE_REAL:
				element = LineEdit.new()
				element.rect_min_size.x = 50
				element.text = str(value)
		if element:
			var container = HBoxContainer.new()
			container.name = setting_key
			var label = Label.new()
			label.text = setting_key
			container.add_child(label)			
			container.add_child(element)
			advanced_settings_container.add_child(container)

func save_advanced_settings():
	for child in advanced_settings_container.get_children():
		var setting_key = child.name
		var element = child.get_children()[1]
		var old_value = cfc.game_settings.get(setting_key, null)
		if old_value == null:
			continue				
		match typeof(old_value):
			TYPE_STRING:
				cfc.game_settings[setting_key] = element.text
			TYPE_BOOL:
				cfc.game_settings[setting_key] = element.pressed
			TYPE_INT, TYPE_REAL:
				var value = element.text
				if value.is_valid_integer():
					 cfc.game_settings[setting_key] = int(value)
				else:
					cfc.game_settings[setting_key] = float(value)

	cfc.save_settings()

func show_controls():
	var overlay = get_node("%Overlay")
	var overlay_texture = overlay.get_children()[0]
	if !overlay_texture.texture:
		overlay_texture.texture = load("res://assets/other/controls_switch.png")
	if !overlay.visible:			
		overlay.visible = true
		hide_menu()
		
func hide_controls() -> bool:
	var overlay = get_node("%Overlay")	
	if overlay.visible:			
		overlay.visible = false
		show_menu()
		return true
	return false

func hide_menu():
	$PanelContainer.hide()
	
func show_menu():
	$PanelContainer.show()
	
	#doing a pause here to not react to a previous button press
	yield(get_tree().create_timer(0.1), "timeout")
	cfc.default_button_focus($PanelContainer)
	
func _input(event):
	if !self.visible:
		return
	if event.is_pressed() and !event.is_echo():
		if hide_controls():
			return

	if gamepadHandler.is_ui_cancel_pressed(event):
#		get_tree().is_input_handled()
		for tab in ["general", "gameplay"]:
			if get_node("%" + tab).visible:
				var button:Button = get_cancel_button(tab)
#				get_tree().is_input_handled()
				on_button_pressed(button.name)
				return

var _temporary_disabled_nodes = {}
var disabled_container = null
		
func close_me():
	#set_process(false)
	cfc.set_game_paused(false)
	visible = false
	#doing a pause here to not react to a previous button press
	yield(get_tree().create_timer(0.1), "timeout")
	if cfc.NMAP.has("board"):	
		cfc.NMAP.board.enable_focus_mode()
		cfc.NMAP.board.visible = true

	if _temporary_disabled_nodes:
		cfc.enable_focus_mode(_temporary_disabled_nodes)
	if disabled_container:
		cfc.default_button_focus(disabled_container)

func show_me(container_to_disable = null):

	get_node("%GameplayBackButton").icon = gamepadHandler.get_icon_for_action("ui_cancel")
	get_node("%BackButton").icon = gamepadHandler.get_icon_for_action("ui_cancel")


	if container_to_disable:
		_temporary_disabled_nodes= cfc.disable_focus_mode(container_to_disable) 
		disabled_container = container_to_disable
		
	if gamepadHandler.is_controller_input():
		get_node("%Controls").visible = true
	else:
		get_node("%Controls").visible = false

	if !cfc.NMAP.has("board"):
		board_mode = false
	
	if !board_mode:
		for button_name in ["%LoadSave", "%DebugContainer", "%RestartButton", "%MainMenuButton"]:
			get_node(button_name).visible = false
		$PanelContainer.self_modulate.a = 1	
		
	visible = true
	cfc.set_game_paused(true)
	if cfc.NMAP.has("board"):
		cfc.NMAP.board.disable_focus_mode()
		cfc.NMAP.board.visible = false 		
		
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

