# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:UNUSED_VARIABLE
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name TestSuite
extends Node

#smaller numbers means the tests will run faster, but might lead to issues
#to visually see what a test is doing, set this value to e.g. 1.0 or 1.5
# note: 0.1 has failures
#Note this gets modified to 0.2 for speedy tests 
# if adapt_speed_to_number_of_tests is set to true
var min_time_between_steps: float = 2
const adapt_speed_to_number_of_tests := true
const sped_up_time_between_steps: float = 0.2

var time_between_tests = 0.3 #waiting between tests to clean stuff up
#long amount of time to wait if the game state is not the one we expect
const long_wait_time: = 2 #below 2 sec fails for multiplayer
#same as above but for events that require a shorter patience time
const short_wait_time: = 0.4 #below 0.4 has had failures formultiplayer
#amount of time to wait if the test explicitely requests it
const max_wait_time: = 2
const shorten_animations = true
const STOP_AFTER_FIRST_FAILURE = true
const ANNOUNCE_VERBOSE = false

var start_time = 0
var end_time = 0

enum TestStatus {
	NONE,
	PASSED,
	SKIPPED,
	FAILED,
}

var count_delays = {}


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
var fail_details: Array = []

var skipped_reason: Array = []
var finished: bool = false
var forced_status: int = TestStatus.NONE

#current tests
var initial_state:Dictionary
var end_state:Dictionary
var test_conditions: Dictionary
var actions:Array
var current_action:int = 0
var current_playing_hero_id: int = 0

var game_loaded:bool = false

var delta:float = 0

#temporary variables to keep track of objects to interact with
var _current_selection_window = null
var _current_targeting_card = null
var _current_targeted_card = null
var _action_ongoing = false

var _allclients_finalized: = {}

#for internal statistics to find slow stuff
func count_delay(_name):
	if !count_delays.has(_name):
		count_delays[_name] = 0

	count_delays[_name] += 1	
		

func _init():
	scripting_bus.connect("all_clients_game_loaded", self, "all_clients_game_loaded")
	scripting_bus.connect("selection_window_opened", self, "_selection_window_opened")
	scripting_bus.connect("card_selected", self, "_selection_window_closed")
	scripting_bus.connect("selection_window_canceled", self, "_selection_window_closed")
	scripting_bus.connect("initiated_targeting", self, "_initiated_targeting")	
	create_text_edit()

func reset_between_tests():
	#force close any open window:
	cancel_current_selection_window()
	
	gameData.cleanup_post_game()
	current_test_file= ""
	forced_status = TestStatus.NONE
	
	#current tests
	initial_state = {}
	end_state = {}
	test_conditions = {}
	actions = []
	current_action= 0
	current_playing_hero_id = 0

	game_loaded = false

	delta = 0

	#temporary variables to keep track of objects to interact with
	_current_selection_window = null
	_current_targeting_card = null
	_current_targeted_card = null
	_action_ongoing = false	
	
func reset():
	start_time = Time.get_ticks_msec()
	end_time = 0
	if text_edit:
		text_edit.text = ""

	count_delays = {}
	reset_between_tests()

	test_files = []
	current_test = 0


	passed = []
	failed = []
	skipped = []
	failed_reason = []
	fail_details = []

	skipped_reason = []
	finished = false

		
	if 1 != get_tree().get_network_unique_id():
		return
		
	gameData.theAnnouncer.skip_announcer()			
	load_test_files()
	var _next = next_test()
		
func _ready():
	cfc.connect("json_parse_error", self, "_loading_error")	
	reset()

func _loading_error(msg):
	text_edit.text = "ERROR: " + msg + "\n"
	

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
	_reposition_text_edit()
	#text_edit.anchor_bottom = 0.5	

func _reposition_text_edit():
	var other_text = gameData.phaseContainer.text_edit
	if other_text and other_text.visible:
		text_edit.anchor_left = 0.5
		text_edit.anchor_right = 0.9
		text_edit.anchor_top = 0
		text_edit.anchor_bottom = 0.2

