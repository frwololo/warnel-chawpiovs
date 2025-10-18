# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

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

enum EnemyAttackStatus {
	NONE,
	PENDING_INTERRUPT,
	OK_TO_START_ATTACK,
	PENDING_DEFENDERS,
	ATTACK_COMPLETE
}
var _current_enemy_attack_step: int = EnemyAttackStatus.NONE

enum EncounterStatus {
	NONE,
	ABOUT_TO_REVEAL,
	PENDING_REVEAL_INTERRUPT,
	OK_TO_EXECUTE,
	PENDING_COMPLETE,
	ENCOUNTER_COMPLETE
}
var _current_encounter_step: int = EncounterStatus.NONE
var _current_encounter:Card = null

#emit whenever something changes in the game state. This will trigger some recomputes
signal game_state_changed(details)

#Singleton for game data shared across menus and views
var network_players := {}
var id_to_network_id:= {}
var is_multiplayer_game:bool = true

#1 indexed {hero_id: {"hero_data": HeroDeckData, "manapool" : ManaPool}}
var team := {}

var dead_heroes := []

var gamesave_load_status:= {}

var scenario:ScenarioDeckData
var phaseContainer: PhaseContainer #reference link to the phaseContainer
var theStack: GlobalScriptStack
var testSuite: TestSuite = null

# Hero currently playing. We might need another one for interruptions
var current_hero_id := 1

#temp vars for bean counting
var _villain_current_hero_target :=1
var _current_enemy = null
var attackers:Array = []
var user_input_ongoing:int = 0 #ID of the current player (or remote player) doing a blocking game interraction
var _garbage:= []

func _init():
	scenario = ScenarioDeckData.new()
	theStack = GlobalScriptStack.new()

# Called when the node enters the scene tree for the first time.
func _ready():
	#Signals
	#TODO: the attempt to lock should happen BEFORE we actually open the windows
	scripting_bus.connect("selection_window_opened", self, "attempt_user_input_lock")
	scripting_bus.connect("card_selected", self, "attempt_user_input_unlock")
	scripting_bus.connect("scripting_event_triggered", self, "_scripting_event_triggered")
	scripting_bus.connect("scripting_event_about_to_trigger", self, "_scripting_event_about_to_trigger")

	self.add_child(theStack) #Stack needs to be in the tree for rpc calls	

	#scripting_bus.connect("optional_window_opened", self, "attempt_user_input_lock")
	#scripting_bus.connect("optional_window_closed", self, "attempt_user_input_unlock")	

func _process(_delta: float):
	#theStack.process(_delta)
	#if (testSuite):
	#	testSuite.process(_delta)
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

func _acquire_user_input_lock(requester:int, _details = {}):
	user_input_ongoing = requester
	
func _release_user_input_lock(_requester:int,_details = {}):
	user_input_ongoing = 0
	#TODO error check: if requester not equal to current user_input_ongoing, we have a desync 
	
func attempt_user_input_lock(_request_object = null,details = {}):
	#if "is_master" key is set, we use this to check whether we are authorized to request the lock
	var is_master = details.get("is_master", true)
	if (!is_master):
		return
			
	rpc_id(1, "request_user_input_lock" )		
	
func attempt_user_input_unlock(_request_object = null,_details = {}):	
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

func start_tests():
	rpc("init_client_tests")

remotesync func init_client_tests():
	testSuite = TestSuite.new()
	testSuite.name = "testSuite"
	self.add_child(testSuite) #Test suite needs to be in the tree for rpc calls	


func registerPhaseContainer(phasecont:PhaseContainer):
	phaseContainer = phasecont

func _scripting_event_about_to_trigger(_trigger_object = null,
		trigger: String = "manual",
		_trigger_details: Dictionary = {}):
	
	match trigger:
		"card_moved_to_board":
			check_ally_limit()
	return

