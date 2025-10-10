class_name GlobalScriptStack
extends Node2D

#Action stack (similar to the MTG stack) where actions get piled, waiting for user input if needed

enum InterruptMode {
	NONE,
	FORCED_INTERRUPT_CHECK,
	OPTIONAL_INTERRUPT_CHECK,
	HERO_IS_INTERRUPTING,
	NOBODY_IS_INTERRUPTING
}

const INTERRUPT_FILTER := {
	InterruptMode.FORCED_INTERRUPT_CHECK:  CFConst.CanInterrupt.MUST,
	InterruptMode.OPTIONAL_INTERRUPT_CHECK: CFConst.CanInterrupt.MAY,
}

var interrupt_mode:int = InterruptMode.NONE
var interrupting_hero_id = 0

#potential_interrupters:
#	{hero_id => [list of cards that can interrupt] or "skip"}
var potential_interrupters: Dictionary = {}

var stack:Array = []
var waitOneMoreTick = 0


#stores data relevant to the ongoing interrupt signal
var _current_interrupted_event: Dictionary = {}

#stores unique IDs for all stack events
var current_stack_uid:int = 0
var stack_uid_to_object:Dictionary = {}
var object_to_stack_uid:Dictionary = {}
var card_already_played_for_stack_uid:Dictionary = {}

func add_script(object):
	#if somebody is adding a script while in interrupt mode,
	# we add the script (its owner card for now - TODO need to change?)
	# to the list of scripts that already responded to the last event
	#this prevents them from triggering infinitely to the same event 
	if interrupt_mode == InterruptMode.HERO_IS_INTERRUPTING:
		if (!card_already_played_for_stack_uid.has(current_stack_uid)):
			card_already_played_for_stack_uid[current_stack_uid] = []
		card_already_played_for_stack_uid[current_stack_uid].append(object.sceng.owner)

	#setup UID for the stack event
	current_stack_uid = current_stack_uid + 1
	object.stack_uid = current_stack_uid
	stack_uid_to_object[current_stack_uid] = object
	object_to_stack_uid[object] = current_stack_uid
	
	stack.append(object)
	object.added_to_global_stack()
	reset_interrupt_states()
	return

func reset_interrupt_states():
	interrupting_hero_id = 0
	potential_interrupters = {}
	set_interrupt_mode(InterruptMode.NONE)

	
func _process(_delta: float):
	if stack.empty(): 
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
				set_interrupt_mode(InterruptMode.FORCED_INTERRUPT_CHECK)
				rpc("client_send_before_trigger", interrupt_mode)

				
		InterruptMode.NOBODY_IS_INTERRUPTING:
			var next_script = stack.pop_back()
			var func_return = next_script.execute()	
			while func_return is GDScriptFunctionState && func_return.is_valid():
				func_return = func_return.resume()
			
			set_interrupt_mode(InterruptMode.NONE)
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

func is_processing():
	return !stack.empty()

func set_interrupt_mode(value:int):
	interrupt_mode = value
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
			_current_interrupted_event = {"event_name": task.script_name, "details": task.script_definition}
			for card in get_tree().get_nodes_in_group("cards"):
				#TODO makes a distinction between MAY and MUST here
				#Forced interrupts happen before optional ones
				if (card in card_already_played_for_stack_uid.get(script_uid, [])):
					continue
				if (task.script_name == "receive_damage"):
					if (card.canonical_name == "Backflip"):
						var _tmp = 1
				var can_interrupt = card.can_interrupt(hero_id,card, _current_interrupted_event)
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
	if !( interrupt_mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]):
		var _error = true
		#TODO error check
	var interrupters:Array = []
	for uid in guids:
		var card = guidMaster.get_object_by_guid(uid)	
		interrupters.append(card)
	potential_interrupters[hero_id] = interrupters

	if (potential_interrupters.size() == gameData.team.size()):
		select_interrupting_player()

#pass my opportunity to interrupt 
func pass_interrupt (hero_id):
	#TODO ensure that caller network id actually controls that hero
	rpc_id(1,"master_pass_interrupt", hero_id)
	
#call to master when I've chosen to pass my opportunity to interrupt 
mastersync func master_pass_interrupt (hero_id):
	#TODO ensure that caller network id actually controls that hero
	potential_interrupters[hero_id] = []
	select_interrupting_player()

func select_interrupting_player():
	if !cfc.is_game_master():
		return #TODO error check, this shouldn't even be possible
		
	for hero_id in potential_interrupters.keys():
		var interrupters = potential_interrupters[hero_id]
		if (interrupters):
			set_interrupt_mode(InterruptMode.HERO_IS_INTERRUPTING)
			rpc("client_set_interrupting_hero", hero_id)
			return
	
	#nobody is interrupting for this step, move to the next one
	if (interrupt_mode == InterruptMode.FORCED_INTERRUPT_CHECK):
		set_interrupt_mode(InterruptMode.OPTIONAL_INTERRUPT_CHECK)
		rpc("client_send_before_trigger", interrupt_mode)
	else:
		set_interrupt_mode(InterruptMode.NOBODY_IS_INTERRUPTING)
		rpc("client_move_to_next_step", interrupt_mode)
	return
	
remotesync func client_set_interrupting_hero(hero_id):
	set_interrupt_mode(InterruptMode.HERO_IS_INTERRUPTING)	
	interrupting_hero_id = hero_id
	
remotesync func client_move_to_next_step(_interrupt_mode):
	set_interrupt_mode(_interrupt_mode)
	potential_interrupters = {}
	if (interrupt_mode == InterruptMode.NOBODY_IS_INTERRUPTING):
		interrupting_hero_id = 0
	
func _delete_object(variant):
	if (!variant):
		return false				
	var index:int = stack.rfind(variant)
	stack.remove(index)
	return true
	
func delete_last_event():
	stack.pop_back()

func find_event(_name, details, owner_card):
	for x in stack.size():
		var event = stack[-x-1]
		var task = event.get_script_by_event_name(_name)
		if (!task):
			continue			
		if event.matches_filters(task, details, owner_card):
			return event
	return null			
	
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
