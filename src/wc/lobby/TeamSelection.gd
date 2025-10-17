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
#Selector drag and drop on the left panem
var heroSelect = preload("res://src/wc/lobby/HeroSelect.tscn")
#Deck Selection element once in the team (right panel)
var heroDeckSelect = preload("res://src/wc/lobby/HeroDeckSelect.tscn")

#
#data
#
var team := {} #container for the team information, indexed by slot id (0,1,2,3)

#
# shortcuts
#
onready var main_menu := $MainMenu
onready var scenarios_container: OptionButton = get_node("%ScenarioSelect")
onready var all_heroes_container = get_node("%Heroes")
onready var heroes_container = get_node("%TeamContainer")
onready var ready_button = get_node("%ReadyButton")
onready var launch_button = get_node("%LaunchButton")

# Called when the node enters the scene tree for the first time.
func _ready():
	# If nothing's setup, start server for Single player mode
	if (not get_tree().get_network_peer()):
		gameData.init_1player()
	
	
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	_create_team_container()
	_create_hero_container()
	_load_scenarios()
	
	ready_button.hide() #todo do something with this guy
	launch_button.hide()
	launch_button.connect('pressed', self, 'on_button_pressed', [launch_button.name])

#Quickstart for tests
#TODO remove
	if (gameData.is_multiplayer_game and cfc.is_game_master()):
		yield(get_tree().create_timer(1), "timeout")	
		owner_changed(2, 1)
		rpc("assign_hero", "01001a", 0)
		rpc("assign_hero", "01010a", 1)
		yield(get_tree().create_timer(1), "timeout")	
		_launch_server_game()
	else:
		yield(get_tree().create_timer(1), "timeout")	
		rpc("assign_hero", "01001a", 0)
		yield(get_tree().create_timer(1), "timeout")	
		_launch_server_game()		
	
	
func _load_scenarios():
	for scenario_id in cfc.scenarios:
		#TODO more advanced?
		var scenario = cfc.get_card_by_id(scenario_id)
		var scenario_display_name = scenario["card_set_code"]	
		scenarios_container.add_item(scenario_display_name)	

func _create_hero_container():
	for hero_id in cfc.idx_hero_to_deck_ids:
		var new_hero = heroSelect.instance()
		new_hero.load_hero(hero_id)
		all_heroes_container.add_child(new_hero)	
	
func _create_team_container():	
	for i in HERO_COUNT: 
		var new_team_member = heroDeckSelect.instance()
		new_team_member.set_idx(i)
		heroes_container.add_child(new_team_member)
		team[i] = HeroDeckData.new()

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
		if (data.owner.network_id == client_id and data.hero_id == ""):
			rpc("assign_hero", hero_id, i)
			return i
	return -1			

remotesync func assign_hero(hero_id, slot):
	#data update
	var hero_deck_data: HeroDeckData = team[slot]
	hero_deck_data.hero_id = hero_id #todo could use a signal here and the GUI would be listening
	
	#gui update
	var hero_deck_select = heroes_container.get_child(slot)
	hero_deck_select.load_hero(hero_id)
	
	if (hero_id and cfc.is_game_master()):
		launch_button.show()
	
	
func request_release_hero_slot(hero_id):
	rpc_id(1, "release_hero_slot",hero_id)

#Attempt to release a slot for a given hero for a given player
#If succesful, tell everyone to update their info
remotesync func release_hero_slot(hero_id) -> int:
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id()
	var remaining_team_members = 0;
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.hero_id):
			remaining_team_members += 1
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.owner.network_id == client_id and data.hero_id == hero_id):
			rpc("assign_hero", "", i)
			remaining_team_members -=1
			if (not remaining_team_members):
				launch_button.hide()
			return i
	return -1			

func owner_changed(id, index):
	var player : PlayerData = gameData.get_player_by_index(id)
	team[index].owner = player
	rpc("remote_owner_changed",id,index)

remote func remote_owner_changed (id, index):
	#update data
	var player : PlayerData = gameData.get_player_by_index(id)
	team[index].owner = player
	#update GUI
	var _heroDeckSelect = heroes_container.get_child(index)
	_heroDeckSelect.set_owner(id)

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
	var scenario_dropdown_id = scenarios_container.get_selected_id()
	var scenario_name = scenarios_container.get_item_text(scenario_dropdown_id)
	gameData.set_scenario_data({"card_set_code" : scenario_name})
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
