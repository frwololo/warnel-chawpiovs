# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Node

#
#constants
#
var HERO_COUNT = 4 #TODO move to config

#
#sub scenes
#
#Selector drag and drop on the left panel
var heroSelect = preload("res://src/wc/lobby/HeroSelect.tscn")
#Deck Selection element once in the team (right panel)
var heroDeckSelect = preload("res://src/wc/lobby/HeroDeckSelect.tscn")

var scenarioSelect = preload("res://src/wc/lobby/ScenarioSelect.tscn")

var modularSelect = preload("res://src/wc/lobby/ModularSelect.tscn")


#
#data
#
var team := {} #container for the team information, indexed by slot id (0,1,2,3)
var _scenario:= ""
var selected_modulars:= []
var _rotation = 0
var _preview_rotation = 0
var launch_data

var ERROR_COLOR := 	Color(1,0.11,0.1)
var OK_COLOR := 	Color(0.1,11,0.1)
#
# download info
#
var http_request: HTTPRequest = null

#integers per client
var _pending_ack:= {}
#
# shortcuts
#
onready var main_menu := $MainMenu
onready var expert_mode: CheckBox = get_node("%ExpertMode")
onready var all_heroes_container = get_node("%Heroes")
onready var heroes_container = get_node("%TeamContainer")
onready var launch_button = get_node("%LaunchButton")
onready var all_scenarios_container = get_node("%Scenarios")
onready var v_folder_label = get_node("%FolderLabel")
onready var modular_selection = $MainMenu/ModularSelection

# Called when the node enters the scene tree for the first time.

var focus_chosen = false
var large_picture_id = ""
var modular_one_or_more = 1

func grab_scenario_focus():
	for child in all_scenarios_container.get_children():
		child.grab_focus()	
		return	

func grab_default_focus():
	if modular_selection.visible:
		get_node("%ModularOK").grab_focus()
		return
	
	for child in all_heroes_container.get_children():
		child.grab_focus()	
		return
	
	#last hope
	get_node("%CancelButton").grab_focus()

func critical_error():
	var label =  get_node("%AdventureModeWarning")
	label.visible = true
	label.add_color_override("font_color", Color8(255, 50,50))
	label.text = "It seems there was a critical issue loading the database. Please check your network connection and your local files (settings, Sets/*, etc...)"

func _ready():
	# If nothing's setup, start server for Single player mode
	if (not get_tree().get_network_peer()):
		gameData.init_1player()
	
	var adventure_mode = cfc.is_adventure_mode()
	get_node("%AdventureModeWarning").visible = adventure_mode
	if adventure_mode:
		var suffix = " (all unlocked!)"
		var heroes_left_to_unlock = cfc.get_locked_heroes().size()
		if heroes_left_to_unlock:
			suffix = " (" +str(heroes_left_to_unlock) + " left to unlock)"
		get_node("%HeroesTitle").text += suffix

		suffix = " (all unlocked!)"
		var scenarios_left_to_unlock = cfc.get_locked_scenarios().size()
		if scenarios_left_to_unlock:
			suffix = " (" +str(scenarios_left_to_unlock) + " left to unlock)"
		get_node("%ScenarioHeader").text +=  suffix
	
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")

	get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")	
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	_create_team_container()
	_create_hero_container()
	_load_scenarios()
	get_node("%ModularButton").disabled = true
	
	launch_button.connect('pressed', self, 'on_button_pressed', [launch_button.name])

	if !cfc.is_game_master():
		get_node("%ExpertMode").disabled = true

	http_request = HTTPRequest.new()
	add_child(http_request)	
	http_request.connect("request_completed", self, "_deck_download_completed")

	cfc.buttons_grab_focus_on_mouse_entered(self)	
	disable_launch_button()

#Quickstart for tests
#TODO remove
	if (cfc.is_game_master() and CFConst.DEBUG_AUTO_START_MULTIPLAYER):
		if (gameData.is_multiplayer_game):
			yield(get_tree().create_timer(0.5), "timeout")	
			owner_changed(1, 1)
			cfc._rpc(self, "assign_hero", "01001a", 0)
			cfc._rpc(self, "assign_hero", "01010a", 1)
			yield(get_tree().create_timer(0.5), "timeout")
			scenario_select("01097")
			yield(get_tree().create_timer(0.5), "timeout")	
			if CFConst.DEBUG_AUTO_START_MULTIPLAYER:			
				_launch_server_game()
		pass	

	resize()

