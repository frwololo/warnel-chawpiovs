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
	BOOST_CARDS,
	DAMAGE_OR_THREAT,
	ATTACK_COMPLETE
}
const EnemyAttackStatusStr =  [
	"NONE",
	"PENDING_INTERRUPT",
	"OK_TO_START_ATTACK",
	"PENDING_DEFENDERS",
	"BOOST_CARDS",
	"DAMAGE_OR_THREAT",
	"ATTACK_COMPLETE"
]

var _current_enemy_attack_step: int = EnemyAttackStatus.NONE

enum EncounterStatus {
	NONE,
	ABOUT_TO_REVEAL,
	PENDING_REVEAL_INTERRUPT,
	OK_TO_EXECUTE,
	PENDING_COMPLETE,
	ENCOUNTER_COMPLETE,
	ENCOUNTER_POST_COMPLETE
}


const EncounterStatusStr = [
	"NONE",
	"ABOUT_TO_REVEAL",
	"PENDING_REVEAL_INTERRUPT",
	"OK_TO_EXECUTE",
	"PENDING_COMPLETE",
	"ENCOUNTER_COMPLETE",
	"ENCOUNTER_POST_COMPLETE"
]

var _current_encounter = null #WCCard

#emit whenever something changes in the game state. This will trigger some recomputes
signal game_state_changed(details)
signal first_player_changed(details)

#Singleton for game data shared across menus and views
#network_players, indexed by network_id
var network_players := {}
var id_to_network_id:= {}
var is_multiplayer_game:bool = true

#1 indexed {hero_id: {"hero_data": HeroDeckData, "manapool" : ManaPool}}
var team := {}

var dead_heroes := []

var gamesave_load_status:= {}
var current_round :int = 1

var scenario:ScenarioDeckData
var phaseContainer: PhaseContainer #reference link to the phaseContainer
var theStack: GlobalScriptStack
var testSuite: TestSuite = null
var theAnnouncer: Announcer = null
var theGameObserver = null

# Hero that I am currently controlling
var current_local_hero_id := 1
var scripted_play_sequence:= []


#temp vars for bean counting
var _villain_current_hero_target :=1
var _first_player_hero_id := 1
var _current_enemy = null
#list of enemies with a current attack intent
var attackers: = []
#list of encounters that need to be revealed asap
var immediate_encounters: = []
var user_input_ongoing:int = 0 #ID of the current player (or remote player) doing a blocking game interraction
var _garbage:= []
var _targeting_ongoing:= false
var _desync_recovery_enabled = true

var _clients_current_activation = {}
var _clients_activation_counter = {}
var _clients_desync_start_time: int = 0


#a timer to avoid double registering a click on a target
# as a click for its abilities
var _targeting_timer:= 0.2
 
#var _systems_check_ongoing := false
#var _clients_system_status: Dictionary = {}
var _network_ack: Dictionary = {}
var _multiplayer_desync = null
var _game_over := false
var _game_started := false 

func stop_game():
	_game_started = false

func start_game():
	cfc.LOG("game starting")
	_game_started = true

func is_game_started():
	return _game_started

func is_announce_ongoing():
	return theAnnouncer and theAnnouncer.is_announce_ongoing()

func _init():
	scenario = ScenarioDeckData.new()
	theStack = GlobalScriptStack.new()
	theAnnouncer = Announcer.new()
	theGameObserver = GameObserver.new()

# Called when the node enters the scene tree for the first time.
func _ready():	
	#Signals

# Network setup
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected_ok")
	get_tree().connect("connection_failed", self, "_connected_fail")
	get_tree().connect("server_disconnected", self, "_server_disconnected")		
	
	#TODO: the attempt to lock should happen BEFORE we actually open the windows
	#scripting_bus.connect("selection_window_opened", self, "attempt_user_input_lock")
	#scripting_bus.connect("card_selected", self, "_selection_window_closed")	
	scripting_bus.connect("scripting_event_triggered", self, "_scripting_event_triggered")
	scripting_bus.connect("scripting_event_about_to_trigger", self, "_scripting_event_about_to_trigger")

	scripting_bus.connect("initiated_targeting", self, "_initiated_targeting")
	scripting_bus.connect("target_selected", self, "_target_selected")
	
	scripting_bus.connect("stack_event_deleted", self, "_stack_event_deleted")
	scripting_bus.connect("all_clients_game_loaded", self, "_all_clients_game_loaded")
	
	
	theStack.connect("script_executed_from_stack", self, "_script_executed_from_stack")
	theStack.connect("script_added_to_stack", self, "_script_added_to_stack")


	self.add_child(theStack) #Stack needs to be in the tree for rpc calls	
	self.add_child(theAnnouncer)
	self.add_child(theGameObserver)
	#scripting_bus.connect("optional_window_opened", self, "attempt_user_input_lock")
	#scripting_bus.connect("optional_window_closed", self, "attempt_user_input_unlock")	

func _all_clients_game_loaded(status):
	rpc("start_phaseContainer")
	pass

func _script_added_to_stack (script):
	theAnnouncer.announce_from_stack(script)

func _script_executed_from_stack (script):
	if script.get_first_task_name() == "enemy_attack":
		defenders_chosen()
		return
	if script.get_first_task_name() == "reveal_encounter":	
		encounter_revealed() #this forces passing to the next step

func _initiated_targeting(owner_card) -> void:
	_targeting_ongoing = true

func _target_selected(owner_card, details) -> void:	
	_targeting_ongoing = false
	
func is_targeting_ongoing():
	return _targeting_ongoing	


func end_game(result:String):
	init_save_folder()
	cleanup_post_game()	
	cfc.set_game_paused(true)
	var end_dialog:AcceptDialog = AcceptDialog.new()
	end_dialog.window_title = result
	end_dialog.add_button ( "retry", true, "retry")
	end_dialog.connect("custom_action", cfc.NMAP.board, "_retry_game")
	end_dialog.connect("confirmed", cfc.NMAP.board, "_close_game")
	cfc.NMAP.board.add_child(end_dialog)
	end_dialog.popup_centered()


#for testing
func disable_desync_recovery():
	_desync_recovery_enabled = false

func attempt_resync(result:String):
	if ! _desync_recovery_enabled:
		return
	_clients_system_status = {}	
	reload_round_savegame(current_round)
	
#	cfc.set_game_paused(true)
#	var end_dialog:AcceptDialog = AcceptDialog.new()
#	end_dialog.window_title = result
#	end_dialog.add_button ( "reload", true, "reload")
#	end_dialog.connect("custom_action", cfc.NMAP.board, "_reload_last_save")
#	end_dialog.connect("confirmed", cfc.NMAP.board, "_close_game")
#	cfc.NMAP.board.add_child(end_dialog)
#	end_dialog.popup_centered()

func targeting_happened_too_recently():
	return (_targeting_timer > 0)

func _process(_delta: float):
	cfc.ping()
	#mechanism to avoid processing
	#a target click as an action click
	if _targeting_ongoing:
		_targeting_timer = 0.2
	else:
		_targeting_timer -= _delta
		_targeting_timer = max(0, _targeting_timer)
		
	if theAnnouncer.get_blocking_announce():
		return
		
	if _game_over: 
		end_game("game over")
		_game_over = false
		return
		
	if _multiplayer_desync:
			attempt_resync("desync")
			
	play_scripted_sequence()		

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

