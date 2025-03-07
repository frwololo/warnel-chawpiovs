#Stores all global game data, multiplayer info, etc...

# Hero vs Player:
# Generally speaking: Player is the physical person, Hero is the currently playing Hero
# Important distinction since you can play multiple heroes per player
class_name GameData
extends Node

# The path to the optional confirm scene. This has to be defined explicitly
# here, in order to use it in its preload, otherwise the parser gives an error
const _OPTIONAL_CONFIRM_SCENE_FILE = CFConst.PATH_CORE + "OptionalConfirmation.tscn"
const _OPTIONAL_CONFIRM_SCENE = preload(_OPTIONAL_CONFIRM_SCENE_FILE)



#Singleton for game data shared across menus and views
var network_players := {}
var id_to_network_id:= {}
var is_multiplayer_game:bool = true
#1 indexed {id: HeroDeckData}
var team := {}

var scenario:ScenarioDeckData
var phaseContainer: PhaseContainer #reference link to the phaseContainer
var theStack: GlobalScriptStack
var testSuite: TestSuite = null

# Hero currently playing. We might need another one for interruptions
var current_hero_id := 1

var _villain_current_hero_target :=1
var attackers:Array = []

var user_input_ongoing:int = 0 #ID of the current player (or remote player) doing a blocking game interraction

func _process(_delta: float):
	theStack.process(_delta)
	if (testSuite):
		testSuite.process(_delta)
	return

puppetsync func user_input_lock_denied():
	return #TODO ?
	
puppetsync func user_input_unlock_denied():
	return #TODO ?	

mastersync func request_user_input_lock():
	var requester = get_tree().get_rpc_sender_id()
	if (user_input_ongoing && (user_input_ongoing != requester)):
		rpc_id(requester,"user_input_lock_denied") # tell the sender their request is denied
	rpc("acquire_user_input_lock", requester)	

mastersync func request_user_input_unlock():
	var requester = get_tree().get_rpc_sender_id()
	if (!user_input_ongoing || (user_input_ongoing != requester)):
		rpc_id(requester,"user_input_unlock_denied") # tell the sender their request is denied
	rpc("release_user_input_lock", requester)

puppetsync func acquire_user_input_lock(requester:int, details = {}):
	_acquire_user_input_lock(requester, details)
	
puppetsync func release_user_input_lock(requester:int,details = {}):
	_release_user_input_lock(requester, details)

func _acquire_user_input_lock(requester:int, details = {}):
	user_input_ongoing = requester
	
func _release_user_input_lock(requester:int,details = {}):
	user_input_ongoing = 0
	#TODO error check: if requester not equal to current user_input_ongoing, we have a desync 
	
func attempt_user_input_lock(request_object = null,details = {}):
	#if "is_master" key is set, we use this to check whether we are authorized to request the lock
	var is_master = details.get("is_master", true)
	if (!is_master):
		return
			
	rpc_id(1, "request_user_input_lock" )		
	
func attempt_user_input_unlock(request_object = null,details = {}):	
	rpc_id(1, "request_user_input_unlock")	
	
	
#Returns true if I am allowed to play cards/abilities
#This is a more complex question than might seem
#even if I am allowed to play by this function, I might not be able to play all cards/abilities at a given time)
func can_i_play() -> bool:
	
	#If there is blocking user input ongoing and it isn't me, I can't play
	if (user_input_ongoing):
		if (user_input_ongoing != get_tree().get_network_unique_id()):
			return false
	
	return true 	

func _init():
	scenario = ScenarioDeckData.new()
	theStack = GlobalScriptStack.new()

func start_tests():
	testSuite = TestSuite.new()

func registerPhaseContainer(phasecont:PhaseContainer):
	phaseContainer = phasecont

# Called when the node enters the scene tree for the first time.
func _ready():
	#Signals
	#TODO: the attempt to lock should happen BEFORE we actually open the windows
	scripting_bus.connect("selection_window_opened", self, "attempt_user_input_lock")
	scripting_bus.connect("card_selected", self, "attempt_user_input_unlock")

	#scripting_bus.connect("optional_window_opened", self, "attempt_user_input_lock")
	#scripting_bus.connect("optional_window_closed", self, "attempt_user_input_unlock")	


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
	is_multiplayer_game = false
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
		var hand:Hand = cfc.NMAP["hand" + str(i+1)]
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
		_villain_current_hero_target = 1 #Is this the right place? Causes lots of errors otherwise...
		return 0
	return 	_villain_current_hero_target

func enemy_activates() -> int :
	var target_id = _villain_current_hero_target
	
	#If we're not the targeted player, we'll fail this one,
	#and go into "wait for next phase" instantly. This should 
	#force us to wait for the targeted player to trigger the script via network
	if not (can_i_play_this_hero(target_id)):
		return CFConst.ReturnCode.FAILED
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