func announce(text:String, include_test_number:= true):
	_reposition_text_edit()
	if include_test_number:
		if !ANNOUNCE_VERBOSE and not "running" in text:
			return
		text = str(current_test) + "/"+ str(test_files.size()) +"-" + text
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
		count_delay("phaseContainer")
		return

	if cfc.NMAP.board.are_cards_still_animating():
		count_delay("cards_animating")	
		return	
	
	
	#Game is still loading on some clients, do not run tests yet
	if (!game_loaded):
		return
		
	if (finished):
		return
	
	if (_action_ongoing):
		return	
		
	#don't proceed if stack is doing stuff
	#TODO: we'll want to proceed in some cases though (HERO_IS_INTERRUPTING) ?
	if (gameData.theStack.is_processing()):
		count_delay("stack")			
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
	if delta < min_time_between_steps:
		return
		
	if (actions.size() <= current_action):
#		if (delta < time_between_tests): 
#			#crappy way to wait for current actions to finish before finalizing test.
#			# Enable only if we can't find better ways to wait for animation
#			return
		#TODO bug fix
		#currently the phaseContainer runs its stuff independently
		#of the test suite, this can lead to desyncs at the test time
		#crappy way of dealing with it is to let the phase container run a bit
		#before finalizing the test
		var expected_phase = phaseContainer.step_string_to_step_id(end_state["phase"])
		var current_phase = phaseContainer.current_step
		if ((expected_phase != current_phase) && delta < long_wait_time):
			count_delay("expected_phase")
			return
			
		game_loaded = false
		var func_return = finalize_test()
		return false	

	var my_action = actions[current_action]
	var action_type = my_action.get("type", "")
	var action_value = my_action.get("value", "")
	
	#wait a bit if we need to choose from a selection window but that window isn't there
	if (action_type == "select"):
		if (!_current_selection_window) and delta <long_wait_time:
			count_delay("action_select")
			return
 
	if (action_type == "target"):
		if (!_current_targeting_card) and delta <long_wait_time:
			count_delay("action_target")
			return

	if (action_type == "choose"):
		if (!cfc.get_modal_menu()) and delta <long_wait_time:
			count_delay("action_choose")
			return

	#there's an issue where the offer to "pass" sometimes takes a few cycles
	if (action_type == "pass"):
		var hero_id = int(action_value)
		var heroPhase:HeroPhase = phaseContainer.heroesStatus[hero_id-1]
		if (heroPhase.get_label_text()!="PASS" and delta <short_wait_time):
			count_delay("action_pass")
			return
	
	if (action_type == "next_phase"):
		var hero_id = int(action_value)
		var heroPhase:HeroPhase = phaseContainer.heroesStatus[hero_id-1]
		if (!heroPhase.can_hero_phase_action() and delta <long_wait_time):
			count_delay("action_nextphase")
			return
			
	if (action_type == "play"):
		var card = get_card(action_value) 
		if card.check_play_costs() != CFConst.CostsState.OK and delta <long_wait_time:
			count_delay("action_play")
			return			

	if (action_type == "other"):
		match action_value:
			"wait_for_interrupt":
				if (!gameData.is_interrupt_mode() and delta <max_wait_time):
					count_delay("action_wait_for_interrupt")
					return			
			"wait_for_player_turn":
				if (phaseContainer.current_step != CFConst.PHASE_STEP.PLAYER_TURN and delta <max_wait_time):
					count_delay("action_wait_for_player_turn")
					return
			"wait_a_bit":
				if (delta < max_wait_time):
					count_delay("action_wait_a_bit")
					return					

	delta = 0

	#look ahead (targeting, etc...)
	if actions.size() > current_action + 1:
		var next_action = actions[current_action + 1]
		var next_action_type = next_action.get("type", "")
		var next_action_value = next_action.get("value", "")
		match next_action_type:
			"target":
				rpc("set_upcoming_target", next_action_value)			
	
	process_action(my_action)
	
	current_action += 1

	#look ahead (messaging)
	if actions.size() > current_action:
		var next_action = actions[current_action]
		var next_action_type = next_action.get("type", "")
		var next_action_value = next_action.get("value", "")	
		announce("upcoming: " + next_action_type + " - " + str(next_action_value) + ")\n")
	return