func _selection_window_closed(request_object = null,details = {}):	
	attempt_user_input_unlock(request_object, details)
	
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
	if !testSuite:
		testSuite = TestSuite.new()
		testSuite.name = "testSuite"
		self.add_child(testSuite) #Test suite needs to be in the tree for rpc calls	
	else:
		testSuite.reset()

func registerPhaseContainer(phasecont:PhaseContainer):
	phaseContainer = phasecont

func _scripting_event_about_to_trigger(_trigger_object = null,
		trigger: String = "manual",
		_trigger_details: Dictionary = {}):
	
	match trigger:
		"card_moved_to_board":
			check_ally_limit()
	return

#emit sub _signals for convenience
func _emit_additional_signals(_trigger_object = null,
		trigger: String = "manual",
		_trigger_details: Dictionary = {}):
	match trigger:
		"card_moved_to_board":
			var card_type = _trigger_object.get_property("type_code", "")
			if card_type:
				var signal = card_type + "_moved_to_board"
				scripting_bus.emit_signal(signal, _trigger_object, _trigger_details)
				

func _scripting_event_triggered(_trigger_object = null,
		trigger: String = "manual",
		_trigger_details: Dictionary = {}):
	
	match trigger:
		"card_moved_to_board":
			_emit_additional_signals(_trigger_object, trigger, _trigger_details)	
			
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

	#Game state changed signal (to compute card costs, etc...)
	match trigger:
		"card_moved_to_board", \
				"card_played", \
				"card_token_modified",\
				"step_started" :		
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
			display_debug("shuffle villain deck after empty")
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
			display_debug("shuffle hero deck after empty:" + hero_id_str)
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
			

			#hacky way to move the current card out of the way
			#while still leaving it on the board
			if current_scheme._placement_slot:
				current_scheme._placement_slot.remove_occupying_card(current_scheme)
	
		
			var new_card = board.load_scheme(code)
		
			set_aside(current_scheme)	
				

			var func_return = new_card.execute_scripts(new_card, "reveal_side_a")
			while func_return is GDScriptFunctionState && func_return.is_valid():
				func_return = func_return.resume()			
			
			func_return = new_card.execute_scripts(new_card, "reveal")
			while func_return is GDScriptFunctionState && func_return.is_valid():
				func_return = func_return.resume()			
		
			
			return new_card
	
	return null

func check_ally_limit():
	var my_heroes = gameData.get_my_heroes()
	for hero_id in my_heroes:
		var identity_card = get_identity_card(hero_id)
		if !identity_card:
			continue #this can happen at setup time
		var ally_limit = identity_card.get_property("ally_limit", 0)
		var my_cards = cfc.NMAP.board.get_grid("allies" + String(hero_id)).get_all_cards()
		if (my_cards.size()) > ally_limit:
			identity_card.execute_scripts(identity_card, "ally_limit_rule")
		
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
		defeat()	
	
func game_state_changed():
	emit_signal("game_state_changed",{})

func init_network_players(players:Dictionary):
	for player_network_id in players:
		if is_multiplayer_game and (player_network_id != cfc.get_network_unique_id()):
				get_tree().network_peer.set_peer_timeout(player_network_id, 1000, 5000, 15000)
		var info = players[player_network_id]
		var new_player_data := PlayerData.new(info.name, info.id, player_network_id)
		network_players[player_network_id] = new_player_data 
		id_to_network_id[info.id] = player_network_id
	


func set_team_data(_team:Dictionary):
	#filter out empty slots
	var hero_count = 0;
	for hero_idx in _team:
		var hero_data:HeroDeckData = _team[hero_idx]
		if (hero_data.deck_id and hero_data.get_hero_id()):
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

func get_network_id_by_hero_id(hero_id):
	var hero_deck_data:HeroDeckData = team[hero_id]["hero_data"]
	var owner:PlayerData = hero_deck_data.owner
	return owner.network_id

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
	var err = peer.create_server(CFConst.MULTIPLAYER_PORT, 4) # Maximum of 4 peers. TODO make this a config
	if err != OK:
		return err #does this ever run?
	get_tree().set_network_peer(peer)
	return err	

func archive_save_folder(save_dir):
	var dir:Directory = Directory.new()
	var past_dir = "user://Saves/past_games/"
	dir.make_dir_recursive(past_dir)
	if !dir.dir_exists(save_dir):
		return
	if !dir.dir_exists(past_dir):
		return
	
	var files_in_save = CFUtils.list_files_in_directory(save_dir)
	if !files_in_save:
		return	
	var cur_time = Time.get_datetime_dict_from_system()
	var cur_time_str = str(cur_time["month"]) + "_" + str(cur_time["day"]) + "_" + str(cur_time["hour"]) + "_" + str(cur_time["minute"])
	dir.rename(save_dir, past_dir + cur_time_str + "/")

#we delete all existing saves of a previous game
func init_save_folder():
	var dir:Directory = Directory.new()
	var save_dir = "user://Saves/current_game/"
	archive_save_folder(save_dir)
	dir.make_dir_recursive(save_dir)
	if !dir.dir_exists(save_dir):
		#todo error handling
		var _error = 1
		return
	var files_in_save = CFUtils.list_files_in_directory(save_dir)
	for file in files_in_save:
		if file.ends_with(".json"):
			dir.remove(save_dir + file)

func get_ongoing_game():
	var dir:Directory = Directory.new()
	var save_dir = "user://Saves/current_game/"
	if !dir.dir_exists(save_dir):
		return {}
	var files_in_save:Array = CFUtils.list_files_in_directory(save_dir, "", true)
	if !files_in_save:
		return {}
	files_in_save.sort()
	var latest = files_in_save.back()
	var json = WCUtils.read_json_file(latest)
	return json
	

func save_round(round_id):
	var save_dir = "user://Saves/current_game/"
	var save_file = "round_" + str(round_id) + ".json"
	save_gamedata_to_file(save_dir + save_file)

func reload_round_savegame(round_id):
	if !cfc.is_game_master():
		return
	var save_dir = "user://Saves/current_game/"
	var file_name = "round_" + str(round_id) + ".json"
	var json = WCUtils.read_json_file(save_dir + file_name)
	if round_id >1 and !json:
		reload_round_savegame(round_id-1)
		return
	if !json:
		display_debug("no game to load, sorry")
		return
	gameData.load_gamedata(json)
			
func get_team_size():
	return team.size()

func get_team_member(id:int):
	return team[id]
		
func get_current_local_hero_id():
	return self.current_local_hero_id

#returns a list of hero ids that are currently allowed to play
#(outsde of asking them for possible interruptions)
func get_currently_playing_hero_ids():
	#TODO how do obligations fit into this ?
	
	#interruption takes precedence, if a player is interrupting,only them can interract with the game
	if is_interrupt_mode():
		return [theStack.interrupting_hero_id]
	
	#if some attacks are ongoing or enouncters are being revealed, the
	#target player is the one being returned
	if !attackers.empty():
		return [_villain_current_hero_target]
	
	if !immediate_encounters.empty():
		return [_villain_current_hero_target]
		
	if phaseContainer.current_step in [
		CFConst.PHASE_STEP.VILLAIN_ACTIVATES,
		CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER
	]:
		return [_villain_current_hero_target]
	
	#during player turn and outside of all other considerations, all heroes can play simultaneously
	if phaseContainer.current_step in [CFConst.PHASE_STEP.PLAYER_TURN, CFConst.PHASE_STEP.PLAYER_MULLIGAN, CFConst.PHASE_STEP.PLAYER_DISCARD]:
		var all = []
		for i in range (team.size()):
			all.append(i+1)
		return all
	
	#early game, we let player 1 activate stuff for setup
	if phaseContainer.current_step < CFConst.PHASE_STEP.PLAYER_TURN:
		return[1]
		
	#outside of these events, players can't play ?	
	return []
	

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
			if card.get_controller_hero_id() > 0:
				if not card.properties.get("_horizontal", false):
					card.readyme()	




