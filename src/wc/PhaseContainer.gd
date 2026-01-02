# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name PhaseContainer
extends Node2D

var phaseLabel
var heroesStatus = []
var heroPhaseScene = preload("res://src/wc/board/HeroPhase.tscn")
onready var container = $MarginContainer/VBoxContainer
var positioned = false

#debug display for 
#TODO something fancier
var text_edit:TextEdit = null
var show_text_edit = false
#quick and dirty way to filter out some messages.
#whitelist has priority, if it's set, only messages containing
#specific words will go through
#if blackslit is set,, messages containing specific words will be explicitly banned 
const _debug_msg_whitelist = [] #["executing", "owner", "villain target"] #"script", "all clients", "error"]
const _debug_msg_blacklist = []

func toggle_display_debug(on_off):
	show_text_edit =  on_off
	if text_edit:
		text_edit.visible = on_off

func create_text_edit():
	if not cfc.NMAP.has("board") or not is_instance_valid(cfc.NMAP.board):
		return
	text_edit = TextEdit.new()  # Create a new TextEdit node
	text_edit.text = ""  # Set default text
	text_edit.rect_min_size = Vector2(400, 200)  # Set minimum size
	text_edit.wrap_enabled = true  # Enable text wrapping
	cfc.NMAP.board.add_child(text_edit)  # Add it to the current scene
	text_edit.anchor_left = 0.6
	text_edit.anchor_right = 1
	text_edit.anchor_top = 0.5
	text_edit.visible = false
	#text_edit.anchor_bottom = 0.5	

var _previous_debug_msg = ""
var _previous_equal_count := 0

func flush_debug_display():
	if !text_edit:
		return
	text_edit.text = ""	
	
func display_debug(msg:String, prefix = "phase"):
	if !CFConst.DISPLAY_DEBUG_MSG:
		return
	
	var good_to_display = true
	var lc_msg = msg.to_lower()
	if _debug_msg_whitelist:
		good_to_display = false
		for word in _debug_msg_whitelist:
			if word in lc_msg:
				good_to_display = true
	elif _debug_msg_blacklist:
		for word in _debug_msg_blacklist:
			if word in lc_msg:
				good_to_display = false
		
	if !good_to_display:
		return
		
	if !text_edit:
		create_text_edit()
	if !text_edit:
		return
			
	text_edit.visible = show_text_edit
	
	if (!msg):
		return	
	
	if (prefix):
		msg = "(" + prefix  +") " + msg
	
	if _previous_debug_msg == msg:
		_previous_equal_count +=1
#		if _previous_equal_count < 10:
		msg = " ."
#		else:
#			msg = ""
	else:
		_previous_debug_msg = msg
		_previous_equal_count = 0	
		if (text_edit.text):
			text_edit.text += "\n"	
		cfc.LOG(msg)	

	text_edit.text += msg
		
	if text_edit.text.length() > 1000:
		flush_debug_display()
	
	var last_line = text_edit.get_line_count() - 1
	text_edit.cursor_set_line(last_line)
	text_edit.center_viewport_to_cursor()	

#WARNING: These are just strings, the actual enum is in CFConst
const StepStrings = [
	"GAME_NOT_STARTED",
	"PLAYER_MULLIGAN",
	"MULLIGAN_DONE",
	"IDENTITY_SETUP",
	"GAME_READY",
	"PLAYER_TURN",
	"PLAYER_DISCARD",
	"PLAYER_DRAW",
	"PLAYER_READY",
	"PLAYER_END",
	"VILLAIN_THREAT",
	"VILLAIN_ACTIVATES",
	"VILLAIN_DEAL_ENCOUNTER",
	"VILLAIN_REVEAL_ENCOUNTER",
	"VILLAIN_PASS_PLAYER_TOKEN",
	"VILLAIN_END",
	"ROUND_END",
	"SYSTEMS_CHECK"	
]

const DEFAULT_HERO_STATUS: = {
	CFConst.PHASE_STEP.PLAYER_TURN: HeroPhase.State.ACTIVE
}

var current_step = CFConst.PHASE_STEP.GAME_NOT_STARTED
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
	reset(true)	
	gameData.registerPhaseContainer(self)
	update_text()
	
	
func _init():
	scripting_bus.connect("step_started", self, "_step_started")
	scripting_bus.connect("step_ended", self, "_step_ended")
	if CFConst.SKIP_MULLIGAN:
		current_step = CFConst.PHASE_STEP.MULLIGAN_DONE