func enable_launch_button():
	if !launch_button.disabled:
		return
			
	launch_button.disabled = false
	launch_button.connect("mouse_entered", launch_button, "grab_focus")

func disable_launch_button():
	if launch_button.disabled:
		return
		
	launch_button.disabled = true
	launch_button.disconnect("mouse_entered", launch_button, "grab_focus")	

#TODO: need to do this hack because gamepadHandler "gui_focus_changed" only works automatically when the
#board has been set up
#this is because a new viewport is created for the board
func gui_focus_changed(control):
	gamepadHandler.gui_focus_changed(control)

func _process(delta:float):
	var large_picture = get_node("%LargePicture")
	if gamepadHandler.is_mouse_input():		
		large_picture.rect_position = get_tree().current_scene.get_global_mouse_position()
	else:
		var focused = get_focus_owner()
		if focused:
			large_picture.rect_position = focused.get_global_position() + focused.rect_size/2
	large_picture.rect_size = Vector2(300, 420)
	large_picture.rect_scale = cfc.screen_scale
	large_picture.rect_rotation = _preview_rotation

func resize():
	var stretch_mode = cfc.get_screen_stretch_mode()

	var screen_size = get_viewport().size
	var scenario_picture:TextureRect = get_node("%ScenarioTexture") 
	if stretch_mode == SceneTree.STRETCH_MODE_VIEWPORT and screen_size.x > 1800:
		get_node("%LeftRight").add_constant_override("separation", 100)
		get_node("%TeamScenarioPanel").add_constant_override("separation", 20)
		get_node("%ScenarioOverContainer").add_constant_override("separation", 20)		
		scenario_picture.rect_min_size = Vector2(300, 300)
		scenario_picture.rect_size = scenario_picture.rect_min_size
		get_node("%VBoxContainer").add_constant_override("separation", 20)
	else:		
		get_node("%LeftRight").add_constant_override("separation", 10)
		get_node("%TeamScenarioPanel").add_constant_override("separation", 5)
		get_node("%ScenarioOverContainer").add_constant_override("separation", 2)
		get_node("%VBoxContainer").add_constant_override("separation", 5)
		get_node("%MarginContainer").add_constant_override("margin_top", 5)
		get_node("%MarginContainer").add_constant_override("margin_bottom", 5)
		scenario_picture.rect_min_size = Vector2(200, 200)
		scenario_picture.rect_size = scenario_picture.rect_min_size
		$MainMenu.rect_position.y = 5
		

	scenario_picture.rect_pivot_offset = scenario_picture.rect_size / 2
	scenario_picture.rect_rotation = _rotation
	
func _load_scenarios():
	
	var no_scenario_loaded = true
	#sorting by alphabetical name of villain
	var names_to_id = {}
	for scenario_id in cfc.get_unlocked_scenarios():
		var villain = ScenarioDeckData.get_first_villain_from_scheme(scenario_id)
		if villain:
			var	villain_name = villain["shortname"]
			names_to_id[villain_name] = scenario_id			

	var ordered_names = names_to_id.keys()
	ordered_names.sort()

	var grid_columns = int(ceil(sqrt(2 * ordered_names.size())))
	grid_columns = max(grid_columns, 3)
	all_scenarios_container.columns = grid_columns

	for villain_name in ordered_names:
		var scenario_id = names_to_id[villain_name]
		var new_scenario = scenarioSelect.instance()
		var load_success = new_scenario.load_scenario(scenario_id)
		if !load_success:
			continue
		new_scenario.name = "scenario_" + scenario_id
		all_scenarios_container.add_child(new_scenario)
		no_scenario_loaded = false
	
	if no_scenario_loaded:
		critical_error()

func _create_hero_container():
	
	var no_hero_loaded = true
	#show in alphabetical order
	var names_to_id = {}
	for hero_id in cfc.get_unlocked_heroes():
		#skip heroes that are not implemented
		var hero_card_data = cfc.get_card_by_id(hero_id)
		var alter_ego_id =  hero_card_data.get("back_card_code", "undef")
		if !cfc.unmodified_set_scripts.get(hero_id,{}) and\
			 !cfc.unmodified_set_scripts.get(alter_ego_id,{}):
			continue
		var hero_name = cfc.get_card_name_by_id(hero_id)
		names_to_id[hero_name] = hero_id
		
	var ordered_names = names_to_id.keys()
	ordered_names.sort()

	var grid_columns = int(ceil(sqrt(ordered_names.size())))
	grid_columns = max(grid_columns, 3)
	all_heroes_container.columns = grid_columns
	
	
	for hero_name in ordered_names:
		var hero_id = names_to_id[hero_name]

		var new_hero = heroSelect.instance()
		new_hero.load_hero(hero_id)
		all_heroes_container.add_child(new_hero)
		no_hero_loaded = false
		if !focus_chosen:
			new_hero.grab_focus()
			focus_chosen = true	
	
	if no_hero_loaded:
		critical_error()

