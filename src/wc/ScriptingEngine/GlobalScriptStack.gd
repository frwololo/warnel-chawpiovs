# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name GlobalScriptStack
extends Node2D

#Action stack (similar to the MTG stack) where actions get piled, waiting for user input if needed

#Types of Stack Objects:
#StackScript: regular event using an sceng, typically an ability from a card
#SimplifiedStackScript: quick and dirty task created in the code that doesn't involve Cost payments etc...
#SignalStackScript: a scripting bus signal added to the stack
# Example: "enemy_initiates_attack" is added to the stack before enemy attack starts

#Global or "Remote" scripts are sent by *one* client to the master,
#in order to be propagated to all clients (including self) for execution.
#
#"Local" scripts are run locally by all clients, and for sync purposes it is expected that all clients
#will want to run the exact same local scripts at the exact same moment.
#To enforce this, there is a mechanism where they all wait for the game master to tell them 
#it's ok to run the script. 
#At the end of the day, the main difference between global and local scripts is that sometimes 
#I don't want to bother guessing who's responsible for sending the script globally. This might be worth correcting
#

signal script_executed_from_stack(script)
signal script_added_to_stack(script)

enum STACK_STATUS {
	NONE,
	PENDING_UID,
	PENDING_CLIENT_ACK,
	READY_TO_EXECUTE,
	EXECUTING,
	DONE,	
	PENDING_REMOVAL,

}

const StackStatusStr := [
	"NONE",
	"PENDING_UID",
	"PENDING_CLIENT_ACK",
	"READY_TO_EXECUTE",
	"EXECUTING",
	"DONE",	
	"PENDING_REMOVAL",	
]

enum InterruptMode {
	NONE,
	FORCED_INTERRUPT_CHECK,
	OPTIONAL_INTERRUPT_CHECK,
	HERO_IS_INTERRUPTING,
	NOBODY_IS_INTERRUPTING
}

const InterruptModeStr := [
	"NONE",
	"FORCED_INTERRUPT_CHECK",
	"OPTIONAL_INTERRUPT_CHECK",
	"HERO_IS_INTERRUPTING",
	"NOBODY_IS_INTERRUPTING"
]

const INTERRUPT_FILTER := {
	InterruptMode.FORCED_INTERRUPT_CHECK:  CFConst.CanInterrupt.MUST,
	InterruptMode.OPTIONAL_INTERRUPT_CHECK: CFConst.CanInterrupt.MAY,
}

var interrupt_mode:int = InterruptMode.NONE
var interrupting_hero_id = 0

#potential_interrupters:
#	{hero_id => [list of cards that can interrupt] or "skip"}
var potential_interrupters: Dictionary = {}

#client_current_mode:
#	{network_id => current interrupt mode for the player}
var clients_current_mode: Dictionary = {}
var stack_integrity_check: Dictionary = {}


#the Stack is actually a dictionary, indexed by stack_uids.
#The real ordering is performed by the master_queue below
var stack:Dictionary = {}
var master_queue: Array = []
var waitOneMoreTick = 0
var time_since_started_waiting:float = 0


#stores data relevant to the ongoing interrupt signal
var _current_interrupted_event: Dictionary = {}

#stores unique IDs for all stack events
var current_stack_uid:int = 0
var current_local_uid: int = 0
var pending_local_scripts: Dictionary = {}

var stack_uid_to_object:Dictionary = {}
var object_to_stack_uid:Dictionary = {}
var card_already_played_for_stack_uid:Dictionary = {}


var my_script_requests_pending_execution: = 0

#display
#TODO something fancier
var text_edit:TextEdit = null

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

func get_next_local_uid():
	#setup UID for the stack event
	current_local_uid = current_local_uid + 1
	return current_local_uid

func get_next_stack_uid():
	#setup UID for the stack event
	current_stack_uid = current_stack_uid + 1
	return current_stack_uid

func create_and_add_simplescript( _owner, trigger_card, definition,  trigger_details):
	#we deconstruct locally here to reconstruct it on all clients then add it to all stacks
	#also send GUIDs to find the right cards/targets

	var owner_uid = guidMaster.get_guid(_owner)
	var trigger_card_uid = guidMaster.get_guid(trigger_card)
	my_script_requests_pending_execution += 1	
	rpc_id(1, "master_create_and_add_simplescript",  owner_uid, trigger_card_uid, definition, trigger_details)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_simplescript(  _owner_uid, trigger_card_uid, definition, trigger_details):
	var stack_uid = get_next_stack_uid()
	var client_id = get_tree().get_rpc_sender_id() 		
	add_to_ordering_queue(stack_uid, client_id)
	rpc("client_create_and_add_simplescript", stack_uid, _owner_uid, trigger_card_uid, definition, trigger_details)