func _scripting_event_triggered(_trigger_object = null,
		trigger: String = "manual",
		_trigger_details: Dictionary = {}):
	
	match trigger:
		"card_token_modified":
			check_main_scheme_defeat()
		"card_moved_to_board",\
				"card_moved_to_pile", \
				"card_moved_to_hand" :
			check_empty_decks(_trigger_details["source"])
		"enemy_initiates_attack",\
				"enemy_initiates_scheme":
			pre_attack_interrupts_done()			

	match trigger:
		"card_moved_to_board", \
				"card_played", \
				"card_token_modified" :		
			game_state_changed()
	return

#a function that checks if any deck becomes empty after a card is moved,
#and triggers the appropriate measures as needed
func check_empty_decks(pile_to_check):
	if (pile_to_check == "deck_villain"):
		var villain_deck:Pile = cfc.NMAP[pile_to_check]
		if (villain_deck.get_card_count() == 0):
			#shuffle discard into deck
			var villain_discard:Pile = cfc.NMAP["discard_villain"]
			var all_discarded = villain_discard.get_all_cards()
			for card in all_discarded:
				card.move_to(villain_deck)
			villain_deck.shuffle_cards()
			#add acceleration to main scheme
			var scheme = find_main_scheme()
			if (scheme):
				scheme.tokens.mod_token("acceleration", 1)
			else:
				var _error = 1 #TODO error handling 
		return
	
	elif (pile_to_check.begins_with("deck")): #player decks
		var hero_id_str = pile_to_check.substr(4,1)
		var hero_deck:Pile = cfc.NMAP[pile_to_check]
		if (hero_deck.get_card_count() == 0):
			#shuffle discard into deck
			var hero_discard:Pile = cfc.NMAP["discard" + hero_id_str]
			var all_discarded = hero_discard.get_all_cards()
			for card in all_discarded:
				card.move_to(hero_deck)
			hero_deck.shuffle_cards()
			#deal a new encounter
			deal_one_encounter_to(int(hero_id_str))
		return		
	
func move_to_next_scheme(current_scheme):
	var set_code = current_scheme.get_property("card_set_code", "").to_lower()
	var stage = current_scheme.get_property("stage")
	
	var next_stage = stage + 1
	var set_schemes = cfc.schemes[set_code]
	for scheme in set_schemes:
		if (scheme.get("stage", 0) == next_stage):
			var board = cfc.NMAP.board
			var code = scheme.get("_code")
			var new_card = cfc.instance_card(code,current_scheme.get_owner_hero_id())

			var slot = current_scheme._placement_slot
			board.add_child(new_card)
			current_scheme.queue_free() #is more required to remove it?		
			new_card.position = slot.rect_global_position
			new_card._placement_slot = slot
			slot.occupying_card = new_card
			new_card.state = Card.CardState.ON_PLAY_BOARD
			return new_card
	
	return null

func check_ally_limit():
	var my_heroes = gameData.get_my_heroes()
	for hero_id in my_heroes:
		var hero_data = gameData.team[hero_id]["hero_data"]
		var ally_limit = hero_data.get_ally_limit()
		var my_cards = cfc.NMAP.board.get_grid("allies" + String(hero_id)).get_all_cards()
		if (my_cards.size()) > ally_limit:
			var hero_card = gameData.get_identity_card(hero_id)
			hero_card.execute_scripts(hero_card, "ally_limit")
		
#a function that checks regularly (sepcifically, whenever threat changes) if the main scheme has too much threat	
func check_main_scheme_defeat():
	var scheme = find_main_scheme()
	if (!scheme):
		var _error = 1 #TODO error handling
		return
	
	if scheme.get_current_threat() < scheme.get_property("threat", 0):
		return
	
	var next_scheme = move_to_next_scheme(scheme)
	
	if (!next_scheme):		
		var board:Board = cfc.NMAP.board
		board.end_game("defeat")	
	
func game_state_changed():
	emit_signal("game_state_changed",{})

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

func get_player_by_network_id(network_id) -> PlayerData:
	return network_players[network_id]

func get_player_by_index(id) -> PlayerData:
	return network_players[id_to_network_id[id]]

