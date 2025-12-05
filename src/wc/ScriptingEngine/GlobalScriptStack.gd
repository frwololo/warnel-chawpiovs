# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name GlobalScriptStack
extends Node2D


signal script_executed_from_stack(script)
signal script_added_to_stack(script)

#display
#TODO something fancier
var text_edit:TextEdit = null
var stack:= []
#stores data relevant to the ongoing interrupt signal
var _current_interrupted_event: Dictionary = {}

enum InterruptMode {
	NONE,
	FORCED_INTERRUPT_CHECK,
	OPTIONAL_INTERRUPT_CHECK,
	NOBODY_IS_INTERRUPTING
}

const InterruptModeStr := [
	"NONE",
	"FORCED_INTERRUPT_CHECK",
	"OPTIONAL_INTERRUPT_CHECK",
	"NOBODY_IS_INTERRUPTING",
]

const INTERRUPT_FILTER := {
	InterruptMode.FORCED_INTERRUPT_CHECK:  CFConst.CanInterrupt.MUST,
	InterruptMode.OPTIONAL_INTERRUPT_CHECK: CFConst.CanInterrupt.MAY,
}


enum RUN_MODE {
	NOTHING_TO_RUN, #stack is empty and I have nothing to run
	PENDING_REQUEST_ACK, #I have requested the master to run a script from me
	NO_BRAKES, #I'm running everything that goes on the stacl
	PENDING_USER_INTERACTION, #I detected that another user interaction is required
}

const RunModeStr := [
	"NOTHING_TO_RUN", #stack is empty and I have nothing to run
	"PENDING_REQUEST_ACK", #I have requested the master to run a script from me
	"NO_BRAKES", #I'm running everything that goes on the stacl
	"PENDING_USER_INTERACTION", #I detected that another user interaction is required
]

var all_clients_status:= {}
var run_mode = RUN_MODE.NOTHING_TO_RUN
var interrupt_mode = InterruptMode.NONE
var interrupting_hero_id = 0
var _heroes_passed_optional_interrupt := {}
var _current_interrupting_cards:= []
var throttle_after_no_brakes:int = 0
var pending_stack_yield = {}
const yield_max_wait_time : float= 5.0
var yield_wait_time: float= 0
var history := {}
var pending_interaction_checksums := {}
var sync_enabled = true


#stores unique IDs for all stack events
var current_stack_uid:int = 0
var card_already_played_for_stack_uid:Dictionary = {}
var my_script_requests_pending_execution: = 0

func _ready():
	scripting_bus.connect("step_started", self, "_step_started")

func _step_started(details:Dictionary):
	var current_step = details["step"]
	match current_step:
		CFConst.PHASE_STEP.PLAYER_MULLIGAN, CFConst.PHASE_STEP.PLAYER_DISCARD:
			disable_sync()
		_:
			enable_sync()

func add_yield_counter(name):
	yield_wait_time = 0
	if !pending_stack_yield.has(name):
		pending_stack_yield[name] = 0
	pending_stack_yield[name] +=1
	
func remove_yield_counter(name):
	if !pending_stack_yield.has(name):
		display_debug("error remove_yield_counter " + name + " doesn't exist")
		return
	pending_stack_yield[name] -=1
	if pending_stack_yield[name] <= 0:
		pending_stack_yield.erase(name)
	yield_wait_time = 0
					
func create_and_add_script(sceng, run_type, trigger, trigger_details, action_name, checksum):
	add_yield_counter("create_and_add_script")
	if !run_mode in [RUN_MODE.NOTHING_TO_RUN, RUN_MODE.PENDING_USER_INTERACTION] :
		if trigger in ["manual"]: #todo might need interrupt in there as well?
			var _error = 1
			display_stack_error_for_card(sceng.owner)
			return
		elif sync_enabled:
			while (yield_wait_time < yield_max_wait_time) and !run_mode in [RUN_MODE.NOTHING_TO_RUN, RUN_MODE.PENDING_USER_INTERACTION]:
				display_debug("yield for NOTHING_TO_RUN or PENDING_USER_INTERACTION in create_and_add_script")
				yield(get_tree().create_timer(0.1), "timeout")
				yield_wait_time += 0.1
	remove_yield_counter("create_and_add_script")
	#if the script required user interaction, we send it
	#to the master for replication on all clients
	#else, all machines are expected to run it locally
	var expected_run_mode = run_mode
	match sceng.user_interaction_status:
		CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER:
		#we deconstruct locally here to reconstruct it on all clients then add it to all stacks
		#also send GUIDs to find the right cards/targets			
			var prepaid: Array = sceng.network_prepaid
			var prepaid_uids: Array = []

			#NOTE in some cases it is ok for prepaid to be empty. E.g. when refusing to defend

			for array in prepaid:
				var prepaid_uids_task = guidMaster.array_of_objects_to_guid(array)
				prepaid_uids.append(prepaid_uids_task)
			var remote_trigger_details: Dictionary = trigger_details.duplicate()
			remote_trigger_details["network_prepaid"] =  prepaid_uids
			
			var trigger_card_uid = guidMaster.get_guid(sceng.trigger_object)
			var owner_uid = guidMaster.get_guid(sceng.owner)
			var state_scripts = sceng.state_scripts
			my_script_requests_pending_execution += 1
			set_run_mode(RUN_MODE.PENDING_REQUEST_ACK, "create_and_add_script - "  + action_name)
			rpc_id(1, "master_create_and_add_script", expected_run_mode, state_scripts, owner_uid, trigger_card_uid, run_type, trigger, remote_trigger_details, sceng.stored_integers, action_name, checksum)
			#TODO should wait for ack from all clients before anybody can do anything further in the game
		CFConst.USER_INTERACTION_STATUS.DONE_INTERACTION_NOT_REQUIRED:
			var stackEvent:StackScript = StackScript.new(sceng, run_type, trigger)
			stackEvent.set_display_name(action_name)
			add_script_and_run(stackEvent)
		_:
			#this shouldn't happen
			display_debug("error in create_and_add_script, invalid sceng.user_interaction_status:" +str(sceng.user_interaction_status))

