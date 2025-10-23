# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:UNUSED_VARIABLE

class_name TestSuite
extends Node

#smaller numbers means the tests will run faster, but might lead to issues
#to visually see what a test is doing, set this value to e.g. 1.0 or 1.5
const MIN_TIME_BETWEEN_STEPS: = 0.2

enum TestStatus {
	NONE,
	PASSED,
	SKIPPED,
	FAILED,
}

const GRID_SETUP = CFConst.GRID_SETUP
const HERO_GRID_SETUP = CFConst.HERO_GRID_SETUP

#GUI components required for interaction
var phaseContainer:PhaseContainer = null
var initialized:bool = false
var text_edit:TextEdit = null

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
var test_conditions: Dictionary
var actions:Array
var current_action:int = 0
var current_player_id: int = 0

var game_loaded:bool = false

var delta:float = 0

#temporary variables to keep track of objects to interact with
var _current_selection_window = null
var _current_targeting_card = null

func _init():
	scripting_bus.connect("all_clients_game_loaded", self, "all_clients_game_loaded")
	scripting_bus.connect("selection_window_opened", self, "_selection_window_opened")
	scripting_bus.connect("card_selected", self, "_selection_window_closed")
	scripting_bus.connect("initiated_targeting", self, "_initiated_targeting")	
	create_text_edit()
		
func _ready():
	#only server is allowed to run the main process	
	if 1 != get_tree().get_network_unique_id():
		return
				
	load_test_files()
	var _next = next_test()


func create_text_edit():
	text_edit = TextEdit.new()  # Create a new TextEdit node
	text_edit.text = ""  # Set default text
	text_edit.rect_min_size = Vector2(300, 200)  # Set minimum size
	text_edit.wrap_enabled = true  # Enable text wrapping
	cfc.NMAP.board.add_child(text_edit)  # Add it to the current scene
	text_edit.anchor_left = 0.75
	text_edit.anchor_right = 1
	text_edit.anchor_top = 0.5
	text_edit.set_syntax_coloring(true)
	text_edit.add_color_override("number_color", Color(0.88, 0.88, 0.88))
	text_edit.add_color_override("function_color", Color(0.88, 0.88, 0.88))
	text_edit.add_color_override("member_variable_color", Color(0.88, 0.88, 0.88))
	text_edit.add_color_region("<", ">", Color(1,1,0))
	#text_edit.anchor_bottom = 0.5	

func announce(text:String):
	text_edit.text += text
	text_edit.text = text_edit.text	
	var last_line = text_edit.get_line_count() - 1
	text_edit.cursor_set_line(last_line)
	text_edit.center_viewport_to_cursor()

	

#Gathers GUI objects from the game that we will be calling
func initialize_components():
	phaseContainer = gameData.phaseContainer
	initialized = true

func _process(_delta: float) -> void:	
	if (!initialized):
		initialize_components()

	if phaseContainer.is_in_progress():
		return

	if cfc.NMAP.board.are_cards_still_animating():
		return	
	
	
	#Game is still loading on some clients, do not run tests yet
	if (!game_loaded):
		return
		
	if (finished):
		return
	
	#don't proceed if stack is doing stuff
	#TODO: we'll want to proceed in some cases though (HERO_IS_INTERRUPTING) ?
	if (gameData.theStack.is_processing()):
		return
	
	#only server is allowed to run the main process	
	if 1 != get_tree().get_network_unique_id():
		return

	delta += _delta
		
	next_action()		
	return	

#processes the next action for the current test
#If no actions remaining, check final state and load the next test
func next_action():
	#TODO need to ensure the previous action and its effects are completed before moving to the next
	#If phasecontainer is running stuff, we wait
	if phaseContainer.is_in_progress():
		return

	if cfc.NMAP.board.are_cards_still_animating():
		return	
		

	#bug fix. Introduced to temporize tests
	#to let actions happen
	#TODO shouldn't be needed!
	if delta < MIN_TIME_BETWEEN_STEPS:
		return
		
	if (actions.size() <= current_action):
		#if (delta < 5): 
			#crappy way to wait for current actions to finish before finalizing test.
			# Enable only if we can't find better ways to wait for animation
		#	return
		#TODO bug fix
		#currently the phaseContainer runs its stuff independently
		#of the test suite, this can lead to desyncs at the test time
		#crappy way of dealing with it is to let the phase container run a bit
		#before finalizing the test
		var expected_phase = phaseContainer.step_string_to_step_id(end_state["phase"])
		var current_phase = phaseContainer.current_step
		if ((expected_phase != current_phase) && delta < 5):
			return

		var func_return = finalize_test()
		var _next = next_test()
		return false	

	var my_action = actions[current_action]
	var action_type = my_action.get("type", "")
	
	#wait a bit if we need to choose from a selection window but that window isn't there
	if (action_type == "select"):
		if (!_current_selection_window) and delta <5:
			return
 
	if (action_type == "target"):
		if (!_current_targeting_card) and delta <5:
			return

	if (action_type == "choose"):
		if (!cfc.modal_menu) and delta <5:
			return

	#there's an issue where the offer to "pass" sometimes takes a few cycles
	if (action_type == "pass"):
		if delta <1:
			return

	delta = 0

	
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
		var action_value = 	my_action.get("value", "")
		match action_type:
			"activate":
				player = get_card_owner(action_value)
			"play":
				player = get_card_owner(action_value)
			"choose":
				player = get_current_player()
			"target":
				player = current_player_id
			"select":
				player = get_current_player()
			"next_phase",\
			"pass":
				var hero_id = int(action_value)
				var player_data:PlayerData = gameData.get_hero_owner(hero_id)
				if (player_data):
					player = player_data.get_id()		
			"other":
				player = get_current_player()
			_:
				player = get_current_player()			

	current_player_id = player
	my_action["player"] = current_player_id #This will pass the determined player id to the rpc call 
	var network_player_id = gameData.id_to_network_id[player]
	rpc_id(network_player_id, "run_action", my_action)
	
