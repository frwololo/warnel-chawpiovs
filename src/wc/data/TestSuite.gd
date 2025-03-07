class_name TestSuite
extends Reference

#GUI components required for interaction
var phaseContainer:PhaseContainer = null
var initialized:bool = false

#All tests
var test_files:Array
var current_test:int = 0
var passed: int = 0
var failed: int = 0
var finished: bool = false

#current tests
var initial_state:Dictionary
var end_state:Dictionary
var actions:Array
var current_action:int = 0

func _init():
	load_test_files()
	next_test()

#Gathers GUI objects from the game that we will be calling
func initialize_components():
	phaseContainer = gameData.phaseContainer
	initialized = true

func process(_delta: float) -> void:
	if (!initialized):
		initialize_components()
		
	if (finished):
		return
	next_action()	
	return	

#processes the next action for the current test
#If no actions remaining, check final state and load the next test
func next_action():
	#TODO need to ensure the previous action and its effects are completed before moving to the next
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
	
	#TODO select correct player
	if (0 == player):
		player = 1
	
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
			action_next_phase(player, action_value)
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
func action_next_phase(player, action_value):
	var hero_id = int(action_value)
	var heroPhase:HeroPhase = phaseContainer.heroesStatus[hero_id]
	heroPhase.heroPhase_action()
	return	
	
func action_other(player, action_value):
	match action_value:
		_:
			#TODO error
			return
	return				


#Find a card object 
func get_card(cardname:String):
	
	return null
	
#Check the end state for the current test
func finalize_test():
	return
	
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
	file.close		

#Loads a single test file 	
func load_test(test_file)-> bool:
	var json_card_data:Dictionary = WCUtils.read_json_file(test_file)
	initial_state = json_card_data["init"]
	actions = json_card_data["actions"]
	end_state = json_card_data["end"]
	current_action = 0
	#TODO load board state with initial data
	gameData.load_gamedata(initial_state)
	return true
		
#Loads the next test. If no next test, returns false	
func next_test() -> bool:
	if (test_files.size() <= current_test):
		finished = true
		save_results()
		return false
	var result = load_test(test_files[current_test])
	current_test+=1
	return result

func save_results():
	var file = File.new()
	var to_print:String = "total tests: " + str(test_files.size()) + "\n"
	to_print = to_print +  "failed: " + str(failed) + "\n"
	to_print = to_print +  "passed: " + str(passed) + "\n"
	file.open("user://test_results.txt", File.WRITE)
	file.store_string(to_print + "\n")
	file.close() 	