#The bulk of the GUI control to process one event	
func process_action(my_action:Dictionary):
	var hero: int = int(my_action.get("hero", 0))
	#If hero is 0 we'll try to guess it from the card
	#hero 1 belongs to the master player, runing the test suite
	#Other heroes will receive the test request via rpc

	if (!hero):
		#guessing hero from action/card
		hero = 1 #default
		var action_type: String = my_action.get("type", "play")
		var action_value = 	my_action.get("value", "")
		match action_type:
			"activate":
				hero = get_card_owner_hero_id(action_value)
			"play":
				hero = get_card_owner_hero_id(action_value)
			"choose":
				hero = get_default_hero()
			"target":
				hero = current_playing_hero_id
			"select":
				hero = get_default_hero()
			"next_phase",\
			"pass":
				hero = int(action_value)
				
	
			"other":
				hero = get_default_hero()
			_:
				hero = get_default_hero()			

	current_playing_hero_id = hero
	my_action["hero"] = current_playing_hero_id #This will pass the determined hero id to the rpc call 
	var network_player_id = get_hero_player_network_owner(current_playing_hero_id)
	_action_ongoing = true
	rpc_id(network_player_id, "run_action", my_action)

func get_hero_player_network_owner(hero_id):
	var player = 1
	var player_data:PlayerData = gameData.get_hero_owner(hero_id)
	if (player_data):
		player = player_data.get_id()		
	return gameData.id_to_network_id[player]
	
mastersync func action_complete():
	_action_ongoing = false
	
remotesync func run_action(my_action:Dictionary):	
	#valid types: play, activate, choose, target, select, pass ("next_phase" is a synonym), other
	# Play: play a card
	# activate: double click on a card to activate its ability 
	#For "other", valid values are TBD
	var action_type: String = my_action.get("type", "play")
	var action_value = 	my_action.get("value", "")
	var action_hero = my_action["hero"]
	
	if (!action_value):
		#TODO error
		return
	
	announce("action: " + action_type + " - " + str(action_value) + " (hero " + str(action_hero) +")\n")
	var action_comment = my_action.get("_comments", "")
	if (action_comment):
		announce("<" + action_comment + ">\n")
	
	if gameData.get_current_local_hero_id() != action_hero:
		gameData.select_current_playing_hero(action_hero)
		
	match action_type:
		 #activate and play are actually the same behavior
		"activate":
			action_activate(action_hero, action_value)
		"play":
			action_play(action_hero, action_value)
		"select":
			action_select(action_hero, action_value)
		"target":
			action_target(action_hero, action_value)
		"choose":
			action_choose(action_hero, action_value)
		"next_phase",\
		"pass":
			action_pass(action_hero)			
		"other":
			action_other(action_hero)
		_:
			#TODO error
			var _error = 1
	rpc_id(1, "action_complete")
	return

func action_other(action_value):
	match action_value:
		"gain_control":
			finished = true #forces pause the test suite to give user control

func action_play(hero_id, card_id_or_name):
	var card:WCCard = get_card(card_id_or_name)
	card.attempt_to_play()
	return
	
func action_activate(hero_id, card_id_or_name):
	return action_play(hero_id, card_id_or_name)

