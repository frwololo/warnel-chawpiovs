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

#
#data
#
var team := {} #container for the team information, indexed by slot id (0,1,2,3)
var _scenario:= ""
var _rotation = 0
#
# shortcuts
#
onready var main_menu := $MainMenu
onready var modular_container: OptionButton = get_node("%EncounterSelect")
onready var all_heroes_container = get_node("%Heroes")
onready var heroes_container = get_node("%TeamContainer")
onready var ready_button = get_node("%ReadyButton")
onready var launch_button = get_node("%LaunchButton")
onready var all_scenarios_container = get_node("%Scenarios")

# Called when the node enters the scene tree for the first time.
func _ready():
	# If nothing's setup, start server for Single player mode
	if (not get_tree().get_network_peer()):
		gameData.init_1player()
	
	
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	_create_team_container()
	_create_hero_container()
	_load_scenarios()
	_load_encounters()
	
	ready_button.hide() #todo do something with this guy
	launch_button.hide()
	launch_button.connect('pressed', self, 'on_button_pressed', [launch_button.name])

	if !cfc.is_game_master():
		get_node("%EncounterSelect").disabled = true
		get_node("%ExpertMode").disabled = true

#Quickstart for tests
#TODO remove
	if (cfc.is_game_master()):
#		if (gameData.is_multiplayer_game):
#			yield(get_tree().create_timer(1), "timeout")	
#			owner_changed(2, 1)
#			rpc("assign_hero", "01001a", 0)
#			rpc("assign_hero", "01010a", 1)
#			yield(get_tree().create_timer(1), "timeout")	
#			_launch_server_game()
#		else:
#			yield(get_tree().create_timer(0.05), "timeout")	
#			#rpc("assign_hero", "01001a", 0) #peter
#			rpc("assign_hero", "01010a", 0)#carol		
#			yield(get_tree().create_timer(0.2), "timeout")	
#			_launch_server_game()	
		pass	

func _process(delta:float):
	var scenario_picture:TextureRect = get_node("%ScenarioTexture") 
	scenario_picture.rect_pivot_offset = scenario_picture.rect_size / 2
	scenario_picture.rect_rotation = _rotation
	scenario_picture.rect_size = Vector2(150, 150)
	
func _load_scenarios():
	for scenario_id in cfc.scenarios:

		var new_scenario = scenarioSelect.instance()
		new_scenario.load_scenario(scenario_id)
		new_scenario.name = "scenario_" + scenario_id
		all_scenarios_container.add_child(new_scenario)

func _create_hero_container():
	for hero_id in cfc.idx_hero_to_deck_ids:
		var new_hero = heroSelect.instance()
		new_hero.load_hero(hero_id)
		all_heroes_container.add_child(new_hero)	
	

func _load_encounters():
	var modular_sets = cfc.modular_encounters.keys()
	modular_sets.sort()
	for modular_set in modular_sets:
		#TODO more advanced?
		var display_name = modular_set	
		modular_container.add_item(display_name)	

	
func _create_team_container():	
	for i in HERO_COUNT: 
		var new_team_member = heroDeckSelect.instance()
		new_team_member.set_idx(i)
		heroes_container.add_child(new_team_member)
		team[i] = HeroDeckData.new()

remotesync func client_scenario_select(scenario_id):
	_scenario = scenario_id

	var default_modular = ScenarioDeckData.get_recommended_modular_encounter(scenario_id)
	if default_modular:
		var modular_option:OptionButton = get_node("%EncounterSelect")
		for i in modular_option.get_item_count():
			if modular_option.get_item_text(i) == default_modular:
				modular_option.select(i)
				break	
	
	var scenario_scene = all_scenarios_container.get_node("scenario_" + scenario_id)
	if (scenario_scene):
		var imgtex = scenario_scene.get_texture()
		var scenario_picture: TextureRect = get_node("%ScenarioTexture")
		if (imgtex):
			scenario_picture.texture = imgtex
			scenario_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			scenario_picture.rect_size = Vector2(150, 150)
			_rotation = scenario_scene._rotation
			scenario_picture.rect_rotation = _rotation
		var scenario_title = get_node("%ScenarioTitle")
		scenario_title.text = scenario_scene.get_text()
		
		
	verify_launch_button()
	