func create_and_add_signal(_name, _owner, _details):
	var stackEvent:SignalStackScript = SignalStackScript.new(_name, _owner, _details)
	stackEvent.set_display_name(_name)
	add_script_and_run(stackEvent)

func create_and_add_simplescript( _owner, trigger_card, definition,  trigger_details):
	var task = ScriptTask.new(_owner, definition, trigger_card, trigger_details)	
	var stackEvent = SimplifiedStackScript.new(task)
	add_script_and_run(stackEvent)

func set_client_status(client_id, key, value):
	if !all_clients_status.has(client_id):
		all_clients_status[client_id] = {}
	all_clients_status[client_id][key] = value

func get_client_status(client_id, key):
	if !all_clients_status.has(client_id):
		all_clients_status[client_id] = {}
	var result = all_clients_status[client_id].get(key, "")
	if !result:
		match key:
			"run_mode":
				result = RUN_MODE.NOTHING_TO_RUN
	return result

func client_status_is_ahead(client_id, key):
	if !all_clients_status.has(client_id):
		all_clients_status[client_id] = {}
			
	var min_value = -1
	for network_id in all_clients_status:
		var value = all_clients_status[network_id].get(key, -1)
		if min_value == -1 or min_value > value:
			min_value = value
	
	var my_value = all_clients_status[client_id].get(key, -1)
	if my_value > min_value:
		return true
	return false
	
func client_status_is_behind(client_id, key):	
	if !all_clients_status.has(client_id):
		all_clients_status[client_id] = {}
			
	var max_value = -1
	for network_id in all_clients_status:
		var value = all_clients_status[network_id].get(key, -1)
		if max_value < value:
			max_value = value
	
	var my_value = all_clients_status[client_id].get(key, max_value)
	if my_value < max_value:
		return true
	return false
	
mastersync func master_create_and_add_script(expected_run_mode, state_scripts, owner_uid, trigger_card_uid,  run_type, trigger, remote_trigger_details, stored_integers, action_name, checksum):
	var client_id = get_tree().get_rpc_sender_id() 
	set_client_status(client_id, "run_mode", RUN_MODE.PENDING_REQUEST_ACK)	
	var original_details = {
		"type": "script",
		"state_scripts": state_scripts,
		"owner_uid": owner_uid, 
		"trigger_card_uid": trigger_card_uid,  
		"run_type": run_type, 
		"trigger": trigger,	
		"remote_trigger_details":remote_trigger_details,
		"stored_integers": stored_integers, 
		"action_name": action_name	
	}		
	
	#we will reject "manual" requests if the stack isn't empty 
	#and the card isn't one of the currently allowed ones
	var accept_request = true
	#TODO
	if trigger == "manual":
		var allowed_interrupters = get_allowed_interrupting_cards()
		if allowed_interrupters:
			if !owner_uid in allowed_interrupters:
				accept_request = false
		else:
			#reject everything if other clients have something going on
			for network_id in all_clients_status.keys():
				if network_id == client_id:
					continue #TODO other checks? 
				if ! get_client_status(network_id, "run_mode") in [RUN_MODE.NOTHING_TO_RUN, RUN_MODE.PENDING_USER_INTERACTION]:
					accept_request = false

	
	if accept_request:
		#master_request_add_stack_object(client_id, original_details)
		rpc_id(client_id, "accepted_add_script_request", expected_run_mode, original_details)				
		display_debug("Asking clients to add script " + action_name) 			
		rpc("client_create_and_add_stackobject", client_id, expected_run_mode, original_details, checksum)
	else:
		rpc_id(client_id, "rejected_add_script_request", expected_run_mode, original_details)