remotesync func client_create_and_add_simplescript( stack_uid, _owner_uid, trigger_card_uid, definition, trigger_details):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " wants me to add a script:" + str(definition["name"]) )

	var owner_card = guidMaster.get_object_by_guid(_owner_uid)
	var trigger_card = guidMaster.get_object_by_guid(trigger_card_uid)
	var script = definition
	var script_name = script["name"]
	var task = ScriptTask.new(owner_card, script, trigger_card, trigger_details)	
	var stackEvent = SimplifiedStackScript.new(script_name, task)

	add_script(stackEvent, stack_uid)
	rpc_id(1, "from_client_script_received_ack", stack_uid)

func create_and_add_signal(_name, _owner, _details):
	#we deconstruct locally here to reconstruct it on all clients then add it to all stacks
	#also send GUIDs to find the right cards/targets
	
	var owner_uid = guidMaster.get_guid(_owner)
	my_script_requests_pending_execution += 1
	rpc_id(1, "master_create_and_add_signal", _name, owner_uid, _details)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_signal( _name, _owner_uid, _details):
	var stack_uid = get_next_stack_uid()
	var client_id = get_tree().get_rpc_sender_id() 	
	add_to_ordering_queue(stack_uid, client_id)	
	rpc("client_create_and_add_signal", stack_uid, _name, _owner_uid, _details)

remotesync func client_create_and_add_signal(stack_uid, _name, _owner_uid, _details):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " wants me to add a signal:" + _name)

	var owner_card = guidMaster.get_object_by_guid(_owner_uid)
				
	var stackEvent:SignalStackScript = SignalStackScript.new(_name, owner_card, _details)
	add_script(stackEvent, stack_uid)
	rpc_id(1, "from_client_script_received_ack", stack_uid)

func create_and_add_script(sceng, run_type, trigger, trigger_details, action_name):
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
	rpc_id(1, "master_create_and_add_script", state_scripts, owner_uid, trigger_card_uid, run_type, trigger, remote_trigger_details, sceng.stored_integers, action_name)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_script(state_scripts, _owner_uid, trigger_card_uid,  run_type, trigger, remote_trigger_details, stored_integers, action_name):
	var client_id = get_tree().get_rpc_sender_id() 
	var stack_uid = get_next_stack_uid()
	add_to_ordering_queue(stack_uid, client_id)
	rpc("client_create_and_add_script", stack_uid, state_scripts, _owner_uid, trigger_card_uid, run_type, trigger, remote_trigger_details, stored_integers, action_name)		

remotesync func client_create_and_add_script(stack_uid, state_scripts, _owner_uid, trigger_card_uid,  run_type, trigger, remote_trigger_details, stored_integers, action_name):

	var trigger_card = guidMaster.get_object_by_guid(trigger_card_uid)
	var owner_card = guidMaster.get_object_by_guid(_owner_uid)

	#debug stuff
	var client_id = get_tree().get_rpc_sender_id() 
	display_debug(str(client_id) + " wants me to add a script for:" + action_name)
	#/debug
	
	var sceng = cfc.scripting_engine.new(
				state_scripts,
				owner_card,
				trigger_card,
				remote_trigger_details)
	sceng.stored_integers = stored_integers			
	var stackEvent:StackScript = StackScript.new(sceng, run_type, trigger)
	stackEvent.set_display_name(action_name)
	add_script(stackEvent, stack_uid)
	rpc_id(1, "from_client_script_received_ack", stack_uid)

func add_to_ordering_queue(stack_uid, requester_client_id = 0, starting_status = STACK_STATUS.PENDING_CLIENT_ACK, local_uid = 0, checksum = ""):
	display_debug("adding to queue: " + str(stack_uid))
	var status = {}
	for network_id in gameData.network_players:
		status[network_id] = starting_status
	var queue_item = {
		"requester_id": requester_client_id,
		"stack_uid" : stack_uid, 
		"status" : status,
		"local_uid": local_uid,
		"checksum": checksum,
	}
	master_queue.append(queue_item) 
	#process_next_queue_script()

mastersync func from_client_script_received_ack(stack_uid):
	var client_id = get_tree().get_rpc_sender_id() 	
	var found = change_queue_item_state(stack_uid, client_id, STACK_STATUS.READY_TO_EXECUTE,"from_client_script_received_ack")
	if found:
		display_debug(str(client_id) + " is ready to execute " +  str(stack_uid))
	else:
		display_debug(str(client_id) + " did an ack but I couldn't find " +  str(stack_uid))		
				
#	attempt_to_execute_from_queue(found)

#func attempt_to_execute_from_queue(found):
#	if !found:
#		var _error = 1
#		display_debug("trying to execute empty item from queue")	
#	if all_players_are_state(found, STACK_STATUS.READY_TO_EXECUTE):	
#		display_debug("ready to execute :" + to_json(found))	
#		master_execute_script(found["stack_uid"])