func reset(reset_phase:= true):
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	heroesStatus = []
	
	#create the hero face buttons
	for i in range(gameData.get_team_size()):
		var hero_index = i+1
		var heroButton = heroPhaseScene.instance()
		heroButton.init_hero(hero_index)
		heroButton.name = "HeroButton" + str(hero_index)
		container.add_child(heroButton)
		heroesStatus.append(heroButton)
			
	#Create label
	phaseLabel = Label.new()
	container.add_child(phaseLabel)
	update_text()	
	
	if text_edit:
		flush_debug_display()
		text_edit.text = ""
	
	#reinit misc variables	
	set_current_step_complete(false, "reset") 	
	if (reset_phase):
		start_current_step()
		
#Moving to next step needs to happen outside of the signal processing to avoid infinite loops or recursive signals
func _process(_delta: float) -> void:
	if !gameData.is_game_started():
		return
	
	#don't move if the stack has something going on
	#NOTE: calling theStack.is_processing() here doesn't work: if the stack is idle
	#but not empty, it means it is waiting for some playing interruption
	if !gameData.theStack.is_phasecontainer_allowed_to_process():
		return
			
	if gameData.user_input_ongoing:
		return
		
	if cfc.game_paused:
		return
		
	if cfc.get_modal_menu():
		return

	if cfc.is_process_ongoing():
		return
		
	if gameData.is_announce_ongoing():
		return	
		
	if gameData.pending_network_ack():
		return	

	var forced_scripts = gameData.execute_priority_scripts()
	if forced_scripts: #it eiter returns a bool (true if executing script) of a function (ongoing compute)
		return

	#some encounters need to be revealed outside of their regular schedule
	# e.g. with surge. We place them in this specific dictionary
	#and gamedata checks for them
	if (gameData.immediate_encounters):
		gameData.reveal_encounter()
		return

	#scheme and attack can happen outside of specific phases,
	#so instead we check if "attacker" has something going on
	if (gameData.attackers):
		gameData.enemy_activates()
		return


	#phases that do something particular  in their process step
	match current_step:			
		CFConst.PHASE_STEP.PLAYER_TURN:
			#nothing automated in player turn, they will tell us when they're done
			return
		CFConst.PHASE_STEP.VILLAIN_ACTIVATES:
			#villain activate phase is doing some automated stuff in its process step
			gameData.enemy_activates()
			return		
		CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER:
			if (!current_step_complete):
				gameData.reveal_encounter()
			return	
	#other phases are just constantly requesting to move to the next step if they can	
	if (!current_step_complete) :
		return		


		
	match current_step:
		CFConst.PHASE_STEP.SYSTEMS_CHECK:
			if !gameData._multiplayer_desync:
				request_next_phase("from _process systems_check")	
		_:
			request_next_phase("from _process _:")				

func offer_to_mulligan() -> void:
	cfc.add_ongoing_process(self, "offer_to_mulligan")
	var my_heroes = gameData.get_my_heroes()
	for hero_id in my_heroes:	
		var hero_card = gameData.get_identity_card(hero_id)
		var func_return = hero_card.execute_scripts(hero_card, "mulligan")
		if func_return is GDScriptFunctionState && func_return.is_valid():
			yield(func_return, "completed")	
	set_current_step_complete(true, "offer_to_mulligan")		
	cfc.remove_ongoing_process(self, "offer_to_mulligan")

func identity_setup() -> void:
	cfc.add_ongoing_process(self, "identity_setup")	
	for i in range (gameData.get_team_size()): 
		var hero_id = i+1
		if hero_id in gameData.get_my_heroes():
			var identity_card = gameData.get_identity_card(hero_id)
			var func_return = identity_card.execute_scripts(identity_card, "setup")
			if func_return is GDScriptFunctionState && func_return.is_valid():
				yield(func_return, "completed")
	set_current_step_complete(true, "identity_setup")		
	cfc.remove_ongoing_process(self, "identity_setup")				

#called by gamedata once all encounters are revealed for the current hero
func all_encounters_done():
	if (current_step != CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER):
		var _error = 1
		return
	if current_step_complete:
		display_debug("calling all_encounters_done but it should already be the case")
		return
	display_debug("all_encounters_done for the current target hero")
	var result = _force_go_to_next_phase("all_encounters_done")	
	if !result:
		display_debug("all_encounters_done: tried to move to the next phase but got rejected")
		set_current_step_complete(false, "all_encounters_done (failure to go to next phase)")
	#request next phase forces the current step to be marked as incomplete
	#this doesn't work well for this case so I'm moving it	
	#set_current_step_complete(result, "all_encounters_done")
	