func display_stack_error_for_card(card):
	if guidMaster.is_guid(card):
		card = guidMaster.get_object_by_guid(card)
	if !card:
		return
	card.network_request_rejected()
	display_debug("Add script request rejected for " + card.canonical_name)	

remotesync func accepted_add_script_request (expected_run_mode, _original_details):	
	my_script_requests_pending_execution -= 1
	set_run_mode(expected_run_mode, "accepted_add_script_request")

remotesync func rejected_add_script_request(expected_run_mode, details:={}):
	var owner_uid = details.get("owner_uid", "")
	display_stack_error_for_card(owner_uid)
		
	my_script_requests_pending_execution -= 1
	if !my_script_requests_pending_execution:
		set_run_mode(expected_run_mode, "rejected_add_script_request")


func get_allowed_interrupting_cards():
	#todo
	return _current_interrupting_cards


var _ack_received = {}
master func from_client_script_received_ack(expected_run_mode, checksum):
	var client_id = get_tree().get_rpc_sender_id()
	_ack_received[client_id] = true
	if _ack_received.size() == gameData.network_players.size():
		_ack_received = {}
		rpc("resume_operations", expected_run_mode, checksum)
	

remotesync func client_create_and_add_stackobject( original_requester_id, expected_run_mode, details, checksum):
	var client_id = get_tree().get_rpc_sender_id()
					
	var type = details["type"]
	display_debug(str(client_id) + " wants me to add a " + type + "- " + checksum )
	var stackEvent = null
	match type:
		"simplescript":
			#TODO
			#stackEvent = client_create_simplescript(details)
			pass
		"signal":
			#TODO
			#stackEvent = client_create_signal( details)
			pass
		_:	
			stackEvent = client_create_script(details)

	if !stackEvent:
		var _error = 1
		return

	add_yield_counter("client_create_and_add_stackobject")
	#the expectation here is that all clients will reach either 
	# "NOTHING TO RUN" or "PENDING USER INTERACTION" and be in sync with the current ask
	if original_requester_id != cfc.get_network_unique_id():	
		while (yield_wait_time < yield_max_wait_time) and sync_enabled and run_mode != expected_run_mode:
			display_debug("yield for " + RunModeStr[expected_run_mode] + " in client_create_and_add_stackobject for " + checksum)
			yield(get_tree().create_timer(0.1), "timeout")
			yield_wait_time+= 0.1
	remove_yield_counter("client_create_and_add_stackobject")
		
	add_event_to_stack(stackEvent, checksum)
	rpc_id(1, "from_client_script_received_ack", expected_run_mode, checksum)

func set_pending_network_interaction(checksum, reason:=""):
	add_yield_counter("set_pending_network_interaction")
	while (yield_wait_time < yield_max_wait_time) and _pending_flush:
		display_debug("flush ongoing in set_pending_network_interaction")
		yield(get_tree().create_timer(0.1), "timeout")
		yield_wait_time+=0.1
	remove_yield_counter("set_pending_network_interaction")
	
	if reason:
		display_debug(reason)
	if pending_interaction_checksums:
		display_debug("error, assked to set to pending_interaction but pending queue not empty " + to_json(pending_interaction_checksums))
	pending_interaction_checksums[checksum] = true	
	set_run_mode(RUN_MODE.PENDING_USER_INTERACTION, "set_pending_network_interaction - " + checksum)

#client asking everyone to resume
#the expectation is to call this only when it is clear that everyone is pending interaction
func resume_operations_to_all(checksum):
	rpc("resume_operations", RUN_MODE.PENDING_USER_INTERACTION, checksum)
	
remotesync func resume_operations(expected_run_mode, checksum):
	var client_id = get_tree().get_rpc_sender_id()	
#	if stack.empty() or run_mode == RUN_MODE.NO_BRAKES:
#		var _error = 1

	add_yield_counter("resume_operations")
	#the expectation here is that all clients will reach
	# either "NOTHING" or PENDING USER INTERACTION" and be in sync with the current ask
	if client_id != cfc.get_network_unique_id():	
		while (yield_wait_time < yield_max_wait_time) and sync_enabled and run_mode != expected_run_mode :
			display_debug("yield for " + RunModeStr[expected_run_mode] + " in resume_operations")
			yield(get_tree().create_timer(0.1), "timeout")
			yield_wait_time+= 0.1
	remove_yield_counter("resume_operations")
	
	if expected_run_mode == RUN_MODE.PENDING_USER_INTERACTION:
		if !pending_interaction_checksums.has(checksum):
			display_debug("error in resume_operations, unaware of pending interaction " + checksum)
		pending_interaction_checksums.erase(checksum)
	
	set_run_mode(RUN_MODE.NO_BRAKES, "resume_operations")

			