func end_round():
	current_round+=1
	reset_villain_current_hero_target(true, "end_round")
	scripting_bus.emit_signal("round_ended")

func get_hero_name(hero_id):
	var hero_card = self.get_identity_card(hero_id)
	return hero_card.canonical_name

func reset_villain_current_hero_target( force_switch_ui:= true, caller = ""):
	set_villain_current_hero_target(first_player_hero_id(), force_switch_ui, caller)


func set_villain_current_hero_target(value, force_switch_ui:= true, caller:= ""):
	var previous = _villain_current_hero_target
	_villain_current_hero_target = value
	if previous!=value:
		display_debug("(gamedata) new villain target:" + get_hero_name(value) + "(called by " + caller +")")
	if force_switch_ui and previous!= value:
		#in practice this will only switch for players that control the hero
		self.select_current_playing_hero(value) 

func get_villain_current_hero_target():
	return _villain_current_hero_target

func villain_init_attackers():
	attackers = []
	attackers.append(get_villain())
	attackers.append("load_minions")

func villain_next_target(force_switch_ui:= true, caller:= "") -> int:
	var previous_value = _villain_current_hero_target
	var new_value = previous_value + 1
	var to_return = new_value
	caller += " through villain_next_target"
	if new_value > get_team_size():
		new_value = 1 #Is this the right place? Causes lots of errors otherwise...
	if new_value == first_player_hero_id():
		to_return = 0
	set_villain_current_hero_target(new_value, force_switch_ui, caller)
	return 	to_return


func all_attackers_finished():
	phaseContainer.all_enemy_attacks_finished()

func attack_prevented():
	current_enemy_finished()

func current_enemy_finished():
	attackers.pop_front()
	_current_enemy_attack_step = EnemyAttackStatus.NONE
	#rpc("remove_client_status")

func attack_is_ongoing():
	return _current_enemy_attack_step != EnemyAttackStatus.NONE

func pre_attack_interrupts_done():
	if _current_enemy_attack_step != EnemyAttackStatus.PENDING_INTERRUPT:
		display_debug("I'm being told to move to EnemyAttackStatus.OK_TO_START_ATTACK but I'm not at EnemyAttackStatus.PENDING_INTERRUPT")
		var _error = 1 #maybe this happens in network games ?
		return
	display_debug("pre attack interrupts are done, OK to start attack")	
	_current_enemy_attack_step = EnemyAttackStatus.OK_TO_START_ATTACK

func add_enemy_activation(enemy, activation_type:String = "attack", script = null, target_id = 0):
	attackers.append({"subject":enemy, "type": activation_type, "script" : script, "target_id" : target_id})

func start_activity(enemy, action, script, target_id = 0):
	if !target_id:
		target_id = _villain_current_hero_target
		
	display_debug("drawing boost cards")	
	if (enemy.get_property("type_code") == "villain"): #Or villainous?
		display_debug("villain confirmed, drawing boost cards")
		enemy.draw_boost_cards(action)
	else:
		 display_debug("not a villain, won't draw boost cards")
	var script_name
	var next_step
	match action:
		"scheme":
			script_name = "commit_scheme"
			next_step = EnemyAttackStatus.BOOST_CARDS
		"attack":
			script_name = "enemy_attack"
			next_step = EnemyAttackStatus.PENDING_DEFENDERS

	var trigger_details = {
		"additional_tags": []
	}
	if script:
		trigger_details["additional_tags"] += script.get_property(SP.KEY_TAGS, [])
		trigger_details["_display_name"] = "enemy " + action + " (" + enemy.canonical_name + " -> " + get_identity_card(target_id).canonical_name +")" 	
	var _sceng = enemy.execute_scripts(enemy, script_name,trigger_details)
	_current_enemy_attack_step = next_step


func enemy_activates() :
	var target_id = _villain_current_hero_target
	

	var attacker_data = attackers.front() if attackers else null
	if (typeof (attacker_data) == TYPE_STRING):
		match attacker_data:
			"load_minions":
				attackers += get_minions_engaged_with_hero(target_id)
				attackers.pop_front()

	if !attackers.size():
		all_attackers_finished()
		return

	if !can_proceed_activation():
		return

	#there is an enemy, we'll try to attack
	var heroZone:WCHeroZone = cfc.NMAP.board.heroZones[target_id]
	var action = "attack" if (heroZone.is_hero_form()) else "scheme"
	var script = null
	
	attacker_data = attackers.front()
	var enemy = null
	if (typeof (attacker_data) == TYPE_DICTIONARY):
		enemy = attacker_data["subject"]
		action = attacker_data["type"]
		script = attacker_data["script"]
		var override_target_id = attacker_data.get("target_id")
		if override_target_id:
			target_id = override_target_id
	else:
		enemy = attacker_data


	var status = "stunned" if (action=="attack") else "confused"
	
	#check for stun/confused
	var is_status = enemy.tokens.get_token_count(status)
	if (is_status):
		enemy.tokens.mod_token(status, -1)
		current_enemy_finished()
		return
	
	var guid = guidMaster.get_guid(enemy)
	rpc("set_client_status",  "activation", guid,  _current_enemy_attack_step)	
	#not stunned, proceed
	match _current_enemy_attack_step:
		EnemyAttackStatus.NONE:	
				#GUI announce
				var top_color = Color8(40,20,20,255)
				if action == "scheme":
					top_color = Color8(40,20,40,255)
				var announce_settings = {
					"top_text": enemy.get_property("shortname", ""),
					"bottom_text" : action,
					"top_color": top_color,
					"bottom_color": Color8(18,18,18,255),
					"bg_color" : Color8(0,0,0,0),
					"scale": 0.6,
					"duration": 2,
					"animation_style": Announce.ANIMATION_STYLE.SPEED_OUT,
					"top_texture_filename": enemy.get_art_filename(false),
					"bottom_texture_filename": get_identity_card(target_id).get_art_filename(),
				}
				theAnnouncer.simple_announce(announce_settings )
				
				#target player is the one adding the event to the stack
