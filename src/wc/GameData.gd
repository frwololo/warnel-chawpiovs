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

# Hero currently playing. We might need another one for interruptions
var current_hero_id := 1

var _villain_current_hero_target :=1
var attackers:Array = []

func _init():
	scenario = ScenarioDeckData.new()

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

func end_round():
	_villain_current_hero_target = 1

func villain_init_attackers():
	attackers = []
	var current_target = _villain_current_hero_target
	#TODO per player
	attackers.append(get_villain())
	attackers += get_minions_engaged_with_player(current_target)
	var temp = attackers.size()
	temp = 0

func villain_next_target() -> int:
	_villain_current_hero_target += 1
	if _villain_current_hero_target > get_team_size():
		return 0
	return 	_villain_current_hero_target

func enemy_activates() -> int :
	var target_id = _villain_current_hero_target
	var enemy:Card = attackers.pop_front()
	if (enemy):
		var sceng = enemy.execute_scripts(enemy, "automated_enemy_attack")
		if sceng is GDScriptFunctionState:
			sceng = yield(sceng, "completed")
		return CFConst.ReturnCode.OK
	return CFConst.ReturnCode.FAILED
	
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
func deal_encounters():
	var villain_deck:Pile = cfc.NMAP["deck_villain"]
	var encounter:Card = villain_deck.get_top_card()
	
	var destination  = cfc.NMAP["encounters_facedown"] #TODO per player 
	encounter.move_to(destination)

	

#TODO need something much more advanced here, per player, etc...
func reveal_encounters():
	var facedown_encounters:Pile = cfc.NMAP["encounters_facedown"]
	var encounter:Card = facedown_encounters.get_top_card()

	while Card.CardState.MOVING_TO_CONTAINER == encounter.state:
		yield(get_tree().create_timer(0.05), "timeout")
	
	var typecode = encounter.properties.get("type_code", "")
	var grid_name = CFConst.TYPECODE_TO_GRID.get(typecode, "villain_misc")
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(grid_name)
	
	if grid:
		var slot: BoardPlacementSlot = grid.find_available_slot()
		if slot:
			#Needs a bit of a timer to ensure the slot gets created	
			
			yield(get_tree().create_timer(0.05), "timeout")
			# How to get rid of this mess?
			# We have to flip the card in order for the script to execute
			# But in the main scheme setup this works flawlessly...
			encounter.set_is_faceup(true,true)
			encounter.move_to(cfc.NMAP.board, -1, slot)
			#encounter.set_is_faceup(false, true)
			#encounter.set_is_faceup(true)
			
			

	pass

func get_villain() -> Card :
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("villain")
	if grid:
		var slot: BoardPlacementSlot = grid.get_slot(0)
		return slot.occupying_card
	return null
	
func get_minions_engaged_with_player(player_id:int):
	var results = []
	var minionsGrid:BoardPlacementGrid = cfc.NMAP.board.get_grid("enemies") #TODO per player
	if minionsGrid:
		results = minionsGrid.get_all_cards()
	return results
	
#Returns Hero currently being targeted by the villain and his minions	
func get_current_target_hero() -> Card:
	var board:Board = cfc.NMAP.board
	var heroZone:WCHeroZone = board.heroZones[_villain_current_hero_target]
	return heroZone.get_hero_card()

func compute_potential_defenders():
	var board:Board = cfc.NMAP.board
	for c in board.get_all_cards():
		if c.can_defend():
			c.add_to_group("defenders")
		else:
			c.remove_from_group("defenders")	
