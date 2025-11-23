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
var _current_interrupting_cards = []
var _current_interrupting_mode = InterruptMode.NONE


#client_current_mode:
#	{network_id => current interrupt mode for the player}
var clients_current_mode: Dictionary = {}



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

var card_already_played_for_stack_uid:Dictionary = {}

var _master_interrupt_state:= {}
var _heroes_passed_optional_interrupt:= {}
var _ready_for_next_step: = {} 

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
				var delay = 0.001 if p_id == 1 else CFConst.DEBUG_SIMULATE_NETWORK_DELAY
				if CFConst.DEBUG_NETWORK_DELAY_RANDOM:
					delay = randf()*CFConst.DEBUG_SIMULATE_NETWORK_DELAY
				yield(get_tree().create_timer(delay), "timeout")
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
			var delay = 0.001 if id == 1 else CFConst.DEBUG_SIMULATE_NETWORK_DELAY
			if CFConst.DEBUG_NETWORK_DELAY_RANDOM:
				delay = randf()*CFConst.DEBUG_SIMULATE_NETWORK_DELAY	
			yield(get_tree().create_timer(delay), "timeout")
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
	master_request_add_stack_object(client_id, stack_uid, original_details)


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
	_details =  guidMaster.replace_objects_to_guids(_details)
	my_script_requests_pending_execution += 1
	_rpc_id(1, "master_create_and_add_signal", _name, owner_uid, _details)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

func master_request_add_stack_object(client_id, stack_uid, original_details):
	add_to_ordering_queue(stack_uid, original_details, client_id)
	#wait for interrupts to be done
	
	display_debug("Asking clients to add script " + str(stack_uid)) 			
	_rpc("client_create_and_add_stackobject", stack_uid, original_details)

mastersync func master_create_and_add_signal( _name, _owner_uid, _details):
	var stack_uid = get_next_stack_uid()
	var client_id = get_tree().get_rpc_sender_id() 	

	var original_details = {
		"type": "signal",
		"owner_uid": _owner_uid, 
		"trigger_details": _details,
		"name": _name
	}	
	master_request_add_stack_object(client_id, stack_uid, original_details)


func client_create_signal(details):	
	var _owner_uid = details["owner_uid"]
	var _name = details["name"]
	var _details = guidMaster.replace_guids_to_objects(details["trigger_details"])

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
	
	#we will reject "manual" requests if the stack isn't empty 
	#and the card isn't one of the currently allowed ones
	var accept_request = true
	if trigger == "manual":
		var allowed_interrupters = get_allowed_interrupting_cards()
		if allowed_interrupters:
			if !owner_uid in allowed_interrupters:
				accept_request = false
		else:
			#reject everything if the queue isn't empty
			if stack or master_queue:
				accept_request = false
	if accept_request:
		master_request_add_stack_object(client_id, stack_uid, original_details)	
	else:
		_rpc_id(client_id, "rejected_add_script_request", original_details)

remote func rejected_add_script_request(details:={}):
	var owner_uid = details.get("owner_uid", "")
	var owner = null
	if owner_uid:
		owner = guidMaster.get_object_by_guid(owner_uid)
	if owner:
		owner.network_request_rejected()
		display_debug("Add script request rejected for " + owner.canonical_name)
	else:
		display_debug("Add script request rejected for unknown request : " + to_json(details))		
	my_script_requests_pending_execution -= 1

func get_allowed_interrupting_cards():
	if _master_interrupt_state:
		var potential_interrupters = _master_interrupt_state.get("potential_interrupters", {})
		for i in range(gameData.get_team_size()):
			var hero_id = i+1
			var interrupters = potential_interrupters.get(hero_id, [])
			if interrupters:
				return interrupters
	return [] 

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
	reference_item.set_human_readable(str(stack_uid) + "-" + object.get_display_name())
	if reference_queue.has(stack_uid):
		var _error = 1
		#TODO error handling here
		
	reference_queue[stack_uid] = reference_item


#all clients, for reference and error correction
func set_reference_status(stack_uid, new_state, caller = ""):
	if !caller:
		caller = "set_reference_status"
	var reference_object = reference_queue.get(stack_uid, null)
	if !reference_object:
		#the object should have been added no matter what before this
		var _error = 1
		display_debug("reference queue didn't find " +str(stack_uid))
		return null
	
	reference_object.change_reference_item_state(new_state, caller)
	return reference_object	
	