#				if can_i_play_this_hero(target_id):	
#					display_debug("I am the owner of hero " + str(target_id) +", I will handle the attack")			
#					theStack.create_and_add_signal("enemy_initiates_" + action, enemy, {SP.TRIGGER_TARGET_HERO : get_current_target_hero().canonical_name})
				
				#I had a race condition where if only the executing player would add a global script,
				#it could arrive before network players where at this status.
				#Making it a local script (everyone adds it) is an attempt at fixing this
				var stackEvent:SignalStackScript = SignalStackScript.new("enemy_initiates_" + action, enemy,  {SP.TRIGGER_TARGET_HERO : get_identity_card(target_id).canonical_name})
				theStack.add_script(stackEvent)
				_current_enemy_attack_step = EnemyAttackStatus.PENDING_INTERRUPT
				return
				
		EnemyAttackStatus.OK_TO_START_ATTACK:
			start_activity(enemy, action, script, target_id)
			return
		
		EnemyAttackStatus.BOOST_CARDS:
			#The "commit_scheme" or "enemy_attack" steps have set this variable,
			#this is a good way to check that activity happened
			if !enemy.activity_script:
				display_debug("can't draw boost cards yet, enemy doesn't have an activity script")
				return
			if enemy.next_boost_card_to_reveal():
				display_debug("go for one card boost reveal")
				var stackEvent = SimplifiedStackScript.new({"name": "enemy_boost"}, enemy)
				theStack.add_script(stackEvent)
			else:
				display_debug("no more card boosts, going to the next step")
				_current_enemy_attack_step = EnemyAttackStatus.DAMAGE_OR_THREAT
		
		EnemyAttackStatus.DAMAGE_OR_THREAT:
			var script_name
			match action:
				"scheme":
					script_name = "enemy_scheme_threat"
				"attack":
					script_name = "enemy_attack_damage"
						
			var stackEvent = SimplifiedStackScript.new({"name": script_name}, enemy)
			theStack.add_script(stackEvent)
			_current_enemy_attack_step = EnemyAttackStatus.ATTACK_COMPLETE
			
		EnemyAttackStatus.ATTACK_COMPLETE:
			var boost_cards = enemy.get_boost_cards(CFConst.FLIP_STATUS.FACEUP)
			for boost_card in boost_cards:
				var discard_event = WCScriptingEngine.simple_discard_task(boost_card)
				gameData.theStack.add_script(discard_event)	
			var stackEvent:SignalStackScript = SignalStackScript.new("enemy_" + action + "_happened", enemy,  {SP.TRIGGER_TARGET_HERO : get_identity_card(target_id).canonical_name})
			theStack.add_script(stackEvent)
			#scripting_bus.emit_signal("enemy_" + action + "_happened", enemy, {})
			current_enemy_finished()
			return 

	return

var _latest_activity_script = null
func set_latest_activity_script(script):
	_latest_activity_script = script

func get_latest_activity_script():
	return _latest_activity_script

func defenders_chosen():
	if _current_enemy_attack_step != EnemyAttackStatus.PENDING_DEFENDERS:
		display_debug("defenders_chosen: I'm being told that defenders have been chosen but I'm not in the PENDING_DEFENDERS state, I'm at" + EnemyAttackStatusStr[_current_enemy_attack_step])

		if _current_enemy_attack_step == EnemyAttackStatus.OK_TO_START_ATTACK:
			display_debug("defenders_chosen: I might be off by 1? Attempting to catch up")
			var attacker_data = attackers.front()
			var enemy = null
			var script = null
			var action = "attack"
			if (typeof (attacker_data) == TYPE_DICTIONARY):
				enemy = attacker_data["subject"]
				action = attacker_data["type"]
				script = attacker_data["script"]
			else:
				enemy = attacker_data
					
			start_activity(enemy, action, script)
		
		if _current_enemy_attack_step != EnemyAttackStatus.PENDING_DEFENDERS:
			display_debug("defenders_chosen: I wasn't able to fix my PENDING_DEFENDERS issue :(")
			return

	display_debug("defenders_chosen: Defenders have been chosen, moving to boost cards")
	_current_enemy_attack_step = EnemyAttackStatus.BOOST_CARDS
	return	

func set_aside(card):
	card.move_to(cfc.NMAP["set_aside"])

func retrieve_from_side_or_instance(card_id, owner_id):
	var card = cfc.NMAP["set_aside"].has_card_id(card_id)
	if card:
		return card
	card = cfc.instance_card(card_id, owner_id)
	cfc.NMAP["set_aside"].add_child(card)
	card._determine_idle_state()
	return card
	
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
	if escalation_threat:
		var villain = gameData.get_villain()
		var task = ScriptTask.new(villain, {"name": "add_threat", "amount": escalation_threat, "tags": ["villain_step_one_threat"]}, villain, {})
		task.subjects= [main_scheme]
		var stackEvent = SimplifiedStackScript.new(task)
		gameData.theStack.add_script(stackEvent)			
		#main_scheme.add_threat(escalation_threat)

func get_facedown_encounters_pile(target_id = 0) -> Pile :
	if (!target_id):
		target_id = _villain_current_hero_target
	var pile  = cfc.NMAP["encounters_facedown" + str(target_id)]
	return pile
	
func get_revealed_encounters_pile(target_id = 0) :
	if (!target_id):
		target_id = _villain_current_hero_target
	var pile  = cfc.NMAP["encounters_reveal" + str(target_id)]
	return pile
	
func get_enemies_grid(target_id = 0) -> BoardPlacementGrid :
	if (!target_id):
		target_id = _villain_current_hero_target	
	var grid  = cfc.NMAP.board.get_grid("enemies" + str(target_id))

	return grid	


func deal_encounters():
	cfc.add_ongoing_process(self, "deal_encounters")
	var finished = false
	while !finished: #loop through all heroes. see villain_next_target call below
		deal_one_encounter_to(_villain_current_hero_target)
		yield(get_tree().create_timer(1), "timeout")
		 # This forces to change the next facedown destination
		#the "false" flags prevents from tirggering UI changes
		if (!villain_next_target(false, "deal encounters")):
			finished = true

	#reset _villain_current_hero_target for cleanup	
	#it should already be at 1 here but...
	reset_villain_current_hero_target(false, "deal_encounters")
	
	#Hazard cards
	var hazard = 0		
	var all_schemes:Array = cfc.NMAP.board.get_grid("schemes").get_all_cards()
	for scheme in all_schemes:
		#we add all hazard icons	
		hazard  += scheme.get_property("scheme_hazard", 0)
	
	while hazard:
		deal_one_encounter_to(_villain_current_hero_target)
		yield(get_tree().create_timer(1), "timeout")
		villain_next_target(false, "deal encounters")
		hazard -=1
		
	#reset _villain_current_hero_target for cleanup	
	reset_villain_current_hero_target(false, "deal_encounters")
	cfc.remove_ongoing_process(self, "deal_encounters")

func deal_one_encounter_to(hero_id, immediate = false, encounter = null):
	var villain_deck:Pile = cfc.NMAP["deck_villain"]
	if !encounter:
		encounter = villain_deck.get_top_card()
	if encounter:
		var destination  =  get_facedown_encounters_pile(hero_id) 
		
		if (immediate):
			immediate_encounters.append({
				"encounter": encounter,
				"target_id" : hero_id
			})
			encounter.move_to(destination, 0) #add it to the bottom to ensure it gets chosen first
		else:
			encounter.move_to(destination)
	else:
		#this shouldn't happen as we constantly reshuffle the encounter deck as soon as it empties
		var _error = 1
		pass		

func all_encounters_finished():
	phaseContainer.all_encounters_done()
	pass

func current_encounter_finished():
	for i in immediate_encounters.size():
		if immediate_encounters[i]["encounter"] == _current_encounter:
			immediate_encounters.remove(i)
			break
	if _current_encounter and is_instance_valid(_current_encounter):
		_current_encounter.encounter_status = EncounterStatus.NONE			
	_current_encounter = null
	#rpc("remove_client_status")
	pass

#actual reveal of the current encounter
func reveal_current_encounter(target_id = 0):
	if (!target_id):
		target_id = _villain_current_hero_target
		
	#todo should we be doing something about target_id ?	
	
	if !_current_encounter:
		#this is a bug. This function should only be called when there's an encounter about to be revealed
		return


	_current_encounter.execute_scripts(_current_encounter, "reveal") 