#setup default for 1player mode	
func init_1player():
	is_multiplayer_game = false
	init_as_server()
	var dic = {1 : {"name" : "Player1", "id" : 1}}
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

func draw_all_players() :
	for hero_id in team.keys():
		var identity = get_identity_card(hero_id)
		var max_hand_size = identity.get_max_hand_size()
		var hand:Hand = cfc.NMAP["hand" + str(hero_id)]
		var to_draw = max_hand_size - hand.get_card_count()
		for _j in range(to_draw):
			hand.draw_card (cfc.NMAP["deck" + str(hero_id)])	

func ready_all_player_cards():
		var cards:Array = cfc.NMAP["board"].get_all_cards() #TODO hero cards only
		for card in cards:
			if not card.properties.get("_horizontal", false):
				card.readyme()	

func find_main_scheme() : 
	var cards:Array = cfc.NMAP.board.get_grid("schemes").get_all_cards()
	for card in cards:
		if "main_scheme" == card.properties.get("type_code", "false"):
			return card
	return null

func end_round():
	_villain_current_hero_target = 1
	scripting_bus.emit_signal("round_ended")

func villain_init_attackers():
	attackers = []
	var current_target = _villain_current_hero_target
	#TODO per player
	attackers.append(get_villain())
	attackers += get_minions_engaged_with_player(current_target)

func villain_next_target() -> int:
	_villain_current_hero_target += 1
	if _villain_current_hero_target > get_team_size():
		_villain_current_hero_target = 1 #Is this the right place? Causes lots of errors otherwise...
		return 0
	return 	_villain_current_hero_target

func all_attackers_finished():
	phaseContainer.all_enemy_attacks_finished()

func current_enemy_finished():
	attackers.pop_front()
	_current_enemy_attack_step = EnemyAttackStatus.NONE

func pre_attack_interrupts_done():
	if _current_enemy_attack_step != EnemyAttackStatus.PENDING_INTERRUPT:
		var _error = 1 #maybe this happens in network games ?
		return
	_current_enemy_attack_step = EnemyAttackStatus.OK_TO_START_ATTACK

func add_enemy_activation(enemy, activation_type:String = "attack"):
	attackers.append({"subject":enemy, "type": activation_type})

func enemy_activates() :
	var target_id = _villain_current_hero_target
	
	#If we're not the targeted player, we'll fail this one,
	#and go into "wait for next phase" instantly. This should 
	#force us to wait for the targeted player to trigger the script via network
	if not (can_i_play_this_hero(target_id)):
		return CFConst.ReturnCode.FAILED
	if !attackers.size():
		all_attackers_finished()
		return

	#there is an enemy, we'll try to attack
	var heroZone:WCHeroZone = cfc.NMAP.board.heroZones[target_id]
	var attacker_data = attackers.front()
	var action = "attack" if (heroZone.is_hero_form()) else "scheme"
	
	var enemy:WCCard = null
	if (typeof (attacker_data) == TYPE_DICTIONARY):
		enemy = attacker_data["subject"]
		action = attacker_data["type"]
	else:
		enemy = attacker_data

	

	var status = "stunned" if (action=="attack") else "confused"
	
	#check for stun
	var is_status = enemy.tokens.get_token_count(status)
	if (is_status):
		#TODO needs to warn all network clients
		enemy.tokens.mod_token(status, -1)
		current_enemy_finished()
		return
		
	#not stunned, proceed
	match _current_enemy_attack_step:
		EnemyAttackStatus.NONE:							
				theStack.create_and_add_signal("enemy_initiates_" + action, enemy, {SP.TRIGGER_TARGET_HERO : get_current_target_hero().canonical_name})
				_current_enemy_attack_step = EnemyAttackStatus.PENDING_INTERRUPT
				return
				
		EnemyAttackStatus.OK_TO_START_ATTACK:	
			if (enemy.get_property("type_code") == "villain"): #Or villainous?
				enemy.draw_boost_card() #TODO send to all clients	
		
			if (action =="attack"):
				#attack		
				var sceng = enemy.execute_scripts(enemy, "enemy_attack")
				_current_enemy_attack_step = EnemyAttackStatus.PENDING_DEFENDERS
			else:
				#scheme		
				enemy.commit_scheme() #todo send to network clients
				current_enemy_finished()
			return
			
		EnemyAttackStatus.PENDING_DEFENDERS:
			#there has to be a better way.... wait for a signal somehow ?
			if !theStack.is_empty():
				return
			if cfc.modal_menu:
				return
			
			_current_enemy_attack_step = EnemyAttackStatus.ATTACK_COMPLETE
			return
			
		EnemyAttackStatus.ATTACK_COMPLETE:
			current_enemy_finished()
			return 

	return
	
