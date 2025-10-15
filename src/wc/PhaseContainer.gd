# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name PhaseContainer
extends VBoxContainer

var phaseLabel
var heroesStatus = []
var heroPhaseScene = preload("res://src/wc/board/HeroPhase.tscn")

#Notes on the phases
#During another player's turn, you can play *actions* (cards or abilities)


#TODO Actual names needed here
const StepStrings = [
	"PLAYER_TURN",
	"PLAYER_DISCARD",
	"PLAYER_DRAW",
	"PLAYER_READY",
	"PLAYER_END",
	"VILLAIN_THREAT",
	"VILLAIN_ACTIVATES",
	"VILLAIN_MINIONS_ACTIVATE",
	"VILLAIN_DEAL_ENCOUNTER",
	"VILLAIN_REVEAL_ENCOUNTER",
	"VILLAIN_PASS_PLAYER_TOKEN",
	"VILLAIN_END",
	"ROUND_END"	
]

const DEFAULT_HERO_STATUS: = {
	CFConst.PHASE_STEP.PLAYER_TURN: HeroPhase.State.ACTIVE
}

var current_step = CFConst.PHASE_STEP.PLAYER_TURN
var current_step_complete:bool = false
var clients_ready_for_next_phase:Dictionary = {}

func step_string_to_step_id(stepString:String) -> int:
	for i in CFConst.PHASE_STEP.values():
		if stepString.to_upper() == StepStrings[i]:
			return i
	return CFConst.PHASE_STEP.PLAYER_TURN #Default

func update_text():
	phaseLabel.text = StepStrings[current_step]

# Called when the node enters the scene tree for the first time.
func _ready():
	gameData.registerPhaseContainer(self)
	scripting_bus.connect("step_started", self, "_step_started")
	scripting_bus.connect("step_ended", self, "_step_ended")
	update_text()
	
	
func _init():
	reset()

func reset():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	heroesStatus = []
	
	#create the hero face buttons
	for i in range(gameData.get_team_size()):
		var hero_index = i+1
		var heroButton = heroPhaseScene.instance()
		heroButton.init_hero(hero_index)
		heroButton.name = "HeroButton" + str(hero_index)
		add_child(heroButton)
		heroesStatus.append(heroButton)
			
	#Create label
	phaseLabel = Label.new()
	add_child(phaseLabel)
	update_text()	
	
	#reinit misc variables	
	set_current_step_complete(false) 	

#Moving to next step needs to happen outside of the signal processing to avoid infinite loops or recursive signals
func _process(_delta: float) -> void:
	#don't move if the stack has something going on
	#NOTE: calling theStack.is_processing() here doesn't work: if the stack is idle
	#but not empty, it means it is waiting for some playing interruption
	if !gameData.theStack.is_empty():
		return
	
	if (!current_step_complete) :
		return
		
	if gameData.user_input_ongoing:
		return
		
	if cfc.game_paused:
		return
		
	if cfc.modal_menu:
		return
		
	match current_step:
		CFConst.PHASE_STEP.PLAYER_TURN:
			return
		CFConst.PHASE_STEP.PLAYER_DISCARD:
			request_next_phase()
		CFConst.PHASE_STEP.PLAYER_DRAW:
			request_next_phase()		
		CFConst.PHASE_STEP.PLAYER_READY:
			request_next_phase()					
		CFConst.PHASE_STEP.PLAYER_END:
			request_next_phase()
		CFConst.PHASE_STEP.VILLAIN_THREAT:
			request_next_phase()
		CFConst.PHASE_STEP.VILLAIN_ACTIVATES:
			request_next_phase()			
		CFConst.PHASE_STEP.VILLAIN_MINIONS_ACTIVATE:
			request_next_phase()			
		CFConst.PHASE_STEP.VILLAIN_DEAL_ENCOUNTER:
			request_next_phase()		
		CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER:
			request_next_phase()			
		CFConst.PHASE_STEP.VILLAIN_PASS_PLAYER_TOKEN:
			request_next_phase()
		CFConst.PHASE_STEP.VILLAIN_END:
			request_next_phase()
		CFConst.PHASE_STEP.ROUND_END:
			request_next_phase()	
	