func client_create_script(details):

	var state_scripts =  details["state_scripts"]
	var _owner_uid = details["owner_uid"]
	var trigger_card_uid = details["trigger_card_uid"]  
	var run_type = details["run_type"] 
	var trigger = details["trigger"]	
	var remote_trigger_details = details["remote_trigger_details"]
	var stored_integers = details["stored_integers"] 
	var action_name = details["action_name"]

	var trigger_card = guidMaster.get_object_by_guid(trigger_card_uid)
	var owner_card = guidMaster.get_object_by_guid(_owner_uid)

	
	var sceng = cfc.scripting_engine.new(
				state_scripts,
				owner_card,
				trigger_card,
				remote_trigger_details)
	sceng.stored_integers = stored_integers			
	var stackEvent:StackScript = StackScript.new(sceng, run_type, trigger)
	stackEvent.set_display_name(action_name)
	return stackEvent


func add_event_to_stack(stackEvent, checksum = ""):
	#if somebody is adding a script while in interrupt mode,
	# we add the script (its owner card for now - TODO need to change?)
	# to the list of scripts that already responded to the last event
	#this prevents them from triggering infinitely to the same event 
#	if interrupt_mode == InterruptMode.HERO_IS_INTERRUPTING:
	var result = {
		"is_interrupt" : false
	}
	
	if run_mode == RUN_MODE.PENDING_USER_INTERACTION:
		display_debug("add_event_to_stack: adding a script in interrupt mode")
		var script_being_interrupted = self.stack_back()
		var authorized_card = true
		var allowed_cards = get_allowed_interrupting_cards()
		if allowed_cards:
			var guid = guidMaster.get_guid(stackEvent.sceng.owner)
			display_debug("add_event_to_stack: list of allowed cards: "  + stackEvent.get_display_name() + "has guid " + guid + " vs list " + to_json(allowed_cards))			
			if !guid or !(stackEvent.sceng.owner in allowed_cards):
				display_debug("add_event_to_stack: card is not authorized")
				authorized_card = false
	
		if (script_being_interrupted and authorized_card):
			result["is_interrupt"] = true
			display_debug("add_event_to_stack: found a card to add")
			var script_uid = script_being_interrupted.stack_uid
			if (!card_already_played_for_stack_uid.has(script_uid)):
				card_already_played_for_stack_uid[script_uid] = []
			card_already_played_for_stack_uid[script_uid].append(stackEvent.sceng.owner)
			display_debug("add_event_to_stack: added " + stackEvent.get_display_name())
			#reset_interrupt_states()

	
	stackEvent.stack_uid = get_next_stack_uid()
	stack.append(stackEvent)
	history[stackEvent.stack_uid] = {
		"stack_uid" : stackEvent.stack_uid,
		"details": stackEvent.get_display_name(),
		"class": stackEvent.get_class(),	
	}
	emit_signal("script_added_to_stack",stackEvent)
	display_debug("added script to stack - " + checksum + ". my current_stack_uid is " + str(current_stack_uid) )
	return result

#wrapper around add_event_to_stack that also tries to restart the execution of scripts
func add_script_and_run(stackEvent):
	var result = add_event_to_stack(stackEvent)
	if run_mode == RUN_MODE.NOTHING_TO_RUN:
		set_run_mode(RUN_MODE.NO_BRAKES, "add_script_and_run")
	if result.get("is_interrupt", false):
		set_run_mode(RUN_MODE.NO_BRAKES, "add_script_and_run interrupt")			
	if run_mode!= RUN_MODE.NO_BRAKES:
		display_debug("error add_script: expected run mode to be NO_BRAKES, but got " + RunModeStr[run_mode])

#legacy
func add_script(stackEvent):
	add_script_and_run(stackEvent)

func _process(_delta: float):
	display_debug_info()
	
	show_server_activity()

	if gameData.is_ongoing_blocking_announce():
		return
			
	if run_mode != RUN_MODE.NO_BRAKES:
		return

	if stack.empty(): 
		#wait for a few ticks before going back to "nothing to run".
		#this allows potential late scripts to reach the stack without
		#authorizing players to play in between
		if throttle_after_no_brakes > 5: 
			set_run_mode(RUN_MODE.NOTHING_TO_RUN, "_process stack.empty()")
			throttle_after_no_brakes = 0
		else:
			throttle_after_no_brakes += 1
		return



	var stack_object = stack.back()
	var _interrupt_state = compute_interrupts(stack_object)
	interrupt_mode = _interrupt_state["interrupt_mode"]
	var potential_interrupters = _interrupt_state.get("potential_interrupters", {})
	match interrupt_mode:
		InterruptMode.FORCED_INTERRUPT_CHECK:
			for i in range(gameData.get_team_size()):
