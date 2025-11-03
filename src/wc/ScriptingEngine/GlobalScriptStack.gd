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


var stack:Array = []
var waitOneMoreTick = 0


#stores data relevant to the ongoing interrupt signal
var _current_interrupted_event: Dictionary = {}

#stores unique IDs for all stack events
var current_stack_uid:int = 0
var current_local_uid: int = 0
var pending_local_scripts: Dictionary = {}

var master_local_scripts_queue: Dictionary = {}

var stack_uid_to_object:Dictionary = {}
var object_to_stack_uid:Dictionary = {}
var card_already_played_for_stack_uid:Dictionary = {}

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
	text_edit.anchor_left = 0.75
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
		
	rpc_id(1, "master_create_and_add_simplescript",  owner_uid, trigger_card_uid, definition, trigger_details)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_simplescript(  _owner_uid, trigger_card_uid, definition, trigger_details):
	var stack_uid = get_next_stack_uid()
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

func create_and_add_signal(_name, _owner, _details):
	#we deconstruct locally here to reconstruct it on all clients then add it to all stacks
	#also send GUIDs to find the right cards/targets
	
	var owner_uid = guidMaster.get_guid(_owner)
	
	rpc_id(1, "master_create_and_add_signal", _name, owner_uid, _details)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_signal( _name, _owner_uid, _details):
	var stack_uid = get_next_stack_uid()	
	rpc("client_create_and_add_signal", stack_uid, _name, _owner_uid, _details)

remotesync func client_create_and_add_signal(stack_uid, _name, _owner_uid, _details):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " wants me to add a signal:" + _name)

	var owner_card = guidMaster.get_object_by_guid(_owner_uid)
				
	var stackEvent:SignalStackScript = SignalStackScript.new(_name, owner_card, _details)
	add_script(stackEvent, stack_uid)

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
	
	rpc_id(1, "master_create_and_add_script", state_scripts, owner_uid, trigger_card_uid, run_type, trigger, remote_trigger_details, sceng.stored_integers, action_name)
	#TODO should wait for ack from all clients before anybody can do anything further in the game

mastersync func master_create_and_add_script(state_scripts, _owner_uid, trigger_card_uid,  run_type, trigger, remote_trigger_details, stored_integers, action_name):
	var stack_uid = get_next_stack_uid()
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

mastersync func master_i_need_id_for_local_script (local_uid, checksum):
	var client_id = get_tree().get_rpc_sender_id() 
	if !master_local_scripts_queue.has(local_uid):
		master_local_scripts_queue[local_uid] = {
			"checksum": checksum,
			"requested" : {}
		}
	else:
		#check checksum
		if master_local_scripts_queue[local_uid]["checksum"] != checksum:
			#TODO error this is badd!
			pass
	
	master_local_scripts_queue[local_uid]["requested"][client_id] = true
	if master_local_scripts_queue[local_uid]["requested"].size() == gameData.network_players.size():
		var uid = get_next_stack_uid()
		#warning-ignore:RETURN_VALUE_DISCARDED
		master_local_scripts_queue.erase(local_uid)		
		rpc("global_uid_assigned", local_uid, uid)


remotesync func global_uid_assigned(local_uid,stack_uid):
	if !cfc.is_game_master():
		var verification_uid = get_next_stack_uid()
		if verification_uid != stack_uid:
			var _error = 1
			#TODO this is baad
				
	var object = pending_local_scripts[local_uid]
	object.set_display_name(object.get_display_name() + "(local)")		
	add_to_stack(object, stack_uid)
	#warning-ignore:RETURN_VALUE_DISCARDED	
	pending_local_scripts.erase(local_uid)