func is_client_aligned(a, b):
	if !a or !b:
		return false
	if a["counter"] != b["counter"]:
		return false
	if a["status"] != b["status"]:
		return false
	return true
	
func is_catching_up(a, b):
	if !a:
		return true
	if !b:
		return false
	if a["counter"] < b["counter"]:
		return true
	if a["counter"] > b["counter"]:
		return false
	
	#counter is equal
	if a["status"] < b["status"]:
		return true
	return false

var _last_clients_aligned_dbg_msg = ""	
func client_aligned_or_catching_up():
	var my_id = cfc.get_network_unique_id()

	var result =  {
		"result": true,
		"catching_up": false
	}
	
	if !_clients_current_activation:
		return result
#	if _clients_current_activation.size() != network_players.size():
#		return false
	var expected_status ={
		"counter": 0,
		"status": -1
	}	
	for client_id in _clients_current_activation:
		var data = _clients_current_activation[client_id]
		if is_catching_up(expected_status, data):
			expected_status = data

	var all_aligned = true
	if _clients_current_activation.size() != network_players.size():
		all_aligned = false		
	else:
		for client_id in _clients_current_activation:
			var data = _clients_current_activation[client_id]
			if !is_client_aligned(expected_status, data):
				all_aligned = false

	if all_aligned:
		return result
	
	result["catching_up"] = true
	var my_data = _clients_current_activation.get(my_id, {})
	#if I'm catching up, allow to run

	if is_catching_up(my_data, expected_status):
		return result

	var msg = "clients are not aligned, can't proceed in activation/encounter: " + to_json(_clients_current_activation)
	if msg != _last_clients_aligned_dbg_msg:
		_last_clients_aligned_dbg_msg = msg
		display_debug(msg) 

	return false
	
remotesync func set_client_status(type, guid, value):
	var client_id = get_tree().get_rpc_sender_id()
	var status_str = ""

	
	match type:
		"activation":
			status_str = EnemyAttackStatusStr[value]
		"encounter":
			 status_str = EncounterStatusStr[value]

	var renew = false
	var existing_data = _clients_current_activation.get(client_id, {})
	if !existing_data:
		renew = true
	else:
		if existing_data["type"]!= type or existing_data["guid"]!= guid or existing_data["status"] > value:
			renew = true
	
	if renew:
		if !_clients_activation_counter.has(client_id):
			 _clients_activation_counter[client_id] = 0
		_clients_activation_counter[client_id]+= 1
						
		_clients_current_activation[client_id] = {
			"type" : type,
			"guid" : guid,
			"status" : value,
			"status_str": status_str,
			"counter" : _clients_activation_counter[client_id]
		}
	else:
		_clients_current_activation[client_id]["status"] = value
		_clients_current_activation[client_id]["status_str"] = status_str	
	
#remotesync func remove_client_status():
#	var client_id = get_tree().get_rpc_sender_id() 
#	_clients_current_activation.erase(client_id)	

#attempt to pace encounters in order to avoid race conditions
func can_proceed_encounter()-> bool:
	return can_proceed_activation()
	
func can_proceed_activation()-> bool:
	var aligned =  client_aligned_or_catching_up()
	if !aligned:
		if not self._clients_desync_start_time:
			_clients_desync_start_time = Time.get_ticks_msec()
		if Time.get_ticks_msec() - self._clients_desync_start_time > (CFConst.DESYNC_TIMEOUT * network_players.size() * 1000):
			self._clients_desync_start_time = 0
			if cfc.is_game_master():
				display_debug("clients alignment issue, attempting resync")
				save_round(current_round)
				init_desync_recover()
		return false

	self._clients_desync_start_time = 0

	if typeof(aligned) == TYPE_DICTIONARY:
		var catching_up = aligned.get("catching_up", false)
		if catching_up:
			return true

	return theStack.is_idle()

func cancel_current_encounter():
	if !_current_encounter:
		return false
	_current_encounter.move_to(cfc.NMAP["discard_villain"])
	current_encounter_finished()	

var _local_encounter_uid = 0
var _last_encounter_dbg_msg = ""		
#TODO need something much more advanced here, per player, etc...
func reveal_encounter(target_id = 0):
	if (!target_id):
		target_id = _villain_current_hero_target
	

	if immediate_encounters:
		for immediate_encounter_data in immediate_encounters:
			var immediate_encounter = immediate_encounter_data["encounter"]
			match immediate_encounter.state:
				Card.CardState.DROPPING_TO_BOARD,\
						Card.CardState.MOVING_TO_CONTAINER:
					return
	
	if immediate_encounters:
		var next = immediate_encounters.back()
		if !_current_encounter:
			_current_encounter = next["encounter"]
		if _current_encounter == next["encounter"]:
			#retrieve the correct target_id if _current_encounter is an immediate encounter
			target_id = next["target_id"]
		
	if !_current_encounter:
		var facedown_encounters:Pile = get_facedown_encounters_pile(target_id)
		_current_encounter = facedown_encounters.get_bottom_card()

	
	var current_encounter_str = "[empty]"
	if _current_encounter:
		current_encounter_str = _current_encounter.canonical_name
		var msg = "current_encounter: " + current_encounter_str + ". Status:" + EncounterStatusStr[_current_encounter.encounter_status]
		if msg != _last_encounter_dbg_msg:
			_last_encounter_dbg_msg = msg
			display_debug(msg)
	
	if !_current_encounter:
		display_debug("didn't get any encounter from the facedown pile of " + str(target_id) +", we're done here")
		all_encounters_finished()
		return

	match _current_encounter.state:
		Card.CardState.DROPPING_TO_BOARD,\
				Card.CardState.MOVING_TO_CONTAINER:
			return

	if !can_proceed_encounter():
		return
	
	var guid = guidMaster.get_guid(_current_encounter)
	rpc("set_client_status", "encounter", guid, _current_encounter.encounter_status)
	#an encounter is available, proceed
	match _current_encounter.encounter_status:
		EncounterStatus.NONE:
			#TODO might need to send a signal before that?
			var pile = get_revealed_encounters_pile(target_id)
			_current_encounter.set_is_faceup(true,false)
			_current_encounter.move_to(pile)
			#_current_encounter.execute_scripts(_current_encounter, "about_to_reveal")
			var task_event = SignalStackScript.new("about_to_reveal", _current_encounter)
			theStack.add_script(task_event)			
			_current_encounter.encounter_status = EncounterStatus.ABOUT_TO_REVEAL
			return
		EncounterStatus.ABOUT_TO_REVEAL:
			var reveal_script  = {
				"name": "reveal_encounter",
			}
			var reveal_task = ScriptTask.new(_current_encounter, reveal_script, _current_encounter, {})	
			var task_event = SimplifiedStackScript.new(reveal_task)
			theStack.add_script(task_event)
			#theStack.create_and_add_simplescript(_current_encounter, _current_encounter, reveal_script, {})
			_current_encounter.encounter_status = EncounterStatus.PENDING_REVEAL_INTERRUPT
			return
					
		EncounterStatus.OK_TO_EXECUTE:
			var pile = get_revealed_encounters_pile(target_id)
			if !pile.has_card(_current_encounter):
				#there is a somewhat valid use case here with some encounters that are moved (as part of their script) as soon as they come into play
				# (e.g. obligations). Depending on Network conditions, the "move" script might have been sent through
				#the wire already, and in that case we skip this step
				#this prevents bugs such as an obligation resolving then coming back from the discard to the encounters reveal pile
				display_debug("encounter: " + _current_encounter.canonical_name + "is not in " + pile.name + ". Assuming it has moved already")
				_current_encounter.encounter_status = EncounterStatus.PENDING_COMPLETE
				return
					
			var grid: BoardPlacementGrid = get_encounter_target_grid(_current_encounter)
			var slot: BoardPlacementSlot = grid.find_available_slot()
			if slot:
				_current_encounter.move_to(cfc.NMAP.board, -1, slot)
				display_debug("encounter: " + _current_encounter.canonical_name + " moving to PENDING_COMPLETE. Target_id " + str(target_id))
				_current_encounter.encounter_status = EncounterStatus.PENDING_COMPLETE
			else:
				push_error("encounter ERROR: Missing target grid in reval_encounters")	
		EncounterStatus.PENDING_COMPLETE:
			#there has to be a better way.... wait for a signal somehow ?
			if cfc.get_modal_menu():
				return
			display_debug("encounter: " + _current_encounter.canonical_name + " moving to ENCOUNTER_COMPLETE. Target_id " + str(target_id))
			_current_encounter.encounter_status = EncounterStatus.ENCOUNTER_COMPLETE
			return
			
		EncounterStatus.ENCOUNTER_COMPLETE:
			var target_pile = get_encounter_target_pile(_current_encounter)
			if (target_pile and !target_pile.has_card(_current_encounter)):
				display_debug("encounter: " + _current_encounter.canonical_name + " moving to pile. Target_id " + str(target_id))
				_current_encounter.move_to(target_pile)
				_current_encounter.encounter_status = EncounterStatus.ENCOUNTER_POST_COMPLETE
			else:
				display_debug("encounter: not moving : " + _current_encounter.canonical_name + ". Finishing it already. Target_id " + str(target_id))
				current_encounter_finished()
		EncounterStatus.ENCOUNTER_POST_COMPLETE:
			var target_pile = get_encounter_target_pile(_current_encounter)
			if target_pile and target_pile.has_card(_current_encounter):
				display_debug("encounter:" + _current_encounter.canonical_name + "is in its target pile. Calling for end of encounter. Target_id " + str(target_id))
				current_encounter_finished()
			return 
	return