#				var hero_id = i+1
				var hero_id = gameData.get_ordered_hero_id(i)
				var interrupters = potential_interrupters.get(hero_id, [])
				if interrupters:
						set_run_mode(RUN_MODE.PENDING_USER_INTERACTION, "_process FORCED_INTERRUPT_CHECK")
						set_interrupting_hero(hero_id, interrupters)
						force_play_card(interrupters)
						return
		InterruptMode.OPTIONAL_INTERRUPT_CHECK:
			set_run_mode(RUN_MODE.PENDING_USER_INTERACTION,  "_process OPTIONAL_INTERRUPT_CHECK")			
			potential_interrupters =  _interrupt_state["potential_interrupters"]
			for i in gameData.get_team_size():
#				var hero_id = i+1
				var hero_id = gameData.get_ordered_hero_id(i)
				if potential_interrupters.get(hero_id, []):
					set_interrupting_hero(hero_id, potential_interrupters[hero_id])
					break
			return
		_:
			flush_script(stack_object)
					

					
	return	

func reset_phase_buttons():
	if gameData.phaseContainer and is_instance_valid(gameData.phaseContainer):
		for i in range (gameData.team.size()):
			gameData.phaseContainer.reset_hero_activation_for_step(i+1)

func activate_exclusive_hero(hero_id):
	add_yield_counter("activate_exclusive_hero")
	for network_id in all_clients_status:
		while (yield_wait_time < yield_max_wait_time) and get_client_status(network_id, "run_mode") != RUN_MODE.PENDING_USER_INTERACTION:
			display_debug("yield for other clients in activate_exclusive_hero")
			yield(get_tree().create_timer(0.1), "timeout")
			yield_wait_time+= 0.1
	remove_yield_counter("activate_exclusive_hero")
	
	for i in range (gameData.team.size()):
		var hero_index = i+1
		if (hero_index == hero_id):
			gameData.phaseContainer.activate_hero(hero_index)
		else:
			gameData.phaseContainer.deactivate_hero(hero_index)	

var _interrupting_hero_data = {}
mastersync func master_set_interrupting_hero(hero_id, interrupters):
	var client_id = get_tree().get_rpc_sender_id()
	_interrupting_hero_data[client_id] = hero_id
	if _interrupting_hero_data.size() == gameData.network_players.size():
		_interrupting_hero_data = {}
		rpc("clients_set_interrupting_hero", hero_id, interrupters)

func set_interrupting_hero(hero_id, interrupters):
	display_debug("set interrupting hero id to " + str(hero_id) + " with interrupters " + to_json(interrupters))

	set_current_interrupting_cards(interrupters)
	interrupting_hero_id = hero_id
#	activate_exclusive_hero(hero_id)
	rpc_id(1, "master_set_interrupting_hero", hero_id, interrupters)

func set_current_interrupting_cards(interrupters):
	display_debug("setting current_interrupting_cards to :" + to_json(interrupters))
	_current_interrupting_cards = []
	for card_guid in interrupters:
		var card = guidMaster.get_object_by_guid(card_guid)
		_current_interrupting_cards.append(card)	

remotesync func clients_set_interrupting_hero(hero_id, interrupters):
	activate_exclusive_hero(hero_id)

func reset_interrupt_states():
	reset_phase_buttons()
	interrupting_hero_id = 0
	interrupt_mode = InterruptMode.NONE
	set_current_interrupting_cards([])
# TODO run_mode ?
#	_current_interrupting_mode = InterruptMode.NONE	

#pass my opportunity to interrupt 
func pass_interrupt (hero_id):
	if not hero_id in gameData.get_my_heroes():
		cfc.LOG("{error}: pass_interrupt called for hero_id by non controlling player")
		return
	#rpc("clients_pass_interrupt", hero_id)	
	rpc("clients_pass_interrupt", hero_id)

func get_current_interrupted_event():
	return _current_interrupted_event

#call to all when I've chosen to pass my opportunity to interrupt 
remotesync func clients_pass_interrupt (hero_id):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " wants to pass for hero:" + str(hero_id) )

	add_yield_counter("clients_pass_interrupt")
	while (yield_wait_time < yield_max_wait_time) and run_mode != RUN_MODE.PENDING_USER_INTERACTION:
		display_debug("yield for PENDING_USER_INTERACTION in clients_pass_interrupt")
		yield(get_tree().create_timer(0.1), "timeout")
		yield_wait_time+= 0.1
	remove_yield_counter("clients_pass_interrupt")
	
	#TODO ensure that caller network id actually controls that hero
	reset_phase_buttons()
	_heroes_passed_optional_interrupt[hero_id] = true
	set_run_mode(RUN_MODE.NO_BRAKES, "clients_pass_interrupt")