func scenario_select(scenario_id):
	if (not cfc.is_game_master()):
		return	
	rpc("client_scenario_select", scenario_id)

puppet func modular_encounter_select(index):
	get_node("%EncounterSelect").select(index)

func _on_EncounterSelect_item_selected(index):
	if (not cfc.is_game_master()):
		return
	rpc("modular_encounter_select", index)			
	pass # Replace with function body.

puppet func expert_mode_toggle (button_pressed):
	get_node("%ExpertMode").set_pressed_no_signal(button_pressed)

func _on_ExpertMode_toggled(button_pressed):
	if (not cfc.is_game_master()):
		return
	rpc("expert_mode_toggle", button_pressed)			
	pass # Replace with function body.	
	pass # Replace with function body.



func request_hero_slot(hero_id):
	rpc_id(1, "get_next_hero_slot",hero_id)

#Attempt to get a slot for a given hero for a given player
#If succesful, tell everyone to update their info
remotesync func get_next_hero_slot(hero_id) -> int:
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id() 
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.owner.network_id == client_id and data.get_hero_id() == ""):
			rpc("assign_hero", hero_id, i)
			return i
	return -1			

remotesync func assign_hero(hero_id, slot):
	#data update
	var hero_deck_data: HeroDeckData = team[slot]
	hero_deck_data.set_hero_id(hero_id) #todo could use a signal here and the GUI would be listening
	
	#gui update
	var hero_deck_select = heroes_container.get_child(slot)
	hero_deck_select.load_hero(hero_id)
	
	verify_launch_button()

func verify_launch_button():
	if check_ready_to_launch():
		launch_button.show()
	else:
		launch_button.hide()

func check_ready_to_launch() -> bool:
	if !cfc.is_game_master():
		return false
	
	#can't launch without scenario	
	if (!_scenario):
		return false
	
	#can't launch if all players don't have at least one hero
	var players_with_heroes:= {}

	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.get_hero_id() and data.owner.network_id):
			players_with_heroes[data.owner.network_id] = true
	if players_with_heroes.size() != gameData.network_players.size():
		return false
	
	return true
	
	
func request_release_hero_slot(hero_id):
	rpc_id(1, "release_hero_slot",hero_id)

#Attempt to release a slot for a given hero for a given player
#If succesful, tell everyone to update their info
remotesync func release_hero_slot(hero_id) -> int:
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id()
#	var remaining_team_members = 0;
#	for i in HERO_COUNT:
#		var data: HeroDeckData = team[i]
#		if (data.hero_id):
#			remaining_team_members += 1
	var result = -1
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.owner.network_id == client_id and data.get_hero_id() == hero_id):
			rpc("assign_hero", "", i)
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
	rpc("remote_owner_changed",id,index)

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
	rpc("remote_deck_changed",_deck_id, hero_index)	

remote func remote_deck_changed (_deck_id, hero_index):
	#update data
	team[hero_index].deck_id = _deck_id
	#update GUI
	var _heroDeckSelect = heroes_container.get_child(hero_index)
	_heroDeckSelect.set_deck(_deck_id)

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
	# server pressed on launch, start the game!
	gameData.set_team_data(team)
	
	#TODO this is gross based on display text. NEed to do something ID based
	gameData.set_scenario_data({"scheme_id" : _scenario})
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'menus/GetReady.tscn')

func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"LaunchButton":
			_launch_server_game()		
		#"Cancel":
			#TODO disconnect?
		#	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

func _on_Menu_resized() -> void:
	for tab in [main_menu]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x