func check_end_of_player_phase():
	if (current_step != CFConst.PHASE_STEP.PLAYER_TURN):
		return
		
	for hero_phase in heroesStatus:
		if hero_phase.current_state == HeroPhase.State.ACTIVE :
			return
		
	_force_go_to_next_phase()
	
#TODO - Actually verify with server what happens:
#- Ask server to update phase
#- Server tells us phase has changed
#- Update information
func _force_go_to_next_phase():
	set_current_step_complete(true)
	request_next_phase()

func _step_ended(	
		trigger_details: Dictionary = {}):
	var step = trigger_details["step"]
	match step:
		CFConst.PHASE_STEP.VILLAIN_THREAT:
			#_after_villain_threat()
			pass	

func deactivate_hero(hero_id):
	var hero_phase = heroesStatus[hero_id -1]
	hero_phase.switch_status(HeroPhase.State.FINISHED)

func activate_hero(hero_id):
	var hero_phase = heroesStatus[hero_id -1]
	hero_phase.switch_status(HeroPhase.State.ACTIVE)	

#Makes the hero badge active to pass an interrupt or request next phase
func reset_hero_activation_for_step(hero_id):
	var hero_phase = heroesStatus[hero_id -1]
	var new_status = DEFAULT_HERO_STATUS.get(current_step, HeroPhase.State.FINISHED)
	hero_phase.switch_status(new_status)	

func _step_started(	
		trigger_details: Dictionary = {}):
	var step = trigger_details["step"]
	set_current_step_complete(false)

	#All heroes can now play
	for i in range(gameData.get_team_size()):
		var hero_index = i+1
		reset_hero_activation_for_step(hero_index)
	
	match step:
		CFConst.PHASE_STEP.PLAYER_TURN:
			return
		CFConst.PHASE_STEP.PLAYER_DISCARD:
			_player_discard()
		CFConst.PHASE_STEP.PLAYER_DRAW:
			_player_draw()			
		CFConst.PHASE_STEP.PLAYER_READY:
			_player_ready()						
		CFConst.PHASE_STEP.PLAYER_END:
			set_current_step_complete(true) # Do nothing
		CFConst.PHASE_STEP.VILLAIN_THREAT:
			_villain_threat()
		CFConst.PHASE_STEP.VILLAIN_ACTIVATES:
			gameData.villain_init_attackers()
			_villain_activates()			
		CFConst.PHASE_STEP.VILLAIN_MINIONS_ACTIVATE:
			_minions_activate()				
		CFConst.PHASE_STEP.VILLAIN_DEAL_ENCOUNTER:
			_deal_encounters()			
		CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER:
			_reveal_encounters()			
		CFConst.PHASE_STEP.VILLAIN_PASS_PLAYER_TOKEN:
			set_current_step_complete(true) # Do nothing
		CFConst.PHASE_STEP.VILLAIN_END:
			set_current_step_complete(true) # Do nothing
		CFConst.PHASE_STEP.ROUND_END:
			_round_end()
	return 0

# a function to check if the phaseContainer is still running automatically
# through phases
# notably we don't want to be able to do interactions (from users, from automated test suite)
# while the phases are automatically proceeding
func is_in_progress()-> bool:
	return is_ready_for_next_phase() 

#returns true if nothing prevents me (player) from *asking* for next phase	
func is_ready_for_next_phase() -> bool :

	#don't move if the stack has something going on
	#NOTE: calling theStack.is_processing() here doesn't work: if the stack is idle
	#but not empty, it means it is waiting for some playing interruption
	#(which can never be a "next phase" request???)
	if !gameData.theStack.is_empty():
		return false
	
	if (!current_step_complete) :
		return	false
	
	# if modal user input is being requested, can't move on
	if (gameData.user_input_ongoing):
		return false
		
	return true	

mastersync func client_ready_for_next_phase():
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id() 

	clients_ready_for_next_phase[client_id] = 1
	if (clients_ready_for_next_phase.size() == gameData.network_players.size()):
		clients_ready_for_next_phase = {}
		rpc("proceed_to_next_phase")
		
