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

# Called when the node enters the scene tree for the first time.
func _ready():
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	_create_team_container()
	_create_hero_container()
	_load_scenarios()
	
func _load_scenarios():
	for scenario_id in cfc.scenarios:
		#TODO more advanced?
		var scenario = cfc.get_card_by_id(scenario_id)
		#var scenario_display_name = scenario["Name"] + " (" + scenario["card_set_name"] + ")"	
		var scenario_display_name = scenario["card_set_name"]	
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
	
func request_release_hero_slot(hero_id):
	rpc_id(1, "release_hero_slot",hero_id)

#Attempt to release a slot for a given hero for a given player
#If succesful, tell everyone to update their info
remotesync func release_hero_slot(hero_id) -> int:
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id() 
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.owner.network_id == client_id and data.hero_id == hero_id):
			rpc("assign_hero", "", i)
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
	var heroDeckSelect = heroes_container.get_child(index)
	heroDeckSelect.set_owner(id)


func _on_Menu_resized() -> void:
	for tab in [main_menu]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x