func add_script(object, stack_uid:int = 0):
	#if somebody is adding a script while in interrupt mode,
	# we add the script (its owner card for now - TODO need to change?)
	# to the list of scripts that already responded to the last event
	#this prevents them from triggering infinitely to the same event 
	if interrupt_mode == InterruptMode.HERO_IS_INTERRUPTING:
		var script_being_interrupted = stack.back()
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
	flush_top_script()
	
	object.stack_uid = stack_uid

	stack.append(object)
	stack.sort_custom(StackObject, "sort_stack")
	var msg = "["
	for item in stack:
		msg+= str(item.stack_uid) +"-" + item.get_display_name() + ","
	msg += "]"
	display_debug("my stack: " + msg)

	reset_interrupt_states()
	rpc_id(1, "master_stack_object_added", object.stack_uid)	

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
#		for i in range (stack.size()):
#			if their_stack[i] != stack[i].stack_uid:
#				display_debug("error: stack integrity")
#				return false
	if master_local_scripts_queue:
		display_debug("need to wait: local scripts still pending (" +to_json(master_local_scripts_queue)  + ")")			
		return false
			
	return true
	
func _process(_delta: float):
	
	if (!text_edit):
		 create_text_edit()
	
	if (!text_edit or !is_instance_valid(text_edit)):
		return

	text_edit.text = ""
	for stack_obj in stack:
		text_edit.text += stack_obj.get_display_name() + "\n"

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
					return	
				set_interrupt_mode(InterruptMode.FORCED_INTERRUPT_CHECK)
				rpc("client_send_before_trigger", interrupt_mode)

				
		InterruptMode.NOBODY_IS_INTERRUPTING:			
			flush_top_script()
			

#		var sceng = next_script.sceng
#		var trigger_details = sceng.trigger_details
#		var is_network_call = trigger_details.has("network_prepaid")
#		if (!is_network_call):
#			#Call other clients to run the script
#			var trigger_card = sceng.trigger_object
#			var trigger = next_script.trigger
#			var run_type = next_script.run_type
#			sceng.owner.network_execute_scripts(trigger_card, trigger, trigger_details, run_type, sceng)		

			
	return	

func flush_top_script():
	if !interrupt_mode == InterruptMode.NOBODY_IS_INTERRUPTING:
		return
	set_interrupt_mode(InterruptMode.NONE)
	var next_script = stack_pop_back()
	if !next_script:
		display_debug("asked for executing script but I have nothing on my stack")
		var _error = 1
		return
	display_debug("executing: " + str(next_script.stack_uid) + "-" + next_script.get_display_name())
	var func_return = next_script.execute()	
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()
	emit_signal("script_executed_from_stack", next_script )		
			
func stack_pop_back():
	var variant = stack.pop_back()
	if !variant:
		return variant
	display_debug("I just removed item "  + str(variant.stack_uid) +  " from stack" )	
	rpc_id(1, "master_stack_object_removed", variant.stack_uid )
	return variant

#Instead of deleting a stack we refresh the existing one
#by cleaning up all bean counters
func reset():
	current_stack_uid = 0
	reset_interrupt_states()
	stack = []	
	clients_current_mode = {}
	stack_integrity_check = {}
	waitOneMoreTick = 0
	_current_interrupted_event= {}
	stack_uid_to_object = {}
	object_to_stack_uid = {}
	card_already_played_for_stack_uid = {}	
	current_local_uid= 0
	pending_local_scripts = {}
	master_local_scripts_queue = {}	
	
func is_empty():
	return stack.empty()

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
	gameData.display_debug(msg, "stack")

func set_interrupt_mode(value:int):
	interrupt_mode = value
	display_debug("I'm now in mode:" +  InterruptModeStr[interrupt_mode] )
	rpc_id(1, "master_interrupt_mode_changed", interrupt_mode)
	gameData.game_state_changed()

func get_current_interrupted_event():
	return self._current_interrupted_event

#When stacks are about to run a script, they send "interrupt" signal <-- this needs to be synchronized, so maybe only the master sends the interrupt. Other clients have to wait (until what ?)
#
#If I'm the master, 
#if "interrupters" is all "skip": go to "interrupters has nobody" step
#Else:
#send interrupt signal to all clients. I Wait for ack 
#Wait for ack == set array interrupters [nb_players] to empty and fill it with each players when ack has matching interrupt details.
#Example of ack: "interrupt put in play blurb -> me (player 1) has a potential interrupt	
			 