#called by gamedata once all enemy attacks are finished for the current hero
func all_enemy_attacks_finished():
	if (current_step != CFConst.PHASE_STEP.VILLAIN_ACTIVATES):
		var _error = 1
		return
	_force_go_to_next_phase("all_enemy_attacks_finished")	

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
func _force_go_to_next_phase(caller = "") -> bool:
	if !caller:
		caller = "_force_go_to_next_phase"
	set_current_step_complete(true, caller + ", _force_go_to_next_phase")
	var result = request_next_phase(caller)
	return result

func _step_ended(	
		trigger_details: Dictionary = {}):
	var step = trigger_details["step"]
	match step:
		CFConst.PHASE_STEP.GAME_READY:
				
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
	set_current_step_complete(false, "_step_started")

	#All heroes can now play
	if (step >= CFConst.PHASE_STEP.PLAYER_TURN):
		for i in range(gameData.get_team_size()):
			var hero_index = i+1
			reset_hero_activation_for_step(hero_index)
	
	match step:	
		CFConst.PHASE_STEP.PLAYER_MULLIGAN:
			offer_to_mulligan()
		CFConst.PHASE_STEP.IDENTITY_SETUP:
			identity_setup()			
		CFConst.PHASE_STEP.PLAYER_TURN:
			return
		CFConst.PHASE_STEP.PLAYER_DISCARD:
			_player_discard()
		CFConst.PHASE_STEP.PLAYER_DRAW:
			_player_draw()			
		CFConst.PHASE_STEP.PLAYER_READY:
			_player_ready()						
		CFConst.PHASE_STEP.PLAYER_END:
			_player_end()
		CFConst.PHASE_STEP.VILLAIN_THREAT:
			_villain_threat()
		CFConst.PHASE_STEP.VILLAIN_ACTIVATES:
			gameData.villain_init_attackers()
			#_villain_activates()						
		CFConst.PHASE_STEP.VILLAIN_DEAL_ENCOUNTER:
			_deal_encounters()	
		CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER:
			pass #do nothing but we don't want to mark it as complete	
		CFConst.PHASE_STEP.VILLAIN_PASS_PLAYER_TOKEN:
			gameData.next_first_player()
			set_current_step_complete(true, "_step_started")							
		CFConst.PHASE_STEP.ROUND_END:
			_round_end()
		CFConst.PHASE_STEP.SYSTEMS_CHECK:
			_systems_check()
		_:
			set_current_step_complete(true, "_step_started") # Do nothing				
	return 0

# a function to check if the phaseContainer is still running automatically
# through phases
# notably we don't want to be able to do interactions (from users, from automated test suite)
# while the phases are automatically proceeding
func is_in_progress()-> bool:
	return is_ready_for_next_phase() 

#returns true if nothing prevents me (player) from *asking* for next phase	
func would_be_ready_for_next_phase() -> bool:
	#don't move if the stack has something going on
	#NOTE: calling theStack.is_processing() here doesn't work: if the stack is idle
	#but not empty, it means it is waiting for some playing interruption
	if !gameData.theStack.is_phasecontainer_allowed_to_next_step():
		return false

	#encounters waiting to be revealed
	if (gameData.immediate_encounters):
		return false

	if gameData.gui_activity_ongoing():
		return false

	return true

#returns true if nothing prevents me (player) from *asking* for next phase			
func is_ready_for_next_phase() -> bool :
	if (!current_step_complete) :
		return	false
	return would_be_ready_for_next_phase()	


mastersync func client_ready_for_next_phase(current_phase):
	if (not cfc.is_game_master()):
		return -1
	var client_id = cfc.get_rpc_sender_id() 
	display_debug(str(client_id) + " is ready for next phase Their current phase is" + StepStrings[current_phase])
	
	#potential desync and tentative to fix, we only go up
	if clients_ready_for_next_phase.has(client_id):
		if current_phase > clients_ready_for_next_phase[client_id]:
			clients_ready_for_next_phase[client_id] = current_phase
	
	clients_ready_for_next_phase[client_id] = current_phase
	if (clients_ready_for_next_phase.size() == gameData.network_players.size()):
		#desync check. All clients should be at the same phase
		var _expected_current_phase = -1
		var desync = false
		for network_id in gameData.network_players:
			if _expected_current_phase == -1:
				_expected_current_phase = clients_ready_for_next_phase[network_id]
			if clients_ready_for_next_phase[network_id] != _expected_current_phase:
				desync = true
		if desync:
			display_debug("we have a discrepancy in next_phase attempts")
			display_debug(to_json(clients_ready_for_next_phase))
		else:
			clients_ready_for_next_phase = {}
			display_debug("everyone is ready for next phase, go")
			cfc._rpc(self,"proceed_to_next_phase")
		
		