#forced activation of card for forced interrupt
remotesync func force_play_card(interrupters):
	#TODO force interrupt mode here for security
	set_current_interrupting_cards(interrupters)
	#_current_interrupting_mode = InterruptMode.FORCED_INTERRUPT_CHECK
	
	var card = _current_interrupting_cards[0]
	
	card.attempt_to_play()

func enable_sync():
	sync_enabled = true

func disable_sync():
	sync_enabled = false

var _pending_flush = 0
func flush_script(stack_object):
	_pending_flush +=1
	if stack.empty() or (stack_object != stack.back()):
		var _error =1
		return
	
	if run_mode != RUN_MODE.NO_BRAKES:
		var _error = 1
		display_debug("called to flush script but not allowed because run_mode is" + RunModeStr[run_mode])
		return
		
	var func_return = stack_object.execute()	
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()
#	var user_interaction_status = stack_object.get_user_interaction_status()
	#something todo here ???

	if run_mode != RUN_MODE.NO_BRAKES:
		var _error = 1
		display_debug("called to flush script but not allowed because run_mode is" + RunModeStr[run_mode])
		return	
	
	history[stack_object.stack_uid]["done"] = true
	stack.erase(stack_object)
	if stack.empty():
		set_run_mode(RUN_MODE.NOTHING_TO_RUN, "flush_script " + stack_object.get_display_name())
	emit_signal("script_executed_from_stack", stack_object )		
	_pending_flush -=1	

func compute_interrupts(script):
	if !script:
		return {}

	var script_uid = script.stack_uid	
	var current_mode = interrupt_mode
	var current_run_mode = run_mode
	var potential_interrupters = {}
	for mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]:
		var interrupters_found = false
		
		#have to do that because can_interrupt checks for the current state of the game
		interrupt_mode = mode
		run_mode = RUN_MODE.PENDING_USER_INTERACTION
		
		for i in range(gameData.get_team_size()):
			var hero_id = i+1
			
			if mode == InterruptMode.OPTIONAL_INTERRUPT_CHECK and _heroes_passed_optional_interrupt.has(hero_id):
				continue

			var tasks = script.get_tasks()
			var my_interrupters:= []
			for task in tasks:
				_current_interrupted_event = task.script_definition.duplicate()
				_current_interrupted_event["event_name"] = task.script_name
				_current_interrupted_event["event_object"] = task
				for card in get_tree().get_nodes_in_group("cards"):
					if (card in card_already_played_for_stack_uid.get(script_uid, [])):
						continue
					if (task.script_name == "reveal_encounter"):
						if (card.canonical_name == "Enhanced Spider-Sense"):
							var _tmp = 1
					var can_interrupt = card.can_interrupt(hero_id,task.owner, _current_interrupted_event)
					if can_interrupt == INTERRUPT_FILTER[mode]:
						var guid = guidMaster.get_guid(card)
						my_interrupters.append(guid)
						interrupters_found = true
		
			potential_interrupters[hero_id] = my_interrupters
		if interrupters_found:
			#reset temp variables
			interrupt_mode = current_mode
			run_mode = current_run_mode
			return {
				"potential_interrupters" : potential_interrupters,
				"interrupt_mode" : mode,
				"interruptmode_str": InterruptModeStr[mode],
				"stack_uid" : script_uid
			}
	
	#no interrupt found, set status to "nobody_is_interrupting"	
	_heroes_passed_optional_interrupt = {}	
	#reset temp variables
	interrupt_mode = current_mode
	run_mode = current_run_mode	
	return {
		"interrupt_mode": InterruptMode.NOBODY_IS_INTERRUPTING,
		"interruptmode_str": InterruptModeStr[InterruptMode.NOBODY_IS_INTERRUPTING],
		"stack_uid": script_uid
	}


func update_local_client_status():
	var my_network_id = cfc.get_network_unique_id()
	all_clients_status[my_network_id] ={
		"run_mode": run_mode,
		"current_stack_uid": self.current_stack_uid
	}

func set_run_mode(new_value, caller = ""):
	if run_mode == new_value:
		return
	if caller == "":
		caller = "set_run_mode"
	display_debug("changing run mode from " + RunModeStr[run_mode] + " to " + RunModeStr[new_value] + "(requested by " + caller + ")"  )		
	run_mode = new_value
	update_local_client_status()
	
	if !run_mode in [RUN_MODE.PENDING_USER_INTERACTION, RUN_MODE.PENDING_REQUEST_ACK]:
		reset_interrupt_states()
	
	gameData.game_state_changed()
	rpc("client_run_mode_changed", all_clients_status[cfc.get_network_unique_id()])

remote func client_run_mode_changed (new_status):
	var client_id = get_tree().get_rpc_sender_id()
	for key in new_status:
		set_client_status(client_id, key, new_status[key])