func villain_threat():
	var main_scheme:Card = find_main_scheme()
	if not main_scheme:
		return CFConst.ReturnCode.FAILED
		
	#basic threat computation, check if it's a constant or multiplied by numbers of players	
	var escalation_threat = main_scheme.properties["escalation_threat"]	
	var escalation_threat_fixed = main_scheme.properties["escalation_threat_fixed"]
	if (not escalation_threat_fixed):
		escalation_threat *= get_team_size()
	
	var all_schemes:Array = cfc.NMAP.board.get_grid("schemes").get_all_cards()
	for scheme in all_schemes:
		#we add all acceleration tokens	
		escalation_threat += scheme.tokens.get_token_count("acceleration")
		
		#we also add acceleration icons from other schemes
		escalation_threat += scheme.get_property("scheme_acceleration", 0)
		
	main_scheme.add_threat(escalation_threat)

func get_facedown_encounters_pile() -> Pile :
	var pile  = cfc.NMAP["encounters_facedown" + str(_villain_current_hero_target)]
	return pile
	
func get_revealed_encounters_grid() :
	var grid  = cfc.NMAP.board.get_grid("encounters_reveal" + str(_villain_current_hero_target))
	return grid	
	
func get_enemies_grid() -> BoardPlacementGrid :
	var grid  = cfc.NMAP.board.get_grid("enemies" + str(_villain_current_hero_target))

	return grid	


func deal_encounters():
	cfc.add_ongoing_process(self, "deal_encounters")
	var finished = false
	while !finished: #loop through all heroes. see villain_next_target call below
		deal_one_encounter_to(_villain_current_hero_target)
		yield(get_tree().create_timer(1), "timeout")
		if (!villain_next_target()): # This forces to change the next facedown destination
			finished = true

	#reset _villain_current_hero_target for cleanup	
	#it should already be at 1 here but...
	_villain_current_hero_target = 1
	
	#Hazard cards
	var hazard = 0		
	var all_schemes:Array = cfc.NMAP.board.get_grid("schemes").get_all_cards()
	for scheme in all_schemes:
		#we add all hazard icons	
		hazard  += scheme.get_property("scheme_hazard", 0)
	
	while hazard:
		deal_one_encounter_to(_villain_current_hero_target)
		yield(get_tree().create_timer(1), "timeout")
		villain_next_target()
		hazard -=1
		
	#reset _villain_current_hero_target for cleanup	
	_villain_current_hero_target = 1
	cfc.remove_ongoing_process(self, "deal_encounters")

func deal_one_encounter_to(hero_id):
	var villain_deck:Pile = cfc.NMAP["deck_villain"]
	var encounter = villain_deck.get_top_card()
	if encounter:
		var destination  =  cfc.NMAP["encounters_facedown" + str(hero_id)] 
		encounter.move_to(destination)
	else:
		#this shouldn't happen as we constantly reshuffle the encounter deck as soon as it empties
		var _error = 1
		pass		

func all_encounters_finished():
	phaseContainer.all_encounters_done()
	pass

func current_encounter_finished():
	_current_encounter = null
	_current_encounter_step = EncounterStatus.NONE
	pass