#
# modular encounters functions
#
var _mainmenu_focus_nodes = {}
func display_modular_selection():
	var title = get_node("%ModularSelectionTitle")
	var default_modulars = ScenarioDeckData.get_recommended_modular_encounters(_scenario)		
	var nb_modulars = default_modulars.size()
	var plural = "" if nb_modulars <= 1 else "s"
	var villain = ScenarioDeckData.get_first_villain_from_scheme(_scenario)
	var villain_name = ""
	if villain:
		villain_name = villain["shortname"]
	
	title.text = villain_name + " -  select " + str(nb_modulars) + " modular set" + plural 
	
	var grid:GridContainer = get_node("%ModularGrid")
	for child in grid.get_children():
		var modular_id = child.get_modular_id()
		if modular_id in selected_modulars:
			child.init_status(true)
		else:
			child.init_status(false)
	modular_selection.visible = true
	_mainmenu_focus_nodes = cfc.disable_focus_mode($MainMenu/Outercontainer) 
	grab_default_focus()


var _modulars_init_done = false
func _load_modulars(scenario_id):
	if _modulars_init_done:
		return
	var grid:GridContainer = get_node("%ModularGrid")
	var modular_sets = cfc.modular_encounters.keys()
	modular_sets.sort()
	var sets_per_column = 15
	var columns = modular_sets.size()/sets_per_column
	if modular_sets.size() % sets_per_column:
		columns+=1
	grid.columns = columns
	for modular_set in modular_sets:			
		var new_modular = modularSelect.instance()		
		grid.add_child(new_modular)	
		new_modular.load_modular(modular_set)
	
	var button = get_node("%ModularButton")
	if cfc.is_game_master():
		button.disabled = false	
	_modulars_init_done = true


func _update_modular_button():
	var button:Button = get_node("%ModularButton")
	button.text =  ""
	var separator = ""
	for modular in get_selected_modulars():
		button.text+= separator + modular
		separator = ","		
	button.set_tooltip(button.text)

func _select_default_modular(scenario_id):
	var default_modulars = ScenarioDeckData.get_recommended_modular_encounters(scenario_id)
	if !default_modulars:
		return
	reset_selected_modulars()
	for modular in default_modulars:
		modular_select(modular)
	_update_modular_button()	

func reset_selected_modulars():
	selected_modulars = []

func _update_modular_data():
	var default_modulars = ScenarioDeckData.get_recommended_modular_encounters(_scenario)		
	var nb_modulars = default_modulars.size()

	var disable_all = false
	var disable_ok = false
	
	if selected_modulars.size() >= nb_modulars:
		disable_all = true

	if selected_modulars.size() < nb_modulars:
		disable_ok = true

	
	var grid:GridContainer = get_node("%ModularGrid")
	for child in grid.get_children():
		var modular_id = child.get_modular_id()
		if modular_id in selected_modulars:
			child.set_disabled(false)
		else:
			child.set_disabled(disable_all)

	get_node("%ModularOK").disabled = disable_ok
	
	_update_modular_button()


func get_selected_modulars():
	return selected_modulars
	
func modular_select(modular_id):
	if !modular_id in selected_modulars:
		selected_modulars.append(modular_id)
	_update_modular_data()
	
func modular_deselect(modular_id):
	selected_modulars.erase(modular_id)
	_update_modular_data()		

func _on_ModularButton_pressed():
	display_modular_selection()
	pass # Replace with function body.


func _on_ModularOK_pressed():	
	cfc.enable_focus_mode(_mainmenu_focus_nodes)
	modular_selection.visible = false
	pass # Replace with function body.
		
func _create_team_container():	
	for i in HERO_COUNT: 
		var new_team_member = heroDeckSelect.instance()
		new_team_member.set_idx(i)
		heroes_container.add_child(new_team_member)
		team[i] = HeroDeckData.new()