func get_next_stack_uid():
	#setup UID for the stack event
	current_stack_uid = current_stack_uid + 1
	return current_stack_uid


func show_server_activity():
	if !gameData.is_game_started():
		return
	if !cfc.NMAP.has("board"):
		return
	if !is_instance_valid(cfc.NMAP.board):
		return
			
	var on_off = !is_player_allowed_to_click()
		
	cfc.NMAP.board.server_activity(on_off)

###
### Stack Authority decisions
###

func is_interrupt_mode()  -> bool:
	return (run_mode == RUN_MODE.PENDING_USER_INTERACTION and interrupt_mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK])
#	return theStack.get_interrupt_mode() in [
#		GlobalScriptStack.InterruptMode.HERO_IS_INTERRUPTING,
#		GlobalScriptStack.InterruptMode.OPTIONAL_INTERRUPT_CHECK,
#		GlobalScriptStack.InterruptMode.FORCED_INTERRUPT_CHECK
#	]

func is_optional_interrupt_mode() -> bool:
	return is_interrupt_mode() and interrupt_mode == InterruptMode.OPTIONAL_INTERRUPT_CHECK

func is_forced_interrupt_mode() -> bool:
	return is_interrupt_mode() and interrupt_mode == InterruptMode.FORCED_INTERRUPT_CHECK


func is_player_allowed_to_pass() -> bool:
	if !is_player_allowed_to_click():
		return false
	
	for network_id in all_clients_status:
		if get_client_status(network_id, "run_mode") != RUN_MODE.PENDING_USER_INTERACTION:
			return false

	return true


var _debug_messaged_recently = false		
func is_player_allowed_to_click(card = null) -> bool:
	#Generally speaking : can't play while there's something
	#on the stack, with exceptions in interrupt mode
	
#	if pending_local_scripts:
#		return false		
	
	for client_id in all_clients_status:
		var _run_mode = get_client_status(client_id, "run_mode")
		if _run_mode == RUN_MODE.NO_BRAKES:
			if !_debug_messaged_recently:
				_debug_messaged_recently = true
				display_debug ("not allowed to click because some players are still running")
			return false
			
	_debug_messaged_recently = false			
	#TODO
	match run_mode:
		RUN_MODE.NO_BRAKES:
			#stuff is still progressing in the stack, you don't get to add stuff
			return false
		RUN_MODE.PENDING_USER_INTERACTION:
			if card:
				if _current_interrupting_cards and card in _current_interrupting_cards:
					return true
				display_debug ("not allowed to click because card not in allowed cards for interruption")	
				return false
			var result = interrupting_hero_id in gameData.get_my_heroes() #todo needs to be tested when controling multipler heroes, this might be wrong
			return result				
		RUN_MODE.NOTHING_TO_RUN:
			if card:
				if gameData.phaseContainer.current_step != CFConst.PHASE_STEP.PLAYER_TURN:
					return false
			else:
				if gameData.phaseContainer.current_step != CFConst.PHASE_STEP.PLAYER_TURN:
					if !cfc.get_modal_menu():
						#occasionally some steps ask to select cards. 
						#E.g. mulligan, discard, defenders
						#checking for modal menu is a fair enough way to discriminate here
						return false				
				
			return true	
		RUN_MODE.PENDING_REQUEST_ACK:
			return false
	
			
	return true

func is_phasecontainer_allowed_to_next_step():
#	if !stack.empty():
#		return false
#
#	if my_script_requests_pending_execution:
#		return false

	if !is_idle():
		return false
		
	for client_id in all_clients_status:
		var _run_mode = get_client_status(client_id, "run_mode")
		if _run_mode != RUN_MODE.NOTHING_TO_RUN:
			return false
				
	match run_mode:
		RUN_MODE.NOTHING_TO_RUN:
			return true	
		_:
			return false


#we let clients run their own course as much as possible for regular process
#requests
func is_phasecontainer_allowed_to_process():
	#this used to just call is_idle, but there were cases
	#where "pending_stack_yield" was causing issues
	if my_script_requests_pending_execution:
		return false
		
	if !stack.empty():
		return false
		#TODO
				
	match run_mode:
		RUN_MODE.NOTHING_TO_RUN:
			return true	
		_:
			return false	
		

func is_idle():
	if pending_stack_yield:
		return false
		
	if my_script_requests_pending_execution:
		return false
		
	if !stack.empty():
		return false
		#TODO

	match run_mode:
		RUN_MODE.NOTHING_TO_RUN:
			return true	
		_:
			return false	

func is_accepting_user_interaction():
	return run_mode == RUN_MODE.PENDING_USER_INTERACTION or is_idle()

###
### Stack interaction functions (replacement effects, etc...)
###

func stack_back_id():
	return stack.size()-1
	