#TODO need something much more advanced here, per player, etc...
func reveal_encounter():
	var target_id = _villain_current_hero_target
	
	#If we're not the targeted player, we'll fail this one,
	#and go into "wait for next phase" instantly. This should 
	#force us to wait for the targeted player to trigger the script via network
	if not (can_i_play_this_hero(target_id)):
		return CFConst.ReturnCode.FAILED
		
	if !_current_encounter:
		var facedown_encounters:Pile = get_facedown_encounters_pile()
		_current_encounter = facedown_encounters.get_top_card()
	
	if !_current_encounter:
		all_encounters_finished()
		return

	match _current_encounter.state:
		Card.CardState.DROPPING_TO_BOARD,\
				Card.CardState.MOVING_TO_CONTAINER:
			return

	
	#an encounter is available, proceed
	match _current_encounter_step:
		EncounterStatus.NONE:
			#TODO might need to send a signal before that?
			var grid = get_revealed_encounters_grid()
			var slot = grid.find_available_slot()
			_current_encounter.move_to(cfc.NMAP.board, -1, slot)
			_current_encounter.set_is_faceup(true,false)
			_current_encounter_step = EncounterStatus.ABOUT_TO_REVEAL
			return
		EncounterStatus.ABOUT_TO_REVEAL:
			var state = _current_encounter.state
			var sceng = _current_encounter.execute_scripts(_current_encounter, "reveal")
			_current_encounter_step = EncounterStatus.PENDING_REVEAL_INTERRUPT
			return
		EncounterStatus.PENDING_REVEAL_INTERRUPT:
			#todo replace this with a signal
			if !theStack.is_empty():
				return
			if cfc.modal_menu:
				return
			
			_current_encounter_step = EncounterStatus.OK_TO_EXECUTE
			return					
		EncounterStatus.OK_TO_EXECUTE:
			#todo send to network			
			var grid: BoardPlacementGrid = get_encounter_target_grid(_current_encounter)
			var slot: BoardPlacementSlot = grid.find_available_slot()
			if slot:
				#Needs a bit of a timer to ensure the slot gets created	
				# How to get rid of this mess?
				# We have to flip the card in order for the script to execute
				# But in the main scheme setup this works flawlessly...
				_current_encounter.move_to(cfc.NMAP.board, -1, slot)
				#encounter.set_is_faceup(false, true)
				#encounter.set_is_faceup(true)
				_current_encounter_step = EncounterStatus.PENDING_COMPLETE
			else:
				push_error("ERROR: Missing target grid in reval_encounters")	
		EncounterStatus.PENDING_COMPLETE:
			#there has to be a better way.... wait for a signal somehow ?
			if !theStack.is_empty():
				return
			if cfc.modal_menu:
				return
			
			_current_encounter_step = EncounterStatus.ENCOUNTER_COMPLETE
			return
			
		EncounterStatus.ENCOUNTER_COMPLETE:
			var target_pile = get_encounter_target_pile(_current_encounter)
			if (target_pile):
				_current_encounter.move_to(target_pile)
			current_encounter_finished()
			return 
	return

#TODO need to move this to some configuration driven logic
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
	
func get_encounter_target_pile (encounter):
	var typecode = encounter.properties.get("type_code", "")
	var pile_name = CFConst.TYPECODE_TO_PILE.get(typecode, "")
	
	if !pile_name:
		return null

	return cfc.NMAP.get(pile_name, null)
	

func get_villain() -> Card :
	return cfc.NMAP.board.get_villain_card()
	
func get_minions_engaged_with_player(player_id:int):
	var results = []
	var minionsGrid:BoardPlacementGrid = get_enemies_grid()
	if minionsGrid:
		results = minionsGrid.get_all_cards()
	return results
	
func get_identity_card(owner_id) -> Card:
	if (owner_id) <= 0:
		cfc.LOG ("error owner id is " + String(owner_id))
		return null
	
	var board:Board = cfc.NMAP.board
	var heroZone:WCHeroZone = board.heroZones[owner_id]
	return heroZone.get_identity_card()	