func get_facedown_encounters_pile() -> Pile :
	var pile  = cfc.NMAP["encounters_facedown" + str(_villain_current_hero_target)]
	return pile
	
func get_enemies_grid() -> BoardPlacementGrid :
	var grid  = cfc.NMAP.board.get_grid("enemies" + str(_villain_current_hero_target))
	#var grid  = cfc.NMAP.board.get_grid("enemies1")

	return grid	

#TODO need something much more advanced here, per player, etc...
func deal_encounters():
	var villain_deck:Pile = cfc.NMAP["deck_villain"]
	while true: #loop through all heroes. see villain_next_target call below
		var encounter:Card = villain_deck.get_top_card()
		if encounter:
			var destination  = get_facedown_encounters_pile() 
			encounter.move_to(destination)
		else:
			#TODO shuffle deck + acceleration
			pass
		if (!villain_next_target()): # This forces to change the next facedown destination
			return
	

#TODO need something much more advanced here, per player, etc...
func reveal_encounters():
	while true: #loop through all heroes. see villain_next_target call below
		var facedown_encounters:Pile = get_facedown_encounters_pile()
		var encounter:Card = facedown_encounters.get_top_card()
		while (encounter): #Loop through all encounters in the current facedown pile
			while Card.CardState.MOVING_TO_CONTAINER == encounter.state:
				yield(get_tree().create_timer(0.05), "timeout")
			
			var grid: BoardPlacementGrid = get_encounter_target_grid(encounter)
			
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
			else:
				push_error("ERROR: Missing target grid in reval_encounters")		
		
			encounter = facedown_encounters.get_top_card()
		
		if (!villain_next_target()): # This forces to change the next facedown destination
			return	

	pass

#TODO need to move thi to some configuration driven logic
func get_encounter_target_grid (encounter) -> BoardPlacementGrid:
	var typecode = encounter.properties.get("type_code", "")
	var grid_name = CFConst.TYPECODE_TO_GRID.get(typecode, "villain_misc")
	
	match grid_name:
		"villain_misc":
			pass
		"schemes":
			pass
		_:
			grid_name = grid_name + str(_villain_current_hero_target)
	
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(grid_name)
	
	return grid	

func get_villain() -> Card :
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("villain")
	if grid:
		var slot: BoardPlacementSlot = grid.get_slot(0)
		return slot.occupying_card
	return null
	
func get_minions_engaged_with_player(player_id:int):
	var results = []
	var minionsGrid:BoardPlacementGrid = get_enemies_grid()
	if minionsGrid:
		results = minionsGrid.get_all_cards()
	return results
	
#Returns Hero currently being targeted by the villain and his minions	
func get_current_target_hero() -> Card:
	var board:Board = cfc.NMAP.board
	var heroZone:WCHeroZone = board.heroZones[_villain_current_hero_target]
	return heroZone.get_hero_card()

#Adds a "group_defenders" tag to all cards that can block an attack
func compute_potential_defenders():
	var board:Board = cfc.NMAP.board
	for c in board.get_all_cards():
		if c.can_defend():
			c.add_to_group("group_defenders")
		else:
			if (c.is_in_group ("group_defenders")): c.remove_from_group("group_defenders")	

func hero_died(card:Card):
	#TODO check if other heroes are alive
	var board:Board = cfc.NMAP.board
	board.end_game("defeat")

func villain_died(card:Card):
	#TODO get next villain stage
	var board:Board = cfc.NMAP.board
	board.end_game("victory")

func select_current_playing_hero(hero_index):
	if (not can_i_play_this_hero(hero_index)):
		return
	var previous_hero_id = current_hero_id
	current_hero_id = hero_index
	scripting_bus.emit_signal("current_playing_hero_changed",  {"before": previous_hero_id,"after": current_hero_id })

func can_i_play_this_hero(hero_index)-> bool:
	#Errors. If hero index is out of range I can't use it
	if hero_index < 1 or hero_index> get_team_size():
		return false
		
	#if this isn't a network game, I can play all valid heroes	
	if (!get_tree().get_network_peer()):
		return true
		
	var network_id = get_tree().get_network_unique_id()	
	var hero_deck_data:HeroDeckData = get_team_member(hero_index)["hero_data"]
	var owner_player:PlayerData = hero_deck_data.owner
	if (owner_player.network_id == network_id):
		return true
	return false

#Returns player id who owns a specific hero (by hero card id)	
func get_hero_owner(hero_index)->int:
	#Errors. If hero index is out of range I can't use it
	if hero_index < 1 or hero_index> get_team_size():
		return 0
			
	var hero_deck_data:HeroDeckData = get_team_member(hero_index)["hero_data"]
	var owner_player:PlayerData = hero_deck_data.owner
	return owner_player.get_network_id()	