# master only
func add_to_ordering_queue(stack_uid, script_details, requester_client_id = 0, starting_status = StackQueueItem.STACK_STATUS.PENDING_CLIENT_ACK, local_uid = 0, checksum = ""):
	display_debug("{master} adding new item to master_queue (per request of" + str(requester_client_id) + " ): " + str(stack_uid) + " " + to_json(script_details))
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

	#this should be the last on the pile
	
	var item:StackQueueItem = master_queue.back()		
	if all_players_are_state(item, StackQueueItem.STACK_STATUS.READY_TO_EXECUTE):
		return item.get_stack_uid()
				
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
		display_debug("{as server} error couldn't find script " +str(stack_uid) + " to mark it as done")
		return
	
	found.change_queue_item_state(client_id, StackQueueItem.STACK_STATUS.DONE, "from_client_script_executed")
	if !found:
		return
		
	if all_players_are_state(stack_uid, StackQueueItem.STACK_STATUS.DONE):
		display_debug("{as server} (from_client_script_executed) " + str(client_id) + " has executed " +  str(stack_uid) + " and they were last, will now ask to remove")
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


#Message from the Server that a Global UID was assigned for my local uid
remotesync func global_uid_assigned(local_uid,stack_uid):				
	var object = pending_local_scripts.get(local_uid, null)
	if !object:
		display_debug("{as client} asked to mark local script" + str(local_uid) + " as pending, but I don't have that")
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
		var authorized_card = true
		var allowed_cards = get_allowed_interrupting_cards()
		if allowed_cards:
			var guid = guidMaster.get_guid(object.sceng.owner)
			if !guid or !(guid in allowed_cards):
				authorized_card = false
	
		if (script_being_interrupted and authorized_card):
			var script_uid = script_being_interrupted.stack_uid
			if (!card_already_played_for_stack_uid.has(script_uid)):
				card_already_played_for_stack_uid[script_uid] = []
			card_already_played_for_stack_uid[script_uid].append(object.sceng.owner)
			_rpc_id(1, "client_finished_interrupts", {})
			reset_interrupt_states()
	

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
	
	object.stack_uid = stack_uid

	stack[stack_uid] = object

	var msg = "["
	for stack_uid in stack:
		msg+= str(stack_uid) +"-" + stack[stack_uid].get_display_name() + ","
	msg += "]"
	display_debug("my stack: " + msg)
	emit_signal("script_added_to_stack", object)
	#reset_interrupt_states()
	add_to_reference_queue(object, stack_uid, StackQueueItem.STACK_STATUS.READY_TO_EXECUTE,local_uid)
	
	_rpc_id(1, "master_stack_object_added", object.stack_uid)	

func flush_script(stack_uid):
	if !interrupt_mode == InterruptMode.NOBODY_IS_INTERRUPTING:
		return	
	set_interrupt_mode(InterruptMode.NONE)

	#if we already have that object marked as DONE, we assume it's an error check and 
	#just return an ack
	var reference:StackReferenceItem = reference_queue.get(stack_uid, null)
	if reference and reference.get_status() in [StackQueueItem.STACK_STATUS.DONE,StackQueueItem.STACK_STATUS.PENDING_REMOVAL] :
		display_debug("{as client} asked for executing script " + str(stack_uid) + " but I have already run it. Sending confirmation anyway")
		_rpc_id(1, "from_client_script_executed", stack_uid)
		return		
	
	var next_script = stack.get(stack_uid)	
	if !next_script:
		display_debug("{as client} asked for executing script " + str(stack_uid) + " but I don't have it on my stack.")
		var _error = 1
		return
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
	var the_script = stack.get(stack_uid, null)	
	#we send this signal internally just now (instead of after excuting it)
	#to ensure we only send it after everybody has run it
	if the_script:
		emit_signal("script_executed_from_stack", the_script )	
		stack_remove(stack_uid)
	else:
		_rpc_id(1, "master_stack_object_removed", stack_uid)	
	
	#we send the ack in all cases because this might be an error check	
	_rpc_id(1, "from_client_script_removed_after_exec", stack_uid)				