remotesync func client_scenario_select(scenario_id):
	_scenario = scenario_id

	_load_modulars(scenario_id)
	_select_default_modular(scenario_id)

	
	var scenario_scene = all_scenarios_container.get_node("scenario_" + scenario_id)
	if (scenario_scene):
		var imgtex = scenario_scene.get_texture()
		var scenario_picture: TextureRect = get_node("%ScenarioTexture")
		if (imgtex):
			scenario_picture.texture = imgtex
#			scenario_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
#			scenario_picture.rect_size = Vector2(150, 150)
#			_rotation = scenario_scene._rotation
#			scenario_picture.rect_rotation = _rotation
			resize()
		var scenario_title = get_node("%ScenarioTitle")
		scenario_title.text = scenario_scene.get_text()
	

		
	ack()	
	
func scenario_select(scenario_id):
	if (not cfc.is_game_master()):
		return
	add_pending_acks()			
	cfc._rpc(self, "client_scenario_select", scenario_id)

puppet func expert_mode_toggle (button_pressed):
	ack()
	get_node("%ExpertMode").set_pressed_no_signal(button_pressed)

func _on_ExpertMode_toggled(button_pressed):
	if (not cfc.is_game_master()):
		return
	add_pending_acks()	
	cfc._rpc(self,"expert_mode_toggle", button_pressed)			
	pass # Replace with function body.	
	pass # Replace with function body.


func request_hero_slot(hero_id):
	cfc._rpc_id(self, 1, "get_next_hero_slot",hero_id)

#Attempt to get a slot for a given hero for a given player
#If succesful, tell everyone to update their info
mastersync func get_next_hero_slot(hero_id) -> int:
	if (not cfc.is_game_master()):
		return -1
	var client_id = cfc.get_rpc_sender_id() 
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.get_hero_id() == hero_id):
			return -1

	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.owner.network_id == client_id and data.get_hero_id() == ""):
			add_pending_acks()
			cfc._rpc(self, "assign_hero", hero_id, i)
			return i
	return -1			

remotesync func assign_hero(hero_id, slot):
	#data update
	var hero_deck_data: HeroDeckData = team[slot]
	var previous_hero_id = hero_deck_data.get_hero_id()
	hero_deck_data.set_hero_id(hero_id) #todo could use a signal here and the GUI would be listening
	
	#gui update
	var hero_deck_select = heroes_container.get_child(slot)
	hero_deck_select.load_hero(hero_id)
	if hero_id:
		for child in all_heroes_container.get_children():
			if child.hero_id == hero_id:
				child.disable()
	if previous_hero_id and previous_hero_id!= hero_id:
		for child in all_heroes_container.get_children():
			if child.hero_id == previous_hero_id:
				child.enable()	
	ack()

func verify_launch_button():
	if check_ready_to_launch():
		enable_launch_button()
		launch_button.grab_focus()
	else:
		disable_launch_button()
		
		if all_players_have_a_hero():
			grab_scenario_focus()
		
		if !get_focus_owner():
			grab_default_focus()

#shortcut for cleanliness because get_focus_owner needs a control node...
func get_focus_owner():
	var focus_owner = launch_button.get_focus_owner()
	if !focus_owner:
		grab_default_focus()
		focus_owner = launch_button.get_focus_owner()
	return focus_owner

func check_ready_to_launch() -> bool:
	if !cfc.is_game_master():
		return false
	
	#can't launch without scenario	
	if (!_scenario):
		return false
	
	#some clients are still processing stuff
	if are_acks_pending():
		return false
	
	if !all_players_have_a_hero():
		return false
	
	return true

func all_players_have_a_hero() -> bool:
	#can't launch if all players don't have at least one hero
	var players_with_heroes:= {}

	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.get_hero_id()): 
			if (data.owner.network_id):
				players_with_heroes[data.owner.network_id] = true
			if (!data.deck_id) or heroes_container.get_child(i).deckSelect.get_selected() == -1:
				return false
	if players_with_heroes.size() != gameData.network_players.size():
		return false
	
	return true
	
	
func request_release_hero_slot(hero_id):
	cfc._rpc_id(self,1, "release_hero_slot",hero_id)

