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

#TODO this draws to the wrong hands	
func draw_all_players() :
	for i in range(get_team_size()):
		var hero_deck_data: HeroDeckData = get_team_member(i+1)["hero_data"]
		var alter_ego_data = hero_deck_data.get_alter_ego_card_data()
		var hand_size = alter_ego_data["hand_size"]
		var hand:Hand = cfc.NMAP["hand"] # + str(i+1)]
		hand_size = hand_size - hand.get_card_count()
		for j in range(hand_size):
			hand.draw_card (cfc.NMAP["deck" + str(i+1)])	

func ready_all_player_cards():
		var cards:Array = cfc.NMAP["board"].get_all_cards() #TODO hero cards only
		for card in cards:
			if not card.properties.get("_horizontal", false):
				card.readyme()	

func _find_main_scheme() : 
	var cards:Array = cfc.NMAP["board"].get_all_cards()
	for card in cards:
		if "main_scheme" == card.properties.get("type_code", "false"):
			return card
	return null
	
func villain_threat():
	var scheme:Card = _find_main_scheme()
	if not scheme:
		return CFConst.ReturnCode.FAILED
	var escalation_threat = scheme.properties["escalation_threat"]	
	var escalation_threat_fixed = scheme.properties["escalation_threat_fixed"]
	if (not escalation_threat_fixed):
		escalation_threat *= get_team_size()
	scheme.add_threat(escalation_threat)

#TODO need something much more advanced here, per player, etc...
func reveal_encounters():
	var villain_deck:Pile = cfc.NMAP["deck_villain"]
	var encounter:Card = villain_deck.get_top_card()
	
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("enemies")
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.find_available_slot()
		if slot:
			#Needs a bit of a timer to ensure the slot gets created	
			yield(get_tree().create_timer(0.05), "timeout")
			encounter.move_to(cfc.NMAP.board, -1, slot)	
			encounter.set_is_faceup(true)
			

	pass