func action_select(hero_id, action_value):
	var chosen_cards: Array = []
	if typeof(action_value) == TYPE_ARRAY:
		chosen_cards = action_value
	else:
		match action_value:
			"cancel":
				return cancel_current_selection_window()
			_:
				chosen_cards = [action_value]
	
	if !is_instance_valid(_current_selection_window):
		var _error = 1
		_current_selection_window = null
	
	for i in range (chosen_cards.size()):
		chosen_cards[i] = get_corrected_card_id(chosen_cards[i])
		
	if (chosen_cards):
		if (_current_selection_window):
			_current_selection_window.select_cards_by_name(chosen_cards)

	_current_selection_window = null
	return

func cancel_current_selection_window():
	if !is_instance_valid(_current_selection_window):
		var _error = 1
		_current_selection_window = null
			
	if (_current_selection_window):
		_current_selection_window.force_cancel()
		_current_selection_window = null
	else:
		#TODO error handling
		var _error =1
	
func action_target(hero_id, action_value):
	var target_card = get_card(action_value)

	if (_current_targeting_card):
		_current_targeting_card.targeting_arrow.force_select_target(target_card)
	return
	
func action_choose(hero_id, action_value):
	if !cfc.get_modal_menu():
		#TODO error handling
		var _error =1	
		return
	
	cfc.get_modal_menu().force_select_by_title(action_value)

#clicked on next phase. Value is the hero id	
func action_pass(hero_id):
	var heroPhase:HeroPhase = phaseContainer.heroesStatus[hero_id -1]
	var result = heroPhase.heroPhase_action()
	return		

func get_default_hero() -> int:
	#TODO error handling
	return 1
	
func get_card_owner_hero_id(card_id_or_name:String)-> int:
	var card:WCCard = get_card(card_id_or_name)
	if (!card):
		return 0 #TODO error handling
	return card.get_controller_hero_id()

func get_card_from_pile(card_id_or_name:String, pile:CardContainer):
	var card_id = get_corrected_card_id(card_id_or_name)
	if (!pile):
		return null
		
	var pile_cards = pile.get_all_cards()
	for card in pile_cards:
		if !is_instance_valid(card):
			continue
		if card.canonical_id == card_id:
			return card 
	return null	
	
#Find a card object (on the board, etc...)
func get_card(card_id_or_name:String):
	var card_id = get_corrected_card_id(card_id_or_name)
	#TODO Search in modal windows?
	
	#TODO search in villain cards
	
	#search on board
	var board_cards = cfc.NMAP.board.get_all_cards()
	for card in board_cards:
		if !is_instance_valid(card):
			continue
		if card.canonical_id == card_id:
			return card 
		
	for i in range(gameData.get_team_size()):
		var hero_id = i+1

		#search in hero ghosthands in priority
		var hand_name = "ghosthand" + str(hero_id)
		var pile:CardContainer = cfc.NMAP.get(hand_name)
		var card:WCCard = get_card_from_pile(card_id_or_name,  pile)	
		if (card and is_instance_valid(card)):
			return card	

		#search in hero hands
		hand_name = "hand" + str(hero_id)
		pile = cfc.NMAP.get(hand_name)
		card = get_card_from_pile(card_id_or_name, pile)	
		if (card and is_instance_valid(card)):
			return card	
		
		#search in hero piles
		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var real_grid_name = grid_name + str(hero_id)	
			if "pile" == grid_info.get("type", ""):
				pile = cfc.NMAP.get(real_grid_name)
				card = get_card_from_pile(card_id_or_name, pile)	
				if (card and is_instance_valid(card)):
					return card		
			#no "else" here. Other case is Grid which is handled by board


	
	return null
	
#Check the end state for the current test
func finalize_test():
	rpc("finalize_test_allclients", forced_status)	
	return

mastersync func test_finalized(result):
	var client_id = get_tree().get_rpc_sender_id() 
	_allclients_finalized[client_id] = result
	if _allclients_finalized.size() == gameData.network_players.size():
		for id in _allclients_finalized:
			var success = _allclients_finalized[id]
			if success == TestStatus.FAILED and STOP_AFTER_FIRST_FAILURE:
				current_test = test_files.size()
				announce("failed one test, ABORTING EARLY\n", false)
		_allclients_finalized = {}
		var _next = next_test()