#picks a first hero for a network player
func assign_starting_hero():
	for i in range(get_team_size()):
		var hero_id = i+1
		if (can_i_play_this_hero(hero_id)):
			select_current_playing_hero(hero_id)
			return hero_id
	# error
	return 0

#TODO error handling?
func get_grid_owner_hero_id(grid_name:String) -> int:
	var potential_hero_id = grid_name.right(1).to_int()
	return potential_hero_id

#Returns true if another network player is supposed to play,
# in which case I have to wait for their input
#probably needs an rpc call at some point?
# TODO maybe each player that wants "exclusivity" requests exclusivity to Master
# and master adds it to a pile, so that there can be exclusivity on top of exclusivity? e.g. for interrupts	
func is_waiting_for_other_player_input():
	var current_step = phaseContainer.current_step
	if (current_step == PhaseContainer.PHASE_STEP.VILLAIN_ACTIVATES or current_step == PhaseContainer.PHASE_STEP.VILLAIN_MINIONS_ACTIVATE):
		if not (can_i_play_this_hero(_villain_current_hero_target)):
			return true
	return false

func execute_script_to_remote(caller_card_uid, trigger_card_uid, trigger, remote_trigger_details, only_cost_check):
	rpc("execute_script_from_remote", caller_card_uid, trigger_card_uid, trigger, remote_trigger_details, only_cost_check)

remote func execute_script_from_remote(caller_card_uid, trigger_card_uid, trigger, remote_trigger_details, only_cost_check): 
	var trigger_card = guidMaster.get_object_by_guid(trigger_card_uid)
	var caller_card = guidMaster.get_object_by_guid(caller_card_uid)
	caller_card.execute_scripts(trigger_card, trigger, remote_trigger_details, only_cost_check)	

#TODO all calls to this method are in core which isn't good
#Need to move something, somehow
func confirm(
		owner,
		script: Dictionary,
		card_name: String,
		task_name: String,
		type := "task") -> bool:
	var is_accepted := true
	# We do not use SP.KEY_IS_OPTIONAL here to avoid causing cyclical
	# references when calling CFUtils from SP
	if script.get("is_optional_" + type):
		_acquire_user_input_lock(owner.get_controller_player_id())
		var my_network_id = get_tree().get_network_unique_id()
		var is_master:bool =  (owner.get_controller_player_id() == my_network_id)
		var confirm = _OPTIONAL_CONFIRM_SCENE.instance()
		confirm.prep(card_name,task_name, is_master)
		# We have to wait until the player has finished selecting an option
		yield(confirm,"selected")
		# If the player selected "No", we don't execute anything
		if not confirm.is_accepted:
			is_accepted = false
		# Garbage cleanup
		confirm.hide()
		confirm.queue_free()
		_release_user_input_lock(owner.get_controller_player_id())	
	return(is_accepted)
	
#saves current game data into a json structure	
func save_gamedata():
	var json_data:Dictionary = {}
	#save current phase
	var phase_data:Dictionary = phaseContainer.savestate_to_json()
	json_data.merge(phase_data)
	
	
	#Save Hero data (the bulk: Hero Deck Data (hero id, owner), Manapool, Board state)
	json_data["heroes"] = []
	for i in range(get_team_size()):
		var saved_item:Dictionary = {}
		var hero_deck_data: HeroDeckData = get_team_member(i+1)["hero_data"]
		var hero_deck_data_json = hero_deck_data.savestate_to_json()
		saved_item.merge(hero_deck_data_json)
		
		#Manapool
		var hero_manapool: ManaPool = get_team_member(i+1)["manapool"]
		var hero_manapool_json = hero_manapool.savestate_to_json()
		saved_item.merge(hero_manapool_json)
				
		
		
		#Merge result with the saved data
		json_data["heroes"].append(saved_item)
	
	#Board state
	var boardstate_json = cfc.NMAP.board.savestate_to_json()
	json_data.merge(boardstate_json)
	
	#Save scenario data
	json_data["scenario"] = {}
	return json_data

#loads current game data from a json structure
func load_gamedata(json_data:Dictionary):
	#phase
	phaseContainer.loadstate_from_json(json_data)
	
	var hero_data:Array = json_data["heroes"]

	#hero Deck data	
	var _team:Dictionary = {}
	for i in range(hero_data.size()):
		var saved_item:Dictionary = hero_data[i]
		var hero_deck_data: HeroDeckData = HeroDeckData.new()
		hero_deck_data.loadstate_from_json(saved_item)
		_team[i] = hero_deck_data
	set_team_data(_team)
	
	#Manapools
	for i in range(hero_data.size()):
		var saved_item:Dictionary = hero_data[i]
		var hero_manapool: ManaPool = get_team_member(i+1)["manapool"]
		hero_manapool.loadstate_from_json(saved_item)

	#Board State ()
	cfc.NMAP.board.loadstate_from_json(json_data)
	
	#scenario		
	return