mastersync func client_unready_for_next_phase():
	if (not cfc.is_game_master()):
		return -1
	var client_id = cfc.get_rpc_sender_id() 

	if clients_ready_for_next_phase.has(client_id):
		clients_ready_for_next_phase.erase(client_id)


var _pending_next_phase_reply = false		
func request_next_phase(caller = ""):
	if (!is_ready_for_next_phase()):
		return false
	if _pending_next_phase_reply:
		return true
	
	_pending_next_phase_reply = true	
	display_debug("I'm asking the master to move to next phase (" + caller +  "). I'm currently at " + StepStrings[current_step])	
	#set_current_step_complete(false, caller + ", request_next_phase")
	cfc._rpc_id(self,1, "client_ready_for_next_phase", current_step)
	return true
	
func unrequest_next_phase():
	_pending_next_phase_reply = false
	cfc._rpc_id(self,1, "client_unready_for_next_phase")	

func set_current_step_complete(value:bool, caller = ""):
	if value:
		var _tmp = 1
		if !caller:
			caller = "unknown"
	display_debug("marking current_step_complete as " + str(value) + " per request of " + caller )
	current_step_complete = value

func step_signal(signal_name):
	scripting_bus.emit_signal(signal_name,  {"step" : current_step, "step_name":StepStrings[current_step] })
	
remotesync func proceed_to_next_phase():
	_pending_next_phase_reply = false
	set_current_step_complete(false, "proceed_to_next_phase")
	display_debug("master tells me to move to next phase, I'm currently at " + StepStrings[current_step] )	
	step_signal("step_about_to_end")
	step_signal("step_ended")
	if (current_step == CFConst.PHASE_STEP.SYSTEMS_CHECK):
		current_step = CFConst.PHASE_STEP.PLAYER_TURN
	elif ((current_step == CFConst.PHASE_STEP.VILLAIN_ACTIVATES) and gameData.villain_next_target(true, "proceed_to_next_phase")):
		current_step = CFConst.PHASE_STEP.VILLAIN_ACTIVATES
	elif ((current_step == CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER) and gameData.villain_next_target(true, "proceed_to_next_phase")):
		current_step = CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER		
	else:
		current_step+=1
	start_current_step()

func start_current_step():		
	step_signal("step_about_to_start")
	step_signal("step_started")	
	update_text()
	

func _player_draw():
	gameData.draw_all_players()
	set_current_step_complete(true, "_player_draw")
	pass	
	
func _player_ready():
	gameData.ready_all_player_cards()
	set_current_step_complete(true, "_player_ready")	
	pass	

func _player_discard():
	cfc.add_ongoing_process(self)
	var my_heroes = gameData.get_my_heroes()
	for hero_id in my_heroes:
		var hero_card = gameData.get_identity_card(hero_id)
		var _func_return = hero_card.execute_scripts(hero_card, "end_phase_discard")
		#while _func_return is GDScriptFunctionState && _func_return.is_valid():
		#	_func_return = _func_return.resume()
		while cfc.get_modal_menu():
			yield(get_tree().create_timer(0.05), "timeout")
	cfc.remove_ongoing_process(self)

	set_current_step_complete(true, "_player_discard")
	
func _villain_threat():
	gameData.villain_threat()
	set_current_step_complete(true, "_villain_threat")
	pass	

func _after_villain_threat():
	gameData.villain_init_attackers()
	set_current_step_complete(true, "_after_villain_threat")
	pass				

func _deal_encounters():
	gameData.deal_encounters()
	#yield(get_tree().create_timer(2), "timeout")
	set_current_step_complete(true, "_deal_encounters")
	pass

func _player_end():
	scripting_bus.emit_signal("phase_ended", {"phase": "player"})
	#give time to create the discard option
	set_current_step_complete(true, "_player_end") # Do nothing	

func _round_end():
	scripting_bus.emit_signal("phase_ended", {"phase": "villain"})
	gameData.end_round()
	set_current_step_complete(true, "_round_end")	
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

	current_step = step_string_to_step_id(json_data)


func _systems_check():
	gameData.systems_check()
	#setting the step complete here. gameData has its own variable (_systms_check_ongoing)
	set_current_step_complete(true, "_systems_check") 
	pass
		
# Ensures proper cleanup when a card is queue_free() for any reason
func _on_tree_exiting():	
	flush_debug_display()

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		flush_debug_display()

func resize():
		
	var screen_size = cfc.screen_resolution
	#self.scale = cfc.screen_scale
	var margin_container = $MarginContainer
	margin_container.rect_scale = cfc.screen_scale
	margin_container.margin_right = screen_size.x / cfc.screen_scale.y
	margin_container.margin_bottom = screen_size.y / cfc.screen_scale.y