remotesync func client_send_before_trigger(_interrupt_mode):
	var client_id = get_tree().get_rpc_sender_id()
	display_debug(str(client_id) + " checking for interrupts-" + InterruptModeStr[_interrupt_mode] )
	if !( _interrupt_mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]):
		var _error = 1
		
	set_interrupt_mode(_interrupt_mode)
	var script = stack.back()
	if (! script):
		#TODO error, this shouldn't happen
		return
	var script_uid = script.stack_uid
	var my_heroes = gameData.get_my_heroes()
	for hero_id in my_heroes:
		var tasks = script.get_tasks()
		var my_interrupters:= []
		for task in tasks:
			_current_interrupted_event = task.script_definition.duplicate()
			_current_interrupted_event["event_name"] = task.script_name
			_current_interrupted_event["event_object"] = task
			for card in get_tree().get_nodes_in_group("cards"):
				#TODO makes a distinction between MAY and MUST here
				#Forced interrupts happen before optional ones
				if (card in card_already_played_for_stack_uid.get(script_uid, [])):
					continue
				if (task.script_name == "receive_damage"):
					if (card.canonical_name == "Spider-Man"):
						var _tmp = 1
				var can_interrupt = card.can_interrupt(hero_id,task.owner, _current_interrupted_event)
				if can_interrupt == INTERRUPT_FILTER[_interrupt_mode]:
					my_interrupters.append(card)
	
		set_potential_interrupters(hero_id, my_interrupters)


func set_potential_interrupters (hero_id, cards:Array):
	#todo error checks. Do I own this hero, etc...
	var guids:Array = []
	for card in cards:
		guids.append(guidMaster.get_guid(card))
	rpc_id(1, "master_set_potential_interrupters", hero_id, guids)



mastersync func master_set_potential_interrupters (hero_id, guids:Array):
	var client_id = get_tree().get_rpc_sender_id()
	if guids:
		display_debug(str(client_id) + " gave me back interrupt list with "+ str(guids.size()) + " items for hero:" + str(hero_id) )
	
	if !( interrupt_mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]):
		var _error = true
		#TODO error check
#	var interrupters:Array = []
#	for uid in guids:
#		var card = guidMaster.get_object_by_guid(uid)	
#		interrupters.append(card)
	potential_interrupters[hero_id] = guids

	if (potential_interrupters.size() == gameData.team.size()):
		display_debug("all clients ready to select interrupting player" )
		select_interrupting_player()

#pass my opportunity to interrupt 
func pass_interrupt (hero_id):
	#TODO ensure that caller network id actually controls that hero
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

func select_interrupting_player():
	if !cfc.is_game_master():
		return #TODO error check, this shouldn't even be possible
		
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
	if (interrupt_mode == InterruptMode.FORCED_INTERRUPT_CHECK):

		set_interrupt_mode(InterruptMode.OPTIONAL_INTERRUPT_CHECK)
		rpc("client_send_before_trigger", interrupt_mode)
	else:
		set_interrupt_mode(InterruptMode.NOBODY_IS_INTERRUPTING)
		rpc("client_move_to_next_step", interrupt_mode)
	return

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
	
func _delete_object(variant):
	if (!variant):
		return false				
	var index:int = stack.rfind(variant)
	stack.remove(index)
	rpc_id(1, "master_stack_object_removed", variant.stack_uid )
	return true
	
func delete_last_event():
	var event = stack_pop_back()
	scripting_bus.emit_signal("stack_event_deleted", event)
	
func find_last_event():
	if is_empty():
		return null
	return stack.back()	

func find_event(_event_details, details, owner_card):
	for x in stack.size():
		var event = stack[-x-1]
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