#Returns Hero currently being targeted by the villain and his minions	
func get_current_target_hero() -> Card:
	return get_identity_card(_villain_current_hero_target)

#Adds a "group_defenders" tag to all cards that can block an attack
func compute_potential_defenders():
	var board:Board = cfc.NMAP.board
	for c in board.get_all_cards():
		if c.can_defend():
			c.add_to_group("group_defenders")
		else:
			if (c.is_in_group ("group_defenders")): c.remove_from_group("group_defenders")	

func character_died(card:Card):
	var character_died_definition = {
		"name": "character_died",
	}
	#TODO be more specific about conditoins of death: what caused it, etc...
	var character_died_script:ScriptTask = ScriptTask.new(card, character_died_definition, card, {})
	character_died_script.subjects = [card]
	character_died_script.is_primed = true #fake prime it since we already gave it subjects	
	
	var task_event = SimplifiedStackScript.new("character_died", character_died_script)
	gameData.theStack.add_script(task_event)

func hero_died(card:Card):
	#TODO dead heroes can't play
	dead_heroes.append(card.get_owner_hero_id())
	if (dead_heroes.size() == team.size()):
		var board:Board = cfc.NMAP.board
		board.end_game("defeat")

func move_to_next_villain(current_villain):
	var villains = scenario.villains
	var new_villain_data = null
	for i in range (villains.size() - 1): #-1 here because we want to get the +1 if we find it
		if (villains[i]["Name"] == current_villain.get_property("Name", "")):
			new_villain_data = villains[i+1]
	
	if !new_villain_data :
		return null

	_garbage.append(current_villain)
	current_villain.get_parent().remove_child(current_villain)
	#current_villain.queue_free() #is more required to remove it?	
	
	var ckey = new_villain_data["Name"] #TODO we have name and "Name" which is a problem here...		
	var new_card = cfc.NMAP.board.load_villain(ckey)
	return new_card			

func villain_died(card:Card):
	if (!move_to_next_villain(card)):
		var board:Board = cfc.NMAP.board
		board.end_game("victory")

func select_current_playing_hero(hero_index):
	if (not can_i_play_this_hero(hero_index)):
		return
	var previous_hero_id = current_hero_id
	current_hero_id = hero_index
	scripting_bus.emit_signal("current_playing_hero_changed",  {"before": previous_hero_id,"after": current_hero_id })

func can_i_play_this_ability(card, script) -> bool:
	var my_heroes = get_my_heroes()
	for hero_id in my_heroes:
		if can_hero_play_this_ability(hero_id, card, script):
			return true
	return false
	
func can_hero_play_this_ability(hero_index, card:WCCard, _script) -> bool:
	#TODO some abilities can be played by heroes who don't control the card
	if (card.get_controller_hero_id() == hero_index):
		return true
	return false

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

func get_my_heroes() -> Array:
	var result = []
	var network_id = get_tree().get_network_unique_id()	
	
	for hero_index in team.keys():
		var hero_data = team[hero_index]
		var hero_deck_data:HeroDeckData = hero_data["hero_data"]
		var owner_player:PlayerData = hero_deck_data.owner
		if (owner_player.network_id == network_id):
			result.append(hero_index)
	return result

#Returns player id who owns a specific hero (by hero card id)	
func get_hero_owner(hero_index)->PlayerData:
	#Errors. If hero index is out of range I can't use it
	if hero_index < 1 or hero_index> get_team_size():
		return null
			
	var hero_deck_data:HeroDeckData = get_team_member(hero_index)["hero_data"]
	return hero_deck_data.owner

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
	if (current_step == CFConst.PHASE_STEP.VILLAIN_ACTIVATES or current_step == CFConst.PHASE_STEP.VILLAIN_MINIONS_ACTIVATE):
		if not (can_i_play_this_hero(_villain_current_hero_target)):
			return true
	return false