mastersync func client_unready_for_next_phase():
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id() 

	if clients_ready_for_next_phase.has(client_id):
		clients_ready_for_next_phase.erase(client_id)

		
func request_next_phase():
	if (!is_ready_for_next_phase()):
		return
	set_current_step_complete(false)
	rpc_id(1, "client_ready_for_next_phase")
	
func unrequest_next_phase():
	rpc_id(1, "client_unready_for_next_phase")	

func set_current_step_complete(value:bool):
	if value:
		var _tmp = 1
	current_step_complete = value
	
remotesync func proceed_to_next_phase():	
	scripting_bus.emit_signal("step_about_to_end",  {"step" : current_step})
	scripting_bus.emit_signal("step_ended",  {"step" : current_step})
	if (current_step == CFConst.PHASE_STEP.ROUND_END):
		current_step = CFConst.PHASE_STEP.PLAYER_TURN
	elif ((current_step == CFConst.PHASE_STEP.VILLAIN_MINIONS_ACTIVATE) and gameData.villain_next_target()):
		current_step = CFConst.PHASE_STEP.VILLAIN_ACTIVATES
	else:
		current_step+=1
	scripting_bus.emit_signal("step_about_to_start",  {"step" : current_step})
	scripting_bus.emit_signal("step_started",  {"step" : current_step})	
	update_text()
	

func _player_draw():
	gameData.draw_all_players()
	set_current_step_complete(true)
	pass	
	
func _player_ready():
	gameData.ready_all_player_cards()
	set_current_step_complete(true)	
	pass	

func _player_discard():
	var my_heroes = gameData.get_my_heroes()
	for hero_id in my_heroes:
		var hero_card = gameData.get_identity_card(hero_id)
		var func_return = hero_card.execute_scripts(hero_card, "end_phase_discard")
		#while func_return is GDScriptFunctionState && func_return.is_valid():
		#	func_return = func_return.resume()
		while cfc.modal_menu:
			yield(get_tree().create_timer(0.05), "timeout")


	set_current_step_complete(true)
	
func _villain_threat():
	gameData.villain_threat()
	set_current_step_complete(true)
	pass	

func _after_villain_threat():
	gameData.villain_init_attackers()
	set_current_step_complete(true)
	pass
	
func _villain_activates():
	set_current_step_complete(false)
	var activated_ok = CFConst.ReturnCode.WAITING
	while activated_ok == CFConst.ReturnCode.WAITING:
		activated_ok = gameData.enemy_activates()
		if activated_ok is GDScriptFunctionState:
			activated_ok = yield(activated_ok, "completed")
		if activated_ok == CFConst.ReturnCode.WAITING:
			yield(get_tree().create_timer(0.05), "timeout")	
	
	set_current_step_complete(true)
	pass	
	
func _minions_activate():
	while cfc.game_paused:
		yield(get_tree().create_timer(0.05), "timeout")	
	var activated_ok = CFConst.ReturnCode.OK 
	while activated_ok == CFConst.ReturnCode.OK:
		activated_ok = gameData.enemy_activates()
		if activated_ok is GDScriptFunctionState:
			activated_ok = yield(activated_ok, "completed")
	set_current_step_complete(true)
	pass					

func _deal_encounters():
	gameData.deal_encounters()
	yield(get_tree().create_timer(2), "timeout")
	set_current_step_complete(true)
	pass
	
func _reveal_encounters():
	var func_return = gameData.reveal_encounters()
	if func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = yield(func_return, "completed")
	set_current_step_complete(true)
	pass	

func _round_end():
	gameData.end_round()
	set_current_step_complete(true)	
	pass

func savestate_to_json() -> Dictionary:
	var json_data:Dictionary = {
		"phase": StepStrings[current_step]
	}
	return json_data
	
func loadstate_from_json(json:Dictionary):
	var json_data = json.get("phase", null)
	if (null == json_data):
		return #TODO Error msg
	current_step = step_string_to_step_id(json_data) #TODO better handling