func get_next_script_uid_to_execute():
	for item in master_queue:
		if some_players_are_state(item, STACK_STATUS.EXECUTING):
			return 0
				
	for i in master_queue.size():
		var index = master_queue.size() -1 -i
		var item = master_queue[index]
		if all_players_are_state(item, STACK_STATUS.READY_TO_EXECUTE):
			return item["stack_uid"]
	return 0

mastersync func from_client_global_uid_received(stack_uid):
	var client_id = get_tree().get_rpc_sender_id() 	
	var found = change_queue_item_state(stack_uid, client_id, STACK_STATUS.READY_TO_EXECUTE,"from_client_global_uid_received")
			
	if found:
		display_debug(str(client_id) + " has received uid for their local script and is ready to execute " +  str(stack_uid))
	else:
		display_debug(str(client_id) + " has received uid for their local script but I couldn't find " +  str(stack_uid))				
			
#	attempt_to_execute_from_queue(found)

func display_status_error(client_id, stack_uid, expected, actual, calling_function = ""):
	display_debug("{error}()" + calling_function +")" + str(client_id) + " (uid: " + str(stack_uid) +") was expecting " +  StackStatusStr[expected] + ", but got " + StackStatusStr[actual])

func debug_queue_status_msg(status):
	var copy = status.duplicate(true)
	for network_id in gameData.network_players:
		copy["status"][network_id] = StackStatusStr[copy["status"][network_id]]
	return to_json(copy)

func find_in_queue(stack_uid):
	var found = null
	for item in master_queue:
		if item["stack_uid"] == stack_uid:
			found = item
			break
	return found

func change_queue_item_state(stack_uid, client_id, new_state, caller = ""):
	var _error = ""
	caller =  caller if caller else "change_queue_item_state"
	
	var found = find_in_queue(stack_uid)
	if !found:
		_error = "didn't find"
		display_debug("master queue didn't find " +str(stack_uid))		
		return
		
	var current_state = found["status"][client_id]
	var expected_state = STACK_STATUS.NONE
	#error check
	match new_state:
		STACK_STATUS.DONE:
			expected_state = STACK_STATUS.EXECUTING
			#pending_removal is an ok use case here because we sometimes remove the scrpt before receiving this signal
			if ! current_state in [STACK_STATUS.EXECUTING, STACK_STATUS.PENDING_REMOVAL]:
				_error = "state"
		STACK_STATUS.READY_TO_EXECUTE:
			expected_state = STACK_STATUS.PENDING_CLIENT_ACK
			if !current_state in [STACK_STATUS.PENDING_CLIENT_ACK, STACK_STATUS.PENDING_UID]:
				_error = "state"					
	
	if _error:
		match _error:
			"state":
				display_status_error( client_id,stack_uid, expected_state, current_state , caller)	
	
	if found["status"][client_id] == STACK_STATUS.PENDING_REMOVAL:
		pass
		#it's never ok to go back from a deleted state
	else:	
		found["status"][client_id] = new_state
	display_debug(str(client_id) + " Went from " + StackStatusStr[current_state] + " to " + StackStatusStr[new_state] + " for script " +  str(stack_uid))
	
	#post change actions
	match new_state:
		STACK_STATUS.PENDING_REMOVAL:
			if all_players_are_state(stack_uid, STACK_STATUS.PENDING_REMOVAL):
				display_debug("script " + str(stack_uid) + " is done done done. Removed")
				if found["requester_id"]:
					rpc_id(found["requester_id"], "one_of_your_scripts_was_finalized", stack_uid)
				master_queue.erase(found)
				return null
	return found

remotesync func one_of_your_scripts_was_finalized(stack_uid):
	my_script_requests_pending_execution -=1
	if (my_script_requests_pending_execution <0):
		var _error = 1
		#TODO
		my_script_requests_pending_execution = 0

func some_players_are_state(item_or_stack_uid, state):
	var count = count_item_state(item_or_stack_uid, state)
	if count > 0:
		return true
	return false

func all_players_are_state(item_or_stack_uid, state):
	var count = count_item_state(item_or_stack_uid, state)
	if count == gameData.network_players.size():
		return true
	return false
	
func all_players_same_state(item_or_stack_uid):
	var found = item_or_stack_uid
	if typeof(found) == TYPE_INT:
		found = find_in_queue(found)
		if !found:
			return 0
	var status = -1		
	
	for network_id in gameData.network_players:
		if status ==-1:
			status = found["status"][network_id]
		if found["status"][network_id] != status:
			return false
	return true

func count_item_state(item_or_stack_uid, state):
	var found = item_or_stack_uid
	if typeof(item_or_stack_uid) == TYPE_INT:
		found = find_in_queue(item_or_stack_uid)
		if !found:
			return 0
		
	var count = 0	
	for network_id in gameData.network_players:
		if found["status"][network_id] == state:
			count+=1
	return count
	