func stack_back():
	if !stack.size():
		return null
	return stack.back()

func stack_remove(stack_id):
	stack.remove(stack_id)
	
	#rpc_id(1, "master_stack_object_removed", stack_uid)	
		
func stack_pop_back():
	if !stack.size():
		return null
	return stack.pop_back()
	
func delete_last_event(requester:ScriptTask):
	#the requester usually doesn't want to delete themselves
	var max_id = find_last_event_id_before_me(requester)
	if max_id >=0:
		var event = stack[max_id]
		stack_remove(max_id)
		scripting_bus.emit_signal("stack_event_deleted", event)
	else:
		display_debug("Error: script " + requester.script_name + " asked me to delete event but I couldn't find it")

func is_script_in_stack_object(script:ScriptTask, stack_item):
	if script == stack_item: 
		return true
	for task in stack_item.get_tasks():
		if task == script:
			return true
	return false

func find_last_event_id_before_me(requester:ScriptTask):
	#the requester usually doesn't want to delete themselves
	for i in stack.size():
		var j = stack.size() -1 -i
		if is_script_in_stack_object(requester, stack[j]):
			return j-1
	return -1
		
func find_last_event_before_me(requester:ScriptTask):
	var max_id = find_last_event_id_before_me(requester)
	if max_id < 0:
		return null
		
	return stack[max_id]	

func find_event(_event_details, details, owner_card, _trigger_details):
	for event in stack:
		var task = event.get_script_by_event_details(_event_details)			
		if (!task):
			continue			
		if event.matches_filters(task, details, owner_card, _trigger_details):
			return event
	return null			



#scripted replacement effects
func modify_object(stack_object, script:ScriptTask):
	if !stack_object:
		return false
	return stack_object.modify(script)
	
	
		

###
### Log Functions and other helpers
###

func reset():
	cfc.LOG("\n###\nstack reset\n###\n")
	flush_logs()
	if my_script_requests_pending_execution:
		cfc.LOG("error in stack reset: my_script_requests_pending_execution :" + str(my_script_requests_pending_execution))
	my_script_requests_pending_execution = 0

	if pending_stack_yield:
		cfc.LOG("error in stack reset: pending_stack_yield :" + to_json(pending_stack_yield))	
	pending_stack_yield = {}
	
	all_clients_status = {}
	run_mode = RUN_MODE.NOTHING_TO_RUN
	interrupt_mode = InterruptMode.NONE
	interrupting_hero_id = 0
	_heroes_passed_optional_interrupt = {}
	set_current_interrupting_cards([])
	throttle_after_no_brakes = 0
	current_stack_uid= 0
	card_already_played_for_stack_uid = {}

	stack = []
	_current_interrupted_event = {}
	history = {}
	pending_interaction_checksums = {}
	_pending_flush = 0



func flush_logs():
	var display_text =JSON.print(history, '\t') + "\n"
	if pending_stack_yield:
		display_text+= JSON.print(pending_stack_yield, '\t') + "\n"
	if text_edit and is_instance_valid(text_edit):
		display_text += text_edit.text + "\n"
		text_edit.text = ""
	cfc.LOG(display_text)


func display_debug_info():
	if (!text_edit):
	 create_text_edit()
	
	if (!text_edit or !is_instance_valid(text_edit)):
		return

	var display_text = ""
	if run_mode != RUN_MODE.NOTHING_TO_RUN:
		 display_text += "run mode: " + RunModeStr[run_mode] + "\n"
	if interrupt_mode != InterruptMode.NONE:
		display_text += "interrupt_mode" + InterruptModeStr[interrupt_mode] + "\n" 

	for event in stack:
		display_text += str(event.stack_uid) + " - " + event.get_display_name() + "\n"
	
	if display_text != text_edit.text:
		text_edit.text = display_text
	if text_edit.text:
		text_edit.visible = true
	else:
		text_edit.visible = false

func display_debug(msg):
	gameData.display_debug("{stack}{uid:" + str(current_stack_uid) +"}" + msg, "")


func create_text_edit():
	if not cfc.NMAP.has("board") or not is_instance_valid(cfc.NMAP.board):
		return
	text_edit = TextEdit.new()  # Create a new TextEdit node
	text_edit.text = ""  # Set default text
	text_edit.rect_min_size = Vector2(300, 200)  # Set minimum size
	text_edit.wrap_enabled = true  # Enable text wrapping
	cfc.NMAP.board.add_child(text_edit)  # Add it to the current scene
	text_edit.anchor_left = 0.6
	text_edit.anchor_right = 1
	text_edit.anchor_top = 0.25
	text_edit.visible = false
	#text_edit.anchor_bottom = 0.5	

# Ensures proper cleanup when a card is queue_free() for any reason
func _on_tree_exiting():	
	flush_logs()

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		flush_logs()
	