func reset_interrupt_states():
	reset_phase_buttons()
	interrupting_hero_id = 0
	set_interrupt_mode(InterruptMode.NONE)
	_current_interrupting_cards = []
	_current_interrupting_mode = InterruptMode.NONE	


func _exit_tree():
	if (text_edit and is_instance_valid(text_edit)):
		cfc.NMAP.board.remove_child(text_edit)
	text_edit = null
		
#attempt to fix multiplayer stack issue
func attempt_recovery() -> bool:
	if !CFConst.ENABLE_NETWORK_ERROR_CORRECTION:
		return true
		
	display_debug("recovery attempt begins")
	gameData.flush_debug_display()
	if text_edit:
		cfc.LOG(text_edit.text)
	var found_issue = null

	for client in clients_current_mode:
		if clients_current_mode[client] != interrupt_mode:
			found_issue = true
			display_debug("looks like interrupt modes aren't the same, asking for confirmation (expected " + InterruptModeStr[interrupt_mode] + "got " + InterruptModeStr[clients_current_mode[client]]  +  ")")
			_rpc_id(client, "client_confirm_current_interrupt_mode")			
	if found_issue:
		return true	
	
	return false		
					
var _last_status_aligned_msg = ""					
func clients_status_aligned():
	for client in clients_current_mode:

		if clients_current_mode[client] != interrupt_mode:
			var status_msg = "need to wait: interrupt mode not the same (server:" +InterruptModeStr[interrupt_mode] + " - client " + str(client) +": " + InterruptModeStr[clients_current_mode[client]] + ")"
			if status_msg!= _last_status_aligned_msg:
				_last_status_aligned_msg = status_msg
				display_debug(_last_status_aligned_msg)			
			return false
			
	#as long as there's something to execute, I think we're good
	
	if get_next_script_uid_to_execute():
		return true

	for item in master_queue:
		if !all_players_same_state(item):
			var status_msg = "need to wait: script status not the same (" +debug_queue_status_msg(item)
			if status_msg!= _last_status_aligned_msg:
				_last_status_aligned_msg = status_msg
				display_debug(_last_status_aligned_msg)				
			return false
			
	return true

func show_server_activity():
	if !gameData.is_game_started():
		return
	if !cfc.NMAP.has("board"):
		return
	if !is_instance_valid(cfc.NMAP.board):
		return
			
	var on_off = !is_player_allowed_to_click()
		
	cfc.NMAP.board.server_activity(on_off)



#function for server to ping clients when haven't heard of them for a while
#item is a master_queue item
func ping_client_item(item:StackQueueItem, client_id):
	#we reset ping time on all clients for this event to avoid a resync
	# on other clients that might not have a problem
	item.reset_time_since_last_change()
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
		StackQueueItem.STACK_STATUS.DONE:
			display_debug("{as server} client " + str(client_id) + "apparently haven't removed " + str(stack_uid) + ". Sending complete request again"  )			
			_rpc_id(client_id, "client_remove_script_from_stack_after_exec", stack_uid)
			pass
		StackQueueItem.STACK_STATUS.PENDING_REMOVAL:
			pass		

func display_debug_info():
	if (!text_edit):
	 create_text_edit()
	
	if (!text_edit or !is_instance_valid(text_edit)):
		return

	var display_text = "" #interrupt_mode: " + InterruptModeStr[interrupt_mode] + "\n"
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


	
func _process(_delta: float):
	if cfc.is_game_master():
		for item in master_queue:
			item._process(_delta)
	
	display_debug_info()

	
	if CFConst.ENABLE_NETWORK_ERROR_CORRECTION and cfc.is_game_master():
		for item in master_queue:
			for client_id in gameData.network_players:
				var time_since_last_change = item.get_time_since_last_change(client_id)
				if time_since_last_change > CFConst.DESYNC_TIMEOUT * gameData.network_players.size():
					ping_client_item(item, client_id)
			
	
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
				display_debug("clients status isn't aligned and server has been waiting for more than" + str(time_since_started_waiting) + "seconds" )
				time_since_started_waiting = 0
				if CFConst.ENABLE_NETWORK_ERROR_CORRECTION:		
					attempt_recovery()
			return	
		else:
			time_since_started_waiting = 0.0

	if stack.empty(): 
		return


	match interrupt_mode:
		InterruptMode.NONE:
			#set_interrupt_mode(InterruptMode.FORCED_INTERRUPT_CHECK)
			if cfc.is_game_master():
				#abort if we're still in the process of computing some interrupts
				if _master_interrupt_state:
					return
				var uid = get_next_script_uid_to_execute()
				if uid:
					_master_interrupt_state = compute_interrupts(uid)
					_rpc("start_interrupts", _master_interrupt_state)
					

					
	return	