mastersync func from_client_script_executed(stack_uid):
	var client_id = get_tree().get_rpc_sender_id() 
	
	# at this point it is likely the client has already 
	# sent a signal for removal of the script
	# but just in case we try here as well 
	if !find_in_queue(stack_uid):
		return
	
	var found = change_queue_item_state(stack_uid, client_id, STACK_STATUS.DONE, "from_client_script_executed")
	if !found:
		return
		
	if found:
		display_debug("(from_client_script_executed) " + str(client_id) + " has executed " +  str(stack_uid) + ", will now remove")
		change_queue_item_state(stack_uid, client_id, STACK_STATUS.PENDING_REMOVAL, "from_client_script_executed")

	
#func process_next_queue_script():
#	var script = master_queue.back()
#
#	#nothing to do
#	if !script:
#		return
#	if all_players_are_state(script, STACK_STATUS.READY_TO_EXECUTE):	
#		master_execute_script(script["stack_uid"])
	

#func master_execute_script(stack_uid):
#	#todo check it in the queue
#	var found = find_in_queue(stack_uid)
#
#	if !found:
#		var _error = 1
#		display_debug("I'm supposed to initiate execution of " +str(stack_uid) + " but I didn't find it")	
#		return
#		#TODO error handling
#
#	for network_id in gameData.network_players:
#		change_queue_item_state(stack_uid,network_id,STACK_STATUS.EXECUTING,"master_execute_script")
#

mastersync func master_i_need_id_for_local_script (local_uid, checksum):
	var client_id = get_tree().get_rpc_sender_id()
	var found = {}
	var uid = 0
	for data in master_queue:
		var _local_uid = data["local_uid"]
		if _local_uid == local_uid:
			found = data
			uid = data["stack_uid"]
			if data["checksum"] != checksum:
				var _error = 1
				#TODO desync here
	if !found:  #master queue never heard of this request, we create it
		uid = get_next_stack_uid()
		add_to_ordering_queue(uid, 0,  STACK_STATUS.NONE, local_uid, checksum)

	change_queue_item_state(uid,client_id, STACK_STATUS.PENDING_UID,"master_i_need_id_for_local_script")
	rpc_id(client_id, "global_uid_assigned", local_uid, uid)


remotesync func global_uid_assigned(local_uid,stack_uid):
	if !cfc.is_game_master():
		var verification_uid = get_next_stack_uid()
		if verification_uid != stack_uid:
			var _error = 1
			#TODO this is baad
				
	var object = pending_local_scripts[local_uid]
	
	add_to_stack(object, stack_uid)
	object.set_display_name(object.get_display_name() + "(local)")	
	#warning-ignore:RETURN_VALUE_DISCARDED	
	pending_local_scripts.erase(local_uid)
	rpc_id(1, "from_client_global_uid_received", stack_uid)

func add_script(object, stack_uid:int = 0):
	#if somebody is adding a script while in interrupt mode,
	# we add the script (its owner card for now - TODO need to change?)
	# to the list of scripts that already responded to the last event
	#this prevents them from triggering infinitely to the same event 
	if interrupt_mode == InterruptMode.HERO_IS_INTERRUPTING:
		var script_being_interrupted = self.stack_back()
		if (script_being_interrupted):
			var script_uid = script_being_interrupted.stack_uid
			if (!card_already_played_for_stack_uid.has(script_uid)):
				card_already_played_for_stack_uid[script_uid] = []
			card_already_played_for_stack_uid[script_uid].append(object.sceng.owner)

	#local use case, we're waiting for the master to give us an ID		
	if (!stack_uid):
		var local_uid = get_next_local_uid()
		pending_local_scripts[local_uid] = object		
		rpc_id (1, "master_i_need_id_for_local_script", local_uid, object.get_display_name())	

	else:
		#error check
		if !cfc.is_game_master():
			var verification_uid = get_next_stack_uid()
			if verification_uid != stack_uid:
				var _error = 1
				#TODO this is baad
		object.set_display_name(object.get_display_name() + "(network)")
		add_to_stack(object, stack_uid)

	return


func add_to_stack(object, stack_uid):
	#flush_top_script()
	
	object.stack_uid = stack_uid

	stack[stack_uid] = object
	#stack.sort_custom(StackObject, "sort_stack")
	var msg = "["
	for stack_uid in stack:
		msg+= str(stack_uid) +"-" + stack[stack_uid].get_display_name() + ","
	msg += "]"
	display_debug("my stack: " + msg)
	emit_signal("script_added_to_stack", object)
	reset_interrupt_states()
	rpc_id(1, "master_stack_object_added", object.stack_uid)	

