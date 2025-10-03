class_name TestSuite
extends Node

enum TestStatus {
	NONE,
	PASSED,
	SKIPPED,
	FAILED,
}

#GUI components required for interaction
var phaseContainer:PhaseContainer = null
var initialized:bool = false

#All tests
var test_files:Array
var current_test:int = 0
var current_test_file:String = ""

var passed: Array = []
var failed: Array = []
var skipped: Array = []
var failed_reason: Array = []
var skipped_reason: Array = []
var finished: bool = false
var forced_status: int = TestStatus.NONE

#current tests
var initial_state:Dictionary
var end_state:Dictionary
var actions:Array
var current_action:int = 0
var current_player_id: int = 0

var game_loaded:bool = false

func _init():
	scripting_bus.connect("all_clients_game_loaded", self, "all_clients_game_loaded")
	
func _ready():
	#only server is allowed to run the main process	
	if 1 != get_tree().get_network_unique_id():
		return
				
	load_test_files()
	next_test()


#Gathers GUI objects from the game that we will be calling
func initialize_components():
	phaseContainer = gameData.phaseContainer
	initialized = true

func process(_delta: float) -> void:
	if (!initialized):
		initialize_components()
	
	#Game is still loading on some clients, do not run tests yet
	if (!game_loaded):
		return
		
	if (finished):
		return
	
	#only server is allowed to run the main process	
	if 1 != get_tree().get_network_unique_id():
		return
		
	next_action()		
	return	

#processes the next action for the current test
#If no actions remaining, check final state and load the next test
func next_action():
	#TODO need to ensure the previous action and its effects are completed before moving to the next
	#If phasecontainer is running stuff, we wait
	if phaseContainer.is_in_progress():
		return
	if (actions.size() <= current_action):
		finalize_test()
		next_test()
		return false	
 
	var my_action = actions[current_action]
	
	process_action(my_action)
	
	current_action += 1
	return

#The bulk of the GUI control to process one event	
func process_action(my_action:Dictionary):
	var player: int = my_action.get("player", 0)
	#If player is 0 we'll try to guess it from the card
	#Player 1 is the master, runing the test suite
	#Other players will receive the test request via rpc

	if (!player):
		#guessing player from action/card
		player = 1 #default
		var action_type: String = my_action.get("type", "play")
		var action_value: String = 	my_action.get("value", "")
		match action_type:
			"play":
				player = get_card_owner(action_value)
			"choose":
				player = get_current_player()
			"target":
				player = current_player_id
			"select":
				player = get_current_player()
			"next_phase":
				var hero_id = int(action_value)
				var player_data:PlayerData = gameData.get_hero_owner(hero_id)
				if (player_data):
					player = player_data.get_id()		
			"other":
				player = get_current_player()
			_:
				player = get_current_player()			

	current_player_id = player
	var network_player_id = gameData.id_to_network_id[player]
	rpc_id(network_player_id, "run_action", my_action)
	
remotesync func run_action(my_action:Dictionary):	
	#valid types: play, choose, target, select, "next_phase", other
	#For "other", valid values are TBD
	var action_type: String = my_action.get("type", "play")
	var action_value: String = 	my_action.get("value", "")
	
	if (!action_value):
		#TODO error
		return
	
	match action_type:
		"play":
			return
		"choose":
			return
		"target":
			return
		"select":
			return
		"next_phase":
			action_next_phase(action_value)
			return			
		"other":
			return
		_:
			#TODO error
			return	
	return	

func action_play(player, action_value):
	return

func action_choose(player, action_value):
	return
	
func action_target(player, action_value):
	return
	
func action_select(player, action_value):
	return

#clicked on next phase. Value is the hero id	
func action_next_phase(action_value):
	var hero_id = int(action_value) - 1
	var heroPhase:HeroPhase = phaseContainer.heroesStatus[hero_id]
	heroPhase.heroPhase_action()
	return	
	
func action_other(action_value):
	match action_value:
		_:
			#TODO error
			return
	return				

func get_current_player() -> int:
	#TODO error handling
	var player_network_id = gameData.user_input_ongoing() #TODO this is network id, should be regular id?
	var player:PlayerData = gameData.get_player_by_network_id(player_network_id)
	return player.get_id()
	
func get_card_owner(card_id_or_name:String)-> int:
	var card:WCCard = get_card(card_id_or_name)
	if (!card):
		return 0 #TODO error handling
	return card.get_controller_player_id()
	
#Find a card object (on the board, etc...)
func get_card(card_id_or_name:String)-> WCCard:
	var card_name = get_corrected_card_name(card_id_or_name)
	#TODO Search in modal windows
	
	#search on board
	var board_cards = cfc.NMAP.board.get_all_cards()
	for card in board_cards:
		if card.canonical_name == card_name:
			return card 
	#TODO search in piles
	return null
	
#Check the end state for the current test
func finalize_test():
	rpc("finalize_test_allclients", forced_status)	
	return

remotesync func finalize_test_allclients(force_status:int):
	if (force_status != TestStatus.NONE):
		match force_status:
			TestStatus.PASSED:
				passed.append(current_test_file)
			TestStatus.FAILED:
				failed.append(current_test_file)
			TestStatus.SKIPPED:
				skipped.append(current_test_file)
		return
	var current_gamestate = gameData.save_gamedata()
	if (is_element1_in_element2(end_state, current_gamestate)):
		passed.append(current_test_file)
	else:
		failed.append(current_test_file)	
	return