mastersync func client_started_interrupts(interrupt_request):		
	var client_id = get_tree().get_rpc_sender_id()
	if !_master_interrupt_state.has("client_status"):
		_master_interrupt_state["client_status"] = {}

	var client_status = _master_interrupt_state["client_status"]
		
	if client_status.has(client_id):
		var _error = 1
		display_debug("_master_interrupt_state error, client_status already set at " + client_status[client_id] + " for "  + str(client_id))
	else: 
		client_status[client_id] = "started"		
	pass

mastersync func client_finished_interrupts(interrupt_request):	
	var client_id = get_tree().get_rpc_sender_id() 
	if !_master_interrupt_state.has("client_status"):
		var _error = 1
		display_debug("_master_interrupt_state error, client_status doesn't exist but I want to mark client_id " +str(client_id) + " as finished" )
		return
	
	var client_status = _master_interrupt_state["client_status"]
		

	if !client_status.has(client_id):
		var _error = 1
		display_debug("_master_interrupt_state error, client_status doesn't have client_id but I want to mark client_id " +str(client_id) + " as finished" )
		return
	
	if !client_status[client_id] == "started":
		var _error = 1
		display_debug("_master_interrupt_state error, client_status is " + client_status[client_id] + " for " + str(client_id) + ", expected 'started'" )
		return
		
	client_status[client_id]= "finished"		

	for network_id in gameData.network_players:
		if !client_status.has(network_id):
			return
		if client_status[network_id] != "finished":
			return
	#all done!
	_rpc("finish_interrupts")
	pass


mastersync func ready_for_next_step():
	var client_id = get_tree().get_rpc_sender_id()
	_ready_for_next_step[client_id] = true

	if _ready_for_next_step.size() == gameData.network_players.size():
		_ready_for_next_step = {}
		_master_interrupt_state = {}
		_heroes_passed_optional_interrupt= {}			

remotesync func finish_interrupts():
	set_interrupt_mode(InterruptMode.NONE)
	_rpc_id(1, "ready_for_next_step")

#sets the current interrupting mode depending on computed interrupts
#either all clients execute the current script, or a forced interrupt gets executed,
#or a player gets priority
remotesync func start_interrupts(interrupt_request):
	_rpc_id(1, "client_started_interrupts", interrupt_request)
	var stack_uid = interrupt_request.get("stack_uid", 0)
	set_interrupt_mode(interrupt_request["interrupt_mode"])
	var potential_interrupters = interrupt_request.get("potential_interrupters", {})
	match interrupt_request["interrupt_mode"]:
		InterruptMode.NOBODY_IS_INTERRUPTING:
			flush_script(stack_uid)
			_rpc_id(1, "client_finished_interrupts", interrupt_request)
			return true
		InterruptMode.FORCED_INTERRUPT_CHECK:
			for i in range(gameData.get_team_size()):
				var hero_id = i+1
				var interrupters = potential_interrupters.get(hero_id, [])
				if interrupters:
					set_interrupting_hero(hero_id, interrupters, InterruptMode.FORCED_INTERRUPT_CHECK)
					if hero_id in (gameData.get_my_heroes()):
						blank_compute_interrupts(stack_uid)
						force_play_card(interrupters)
						return true

					
		InterruptMode.OPTIONAL_INTERRUPT_CHECK:
			for i in range(gameData.get_team_size()):
				var hero_id = i+1
				var interrupters = potential_interrupters.get(hero_id, [])
				if interrupters:
					set_interrupting_hero(hero_id, interrupters, InterruptMode.OPTIONAL_INTERRUPT_CHECK)
					blank_compute_interrupts(stack_uid)
					if !hero_id in (gameData.get_my_heroes()):
						#maybe don't call this here and wait for actual card played (or pass) instead ?
						_rpc_id(1, "client_finished_interrupts", interrupt_request)
					return true


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
	flush_logs()
	
	if (text_edit and is_instance_valid(text_edit)):
		text_edit.text = ""	

	current_stack_uid = 0
	reset_interrupt_states()
	_master_interrupt_state = {}
	_heroes_passed_optional_interrupt = {}	
	_ready_for_next_step = {} 
		
	stack = {}
	reference_queue = {}
	clients_current_mode = {}

	waitOneMoreTick = 0
	time_since_started_waiting = 0.0
	_current_interrupted_event= {}

	card_already_played_for_stack_uid = {}	
	current_local_uid= 0
	pending_local_scripts = {}
	my_script_requests_pending_execution = 0
	
	master_queue = []
	_current_interrupting_cards = []