func flush_script(stack_uid):
	if !interrupt_mode == InterruptMode.NOBODY_IS_INTERRUPTING:
		return	
	set_interrupt_mode(InterruptMode.NONE)
	var next_script = stack.get(stack_uid)
	if !next_script:
		display_debug("asked for executing script but I have nothing on my stack")
		var _error = 1
		return
	display_debug("executing: " + str(next_script.stack_uid) + "-" + next_script.get_display_name())
	stack_remove(stack_uid)
	var func_return = next_script.execute()	
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()
	
	rpc_id(1, "from_client_script_executed", stack_uid)	
	emit_signal("script_executed_from_stack", next_script )		
	

func reset_interrupt_states():
	reset_phase_buttons()
	interrupting_hero_id = 0
	potential_interrupters = {}
	set_interrupt_mode(InterruptMode.NONE)

func _exit_tree():
	if (text_edit and is_instance_valid(text_edit)):
		cfc.NMAP.board.remove_child(text_edit)
	text_edit = null
		
		
func clients_status_aligned():
	for client in clients_current_mode:

		if clients_current_mode[client] != interrupt_mode:
			display_debug("need to wait: interrupt mode not the same (" +str(interrupt_mode) + " vs " + str(clients_current_mode[client]) + ")")			
			return false
			
	for client in stack_integrity_check:
		var their_stack = stack_integrity_check[client]
		if their_stack.size() != stack.size():
			display_debug("need to wait: stacks not the same (" +str(stack.size()) + " vs " + str(their_stack.size()) + ")")
			return false

	for item in master_queue:
		if !all_players_same_state(item):
			display_debug("need to wait: script status not the same (" +debug_queue_status_msg(item) )
			return false
			
	return true
	
func _process(_delta: float):
	
	if (!text_edit):
		 create_text_edit()
	
	if (!text_edit or !is_instance_valid(text_edit)):
		return

	var display_text = ""
	if master_queue:
		display_text += "--master_queue--\n"
	for item in master_queue:
		display_text+= debug_queue_status_msg(item) + "\n"
	if stack:
		display_text += "--stack--\n"		
	for stack_uid in stack:
		display_text += "{" + str(stack_uid) + "}" + stack[stack_uid].get_display_name() + "\n"
	
	if display_text != text_edit.text:
		text_edit.text = display_text
	if text_edit.text:
		text_edit.visible = true
	else:
		text_edit.visible = false
	
	if stack.empty(): 
		return

	
	if gameData.is_ongoing_blocking_announce():
		return
			
	if (gameData.user_input_ongoing):
		waitOneMoreTick = 2; #TODO MAGIC NUMBER. Why do we have to wait 2 passes before damage gets prevented?
		return
	
	if waitOneMoreTick:
		waitOneMoreTick -= 1
		return		
	

	match interrupt_mode:
		InterruptMode.NONE:
			if cfc.is_game_master():
				#if not everyone is ready here, I need to wait
				if !clients_status_aligned():
					time_since_started_waiting += _delta
					if CFConst.DESYNC_TIMEOUT and time_since_started_waiting > CFConst.DESYNC_TIMEOUT:
						gameData.phaseContainer.flush_debug_display()
						gameData.init_desync_recover()
						time_since_started_waiting = 0.0
					return	
				else:
					time_since_started_waiting = 0.0
					compute_interrupts(InterruptMode.FORCED_INTERRUPT_CHECK)
				#rpc("client_send_before_trigger", interrupt_mode)

					
	return	


func has_script(script):
	for uid in stack:
		var _script = stack[uid]
		if script == _script:
			return true
	return false

#Instead of deleting a stack we refresh the existing one
#by cleaning up all bean counters
func reset():
	display_debug("STACK RESET (NEW GAME?)")
	current_stack_uid = 0
	reset_interrupt_states()
	stack = {}
	clients_current_mode = {}
	stack_integrity_check = {}
	waitOneMoreTick = 0
	_current_interrupted_event= {}
	stack_uid_to_object = {}
	object_to_stack_uid = {}
	card_already_played_for_stack_uid = {}	
	current_local_uid= 0
	pending_local_scripts = {}
	my_script_requests_pending_execution = 0
	
	master_queue = []

func is_phasecontainer_allowed_to_proceed():
	if !stack.empty():
		return false
	if my_script_requests_pending_execution:
		return false		

	if cfc.is_game_master():
		if !master_queue.empty():
			for item in master_queue:
				#TODO hack
				#one weird blocker case is if one of the players is pending
				# a local uid. I let it through for now 
				for network_id in gameData.network_players:
					if item["status"][network_id] == STACK_STATUS.NONE:
						return true
			return false

	return true
	
func is_empty():
	if !stack.empty():
		return false
	if cfc.is_game_master():
		if !master_queue.empty():
			return false
	if my_script_requests_pending_execution:
		return false
	return true

