#Stores all global game data, multiplayer info, etc...

# Hero vs Player:
# Generally speaking: Player is the physical person, Hero is the currently playing Hero
# Important distinction since you can play multiple heroes per player
class_name GameData
extends Node

#Singleton for game data shared across menus and views
var network_players := {}

var id_to_network_id:= {}

#1 indexed {id: HeroDeckData}
var team := {}

var scenario:ScenarioDeckData

func _init():
	scenario = ScenarioDeckData.new()

# Hero currently playing. We might need another one for interruptions
var current_hero_id := 1

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func init_network_players(players:Dictionary):
	for player_network_id in players:
		var info = players[player_network_id]
		var new_player_data := PlayerData.new(info.name, info.id, player_network_id)
		network_players[player_network_id] = new_player_data 
		id_to_network_id[info.id] = player_network_id

func set_team_data(_team:Dictionary):
	#filter out empty slots
	var hero_count = 0;
	for hero_idx in _team:
		var hero_data:HeroDeckData = _team[hero_idx]
		if (hero_data.deck_id and hero_data.hero_id):
			hero_count += 1
			team[hero_count] = { 
				"hero_data" : hero_data,
				"manapool" : ManaPool.new(),
				}
	return 0				

func set_scenario_data(_scenario:Dictionary):
	if (!scenario):
		print_debug("scenario variable is not set")
		return
	scenario.load_from_dict(_scenario)

func get_player_by_index(id):
	return network_players[id_to_network_id[id]]

#setup default for 1player mode	
func init_1player():
	init_as_server()
	var dic = {1 : {"name" : "Player1", "id" : 0}}
	init_network_players(dic)
	
func init_as_server():
	var peer = NetworkedMultiplayerENet.new()
	peer.set_compression_mode(NetworkedMultiplayerENet.COMPRESS_RANGE_CODER)
	var err = peer.create_server(CFConst.MULTIPLAYER_PORT, 3) # Maximum of 3 peers. TODO make this a config
	if err != OK:
		return err #does this ever run?
	get_tree().set_network_peer(peer)
	return err	

func get_team_size():
	return team.size()

func get_team_member(id:int):
	return team[id]
	
func get_current_hero_id():
	return current_hero_id
	
func get_current_team_member():
	return team[current_hero_id]	