func is_player_allowed_to_pass() -> bool:
	if !is_player_allowed_to_click():
		return false
	
	match interrupt_mode:
		#todo need to have a bit better?
		InterruptMode.HERO_IS_INTERRUPTING: 	
			if _current_interrupting_mode == InterruptMode.FORCED_INTERRUPT_CHECK:
				return false
			return !_current_interrupting_cards.empty()

	return false


		
func is_player_allowed_to_click(card = null) -> bool:
	#Generally speaking : can't play while there's something
	#on the stack, with exceptions in interrupt mode
	
	#this check here doesn't work. At least in combat/scheme, 
	#there are events that use the network stack (commit_scheme at least)
	#and those can be interrupted
#	if my_script_requests_pending_execution:
#		return false
	
	if pending_local_scripts:
		return false		
	
	match interrupt_mode:
		#todo need to have a bit better?
		InterruptMode.HERO_IS_INTERRUPTING: 
			if _current_interrupting_mode == InterruptMode.NONE:
				var _error = 1
				return false
			if card:
				if _current_interrupting_cards and card in _current_interrupting_cards:
					return true
				return false
			return true	
		InterruptMode.NONE:	
			if card:
				if gameData.phaseContainer.current_step != CFConst.PHASE_STEP.PLAYER_TURN:
					return false
			if my_script_requests_pending_execution:
				return false
			if stack:
				return false	
		_:
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
					if item.get_status(network_id) in [StackQueueItem.STACK_STATUS.NONE, StackQueueItem.STACK_STATUS.PENDING_UID]:
						return true
			return false

	return true
	
#func is_empty():
#	if !stack.empty():
#		return false
#	if cfc.is_game_master():
#		if !master_queue.empty():
#			return false
#	if my_script_requests_pending_execution:
#		return false
#	return true

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
	#error checks
	match value:
		InterruptMode.NONE:
			if interrupt_mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]:
				#this is weird, we should be going to either HERO_IS_INTERRUPTING or NOBODY_IS_INTERRUPTING
				display_debug("{error}: I shouldn't be going from " +  InterruptModeStr[interrupt_mode]  + "to InterruptMode.NONE")
				var _error = 1
				#return
	
	#we're good to go		
	interrupt_mode = value
	
	match value:
		InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK:
			_current_interrupting_mode = value
		InterruptMode.HERO_IS_INTERRUPTING:
			pass
		_:
			_current_interrupting_mode = InterruptMode.NONE
	
	display_debug("I'm now in mode:" +  InterruptModeStr[interrupt_mode] )
#	reset_phase_buttons()
	send_interrupt_mode_info_to_peer(1)
	gameData.game_state_changed()

remotesync func client_confirm_current_interrupt_mode():
	var client_id = get_tree().get_rpc_sender_id()
	send_interrupt_mode_info_to_peer(client_id)


func send_interrupt_mode_info_to_peer(peer_id):
	_rpc_id(peer_id, "master_interrupt_mode_info", interrupt_mode )

func get_current_interrupted_event():
	return self._current_interrupted_event