remotesync func finalize_test_allclients(force_status:int):
	var result = force_status
	
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
		result = TestStatus.PASSED
	else:
		failed.append(current_test_file)
		self.fail_details.append("***expected:\n" + to_json(end_state) + "\n***Actual:\n" + to_json(current_gamestate))	
		result = TestStatus.FAILED
		
	#Remove crap that might still be lurking around
	reset_between_tests()
	rpc_id(1, "test_finalized", result)

	return

func sort_card_array(array):
	var result = []
	for card in array:
		card["card"] = get_corrected_card_id(card["card"])
	array.sort_custom(WCUtils, "sort_cards")		

#card here is either a card id or a card name, we try to accomodate for both
func get_corrected_card_id (card) -> String:
	return cfc.get_corrected_card_id(card)


func _get_display_name(element):
	var display1 = cfc.get_card_name_by_id(element)
	if display1:
		return display1
	return element

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
				if (key in ["hero", "card", "host"]):
					val1 = get_corrected_card_id(val1)
					val2 = get_corrected_card_id(val2)	
				
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
				failed_reason.append ("(" + _parent_name + ") expected: "\
				 	+ _get_display_name(element1) + " - got: " + _get_display_name(element2))
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
	if file.file_exists("res://Test/_tests.txt"):
		var _file_ok = file.open("res://Test/_tests.txt", File.READ)
		while file.get_position() < file.get_len():
			var line:String = file.get_line()
			if !("#" in line): #We skip comments
				test_files.append("res://Test/" + line)	
	if file.file_exists("user://Test/_tests.txt"):
		var _file_ok = file.open("user://Test/_tests.txt", File.READ)
		while file.get_position() < file.get_len():
			var line:String = file.get_line()
			if !("#" in line): #We skip comments
				test_files.append("user://Test/" + line)
	if !test_files:
		test_files = CFUtils.list_files_in_directory(
				"res://Test/", "test_", true)
		test_files += (CFUtils.list_files_in_directory(
				"user://Test/", "test_", true))

	if (adapt_speed_to_number_of_tests) and (test_files.size() >= 5) :
		min_time_between_steps = sped_up_time_between_steps
	file.close()		

#Lightweight initialize remote clients with just enough data for them to run the final state comparison
remote func initialize_clients_test(details:Dictionary):
	end_state = details["end_state"]
	current_test_file = details["current_test_file"]
	test_conditions = details["test_conditions"]
	delta = 0
	if !cfc.is_game_master():
		announce("running test: " + current_test_file+"\n")


func test_integrity(json_card_data) -> Array:
	var errors = []
	if !json_card_data.has("init"):
		errors.append("missing init section")
	if !json_card_data.has("actions"):
		errors.append("missing actions section")	
	if !json_card_data.has("end"):
		errors.append("missing end section")

	if errors:
		return errors
	
	for section_name in ["init", "end"]:
		var section = json_card_data[section_name]
		var board = section["board"]
		for pile in board:
			var lc_name = pile.to_lower()
			if lc_name.begins_with("identity"):
				var identity_data = board[pile]
				if identity_data.size() != 1:
					errors.append("identity data incorrect")
	return errors