#Attempt to release a slot for a given hero for a given player
#If succesful, tell everyone to update their info
remotesync func release_hero_slot(hero_id) -> int:
	if (not cfc.is_game_master()):
		return -1
	var client_id = cfc.get_rpc_sender_id()

	var result = -1
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.owner.network_id == client_id and data.get_hero_id() == hero_id):
			cfc._rpc(self,"assign_hero", "", i)
#			remaining_team_members -=1
#			if (not remaining_team_members):
#				launch_button.hide()
			result = i
			break
	verify_launch_button()
	return result			

func owner_changed(id, index):
	#item_selected passes the id which is 0 indexed, but players are 1 indexed
	var player : PlayerData = gameData.get_player_by_index(id+1)
	team[index].owner = player
	cfc._rpc(self,"remote_owner_changed",id,index)

remote func remote_owner_changed (id, index):
	#update data
	#item_selected passes the id which is 0 indexed, but players are 1 indexed
	var player : PlayerData = gameData.get_player_by_index(id+1)
	team[index].owner = player
	#update GUI
	var _heroDeckSelect = heroes_container.get_child(index)
	_heroDeckSelect.set_owner(id+1)

func deck_changed(_deck_id, hero_index):
	team[hero_index].deck_id = _deck_id
	cfc._rpc(self,"remote_deck_changed",_deck_id, hero_index)	

remote func remote_deck_changed (_deck_id, hero_index):
	var client_id =  cfc.get_rpc_sender_id() 	
	#update data
	team[hero_index].deck_id = _deck_id
	#update GUI
	var _heroDeckSelect = heroes_container.get_child(hero_index)
	_heroDeckSelect.set_deck(_deck_id, client_id)

func request_deck_data(caller_id, _deck_id):
	cfc._rpc_id(self, caller_id, "upload_deck_data", _deck_id)

remotesync func upload_deck_data(_deck_id):
	var client_id =  cfc.get_rpc_sender_id() 
	var deck_data = cfc.deck_definitions[_deck_id]
	cfc._rpc_id(self,client_id, "receive_deck_data", _deck_id, deck_data)

remotesync func receive_deck_data(_deck_id, deck_data):
	var _client_id =  cfc.get_rpc_sender_id() 
	var existing_data = cfc.deck_definitions.get(_deck_id, {})
	if existing_data:
		var checksum1= WCUtils.ordered_hash(existing_data)
		var checksum2 = WCUtils.ordered_hash(deck_data)
		if checksum1 != checksum2:
			#TODO error handling
			var _error = 1
		#return
	process_deck_download(deck_data)

func deck_download_error(msg):
	var label = get_node("%DeckDownloadError")
	label.add_color_override("font_color", ERROR_COLOR)	
	label.text = msg
	push_error(msg)
	
func process_deck_download(deck_data):
	cfc.load_one_deck(deck_data)
	cfc.save_one_deck_to_file(deck_data)
	refresh_deck_containers()

	if cfc._last_deck_error_msg:
		deck_download_error(cfc._last_deck_error_msg)
	else:
		var label = get_node("%DeckDownloadError")
		label.add_color_override("font_color", OK_COLOR)
		label.text = "Deck Downloaded:" + str(deck_data["id"]) 
	

func refresh_deck_containers():
	for child in heroes_container.get_children():
		child.refresh_decks()

var _ready_to_launch:= {}
mastersync func ready_to_launch():
	var client_id =  cfc.get_rpc_sender_id()
	_ready_to_launch[client_id] = true
	if _ready_to_launch.size() == gameData.network_players.size():
		_ready_to_launch = {}
		cfc._rpc(self,"launch_client_game")

func save_last_used_deck(hero_id, deck_id):
	if !cfc.game_settings.has("last_deck"):
		cfc.game_settings["last_deck"] = {}
		
	var last_deck_used = cfc.game_settings.get("last_deck", {})
	last_deck_used[hero_id] = deck_id
	cfc.save_settings()
	

func _launch_server_game():
	disable_launch_button()
	var serialized_team = {}
	for key in team.keys():
		var hero_data = team[key]
		serialized_team[key] = hero_data.savestate_to_json()
		save_last_used_deck(hero_data.get_hero_id(), hero_data.deck_id)
		
	launch_data = {
		"team": serialized_team,
		"scheme_id" : _scenario, 
		"modular_encounters":get_selected_modulars(),
		"expert_mode": is_expert_mode()
	}
	cfc._rpc(self, "get_launch_data_from_server", launch_data)	
	#_launch_game()
	