func encounter_revealed():
	if _current_encounter.encounter_status !=EncounterStatus.PENDING_REVEAL_INTERRUPT:
		display_debug("encounter_revealed: I'm being told to move to OK_TO_EXECUTE but I'm not at PENDING_REVEAL_INTERRUPT")
		return
	display_debug("encounter_revealed: going from PENDING_REVEAL_INTERRUPT to OK_TO_EXECUTE")

	_current_encounter.encounter_status = EncounterStatus.OK_TO_EXECUTE
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
			grid_name = grid_name + str(encounter.get_controller_hero_id())
	
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(grid_name)
	
	return grid	
	
func get_encounter_target_pile (encounter):
	var typecode = encounter.properties.get("type_code", "")
	var pile_name = CFConst.TYPECODE_TO_PILE.get(typecode, "")
	
	if !pile_name:
		return null

	return cfc.NMAP.get(pile_name, null)

#what happens when events get prevented
func _stack_event_deleted(event):
	match event.get_first_task_name():
		"enemy_initiates_attack":
			attack_prevented()
#		"enemy_attack":
#			defenders_chosen()
		"reveal_encounter":	
			encounter_revealed()				

func get_villain() -> Card :
	return cfc.NMAP.board.get_villain_card()

func get_main_scheme() -> Card :
	return find_main_scheme()
	
func find_main_scheme() : 
	var cards:Array = cfc.NMAP.board.get_grid("schemes").get_all_cards()
	for card in cards:
		if "main_scheme" == card.properties.get("type_code", "false"):
			return card
	return null	
	
func get_minions_engaged_with_hero(hero_id:int):
	var results = []
	var minionsGrid:BoardPlacementGrid = get_enemies_grid(hero_id)
	if minionsGrid:
		results = minionsGrid.get_all_cards()
	return results
	
func get_identity_card(owner_id) -> Card:
	var board:Board = cfc.NMAP.board

	if !board.heroZones.has(owner_id):
		return null
	
	var heroZone:WCHeroZone = board.heroZones[owner_id]
	return heroZone.get_identity_card()	

#Returns Hero currently being targeted by the villain and his minions	
func get_current_target_hero() -> Card:
	return get_identity_card(_villain_current_hero_target)

#Adds a "group_defenders" tag to all cards that can block an attack
func compute_potential_defenders(hero_id, attacker):		
	var board:Board = cfc.NMAP.board
	var defenders = []
	
	for c in board.get_all_cards():
		if c.can_defend(): #hero_id):
			defenders.append(c)

	var modifiers = attacker.retrieve_scripts("modifiers")
	var defense_selection_modifier = modifiers.get("defense_selection", "")
	match defense_selection_modifier:
		"my_allies_if_able":
			var found_ally = false
			var to_erase = []
			for c in defenders:
				if c.get_property("type_code") == "ally" and c.get_controller_hero_id() == hero_id:
					found_ally = true
				else:
					to_erase.append(c)
			if found_ally:
				for c in to_erase:
					defenders.erase(c)
		_:
			pass

	for c in board.get_all_cards():	
		if c in defenders:
			c.add_to_group("group_defenders")
		else:
			if (c.is_in_group ("group_defenders")): c.remove_from_group("group_defenders")	


		

func character_died(card:Card, script = null):
	var character_died_definition = {
		"name": "character_died",
	}
	var trigger_details = {
		"source" : script.trigger_details.get("source", ""),
		"tags": script.get_property("tags", [])
	}
	
	var character_died_script:ScriptTask = ScriptTask.new(card, character_died_definition, card, trigger_details)
	character_died_script.subjects = [card]
	
	var task_event = SimplifiedStackScript.new(character_died_script)
	theStack.add_script(task_event)

func defeat():
	_game_over = true
	var announce_settings = {
		"text": "Defeat Defeat",
		"top_color": Color8(25,20,20,255),
		"bottom_color": Color8(18,18,18,255)
	}
	theAnnouncer.simple_announce(announce_settings, true)	

func victory():
	_game_over = true
	var announce_settings = {
		"text": "Victory Victory",
		"top_color": Color8(50,50,200, 255),
		"bottom_color": Color8(200,50,50,255)
	}
	theAnnouncer.simple_announce(announce_settings, true )
	
func first_player_hero_id():
	#TODO
	return _first_player_hero_id

func next_first_player():
	var previous = _first_player_hero_id
	_first_player_hero_id += 1
	if _first_player_hero_id > get_team_size():
		_first_player_hero_id = 1
	if _first_player_hero_id!= previous:
		emit_signal("first_player_changed", {"before": previous, "after": _first_player_hero_id})

func get_ordered_hero_id(i):
	var hero_id = first_player_hero_id() + i
	if hero_id > get_team_size():
		hero_id = hero_id - get_team_size()
	return hero_id