#returns true if the stack is waiting for automated "acks" to move to the next steps
func is_processing():
	match interrupt_mode:
		InterruptMode.FORCED_INTERRUPT_CHECK:
			return true
		InterruptMode.OPTIONAL_INTERRUPT_CHECK:
			return true
		InterruptMode.HERO_IS_INTERRUPTING:
			return false
		_:
			return !stack.empty()

func display_debug(msg):
	gameData.display_debug("{stack} " + msg, "")

func set_interrupt_mode(value:int):
	interrupt_mode = value
	display_debug("I'm now in mode:" +  InterruptModeStr[interrupt_mode] )
	rpc_id(1, "master_interrupt_mode_changed", interrupt_mode)
	gameData.game_state_changed()

func get_current_interrupted_event():
	return self._current_interrupted_event

#Master computes if any card on the board can interrupt the current stack on the list
func compute_interrupts(_interrupt_mode):
	if !( _interrupt_mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]):
		var _error = 1
	
	var uid = get_next_script_uid_to_execute()
	if !uid:
		return	
	set_interrupt_mode(_interrupt_mode)
	var script = stack[uid]
	if (! script):
		#TODO error, this shouldn't happen
		return
	var script_uid = script.stack_uid

	for i in range(gameData.get_team_size()):
		var hero_id = i+1
		var tasks = script.get_tasks()
		var my_interrupters:= []
		for task in tasks:
			_current_interrupted_event = task.script_definition.duplicate()
			_current_interrupted_event["event_name"] = task.script_name
			_current_interrupted_event["event_object"] = task
			for card in get_tree().get_nodes_in_group("cards"):
				if (card in card_already_played_for_stack_uid.get(script_uid, [])):
					continue
				if (task.script_name == "receive_damage"):
					if (card.canonical_name == "Spider-Man"):
						var _tmp = 1
				var can_interrupt = card.can_interrupt(hero_id,task.owner, _current_interrupted_event)
				if can_interrupt == INTERRUPT_FILTER[_interrupt_mode]:
					var guid = guidMaster.get_guid(card)
					my_interrupters.append(guid)
	
		potential_interrupters[hero_id] = my_interrupters	
	
	#this fills similar data into clients and will then call the "select_interrupters" step
	rpc("blank_compute_interrupts", script_uid)
					 

var _blank_interrupts_computed:= {}
mastersync func blank_interrupts_computed():
	var client_id = get_tree().get_rpc_sender_id()
	_blank_interrupts_computed[client_id] = true
	if _blank_interrupts_computed.size() == gameData.network_players.size():
		_blank_interrupts_computed = {}
		select_interrupting_player()
#an empty call for clients to fill necessary data (_current_interrupted_event)
# need to make something cleaner
remotesync func blank_compute_interrupts(stack_uid):
	var script = stack[stack_uid]
	if (! script):
		#TODO error, this shouldn't happen
		return
	var tasks = script.get_tasks()
	for task in tasks:
		_current_interrupted_event = task.script_definition.duplicate()
		_current_interrupted_event["event_name"] = task.script_name
		_current_interrupted_event["event_object"] = task
	
	rpc_id(1, "blank_interrupts_computed")

func select_interrupting_player():
	if !cfc.is_game_master():
		return #TODO error check, this shouldn't even be possible

	var uid = get_next_script_uid_to_execute()
	if !uid:
		return			
		
	for hero_id in potential_interrupters.keys():
		var interrupters = potential_interrupters[hero_id]
		if (interrupters):
			var forced_interrupt = false
			if (interrupt_mode == InterruptMode.FORCED_INTERRUPT_CHECK):
				forced_interrupt = true
			set_interrupt_mode(InterruptMode.HERO_IS_INTERRUPTING)
			rpc("client_set_interrupting_hero", hero_id)
			if (forced_interrupt):
				var network_hero_owner = gameData.get_network_id_by_hero_id(hero_id)
				rpc_id(network_hero_owner, "force_play_card", interrupters[0])
			return
	
	potential_interrupters = {}
	#nobody is interrupting for this step, move to the next one
	#(first check for the next interrupt level - optional interrupt -, then go to "nobody is interrupting"
	if (interrupt_mode == InterruptMode.FORCED_INTERRUPT_CHECK):

		set_interrupt_mode(InterruptMode.OPTIONAL_INTERRUPT_CHECK)
		compute_interrupts(interrupt_mode)
	else:
		set_interrupt_mode(InterruptMode.NOBODY_IS_INTERRUPTING)
		for network_id in gameData.network_players:
			change_queue_item_state(uid,network_id, STACK_STATUS.EXECUTING, "select_interrupting_player")
		rpc("client_execute_script", uid)
	return