#Loads a single test file 	
func load_test(test_file)-> bool:
	current_test_file = test_file
	var file:File = File.new()
	if !file.file_exists(test_file):
		skipped.append(test_file)
		skipped_reason.append("file does not exist")
		announce("skipped (file doesn't exist)\n")
		return false
				
	var json_card_data:Dictionary = WCUtils.read_json_file(test_file)
	if !json_card_data:
		skipped.append(test_file)
		skipped_reason.append("script error")
		announce("skipped (script error)\n")		
		return false
	json_card_data = WCUtils.replace_real_to_int(json_card_data)
	
	var integrity_errors = test_integrity(json_card_data)
	if integrity_errors:
		var integrity_errors_str = ""
		for error in integrity_errors:
			integrity_errors_str+= error + " - "
		skipped.append(test_file)
		skipped_reason.append("script error - data integrity" + integrity_errors_str)
		announce("skipped (data integrity)\n")		
		return false		
	
	if gameData.is_multiplayer_game:
		var heroes = json_card_data["init"]["heroes"]
		if heroes.size() < 2:
			skipped.append(test_file)
			skipped_reason.append("multiplayer game - skip 1P test")
			return false
	
	announce("running test: " + test_file +"\n")	
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
	gameData.load_gamedata(initial_state)
	rpc("initialize_clients_test", remote_init_data)
	
	return true

func set_card_speeds():
	if (!shorten_animations):
		return
	var cards = get_tree().get_nodes_in_group("cards")
	for card in cards:
		card.in_hand_tween_duration = 0.01
		card.reorganization_tween_duration = 0.01
		card.focus_tween_duration = 0.01
		card.to_container_tween_duration = 0.01
		card.pushed_aside_tween_duration = 0.01
		card.to_board_tween_duration = 0.01
		card.on_board_tween_duration = 0.01
		card.dragged_tween_duration = 0.01

func all_clients_game_loaded(details = {}):
	#increase speed
	set_card_speeds()
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
	yield(get_tree().create_timer(time_between_tests), "timeout")
	reset_between_tests()
	if (test_files.size() <= current_test):
		finished = true
		rpc("save_results")
		return false
	var found = false
	while !found and current_test < test_files.size():
		current_test+=1		
		found = load_test(test_files[current_test-1])
	if (!found):
		finished = true
		rpc("save_results")
		return false

	return found

#Save test results to an output file
remotesync func save_results():
	end_time = Time.get_ticks_msec()
	
	var delta_time_sec:float = (end_time - start_time) /1000
	var delta_time_min = stepify(delta_time_sec/60.0, 0.01)
	var divider = test_files.size() if test_files.size() else 1
	var time_per_test:float = stepify(delta_time_sec / divider , 0.1)
	
	announce("all tests complete, saving\n", false)
	announce("total time:" + str(delta_time_min) + " mins (" + str(time_per_test) + " secs per test)\n", false)
	var file = File.new()
	var to_print := ""
	if (failed.size()):
		to_print+= "FAILED!\n\n"
	else:
		to_print+= "SUCCESS! (passed " +String(passed.size()) + "/" + str(test_files.size()) \
		 + ", skipped " +  String(skipped.size()) + "/" + str(test_files.size())  + ")\n\n" 

	announce (to_print, false)
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

	for fail_detail in fail_details:
		to_print +=  fail_detail + "\n"	

	var player = gameData.get_player_by_network_id(get_tree().get_network_unique_id())
	var player_id = player.get_id()
	var filename = "user://test_results_" + str(player_id) +".txt"
	
	file.open(filename, File.WRITE)
	file.store_string(to_print + "\n")
	file.close() 	

remotesync func set_upcoming_target(value:String):
	_current_targeted_card = get_card(value)

func _initiated_targeting(_request_object = null):
	_current_targeting_card = _request_object
	
	#is_instance_valid_check below:
	#I've had cases where the wrong target was selected (race condition somewhere 
	#when tests run fast),leading to issues
	#Since this is only needed for cosmetics (graphically showing the arrow pointing at the right target),
	#skipping if the target is invalid doesn't matter too much
	if (_current_targeted_card):
		_current_targeting_card.targeting_arrow.set_destination(_current_targeted_card.global_position + Vector2(70, 70))

func _selection_window_opened(_request_object = null,details = {}):
	_current_selection_window = _request_object

func _selection_window_closed(_request_object = null,details = {}):
	_current_selection_window = null