remotesync func run_action(my_action:Dictionary):	
	#valid types: play, activate, choose, target, select, pass ("next_phase" is a synonym), other
	# Play: play a card
	# activate: double click on a card to activate its ability 
	#For "other", valid values are TBD
	var action_type: String = my_action.get("type", "play")
	var action_value = 	my_action.get("value", "")
	var action_player = my_action["player"]
	
	if (!action_value):
		#TODO error
		return
	
	announce("action: " + action_type + " - " + str(action_value) + " (player " + str(action_player) +")\n")
	var action_comment = my_action.get("_comments", "")
	if (action_comment):
		announce("<" + action_comment + ">\n")
		
	match action_type:
		 #activate and play are actually the same behavior
		"activate", \
		"play":
			action_play(action_player, action_value)
			return
		"select":
			action_select(action_player, action_value)
			return
		"target":
			action_target(action_player, action_value)
			return
		"choose":
			action_choose(action_player, action_value)
			return
		"next_phase",\
		"pass":
			action_pass(action_value)
			return			
		"other":
			return
		_:
			#TODO error
			return	

func action_play(player, card_id_or_name):
	var card:WCCard = get_card(card_id_or_name)
	card.attempt_to_play()
	return

func action_select(player, action_value):
	var chosen_cards: Array = []
	if typeof(action_value) == TYPE_ARRAY:
		chosen_cards = action_value
	else:
		match action_value:
			"cancel":
				return cancel_current_selection_window()
			_:
				chosen_cards = [action_value]
	
	for i in range (chosen_cards.size()):
		chosen_cards[i] = get_corrected_card_name(chosen_cards[i])
		
	if (chosen_cards):
		if (_current_selection_window):
			_current_selection_window.select_cards_by_name(chosen_cards)
	return

func cancel_current_selection_window():
	if (_current_selection_window):
		_current_selection_window.force_cancel()
	else:
		#TODO error handling
		var _error =1
	
func action_target(player, action_value):
	var target_card = get_card(action_value)
	if (_current_targeting_card):
		_current_targeting_card.targeting_arrow.force_select_target(target_card)
	return
	
func action_choose(player, action_value):
	if !cfc.modal_menu:
		#TODO error handling
		var _error =1	
		return
	
	cfc.modal_menu.force_select_by_title(action_value)

#clicked on next phase. Value is the hero id	
func action_pass(action_value):
	var hero_id = int(action_value) - 1
	var heroPhase:HeroPhase = phaseContainer.heroesStatus[hero_id]
	var result = heroPhase.heroPhase_action()
	return	
	
func action_other(action_value):
	match action_value:
		_:
			#TODO error
			return			

func get_current_player() -> int:
	#TODO error handling
	var player_network_id = gameData.user_input_ongoing if gameData.user_input_ongoing else 1 #TODO this is network id, should be regular id?
	var player:PlayerData = gameData.get_player_by_network_id(player_network_id)
	return player.get_id()
	
func get_card_owner(card_id_or_name:String)-> int:
	var card:WCCard = get_card(card_id_or_name)
	if (!card):
		return 0 #TODO error handling
	return card.get_controller_player_id()

func get_card_from_pile(card_id_or_name:String, pile:CardContainer)-> WCCard:
	var card_name = get_corrected_card_name(card_id_or_name)
	if (!pile):
		return null
		
	var pile_cards = pile.get_all_cards()
	for card in pile_cards:
		if card.canonical_name == card_name:
			return card 
	return null	
	
#Find a card object (on the board, etc...)
func get_card(card_id_or_name:String)-> WCCard:
	var card_name = get_corrected_card_name(card_id_or_name)
	#TODO Search in modal windows?
	
	#TODO search in villain cards
	
	#search on board
	var board_cards = cfc.NMAP.board.get_all_cards()
	for card in board_cards:
		if card.canonical_name == card_name:
			return card 
		
	for i in range(gameData.get_team_size()):
		var hero_id = i+1
		
		#search in hero piles
		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var real_grid_name = grid_name + str(hero_id)	
			if "pile" == grid_info.get("type", ""):
				var pile:CardContainer = cfc.NMAP.get(real_grid_name)
				var card:WCCard = get_card_from_pile(card_id_or_name, pile)	
				if (card):
					return card		
			#no "else" here. Other case is Grid which is handled by board

		#search in hero hands
		var hand_name = "hand" + str(hero_id)
		var pile:CardContainer = cfc.NMAP.get(hand_name)
		var card:WCCard = get_card_from_pile(card_id_or_name, pile)	
		if (card):
			return card	
	
	return null
	