remotesync func client_execute_script(script_uid):
	set_interrupt_mode(InterruptMode.NOBODY_IS_INTERRUPTING)
	flush_script(script_uid)

#pass my opportunity to interrupt 
func pass_interrupt (hero_id):
	if not hero_id in gameData.get_my_heroes():
		cfc.LOG("{error}: pass_interrupt called for hero_id by non controlling player")
		return
	rpc_id(1,"master_pass_interrupt", hero_id)
	
#call to master when I've chosen to pass my opportunity to interrupt 
mastersync func master_pass_interrupt (hero_id):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " wants to pass for hero:" + str(hero_id) )
	
	#TODO ensure that caller network id actually controls that hero
	reset_phase_buttons()
	potential_interrupters[hero_id] = []
	select_interrupting_player()

#forced activation of card for forced interrupt
remotesync func force_play_card(card_guid):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " forces interrupt for card_guid:" + str(card_guid) )
	
	var card = guidMaster.get_object_by_guid(card_guid)
	card.attempt_to_play()



func reset_phase_buttons():
	for i in range (gameData.team.size()):
		gameData.phaseContainer.reset_hero_activation_for_step(i+1)

func activate_exclusive_hero(hero_id):
	for i in range (gameData.team.size()):
		var hero_index = i+1
		if (hero_index == hero_id):
			gameData.phaseContainer.activate_hero(hero_index)
		else:
			gameData.phaseContainer.deactivate_hero(hero_index)	
	
remotesync func client_set_interrupting_hero(hero_id):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " sets interrupting hero to:" + str(hero_id) )
	
	set_interrupt_mode(InterruptMode.HERO_IS_INTERRUPTING)	
	interrupting_hero_id = hero_id
	activate_exclusive_hero(hero_id)
	
remotesync func client_move_to_next_step(_interrupt_mode):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " wants me to move to next step:" + InterruptModeStr[_interrupt_mode] )
	
	set_interrupt_mode(_interrupt_mode)
	reset_phase_buttons()
	potential_interrupters = {}
	if (interrupt_mode == InterruptMode.NOBODY_IS_INTERRUPTING):
		interrupting_hero_id = 0
	
#func _delete_object(variant):
#	if (!variant):
#		return false				
#	var id_to_delete = 0
#	for stack_uid in stack:
#		if stack[stack_uid] == variant:
#			id_to_delete = stack_uid
#	if (id_to_delete):		 
#		stack.erase(id_to_delete)
#		rpc_id(1, "master_stack_object_removed", variant.stack_uid )
#		#Remove item from master queue as well
#		#TODO this shoud live elsewhere
#		var to_erase_idx = -1
#		for i in master_queue.size():
#			var item = master_queue[i]
#			if item["stack_uid"] == id_to_delete:
#				to_erase_idx = i
#		if to_erase_idx >=0:
#			master_queue.remove(to_erase_idx)
#	return true


func stack_back_id():
	var max_uid = 0
	for stack_uid in stack:
		if stack_uid > max_uid:
			max_uid = stack_uid
	return max_uid

#LEGACY! THIS SHOULDN'T WORK THIS WAY ANYMORE	
func stack_back():
	var max_uid = stack_back_id()
	var event = stack.get(max_uid, null)		
	return event 

func stack_remove(stack_uid):
	stack.erase(stack_uid)
	
	rpc_id(1, "master_stack_object_removed", stack_uid)	
		
func stack_pop_back():
	var max_uid = stack_back_id()
	var event = null 
	if (max_uid):
		event = stack[max_uid]
		stack_remove(max_uid)
	return event
	
	
func delete_last_event():
	var event = stack_pop_back()
	scripting_bus.emit_signal("stack_event_deleted", event)
	
func find_last_event():
	return stack_back()

func find_event(_event_details, details, owner_card):
	for stack_uid in stack:
		var event = stack[stack_uid]
		var task = event.get_script_by_event_details(_event_details)			
		if (!task):
			continue			
		if event.matches_filters(task, details, owner_card):
			return event
	return null			

#todo in the future this needs to redo targeting, etc...
func replace_subjects(stack_object, value, script):
	match value:
		"self":
			stack_object.replace_subjects([script.owner])
		_:
			#not implemented
			pass

#scripted replacement effects
func modify_object(stack_object, script:ScriptTask):
	match script.script_name:
		"prevent":
			var amount = script.retrieve_integer_property("amount")
			if !amount:
				var _error = 1
			else:
				stack_object.prevent_value("amount", amount)
		_:
			var replacements = script.get_property("replacements", {})
			for property in replacements.keys():
				var value = replacements[property]
				match property:
					"subject":
						replace_subjects(stack_object, value, script)
					_:
						#not implemented
						pass
	
	
	