remotesync func get_launch_data_from_server(_scenario_data):
	launch_data = _scenario_data
	cfc._rpc_id(self, 1, "ready_to_launch")
	
remotesync func launch_client_game():
	_launch_game() 	

	
func is_expert_mode():
	return expert_mode.pressed
	
func _launch_game():	
	# server pressed on launch, start the game!
	if !launch_data:
		var _error = 1
		return
		#panic!
	var serialized_team = launch_data["team"]
	#team = {} 
	for key in serialized_team.keys():
		team[key].loadstate_from_json(serialized_team[key])
	gameData.set_team_data(team)
	
	gameData.set_scenario_data(launch_data)
	set_process(false) #prevents calling process on variables being deleted during scene change
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'menus/GetReady.tscn')

func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"LaunchButton":
			_launch_server_game()		
		#"Cancel":
			#TODO disconnect?
		#	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

func _on_Menu_resized() -> void:
	resize()


#
# Network Sanity functions
#

func add_pending_acks(except_me:=true):
	var my_id = cfc.get_network_unique_id()
	for client_id in gameData.network_players:
		if client_id == my_id and except_me:
			continue 
		add_pending_ack(client_id)	

func add_pending_ack(client_id):
	if (!_pending_ack.has(client_id)):
		_pending_ack[client_id] = 0	
	_pending_ack[client_id] +=1

func remove_pending_ack(client_id):
	if (!_pending_ack.has(client_id)):
		_pending_ack[client_id] = 0	
			
	if (_pending_ack[client_id]) > 0:
		_pending_ack[client_id] -=1
		return true
	else:
		var _error = 1
		return false

func ack():
	cfc._rpc_id(self, 1, "master_ack")

mastersync func master_ack():
	var client_id = cfc.get_rpc_sender_id()
	remove_pending_ack(client_id)
	verify_launch_button()

func are_acks_pending():
	for client_id in gameData.network_players:
		if (!_pending_ack.has(client_id)):
			_pending_ack[client_id] = 0			
		if _pending_ack[client_id]:
			return true
	return false

#
# Deck Download functions
#

func _deck_download_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Set couldn't be downloaded.")
	else:
		var content = body.get_string_from_utf8()

		var json_result:JSONParseResult = JSON.parse(content)
		if (json_result.error != OK):
			push_error("Set couldn't be downloaded.")
		else:
			process_deck_download(json_result.result)	 		
	
	var button = get_node("%DownloadDeckButton")
	button.disabled = false

func start_deck_download(deck_id_str):
	var button = get_node("%DownloadDeckButton")
	button.disabled = true
	var base_url = cfc.game_settings.get("decks_base_url","")
	if !base_url:
		deck_download_error("missing download url in settings file")
		button.disabled = false
		return
	var url = base_url + deck_id_str + ".json"
	var error = http_request.request(url)
	if error != OK:
		deck_download_error("An error occurred in the HTTP request.")
		button.disabled = false
		return
	

func _on_DownloadDeck_pressed():
	var to_download:LineEdit = get_node("%DownloadDeckNumber")
	if !to_download.text.is_valid_integer():
		return
	start_deck_download(to_download.text)
	pass # Replace with function body.


func _on_OpenFolderButton_pressed():
	OS.shell_open(ProjectSettings.globalize_path("user://"))
	pass # Replace with function body.

func show_preview(card_id):
	var large_picture = get_node("%LargePicture")

	var card_data = cfc.get_card_by_id(card_id)
	var horizontal = card_data["_horizontal"]
	var filename = cfc.get_img_filename(card_id)	
	var new_img = WCUtils.load_img(filename)
	if not new_img:
		return	
	var imgtex = ImageTexture.new()
	imgtex.create_from_image(new_img)	
	large_picture.texture = imgtex
	large_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# In case the generic art has been modulated, we switch it back to normal colour
	large_picture.self_modulate = Color(1,1,1)
	large_picture.visible = true
	if horizontal:
		_preview_rotation = 90
	else:
		_preview_rotation = 0
	large_picture.rect_size = Vector2(300, 420)
	large_picture_id = card_id
	
func hide_preview(card_id):
	if large_picture_id!= card_id:
		return
	var large_picture = get_node("%LargePicture")		
	large_picture.visible = false


func _on_CancelButton_pressed():
	self.queue_free()
	gameData.disconnect_from_network()
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')