# Additional filter for triggers,
# also see core/ScriptProperties.gd
#todo move this logic to SP.gd
func filter_trigger(
		trigger:String,
		card_scripts,
		trigger_card,
		owner_card,
		_trigger_details) -> bool:

	#if this is not an interrupt, I let it through
	if (trigger != "interrupt"):
		return true
	
	#If this *is* an interrupt but I don't have an answer, I'll fail it
	
	#if this card has no scripts to handle interrupts, we fail
	if !card_scripts:
		return false

	var event_name = _trigger_details["event_name"]
	
	if event_name == "receive_damage":
		var _tmp = 1
	
	var expected_trigger_name = card_scripts.get("event_name", "")
	
	#skip if we're expecting an interrupt but not this one
	if expected_trigger_name and (expected_trigger_name != event_name):
		return false;
	
	var expected_trigger_type = card_scripts.get("event_type", "")
	if expected_trigger_type and (expected_trigger_type != _trigger_details.get("trigger_type", "")):
		return false;
	
	var event_details = {
		"event_name":  expected_trigger_name,
		"event_type": expected_trigger_type
	}	
		
	var trigger_filters = card_scripts.get("event_filters", {})
	var event = (theStack.find_event(event_details, trigger_filters, owner_card))

	return event #note: force conversion from stack event to bool

func is_interrupt_mode() -> bool:
	return theStack.get_interrupt_mode() == GlobalScriptStack.InterruptMode.HERO_IS_INTERRUPTING
	
func interrupt_player_pressed_pass(hero_id):
	theStack.pass_interrupt(hero_id)

#TODO all calls to this method are in core which isn't good
#Need to move something, somehow
func confirm(
		owner,
		script: Dictionary,
		card_name: String,
		task_name: String,
		type := "task") -> bool:
	cfc.add_ongoing_process(self)
	var is_accepted := true
	# We do not use SP.KEY_IS_OPTIONAL here to avoid causing cyclical
	# references when calling CFUtils from SP
	if script.get("is_optional_" + type):
		_acquire_user_input_lock(owner.get_controller_player_network_id())
		var my_network_id = get_tree().get_network_unique_id()
		var is_master:bool =  (owner.get_controller_player_network_id() == my_network_id)
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
		_release_user_input_lock(owner.get_controller_player_network_id())
	cfc.remove_ongoing_process(self)	
	return(is_accepted)
	

func cleanup_post_game():
	attackers = []
	_current_enemy_attack_step = EnemyAttackStatus.NONE
	_current_encounter_step = EncounterStatus.NONE
	_current_encounter = null
	
	theStack.queue_free()
	theStack = GlobalScriptStack.new()
	self.add_child(theStack)
	
	cfc.reset_ongoing_process_stack()

	
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

func save_gamedata_to_file(path):
	var savedata = save_gamedata()
	var json = JSON.print(savedata, "\t")
	var file = File.new()
	file.open(path, File.WRITE)
	file.store_string(json)
	file.close()

#loads current game data from a json structure (rpc call to all clients)
func load_gamedata(json_data:Dictionary):
	gamesave_load_status = {}
	rpc("remote_load_gamedata",json_data)

remotesync func remote_load_game_data_finished(result:int):
	var caller_id = get_tree().get_rpc_sender_id()
	gamesave_load_status[caller_id] = result
	if (gamesave_load_status.size() == network_players.size()):
		scripting_bus.emit_signal("all_clients_game_loaded",  gamesave_load_status)


#loads current game data from a json structure
remotesync func remote_load_gamedata(json_data:Dictionary):
	var caller_id = get_tree().get_rpc_sender_id()


	var hero_data:Array = json_data["heroes"]
	
	#TODO more file integrity checks 
	#number of players doesn't match loaded data
	if (hero_data.size() != team.size()):
		rpc_id(caller_id,"remote_load_game_data_finished",CFConst.ReturnCode.FAILED)
		return 



	#phase
	phaseContainer.loadstate_from_json(json_data)
	
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
	
	phaseContainer.reset() #This reloads hero faces, etc...
	

	
	#scenario
	#TODO
			
	rpc_id(caller_id,"remote_load_game_data_finished",CFConst.ReturnCode.OK)