#is the current player allowed to play according to the stack?
#returns an array of hero ids if so, empty array otherwise
func can_my_heroes_play() -> Array:
	match interrupt_mode:
		InterruptMode.NONE:
			#nothing going on, but if there's something on the stack I can't play until it resolves
			if (!stack.empty()):
				return []
			return gameData.get_my_heroes()
		InterruptMode.HERO_IS_INTERRUPTING:
			if gameData.can_i_play_this_hero(self.interrupting_hero_id):
				return[self.interrupting_hero_id]
			return[]
		InterruptMode.NOBODY_IS_INTERRUPTING:
			#nothing going on, but if there's something on the stack I can't play until it resolves
			if (!stack.empty()):
				return []
			return gameData.get_my_heroes()
		_:
			#we're in the process of checking who can interrupt.
			#Nobody can play
			return []						
	
func get_interrupt_mode() -> int:
	return interrupt_mode

mastersync func master_stack_object_added (object_uid):
	var client_id = get_tree().get_rpc_sender_id()
	if !stack_integrity_check.has(client_id):
		stack_integrity_check[client_id] = []
	stack_integrity_check[client_id].append(object_uid)
	stack_integrity_check[client_id].sort()

mastersync func master_stack_object_removed (object_uid):
	var client_id = get_tree().get_rpc_sender_id()
	if !stack_integrity_check.has(client_id):
		stack_integrity_check[client_id] = []
	#todo better checks	
	stack_integrity_check[client_id].erase(object_uid)
	stack_integrity_check[client_id].sort()
	
	change_queue_item_state(object_uid, client_id, STACK_STATUS.PENDING_REMOVAL, "master_stack_object_removed" )
	

mastersync func master_interrupt_mode_changed( _interrupt_mode):
	var client_id = get_tree().get_rpc_sender_id()
	clients_current_mode[client_id] = _interrupt_mode

#Docs & Notes

#Scenario:
#Player A plays a card "Blub" that says "add 2 threat to the main scheme"
#Player B has "Great responsibility" (when any amount of threat would be placed on a scheme, you take it as damage instead)
#Need to be given an opportunity to interrupt!
#
#Proposed solution:
#Player A plays Blub
#Pays costs (locally)
#"Put in play" script goes into ALL stacks
#before unstacking, master send "interrupt" signal

#If I'm the master, 
#if "interrupters" is all "skip": go to "interrupters has nobody" step
#Else:
#send interrupt signal to all clients. I Wait for ack 
#Wait for ack == set array interrupters [nb_players] to empty and fill it with each players when ack has matching interrupt details.
#Example of ack: "interrupt put in play blurb -> me (player 1) has a potential interrupt
#
#Client side:
#1) receive "interrupt" signal. set "interrupt mode" to INTERRUPT_CHECK
#2) run through check interrupt for all my cards
#3) if I have at least a card to interrupt with, send "ack" + list of cards, otherwise ack + "skip" (empty list of cards)
#(interrupt mode is still INTERRUPT_CHECK)
#As long as interrupt mode is INTERRUPT CHECK, I cannot play anything
#
#Server side: once interrupters[] has all players:
#
#If interrupters has nobody or interrupters is all "skip":
#master 0) resets "interrupters", 1) pops and executes locally  "put in play" then 1.5) tells remote that "interrupt mode" is off and 2) tells them to run the stack event
#
#Else if interrupters has 1 or more person without "skip":
#master doesn't pop the next script.
#Instead
#0) interrupting player is next player in the interrupters list that doesn't say "skip"
#1) master tells all clients that interrupt_mode becomes "PLAYER_IS_INTERRUPTING" and tells them interrupt_player is (interrupt hero)
#
#Client side:
#if I am the interrupting player, and mode is "PLAYER_IS_INTERRUPTING", let me play my cards for interrupt:
#	1) I pay my card (locally
#	2) script goes into all stacks
#	3) when a script is added to all stacks, "interrupt_mode" is set to NONE (0)
#	Alternatively:
#	1) I click "pass"
#	2) this sends a message to master. Master sets "skip_interrupt" to true for my player in his "interrupters" dictionary
#	3) master moves to the next interrupter player. If there is none: go back to "interrupters has nobody"
#
#If I am *not" the interrupting player and  mode is "PLAYER_IS_INTERRUPTING", I cannot play anything, but I display the face of interrupting player on my screen for visibility
#
#
#Forced interrupts:
#Issues: I was thinking of doing the same as optional interrupts, however: they may trigger infinite times (the same might be true for optional interrupts btw...)
#--> need to implement a system where we trigger (or can activate) only once for a singular event ? Each stack object gets a unique ID (controlled by network master?)
#Sending an interrupt signal also includes the event unique ID.
#when a card/ability is *played* in *response* to this specific event, add a value in globalscript dictionary to mark this card/event combination as "used" --> cannot trigger again