func compute_interrupts(stack_uid):
	var script = stack.get(stack_uid, null)
	if (! script):
		display_debug("didn't find script for " + str(stack_uid))
		return

	var script_uid = script.stack_uid	
	var current_mode = interrupt_mode
	var potential_interrupters = {}
	for mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]:
		var interrupters_found = false
		
		#have to do that because can_interrupt checks for the current state of the game
		interrupt_mode = mode 
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
					if (task.script_name == "receive_damage"):
						if (card.canonical_name == "Spider-Man"):
							var _tmp = 1
					var can_interrupt = card.can_interrupt(hero_id,task.owner, _current_interrupted_event)
					if can_interrupt == INTERRUPT_FILTER[mode]:
						var guid = guidMaster.get_guid(card)
						my_interrupters.append(guid)
						interrupters_found = true
		
			potential_interrupters[hero_id] = my_interrupters
		if interrupters_found:
			interrupt_mode = current_mode
			return {
				"potential_interrupters" : potential_interrupters,
				"interrupt_mode" : mode,
				"interruptmode_str": InterruptModeStr[mode],
				"stack_uid" : stack_uid
			}
	
	#no interrupt found, set status to "nobody_is_interrupting"	
	_heroes_passed_optional_interrupt = {}	
	interrupt_mode = current_mode	
	return {
		"interrupt_mode": InterruptMode.NOBODY_IS_INTERRUPTING,
		"interruptmode_str": InterruptModeStr[InterruptMode.NOBODY_IS_INTERRUPTING],
		"stack_uid": stack_uid
	}



#an empty call for clients to fill necessary data (_current_interrupted_event)
# need to make something cleaner
func blank_compute_interrupts(stack_uid):
	var script = stack.get(stack_uid, null)
	if (! script):
		#TODO error, this shouldn't happen
		return
	var tasks = script.get_tasks()
	for task in tasks:
		_current_interrupted_event = task.script_definition.duplicate()
		_current_interrupted_event["event_name"] = task.script_name
		_current_interrupted_event["event_object"] = task


#pass my opportunity to interrupt 
func pass_interrupt (hero_id):
	if not hero_id in gameData.get_my_heroes():
		cfc.LOG("{error}: pass_interrupt called for hero_id by non controlling player")
		return
	#_rpc("clients_pass_interrupt", hero_id)	
	_rpc_id(1,"master_pass_interrupt", hero_id)



#call to master when I've chosen to pass my opportunity to interrupt 
mastersync func master_pass_interrupt (hero_id):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " wants to pass for hero:" + str(hero_id) )

	#TODO ensure that caller network id actually controls that hero
	reset_phase_buttons()
	_heroes_passed_optional_interrupt[hero_id] = true
	_master_interrupt_state = compute_interrupts(_master_interrupt_state["stack_uid"])
	_rpc("start_interrupts", _master_interrupt_state)


#forced activation of card for forced interrupt
remotesync func force_play_card(interrupters):
	#TODO force interrupt mode here for security
	_current_interrupting_cards = []
	_current_interrupting_mode = InterruptMode.FORCED_INTERRUPT_CHECK
	for card_guid in interrupters:
		var card = guidMaster.get_object_by_guid(card_guid)
		_current_interrupting_cards.append(card)
	
	var card = _current_interrupting_cards[0]
	
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

func set_interrupting_hero(hero_id, interrupters, real_interrupt_mode):
	_current_interrupting_cards = []
	_current_interrupting_mode = real_interrupt_mode
	for card_guid in interrupters:
		var card = guidMaster.get_object_by_guid(card_guid)
		_current_interrupting_cards.append(card)
		

	set_interrupt_mode(InterruptMode.HERO_IS_INTERRUPTING)	
	interrupting_hero_id = hero_id
	activate_exclusive_hero(hero_id)
	

func stack_back_id():
	var max_uid = 0
	for stack_uid in stack:
		if stack_uid > max_uid:
			max_uid = stack_uid
	return max_uid
	
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

func find_event(_event_details, details, owner_card, _trigger_details):
	for stack_uid in stack:
		var event = stack[stack_uid]
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
	
	
					
	
func get_interrupt_mode() -> int:
	return interrupt_mode

mastersync func master_stack_object_added (object_uid):
	var _client_id = get_tree().get_rpc_sender_id()
	pass

mastersync func master_stack_object_removed (object_uid):
	var client_id = get_tree().get_rpc_sender_id()
	change_queue_item_state(object_uid, client_id, StackQueueItem.STACK_STATUS.PENDING_REMOVAL, "master_stack_object_removed" )	
	pass
	

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
	