var _ready_for_next_sequence = true
func play_scripted_sequence():
	if !scripted_play_sequence:
		return

	if !_ready_for_next_sequence:
		return
		
	if gameData.is_targeting_ongoing() or gameData.targeting_happened_too_recently():
		return
	#we already sent a request and should be waiting for full resolution	
	if !gameData.theStack.is_player_allowed_to_click():
		return		
	

	
	_ready_for_next_sequence = false
	var next_play_event = scripted_play_sequence.pop_front()
	var subject = next_play_event["card"]
	var trigger = next_play_event["trigger"]	
		
	var trigger_details = {
		"additional_script_definition": {
			"sequence_trigger": trigger,
			"is_sequence": true,
			"sequence_is_last": (scripted_play_sequence.empty())
		} 
	}
	var func_return = subject.execute_scripts(subject, trigger, trigger_details)
	if func_return is GDScriptFunctionState: # Still working.
		func_return = yield(func_return, "completed")
			
	_ready_for_next_sequence = true

#script requests some manual triggers of cards
func start_play_sequence(cards, trigger, script):
	var owner_hero_id = WCScriptingEngine.get_hero_id_from_script(script)
	if !owner_hero_id in (self.get_my_heroes()):
		return
	for subject in cards:
		scripted_play_sequence.append({
			"card" : subject,
			"trigger" : trigger
		})

	
			

func hero_died(card:Card, script = null):
	#TODO dead heroes can't play
	dead_heroes.append(card.get_owner_hero_id())
	if (dead_heroes.size() == team.size()):
		defeat()
	else:
		#for now if one hero dies, we lose. Will see what I do about this later
		defeat()

func move_to_next_villain(current_villain):
	cfc.add_ongoing_process(self, "move_to_next_villain")
	var villains = scenario.villains
	var new_villain_data = null
	for i in range (villains.size() - 1): #-1 here because we want to get the +1 if we find it
		if (villains[i]["Name"] == current_villain.get_property("Name", "")):
			new_villain_data = villains[i+1]
	
	if !new_villain_data :
		return null

	#hacky way to move the current card out of the way
	#while still leaving it on the board
	if current_villain._placement_slot:
		current_villain._placement_slot.remove_occupying_card(current_villain)
	
	var ckey = new_villain_data["_code"] 		
	var new_card = cfc.NMAP.board.load_villain(ckey)
	current_villain.copy_tokens_to(new_card, {"exclude":["damage"]})
	for attachment in current_villain.attachments:
		if attachment.is_boost():
			continue
		attachment.attach_to_host(new_card)
		
	set_aside(current_villain)	
	var func_return = new_card.execute_scripts(new_card, "reveal")
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()			
	
	cfc.remove_ongoing_process(self, "move_to_next_villain")
	return new_card			

func villain_died(card:Card, script = null):
	if (!move_to_next_villain(card)):
		victory()
	else:	
		var announce_settings = {
			"top_color": Color8(18,18,30,255),
			"bottom_color": Color8(18,18,30,255),
			"bg_color" : Color8(0,0,0,0),
			"scale": 0.6,
			"duration": 2,
			"animation_style": Announce.ANIMATION_STYLE.SPEED_OUT,			
			"top_text": "Next Stage",
			"top_texture_filename": get_villain().get_art_filename()
		}
		theAnnouncer.simple_announce(announce_settings )			


	
#selects a hero for my interface (useful for multiplayer)
func select_current_playing_hero(hero_index):
	if (not can_i_play_this_hero(hero_index)):
		return
	var previous_hero_id = current_local_hero_id
	current_local_hero_id = hero_index
	scripting_bus.emit_signal("current_playing_hero_changed",  {"before": previous_hero_id,"after": current_local_hero_id })

func can_i_play_this_ability(card, script:Dictionary = {}) -> bool:
	var my_heroes = get_my_heroes()
	for hero_id in my_heroes:
		if can_hero_play_this_ability(hero_id, card, script):
			return true
	return false
	
func can_hero_play_this_ability(hero_index, card, _script:Dictionary = {}) -> bool:
	var card_controller_id = card.get_controller_hero_id()
	if (card_controller_id <= 0 or card_controller_id == hero_index):
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
	var network_id = cfc.get_network_unique_id()	
	
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
func get_grid_controller_hero_id(grid_name:String) -> int:
	var potential_hero_id = grid_name.right(1).to_int()
	return potential_hero_id


# Additional filter for triggers,
# also see core/ScriptProperties.gd
#todo move this logic to SP.gd
func filter_trigger(
		trigger:String,
		card_scripts,
		trigger_card,
		owner_card,
		_trigger_details) -> bool:

	#Generally speaking I don't want to trigger
	#on facedown cards such as boost cards
	#(e.g. bug with Hawkeye, Charge, and a bunch of others)
	if trigger_card and is_instance_valid(trigger_card):
		#facedown cards won't have a type_code unless they are used on the board (e.g. facedown ultron drones)
		if !trigger_card.get_property("type_code", null):
			return false
		if trigger_card.is_boost(): 
			if trigger!= "boost":
				return false
			if trigger_card!= owner_card:
				return false


	#from this point this is only checks for interrupts

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
	var event = (theStack.find_event(event_details, trigger_filters, owner_card, _trigger_details))

	return event #note: force conversion from stack event to bool

func is_interrupt_mode() -> bool:
	return theStack.is_interrupt_mode() 

func is_optional_interrupt_mode() -> bool:
	return theStack.is_optional_interrupt_mode() 
	
func is_forced_interrupt_mode() -> bool:
	return theStack.is_forced_interrupt_mode() 	
	
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
		cfc.add_modal_menu(confirm)
		confirm.prep(card_name,task_name, is_master)
		# We have to wait until the player has finished selecting an option
		yield(confirm,"selected")
		# If the player selected "No", we don't execute anything
		if not confirm.is_accepted:
			is_accepted = false
		# Garbage cleanup
		confirm.hide()
		cfc.remove_modal_menu(confirm)
		confirm.queue_free()
		_release_user_input_lock(owner.get_controller_player_network_id())
	cfc.remove_ongoing_process(self)	
	return(is_accepted)

#some gui activity is ongoing, not controlled by any player (animations, etc...)
func auto_gui_activity_ongoing() -> bool:		
	if cfc.NMAP.board.are_cards_still_animating():
		return true
		
	if is_ongoing_blocking_announce():
		return true
	
	return false	

#some gui_activity ongoing, aither player controlled or automated
func gui_activity_ongoing()-> bool:	
	# if modal user input is being requested, can't move on
	if (user_input_ongoing):
		return true
	
	if cfc.get_modal_menu():
		return true

	if auto_gui_activity_ongoing():
		return true
		
	return false


func is_ongoing_blocking_announce():
	return theAnnouncer.get_blocking_announce()	

func cleanup_post_game():
	cfc.LOG("\n###\ngameData cleanup_post_game")
	cfc.set_game_paused(true)
	attackers = []

	_clients_current_activation = {}
	_clients_activation_counter = {}	
	
	_current_enemy_attack_step = EnemyAttackStatus.NONE
	if _current_encounter and is_instance_valid(_current_encounter):
		_current_encounter.encounter_status = EncounterStatus.NONE
	_current_encounter = null
	current_round = 1
	_multiplayer_desync = null
	_clients_system_status = {}
	_villain_current_hero_target = 1
	_first_player_hero_id = 1
	theStack.flush_logs()
	flush_debug_display()
	theStack.reset()

	theGameObserver.reset()
	
	cfc.reset_ongoing_process_stack()
	cfc.flush_cache()
	guidMaster.reset()

	cfc.set_game_paused(false)

	