#Check the end state for the current test
func finalize_test():
	rpc("finalize_test_allclients", forced_status)	
	return

remotesync func finalize_test_allclients(force_status:int):
	
	#Remove crap that might still be lurking around
	cfc.cleanup_modal_menu()
	gameData.cleanup_post_game()
	_current_targeting_card = null
	
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

func sort_card_array(array):
	var result = []
	for card in array:
		card["card"] = get_corrected_card_name(card["card"])
	array.sort_custom(WCUtils, "sort_cards")		

#card here is either a card id or a card name, we try to accomodate for both
func get_corrected_card_name (card) -> String:
	var card_name = cfc.idx_card_id_to_name.get(
		card, 
		cfc.lowercase_card_name_to_name.get(card.to_lower(), "")
	)
	if !card_name:
		card_name = cfc.shortname_to_name.get(card.to_lower(), "")
	return card_name


#check if all elements of dict1 can be found in dict2
#This doesn't mean the dictionaries are necessarily equal
func is_element1_in_element2 (element1, element2, _parent_name = "")-> bool:
	
	if (typeof(element1) != typeof(element2)):
		failed_reason.append ("different types of data:" + str(typeof(element1)) +" - " + str(typeof(element2)))
		return false
	
	var parent_append = ""
	if (_parent_name):
		parent_append = _parent_name + "/"
	
	match typeof(element1):	
		TYPE_DICTIONARY:
			var ignore_order = test_conditions.get("ignore_order", [])
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
				
				if key in (ignore_order):
					if (typeof(val1) == TYPE_ARRAY and typeof(val2) == TYPE_ARRAY):
							sort_card_array(val1)
							sort_card_array(val2)
							var _tmp = 1			
				if !is_element1_in_element2(val1, val2, parent_append + key):
					return false
		TYPE_ARRAY:
			if (element1.size() > element2.size()): #Should we rather check for not equal here?
				failed_reason.append ("arrays not same size (" + _parent_name  + ")\n" + String(element1) + "\n" + String(element2))
				return false
			var i:int = 0
			for value in element1:
				if !is_element1_in_element2(element1[i], element2[i], _parent_name):
					return false
				i+=1
		TYPE_STRING:
			#we don't care for the case
			if (element1.to_lower() != element2.to_lower()):
				failed_reason.append ("(" + _parent_name + ") expected: " + element1 + " - got: " + element2)
				return false
		_:	
			if (element1 != element2):
				failed_reason.append ("(" + _parent_name + ")expected: " + str(element1) + " - got: " + str(element2))
				return false
	return true
	
#load list of test files from test folder
#we either load all files named in a _tests.txt file, OR all files starting with test_ in the folder
func load_test_files():
	var file:File = File.new()
	if file.file_exists("user://Test/_tests.txt"):
		var _file_ok = file.open("user://Test/_tests.txt", File.READ)
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
	test_conditions = details["test_conditions"]
	delta = 0

#Loads a single test file 	
func load_test(test_file)-> bool:
	announce("running test: " + test_file +"\n")
	current_action = 0
	forced_status = TestStatus.NONE
	current_test_file = test_file
	game_loaded = false
	end_state = {}

	var file:File = File.new()
	if !file.file_exists(test_file):
		skipped.append(test_file)
		skipped_reason.append("file does not exist")
		announce("skipped (file doesn't exist)\n")
		return false
				
	var json_card_data:Dictionary = WCUtils.read_json_file(test_file)
	json_card_data = WCUtils.replace_real_to_int(json_card_data)
	initial_state = json_card_data["init"]
	actions = json_card_data["actions"]
	end_state = json_card_data["end"]
	test_conditions = json_card_data.get("test_conditions", {})
	
	#init remote clients
	var remote_init_data = {
		"end_state" : end_state,
		"current_test_file" : current_test_file,
		"test_conditions" : test_conditions,
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
	announce("all tests complete, saving\n")
	var file = File.new()
	var to_print := ""
	if (failed.size()):
		to_print+= "FAILED!\n\n"
	else:
		to_print+= "SUCCESS! (passed " +String(passed.size()) + "/" + str(test_files.size()) \
		 + ", skipped " +  String(skipped.size()) + "/" + str(test_files.size())  + ")\n\n" 

	announce (to_print)
	to_print += "total tests: " + str(test_files.size()) + "\n"
	to_print +=  "###\nskipped: " + str(skipped.size()) + "\n"

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

func _initiated_targeting(_request_object = null):
	_current_targeting_card = _request_object

func _selection_window_opened(_request_object = null,details = {}):
	_current_selection_window = _request_object

func _selection_window_closed(_request_object = null,details = {}):
	_current_selection_window = null
