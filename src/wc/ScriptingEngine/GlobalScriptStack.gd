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


enum NETWORK_ERROR {
	NONE,
	LOCAL_UID_NOT_FOUND,
}


enum InterruptMode {
	UNKNOWN,
	NONE,
	FORCED_INTERRUPT_CHECK,
	OPTIONAL_INTERRUPT_CHECK,
	HERO_IS_INTERRUPTING,
	NOBODY_IS_INTERRUPTING
}

const InterruptModeStr := [
	"UNKNOWN",	
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
var reference_queue: Dictionary = {}
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

func _rpc(func_name, arg0=null,
	arg1 =null,
	arg2 =null,
	arg3 =null,
	arg4 =null,
	arg5 =null,
	arg6 = null,
	arg7 = null,
	arg8 = null):
	
	var params = [func_name]
	for i in [arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8]:
		if i== null:
			break
		params.append(i)

	if !CFConst.DEBUG_ENABLE_NETWORK_TEST:	
		return self.callv("rpc", params)
	
	#below this line is for network debugging mode
	#randomize players, then sleep randomly between rpc calls
	var players = gameData.network_players.keys().duplicate()
	
	CFUtils.shuffle_array(players, true)
	for p_id in players:
		var pparams = params.duplicate()
		pparams.push_front(p_id)	
		var send = 100
		if CFConst.DEBUG_SIMULATE_NETWORK_PACKET_DROP:
			send = randi()%(100)
		if send > 9: #sometimes we just don't send the packet
			if CFConst.DEBUG_SIMULATE_NETWORK_DELAY:
				yield(get_tree().create_timer(randf()), "timeout")
			self.callv("rpc_id", pparams)	
		else:
			display_debug("decided to drop a packet for function call " + func_name)

func _rpc_id(id, func_name, arg0=null,
	arg1 =null,
	arg2 =null,
	arg3 =null,
	arg4 =null,
	arg5 =null,
	arg6 = null,
	arg7 = null,
	arg8 = null):
	
	var params = [id, func_name]
	for i in [arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8]:
		if i== null:
			break
		params.append(i)
	
	if !CFConst.DEBUG_ENABLE_NETWORK_TEST:
		return self.callv("rpc_id", params)	

	#below this line is for network debugging mode
	#sleep randomly befor rpc call
	var send = 100
	if CFConst.DEBUG_SIMULATE_NETWORK_PACKET_DROP:
		send = randi()%(100)
	if send > 9: #sometimes we just don't send the packet
		if CFConst.DEBUG_SIMULATE_NETWORK_DELAY:
			yield(get_tree().create_timer(randf()), "timeout")
		return self.callv("rpc_id", params)	
	else:
		display_debug("decided to drop a packet for function call " + func_name)			


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
	_rpc_id(1, "master_create_and_add_simplescript",  owner_uid, trigger_card_uid, definition, trigger_details)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_simplescript(  _owner_uid, trigger_card_uid, definition, trigger_details):
	var stack_uid = get_next_stack_uid()
	var client_id = get_tree().get_rpc_sender_id() 		
	var original_details = {
		"type": "simplescript",
		"owner_uid": _owner_uid, 
		"trigger_card_uid": trigger_card_uid, 
		"definition": definition, 
		"trigger_details": trigger_details
	}
	add_to_ordering_queue(stack_uid, original_details, client_id)
	_rpc("client_create_and_add_stackobject", stack_uid, original_details)


func client_create_simplescript( details):
	var _owner_uid = details["owner_id"]
	var trigger_card_uid = details["trigger_card_uid"]
	var definition = details["definition"]
	var trigger_details = details["trigger_details"]
	

	var owner_card = guidMaster.get_object_by_guid(_owner_uid)
	var trigger_card = guidMaster.get_object_by_guid(trigger_card_uid)
	var script = definition
#	var script_name = script["name"]
	var task = ScriptTask.new(owner_card, script, trigger_card, trigger_details)	
	var stackEvent = SimplifiedStackScript.new(task)
	return stackEvent


func create_and_add_signal(_name, _owner, _details):
	#we deconstruct locally here to reconstruct it on all clients then add it to all stacks
	#also send GUIDs to find the right cards/targets
	
	var owner_uid = guidMaster.get_guid(_owner)
	my_script_requests_pending_execution += 1
	_rpc_id(1, "master_create_and_add_signal", _name, owner_uid, _details)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_signal( _name, _owner_uid, _details):
	var stack_uid = get_next_stack_uid()
	var client_id = get_tree().get_rpc_sender_id() 	

	var original_details = {
		"type": "signal",
		"owner_uid": _owner_uid, 
		"trigger_details": _details,
		"name": _name
	}	
	
	add_to_ordering_queue(stack_uid, original_details, client_id)	
	_rpc("client_create_and_add_stackobject", stack_uid, original_details)

func client_create_signal(details):	
	var _owner_uid = details["owner_uid"]
	var _name = details["name"]
	var _details = details["trigger_details"] 

	var owner_card = guidMaster.get_object_by_guid(_owner_uid)
				
	var stackEvent:SignalStackScript = SignalStackScript.new(_name, owner_card, _details)
	return stackEvent

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
	_rpc_id(1, "master_create_and_add_script", state_scripts, owner_uid, trigger_card_uid, run_type, trigger, remote_trigger_details, sceng.stored_integers, action_name)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_script(state_scripts, owner_uid, trigger_card_uid,  run_type, trigger, remote_trigger_details, stored_integers, action_name):
	var client_id = get_tree().get_rpc_sender_id() 
	var stack_uid = get_next_stack_uid()

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
	
	add_to_ordering_queue(stack_uid, original_details,  client_id)
	_rpc("client_create_and_add_stackobject", stack_uid, original_details)		

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

remotesync func client_create_and_add_stackobject(stack_uid, details):
	var client_id = get_tree().get_rpc_sender_id()
	
	#if we already have that object on the stack, we assume it's an error check and 
	#just return an ack
	if reference_queue.get(stack_uid, null):
		_rpc_id(client_id, "from_client_script_received_ack", stack_uid)
		return
				
	var type = details["type"]
	display_debug(str(client_id) + " wants me to add a " + type + " with stack uid " +str(stack_uid))
	var stackEvent = null
	match type:
		"simplescript":
			stackEvent = client_create_simplescript(details)
		"signal":
			stackEvent = client_create_signal( details)
		_:	
			stackEvent = client_create_script(details)

	if !stackEvent:
		var _error = 1
		return
		
	add_script(stackEvent, stack_uid)
	_rpc_id(client_id, "from_client_script_received_ack", stack_uid)
			

func some_players_are_state(item_or_stack_uid, state):
	var item = item_or_stack_uid
	if (typeof(item) == TYPE_INT):
		item = find_in_queue(item)
	if !item:
		return false
	return item.some_players_are_state(state)

func all_players_are_state(item_or_stack_uid, state):
	var item = item_or_stack_uid
	if (typeof(item) == TYPE_INT):
		item = find_in_queue(item)
	if !item:
		return false
	return item.all_players_are_state(state)
	
func all_players_same_state(item_or_stack_uid):
	var item = item_or_stack_uid
	if (typeof(item) == TYPE_INT):
		item = find_in_queue(item)
	if !item:
		return false
	return item.all_players_same_state()
	
func change_queue_item_state(stack_uid, client_id, new_state, caller):
	var found:StackQueueItem = find_in_queue(stack_uid)
	if !found:
		return null
	
	found.change_queue_item_state(client_id, new_state, caller)
		
	#post change actions
	match new_state:
		StackQueueItem.STACK_STATUS.PENDING_REMOVAL:
			if found.all_players_are_state(StackQueueItem.STACK_STATUS.PENDING_REMOVAL):
				display_debug("script " + str(stack_uid) + " is done done done. Removed")
				if found.get_requester_id():
					_rpc_id(found.get_requester_id(), "one_of_your_scripts_was_finalized", stack_uid)
				master_queue.erase(found)
				return null
	
	return found
#all clients, for reference and error correction
#this is called when master tells me to add an object to the queue
#I'll keep track of that script's status here
func add_to_reference_queue(object, stack_uid, starting_status = StackQueueItem.STACK_STATUS.PENDING_CLIENT_ACK, local_uid = 0, checksum = ""):
	display_debug("adding to reference queue: " + str(stack_uid))
	var reference_item:StackReferenceItem = StackReferenceItem.new(object, stack_uid, starting_status, local_uid, checksum)

	if reference_queue.has(stack_uid):
		var _error = 1
		#TODO error handling here
		
	reference_queue[stack_uid] = reference_item

func is_reference_status(stack_uid,expected_status):
	var reference_object = reference_queue.get(stack_uid, null)
	if !reference_object:
		return false
	return (reference_object.get_status()  == expected_status)

#all clients, for reference and error correction
func set_reference_status(stack_uid, new_state, caller = ""):
	if !caller:
		caller = "set_reference_status"
	var reference_object = reference_queue.get(stack_uid, null)
	if !reference_object:
		#the object should have been added no matter what before this
		var _error = 1
		display_debug("reference queue didn't find " +str(stack_uid))	
	
	reference_object.change_reference_item_state(new_state, caller)	
	

# master only
func add_to_ordering_queue(stack_uid, script_details, requester_client_id = 0, starting_status = StackQueueItem.STACK_STATUS.PENDING_CLIENT_ACK, local_uid = 0, checksum = ""):
	display_debug("{master} adding new item to master_queue: " + str(stack_uid))
	var queue_item:StackQueueItem = StackQueueItem.new(stack_uid, script_details, requester_client_id, starting_status, local_uid, checksum)
	master_queue.append(queue_item) 
	#process_next_queue_script()

#client correctly received my request to add a script to the stack
mastersync func from_client_script_received_ack(stack_uid):
	var client_id = get_tree().get_rpc_sender_id() 	
	var found:StackQueueItem = change_queue_item_state(stack_uid, client_id, StackQueueItem.STACK_STATUS.READY_TO_EXECUTE,"from_client_script_received_ack")
	if found:
		if client_id == 1:
			found.set_human_readable(human_readable(stack_uid))
		display_debug(str(client_id) + " is ready to execute " +  str(stack_uid))
	else:
		display_debug(str(client_id) + " did an ack but I couldn't find " +  str(stack_uid))		
				
#look for the next script in stack
#that we want all clients to execute
#typically this should be the last one in the master_queue
# assuming all clients are ready to execute it
func get_next_script_uid_to_execute():
	if !master_queue:
		return 0
	#if some clients are still running some script, we wait
	for item in master_queue:
		if item.some_players_are_state(StackQueueItem.STACK_STATUS.EXECUTING):
			return 0

	#this should be the last on the pile
	
	var item:StackQueueItem = master_queue.back()		
	if all_players_are_state(item, StackQueueItem.STACK_STATUS.READY_TO_EXECUTE):
		return item.get_stack_uid()
				
#	for i in master_queue.size():
#		var index = master_queue.size() -1 -i
#		var item = master_queue[index]
#		if all_players_are_state(item, StackQueueItem.STACK_STATUS.READY_TO_EXECUTE):
#			return item["stack_uid"]
	return 0

#client was pending a global UID for their local script,
#and acknowledge that they now have received it
mastersync func from_client_global_uid_received(stack_uid):
	var client_id = get_tree().get_rpc_sender_id() 	
	var found:StackQueueItem = change_queue_item_state(stack_uid, client_id, StackQueueItem.STACK_STATUS.READY_TO_EXECUTE,"from_client_global_uid_received")
			
	if found:
		display_debug(str(client_id) + " has received uid for their local script and is ready to execute " +  str(stack_uid))
	else:
		display_debug(str(client_id) + " has received uid for their local script but I couldn't find " +  str(stack_uid))				
			
#	attempt_to_execute_from_queue(found)

func display_status_error(client_id, stack_uid, expected, actual, calling_function = ""):
	display_debug("{error}()" + calling_function +")" + str(client_id) + " (uid: " + str(stack_uid) +") was expecting " +  StackQueueItem.StackStatusStr[expected] + ", but got " + StackQueueItem.StackStatusStr[actual])

func debug_queue_status_msg(status):
	return status.debug_queue_status_msg()

func find_in_queue(stack_uid):
	var found = null
	for item in master_queue:
		if item.get_stack_uid() == stack_uid:
			found = item
			break
	return found

func human_readable(stack_uid):
	var found:StackQueueItem = find_in_queue(stack_uid)
	if !found:
		return str(stack_uid)
	if found.get_human_readable():
		return found.get_human_readable()
		
	var _human_readable = str(stack_uid) + "-"
	var stack_object = stack.get(stack_uid, null)
	if stack_object: 
		_human_readable += stack_object.get_display_name()
	else:
		_human_readable += ""
	return _human_readable


#Master lets me know that one of my (network) scripts was executed by all clients
remotesync func one_of_your_scripts_was_finalized(stack_uid):
	set_reference_status(stack_uid, StackQueueItem.STACK_STATUS.DONE)
	my_script_requests_pending_execution -=1
	if (my_script_requests_pending_execution <0):
		var _error = 1
		display_debug("{as client} I was told one of my scripts got executed, but I didn't know I had one")
		my_script_requests_pending_execution = 0


#Client tells me they have executed a script	
mastersync func from_client_script_executed(stack_uid):
	var client_id = get_tree().get_rpc_sender_id() 
	
	var found:StackQueueItem = find_in_queue(stack_uid)
	if !found:
		display_debug("error couldn't find script " +str(stack_uid) + " to mark it as done")
		return
	
	found.change_queue_item_state(client_id, StackQueueItem.STACK_STATUS.DONE, "from_client_script_executed")
	if !found:
		return
		
	if all_players_are_state(stack_uid, StackQueueItem.STACK_STATUS.DONE):
		display_debug("(from_client_script_executed) " + str(client_id) + " has executed " +  str(stack_uid) + " and they were last, will now ask to remove")
		_rpc("client_remove_script_from_stack_after_exec", stack_uid)
		
mastersync func from_client_script_removed_after_exec(stack_uid):
	var client_id = get_tree().get_rpc_sender_id() 
	#Note	
	#removal is done in change_queue_item_state
	#this function can be used for additional checks
	pass

func master_assign_local_script_uid(local_uid, client_id, checksum):
	var found = {}
	var uid = 0
	for data in master_queue:
		var _local_uid = data.get_local_uid()
		if _local_uid == local_uid:
			found = data
			uid = data.get_stack_uid()
			if data.checksum != checksum:
				var _error = 1
				#TODO desync here
	if !found:  #master queue never heard of this request, we create it
		uid = get_next_stack_uid()
		#we explicitly state the requesting client here to 0 because they're all supposed
		#to request it
		#we also don't have details on the script so we set it to something dummy
		var script_details = {
			"local" : "local"
		}
		found = add_to_ordering_queue(uid, script_details,  0,  StackQueueItem.STACK_STATUS.NONE, local_uid, checksum)

	change_queue_item_state(uid,client_id, StackQueueItem.STACK_STATUS.PENDING_UID,"master_i_need_id_for_local_script")
	
	#tells clients it's ok to move to their global stack once everyone has it
	if all_players_are_state(uid, StackQueueItem.STACK_STATUS.PENDING_UID ):
		_rpc("global_uid_assigned", local_uid, uid)

mastersync func master_i_need_id_for_local_script (local_uid, checksum):
	var client_id = get_tree().get_rpc_sender_id()
	master_assign_local_script_uid(local_uid, client_id, checksum)


remotesync func network_error(_details:Dictionary):
	pass

#Message from the Server that a Global UID was assigned for my local uid
remotesync func global_uid_assigned(local_uid,stack_uid):
	if !cfc.is_game_master():
		var verification_uid = get_next_stack_uid()
		if verification_uid != stack_uid:
			var _error = 1
			#TODO this is baad?
				
	var object = pending_local_scripts.get(local_uid, null)
	if !object:
		display_debug("{as client} asked to mark local script" + str(local_uid) + " as pending, but I don't have that")
		_rpc_id(1, "network_error", {"error":NETWORK_ERROR.LOCAL_UID_NOT_FOUND, "local_uid":local_uid, "stack_uid": stack_uid})
		return
	
	add_to_stack(object, stack_uid, local_uid)
	object.set_display_name(object.get_display_name() + "(local)")	
	#warning-ignore:RETURN_VALUE_DISCARDED	
	pending_local_scripts.erase(local_uid)
	_rpc_id(1, "from_client_global_uid_received", stack_uid)

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
		display_debug("{as client} adding local script local_uid:" + str(local_uid) + " - " +  object.get_display_name())
		pending_local_scripts[local_uid] = object		
		_rpc_id (1, "master_i_need_id_for_local_script", local_uid, object.get_display_name())	

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


func add_to_stack(object, stack_uid, local_uid = 0):
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
	add_to_reference_queue(object, stack_uid, StackQueueItem.STACK_STATUS.READY_TO_EXECUTE,local_uid)
	_rpc_id(1, "master_stack_object_added", object.stack_uid)	

func flush_script(stack_uid):
	if !interrupt_mode == InterruptMode.NOBODY_IS_INTERRUPTING:
		return	
	set_interrupt_mode(InterruptMode.NONE)
	var next_script = stack.get(stack_uid)
	if !next_script:
		display_debug("asked for executing script but I have nothing on my stack")
		var _error = 1
		return
	set_reference_status(stack_uid, StackQueueItem.STACK_STATUS.EXECUTING)
	display_debug("executing: " + str(next_script.stack_uid) + "-" + next_script.get_display_name())

	var func_return = next_script.execute()	
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()
	set_reference_status(stack_uid, StackQueueItem.STACK_STATUS.DONE)
	_rpc_id(1, "from_client_script_executed", stack_uid)		
	
#this is called after *all* clients have correctly executed the script	
remotesync func client_remove_script_from_stack_after_exec(stack_uid):
	#todo safety checks
	set_reference_status(stack_uid, StackQueueItem.STACK_STATUS.PENDING_REMOVAL)
	var the_script = stack.get(stack_uid)	
	#we send this signal internally just now (instead of after excuting it)
	#to ensure we only send it after everybody has run it
	emit_signal("script_executed_from_stack", the_script )		
	stack_remove(stack_uid)	
	_rpc_id(1, "from_client_script_removed_after_exec", stack_uid)				

func reset_interrupt_states():
	reset_phase_buttons()
	interrupting_hero_id = 0
	potential_interrupters = {}
	set_interrupt_mode(InterruptMode.NONE)

func _exit_tree():
	if (text_edit and is_instance_valid(text_edit)):
		cfc.NMAP.board.remove_child(text_edit)
	text_edit = null
		
#attempt to fix multiplayer stack issue
func attempt_recovery() -> bool:
	display_debug("recovery attempt begins")
	gameData.flush_debug_display()
	if text_edit:
		cfc.LOG(text_edit.text)
	var found_issue = null

	for client in clients_current_mode:
		if clients_current_mode[client] != interrupt_mode:
			found_issue = true
			display_debug("looks like interrupt modes aren't the same, asking for confirmation")
			_rpc_id(client, "client_confirm_current_interrupt_mode")			
	if found_issue:
		return true	
	
	var i = master_queue.size()-1
	while i>0 and !found_issue:
		var item = master_queue[i]
		if !all_players_same_state(item):
			found_issue = item
			display_debug("attempting to fix: " + debug_queue_status_msg(item) )
			var clients_status = item["status"]
			var local_uid = item["local_uid"]
			var checksum = item["checksum"]
			for client_id in clients_status:
				var status = clients_status[client_id]
				match status:
					StackQueueItem.STACK_STATUS.NONE: 
						if local_uid: 
							#This is a local script and it seems the client
							#never told me to add it to the master queue (bad) or I never received the ask (recoverable)
							#attempting to tell them again
							master_assign_local_script_uid(local_uid, client_id, checksum)
							return true
					StackQueueItem.STACK_STATUS.PENDING_UID: 
						if local_uid: 
							#This is a local script and it seems the client
							#never received their UID. Sending it again
							master_assign_local_script_uid(local_uid, client_id, checksum)
							return true							
		i -= 1
	return false		
					
func clients_status_aligned():
	for client in clients_current_mode:

		if clients_current_mode[client] != interrupt_mode:
			display_debug("need to wait: interrupt mode not the same (server:" +InterruptModeStr[interrupt_mode] + " - client " + str(client) +": " + InterruptModeStr[clients_current_mode[client]] + ")")			
			return false
			
#	for client in stack_integrity_check:
#		var their_stack = stack_integrity_check[client]
#		if their_stack.size() != stack.size():
#			display_debug("need to wait: stacks not the same (" +str(stack.size()) + " vs " + str(their_stack.size()) + ")")
#			return false

	#as long as there's something to execute, I think we're good
	
	if get_next_script_uid_to_execute():
		return true

	for item in master_queue:
		if !all_players_same_state(item):
			display_debug("need to wait: script status not the same (" +debug_queue_status_msg(item) )
			return false
			
	return true

func show_server_activity():
	var on_off = !is_player_allowed_to_click()
		
	cfc.NMAP.board.server_activity(on_off)


#remotesync func master_here_is_my_status(stack_uid, their_status):
#	var client_id = get_tree().get_rpc_sender_id()
#	var item = find_in_queue(stack_uid)
#	if !item:
#		var _error = 1
#		return
#
#	var known_status = item["status"][client_id]
#	#TODO
#
#remotesync func client_please_confirm_status(stack_uid):
#	var client_id = get_tree().get_rpc_sender_id()
#	var reference_item = reference_queue.get(stack_uid, {})
#
#	if not reference_item:
#		_rpc_id(client_id, "master_here_is_my_status", stack_uid, StackQueueItem.STACK_STATUS.NONE)
#
#	_rpc_id(client_id, "master_here_is_my_status", stack_uid, reference_item["status"])
#
#

#function for server to ping clients when haven't heard of them for a while
#item is a master_queue item
func ping_client_item(item:StackQueueItem, client_id):
	item.reset_time_since_last_change(client_id)
	var status = item.get_status(client_id)
	var stack_uid = item.get_stack_uid()
	match status:
		StackQueueItem.STACK_STATUS.NONE:
			pass
		StackQueueItem.STACK_STATUS.PENDING_UID:
			pass
		StackQueueItem.STACK_STATUS.PENDING_CLIENT_ACK:
			display_debug("{as server} client " + str(client_id) + "apparently haven't received my ask to create " + str(stack_uid) + ". Sending create request again"  )
			var script_details = item.get_script_details()
			_rpc_id(client_id, "client_create_and_add_stackobject", stack_uid, script_details)
			pass
		StackQueueItem.STACK_STATUS.READY_TO_EXECUTE:
			pass
		StackQueueItem.STACK_STATUS.EXECUTING:
			pass
		StackQueueItem.STACK_STATUS.DONE:
			pass
		StackQueueItem.STACK_STATUS.PENDING_REMOVAL:
			pass		
	
func _process(_delta: float):
	
	if cfc.is_game_master():
		for item in master_queue:
			item._process(_delta)
	
	if (!text_edit):
		 create_text_edit()
	
	if (!text_edit or !is_instance_valid(text_edit)):
		return

	var display_text = ""
	if master_queue:
		display_text += "--master_queue--\n"
	for item in master_queue:
		display_text+= item.debug_queue_status_msg() + "\n"
	if stack:
		display_text += "--stack--\n"		
	for stack_uid in stack:
		display_text += "{" + str(stack_uid) + "}" + stack[stack_uid].get_display_name() + "\n"
	if my_script_requests_pending_execution:
		display_text += "--my_script_requests_pending_execution--\n" + str(my_script_requests_pending_execution) +"\n"
	if pending_local_scripts:
		display_text += "--pending_local_scripts--\n" + str(pending_local_scripts.size()) +"\n"
	

	
	if display_text != text_edit.text:
		text_edit.text = display_text
	if text_edit.text:
		text_edit.visible = true
	else:
		text_edit.visible = false
	
	if cfc.is_game_master():
		for item in master_queue:
			for client_id in gameData.network_players:
				var time_since_last_change = item.get_time_since_last_change(client_id)
				if time_since_last_change > CFConst.DESYNC_TIMEOUT * gameData.network_players.size():
					ping_client_item(item, client_id)
			
	#todo clients also need to confirm packets
	
	show_server_activity()

	if gameData.is_ongoing_blocking_announce():
		return
			
	if (gameData.user_input_ongoing):
		waitOneMoreTick = 2; #TODO MAGIC NUMBER. Why do we have to wait 2 passes before damage gets prevented?
		return
	
	if waitOneMoreTick:
		waitOneMoreTick -= 1
		return		
	

	if cfc.is_game_master():
		#if not everyone is ready here, I need to wait
		if !clients_status_aligned():
			time_since_started_waiting += _delta
			if CFConst.DESYNC_TIMEOUT and  time_since_started_waiting > CFConst.DESYNC_TIMEOUT * gameData.network_players.size():
				time_since_started_waiting = 0
				attempt_recovery()
			return	
		else:
			time_since_started_waiting = 0.0

	if stack.empty(): 
		return


	match interrupt_mode:
		InterruptMode.NONE:
			if cfc.is_game_master():
					compute_interrupts(InterruptMode.FORCED_INTERRUPT_CHECK)

					
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

	if (text_edit and is_instance_valid(text_edit)):
		text_edit.text = ""	

	current_stack_uid = 0
	reset_interrupt_states()
	stack = {}
	reference_queue = {}
	clients_current_mode = {}
	stack_integrity_check = {}
	waitOneMoreTick = 0
	time_since_started_waiting = 0.0
	_current_interrupted_event= {}
	stack_uid_to_object = {}
	object_to_stack_uid = {}
	card_already_played_for_stack_uid = {}	
	current_local_uid= 0
	pending_local_scripts = {}
	my_script_requests_pending_execution = 0
	
	master_queue = []

func is_player_allowed_to_click() -> bool:
	#Generally speaking : can't play while there's something
	#on the stack, except in interrupt mode
	match interrupt_mode:
		#todo need to have a bit better?
		InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK, InterruptMode.HERO_IS_INTERRUPTING:
			return true
		_:	
			if my_script_requests_pending_execution:
				return false
			if pending_local_scripts:
				return false
			if stack:
				return false	
	return true

func is_phasecontainer_allowed_to_next_step():
	if !stack.empty():
		return false
	if my_script_requests_pending_execution:
		return false		

	if cfc.is_game_master() and !master_queue.empty():
		return false

	return true

#we let clients run their own course as much as possible for regular process
#requests
func is_phasecontainer_allowed_to_process():
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
					if item["status"][network_id] in [StackQueueItem.STACK_STATUS.NONE, StackQueueItem.STACK_STATUS.PENDING_UID]:
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
	#display_debug("I'm now in mode:" +  InterruptModeStr[interrupt_mode] )
	send_interrupt_mode_info_to_peer(1)
	gameData.game_state_changed()

remotesync func client_confirm_current_interrupt_mode():
	var client_id = get_tree().get_rpc_sender_id()
	send_interrupt_mode_info_to_peer(client_id)


func send_interrupt_mode_info_to_peer(peer_id):
	_rpc_id(peer_id, "master_interrupt_mode_info", interrupt_mode )

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

	var interrupters_found = false
	
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
					interrupters_found = true
	
		potential_interrupters[hero_id] = my_interrupters	
	
	if interrupters_found:
		#this fills similar data into clients and will then call the "select_interrupters" step
		_rpc("blank_compute_interrupts", script_uid)
	else:
		#otherwise we skip the rpc call and directly go to the next step
		select_interrupting_player()
					 

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
	
	_rpc_id(1, "blank_interrupts_computed")

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
			_rpc("client_set_interrupting_hero", hero_id)
			if (forced_interrupt):
				var network_hero_owner = gameData.get_network_id_by_hero_id(hero_id)
				_rpc_id(network_hero_owner, "force_play_card", interrupters[0])
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
			change_queue_item_state(uid,network_id, StackQueueItem.STACK_STATUS.EXECUTING, "select_interrupting_player")
		_rpc("client_execute_script", uid)
	return

remotesync func client_execute_script(script_uid):
	set_interrupt_mode(InterruptMode.NOBODY_IS_INTERRUPTING)
	flush_script(script_uid)

#pass my opportunity to interrupt 
func pass_interrupt (hero_id):
	if not hero_id in gameData.get_my_heroes():
		cfc.LOG("{error}: pass_interrupt called for hero_id by non controlling player")
		return
	_rpc_id(1,"master_pass_interrupt", hero_id)
	
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
	if gameData.phaseContainer and is_instance_valid(gameData.phaseContainer):
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
	
	_rpc_id(1, "master_stack_object_removed", stack_uid)	
		
func stack_pop_back():
	var max_uid = stack_back_id()
	var event = null 
	if (max_uid):
		event = stack[max_uid]
		stack_remove(max_uid)
	return event
	
func delete_last_event(requester:ScriptTask):
	#the requester usually doesn't want to delete themselves
	var max_uid = find_last_event_uid_before_me(requester)
	if max_uid:
		var event = stack[max_uid]
		stack_remove(max_uid)
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

func find_last_event_uid_before_me(requester:ScriptTask):
	#the requester usually doesn't want to delete themselves
	var max_uid = 0
	var requester_uid = 0
	for stack_uid in stack:
		if is_script_in_stack_object(requester, stack[stack_uid]):
			requester_uid = stack_uid
		else:
			if stack_uid > max_uid:
				max_uid = stack_uid
	if !max_uid:
		return null
	
	if requester_uid and requester_uid <= max_uid:
		display_debug("weird, I was expecting to delete an event before me (uid:" + str(requester_uid) + ") but found " + str(max_uid))
	
	return max_uid
		
func find_last_event_before_me(requester:ScriptTask):
	var max_uid = find_last_event_uid_before_me(requester)
	if !max_uid:
		return null
		
	return stack[max_uid]	

func find_event(_event_details, details, owner_card):
	for stack_uid in stack:
		var event = stack[stack_uid]
		var task = event.get_script_by_event_details(_event_details)			
		if (!task):
			continue			
		if event.matches_filters(task, details, owner_card):
			return event
	return null			



#scripted replacement effects
#most of this should move into the object class itself
func modify_object(stack_object, script:ScriptTask):
	if !stack_object:
		return false
	return stack_object.modify(script)
	
	
	
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
	
	change_queue_item_state(object_uid, client_id, StackQueueItem.STACK_STATUS.PENDING_REMOVAL, "master_stack_object_removed" )
	

mastersync func master_interrupt_mode_info( _interrupt_mode):
	var client_id = get_tree().get_rpc_sender_id()
	var previous_info = clients_current_mode.get(client_id, InterruptMode.UNKNOWN)
	clients_current_mode[client_id] = _interrupt_mode
	display_debug("{as server} client " + str(client_id) + "gave me their interrupt status. Before:" + InterruptModeStr[previous_info] + ". After:" + InterruptModeStr[_interrupt_mode])

func flush_logs():
	cfc.LOG("###SCRIPTSTACK LOGS###\nreference")
	for key in reference_queue:
		var item = reference_queue[key]
		cfc.LOG(str(key) + ":" + item.debug_queue_status_msg())

	var display_text = "\n###interrupt mode: " + InterruptModeStr[interrupt_mode] + "\n"
	display_text+= 	"my_script_requests_pending_execution: " + str(my_script_requests_pending_execution) + "\n"

	display_text += "\n--master_queue--\n"
	for item in master_queue:
		display_text+= debug_queue_status_msg(item) + "\n"
	display_text += "\n--stack--\n"		
	for stack_uid in stack:
		display_text += "{" + str(stack_uid) + "}" + stack[stack_uid].get_display_name() + "\n"

	
	cfc.LOG(display_text)
	cfc.LOG("pending_local_scripts:")
	cfc.LOG_DICT(pending_local_scripts)

# Ensures proper cleanup when a card is queue_free() for any reason
func _on_tree_exiting():	
	flush_logs()

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		flush_logs()
	

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