#card here is either a card id or a card name, we try to accomodate for both
func get_corrected_card_name (card) -> String:
	var card_name = cfc.idx_card_id_to_name.get(
		card, 
		cfc.lowercase_card_name_to_name.get(card.to_lower(), "")
	)
	return card_name
#check if all elements of dict1 can be found in dict2
#This doesn't mean the dictionaries are necessarily equal
func is_element1_in_element2 (element1, element2)-> bool:
	
	if (typeof(element1) != typeof(element2)):
		failed_reason.append (str(typeof(element1)) +" - " + str(typeof(element2)))
		return false
	
	match typeof(element1):	
		TYPE_DICTIONARY:
			for key in element1:
				if not element2.has(key):
					failed_reason.append ("missing key :" + key)
					return false
				var val1 = element1[key]
				var val2 = element2[key]
						
				#handle special cases of card names vs id	
				if (key in ["hero", "card"]):
					val1 = get_corrected_card_name(val1)
					val2 = get_corrected_card_name(val2)	
									
				if !is_element1_in_element2(val1, val2):
					return false
		TYPE_ARRAY:
			if (element1.size() > element2.size()): #Should we rather check for not equal here?
				failed_reason.append ("arrays not same size")
				return false
			var i:int = 0
			for value in element1:
				if !is_element1_in_element2(element1[i], element2[i]):
					return false
				i+=1
		TYPE_STRING:
			#we don't care for the case
			if (element1.to_lower() != element2.to_lower()):
				failed_reason.append (element1 + " - " + element2)
				return false
		_:	
			if (element1 != element2):
				failed_reason.append (str(element1) + " - " + str(element2))
				return false
	return true
	
#load list of test files from test folder
#we either load all files named in a _tests.txt file, OR all files starting with test_ in the folder
func load_test_files():
	var file:File = File.new()
	if file.file_exists("user://Test/_tests.txt"):
		file.open("user://Test/_tests.txt", File.READ)
		while file.get_position() < file.get_len():
			var line:String = file.get_line()
			if !("#" in line): #We skip comments
				test_files.append("user://Test/" + line)
	else:
		test_files = CFUtils.list_files_in_directory(
				"user://Test/", "test_", true)
	file.close()		

#Lightweight initialize remote clients with just enough data for them to run the final state comparison
remote func initialize_clients_test(details:Dictionary):
	end_state = details["end_state"]
	current_test_file = details["current_test_file"]

#Loads a single test file 	
func load_test(test_file)-> bool:
	var json_card_data:Dictionary = WCUtils.read_json_file(test_file)
	initial_state = json_card_data["init"]
	actions = json_card_data["actions"]
	end_state = json_card_data["end"]
	current_action = 0
	forced_status = TestStatus.NONE
	current_test_file = test_file
	game_loaded = false
	
	#init remote clients
	var remote_init_data = {
		"end_state" : end_state,
		"current_test_file" : current_test_file
	}
	rpc("initialize_clients_test", remote_init_data)
	
	gameData.load_gamedata(initial_state)
	return true

func all_clients_game_loaded(details = {}):
	#only server is allowed to run the main process	
	if 1 != get_tree().get_network_unique_id():
		return
			
	game_loaded = true
	for value in details.values():
		if value != CFConst.ReturnCode.OK:
			actions = [] #empty the actions stack, this will force a finalize test
			rpc("add_skipped_msg", "error loading game (wrong number of players?)") #weird that I have to send this kind of info to remote clients, ideally they would compute their own issues
			forced_status = TestStatus.SKIPPED
			return

remotesync func add_skipped_msg(msg):
	skipped_reason.append (msg)
	
#Loads the next test. If no next test, returns false	
func next_test() -> bool:
	if (test_files.size() <= current_test):
		finished = true
		rpc("save_results")
		return false
	var result = load_test(test_files[current_test])
	current_test+=1
	return result

#Save test results to an output file
remotesync func save_results():
	var file = File.new()
	var to_print:String = "total tests: " + str(test_files.size()) + "\n"
	to_print = to_print +  "###\nskipped: " + str(skipped.size()) + "\n"

	var i = 0;
	for skipped_file in skipped:
		to_print = to_print + "\t" + skipped_file + "\n"
		to_print = to_print + "\t\t" + skipped_reason[i]+ "\n"	
		i += 1	
	
		
	to_print = to_print +  "###\nfailed: " + str(failed.size()) + "\n"

	i = 0;
	for failed_file in failed:
		to_print = to_print + "\t" + failed_file + "\n"
		to_print = to_print + "\t\t" + failed_reason[i]+ "\n"	
		i += 1
	
	to_print = to_print +  "###\npassed: " + str(passed.size()) + "\n"

	for passed_file in passed:
		to_print = to_print + "\t" + passed_file + "\n"	

	var network_id = get_tree().get_network_unique_id()
	network_id = str(network_id)
	var filename = "user://test_results_" + network_id +".txt"
	
	file.open(filename, File.WRITE)
	file.store_string(to_print + "\n")
	file.close() 	