#saves current game data into a json structure	
func save_gamedata() -> Dictionary:
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
	
	#other stuff
	json_data["round"] = current_round
	
	#encounters state
	json_data["encounters"] = {
		"immediate_encounters": replace_cards_to_cardids(immediate_encounters)
	}
	if _current_encounter:
		json_data["encounters"]["current_encounter"] = replace_cards_to_cardids(_current_encounter)
	

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
	json_data = WCUtils.replace_real_to_int(json_data)
	gamesave_load_status = {}
	rpc("remote_load_gamedata",json_data)

remotesync func remote_load_game_data_finished(result:int):
	var caller_id = get_tree().get_rpc_sender_id()
	gamesave_load_status[caller_id] = result
	if (gamesave_load_status.size() == network_players.size()):
		scripting_bus.emit_signal("all_clients_game_loaded",  gamesave_load_status)


#loads current game data from a json structure
remotesync func remote_load_gamedata(json_data:Dictionary):
	var previous_pause_state = cfc.game_paused
	cfc.set_game_paused(true)
	var caller_id = get_tree().get_rpc_sender_id()

	#TODO sanity check of the save file
	cleanup_post_game()
	
	current_round = json_data.get("round", 1)

	var hero_data:Array = json_data["heroes"]
	
	
	team = {}


	#phase
	phaseContainer.loadstate_from_json(json_data)
	
	#hero Deck data	
	var _team:Dictionary = {}
	for i in range(hero_data.size()):
		var saved_item:Dictionary = hero_data[i]
		var hero_deck_data: HeroDeckData = HeroDeckData.new()
		#if owner isn't set in the save game, we force it to 1 hero per player
		var default_owner_id = (i % gameData.network_players.size() ) + 1
		saved_item["herodeckdata"]["owner"] = 	int(saved_item["herodeckdata"].get("owner", default_owner_id ))
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

	#encounters
	var encounter_data = json_data.get("encounters", {})
	if encounter_data:
		var immediate = encounter_data.get("immediate_encounters", null)
		if immediate:
			immediate_encounters = replace_cardids_to_cards(immediate)
		var current = encounter_data.get("current_encounter", "")
		if current:
			_current_encounter = replace_cardids_to_cards(current)
	
	
	#This reloads hero faces, etc...
	#we don't start the phaseContainer just yet, we'll wait for other players to be ready
	phaseContainer.reset(false) 


	
	#scenario
	#TODO
	cfc.set_game_paused(previous_pause_state)
	assign_starting_hero()		
	rpc_id(caller_id,"remote_load_game_data_finished",CFConst.ReturnCode.OK)

remotesync func start_phaseContainer():
	phaseContainer.start_current_step()

func display_debug(msg, prefix = ""):
	if(phaseContainer and is_instance_valid(phaseContainer)):
		phaseContainer.display_debug(msg, prefix)

	print_debug(prefix + msg)

func _player_connected():
	pass
	
func _player_disconnected():
	pass
	
func _connected_ok():
	pass
	
func _connected_fail():
	pass

func disconnect_from_network():
	#var network_id = cfc.get_network_unique_id()
	get_tree().network_peer = null
	network_players = {}
	id_to_network_id = {}

func _server_disconnected():
	display_debug("SERVER DISCONNECTED")
	disconnect_from_network()
	cleanup_post_game()
	if testSuite and is_instance_valid(testSuite):
		testSuite.finished = true
	get_tree().change_scene("res://src/wc/MainMenu.tscn")
	
#TODO check for game integrity, save game for undo/save, etc...
func systems_check():
	cfc.LOG ("initiated systems check")
	_clients_system_status[cfc.get_network_unique_id()] = "pending"
	rpc("clients_send_system_status")	
#	pass
#	initiate_network_ack("get_my_system_status")

func init_desync_recover():
	_multiplayer_desync = true
	var announce_settings = {
		"top_text": "DESYNC :(",
		"bottom_text" : "DESYNC :(",
		"top_color": Color8(0,0,0,0),
		"bottom_color": Color8(0,0,0,0),
		"bg_color" : Color8(0,0,0,0),
		"duration": 5,
		"animation_style": Announce.ANIMATION_STYLE.SLOW_BLINK,
		"_forced" : true
	}
	theAnnouncer.simple_announce(announce_settings )

func finalize_get_my_system_status(all_status):
	var my_status = get_my_system_status()
	if cfc.is_game_master():
		save_round(current_round -1 ) #save the current round for a potential rollback
	
	for k in all_status:
		var other_status = all_status[k]
		if !(WCUtils.json_equal(my_status, other_status)):
			cfc.LOG("{error} Desync at Systems Check Step")
			cfc.LOG("My Status:")
			cfc.LOG_DICT(my_status)
			cfc.LOG("Their Status:{" +str(k) +"}")
			cfc.LOG_DICT(other_status)			
			init_desync_recover()			
			return false
	return true

func get_my_system_status() -> Dictionary:
	var board_status = save_gamedata()
	var guid_status = guidMaster.get_guids_check_data()

	#reduces bandwidth by only sending hash values for comparison
	if (CFConst.SYSTEMS_CHECK_HASH_ONLY):
		var board_hash = WCUtils.ordered_hash(board_status)
		var guid_hash = WCUtils.ordered_hash(guid_status)
		board_status = board_hash
		guid_status = guid_hash
			
	var status = {
		"board": board_status,
		"guids": guid_status
	}
	
	if (CFConst.SYSTEMS_CHECK_HASH_ONLY):
		display_debug("SYSTEMS CHECK: " + to_json(status))
	
	return status


var _clients_system_status:= {}

remotesync func receive_system_status(status:Dictionary):
	var client_id = get_tree().get_rpc_sender_id() 	
	_clients_system_status[client_id] = status
	cfc.LOG ("received status from" + str(client_id))
	if _clients_system_status.size() == gameData.network_players.size():
		var status_ok = finalize_get_my_system_status(_clients_system_status)
		if status_ok:
			_clients_system_status = {} #reset just in case
		else:
			if !cfc.is_game_master():
				#cleanup anyway if we're a client and hope that the master will handle it
				_clients_system_status = {} #reset just in case
			pass
			#TODO handle desync

remotesync func clients_send_system_status():
	var client_id  = get_tree().get_rpc_sender_id() 
	var my_status = get_my_system_status()
	rpc_id(client_id, "receive_system_status", my_status)


func pending_network_ack():
	if _clients_system_status:
		return true
	return false

func flush_debug_display():
	if (phaseContainer and is_instance_valid(phaseContainer)):
		phaseContainer.flush_debug_display()


func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		cfc.set_game_paused(true)
		#init_save_folder()


func replace_cards_to_cardids (script_definition):
	var result
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				result[key] = replace_cards_to_cardids(script_definition[key])
		TYPE_ARRAY:	
			result = []
			for value in script_definition:
				result.append(replace_cards_to_cardids(value))
		TYPE_OBJECT:
			if (script_definition is Card):
				result = script_definition.canonical_id
			else:
				result = script_definition	
		_:
			result = script_definition
	return result;	
	
func replace_cardids_to_cards (script_definition):
	var result
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				result[key] = replace_cardids_to_cards(script_definition[key])
		TYPE_ARRAY:	
			result = []
			for value in script_definition:
				result.append(replace_cardids_to_cards(value))
		TYPE_STRING:
			if cfc.get_card_by_id(script_definition):
				result = cfc.NMAP.board.find_card_by_name(script_definition)
			else:
				result = script_definition
		_:
			result = script_definition
	return result;
