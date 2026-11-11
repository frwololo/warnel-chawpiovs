# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name GlobalScriptStack
extends Node2D


signal script_added_to_stack(script)
signal stack_interrupt(script, mode)
signal script_executed_from_stack(script)
signal manual_interaction_added_to_stack(details)

#display
#TODO something fancier
var text_edit:TextEdit = null
var stack:= []
#stores data relevant to the ongoing interrupt signal
var _current_interrupted_event: Dictionary = {}

#configuration for optimizations that might break multiplayer mode,
#but help speed up single player mode
#Ideally in the long run we need none of that and fix
#the underlying bugs/ inconsistent behavior
var all_config = {
	"single_player":{
		"speed_run_incoming_network_event": true, #force attempt to immediately run an event that was delayed
		"disable_status_tick_security_checks": true #disable tick checks for local status update
	},
	"multiplayer": {
	}
}

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

#Work waiting to enter the stack: deferred local scripts and events received
#from the master, in one ordered list (see StackInbox.gd)
const StackInbox = preload("res://src/wc/ScriptingEngine/StackInbox.gd")
var inbox = StackInbox.new()
var _ack_received = {}
var all_clients_status:= {}
var _local_status_counter = 0
var run_mode = RUN_MODE.NOTHING_TO_RUN
var interrupt_mode = InterruptMode.NONE
var interrupting_hero_id = 0
var _heroes_passed_optional_interrupt := {}
var _current_interrupting_cards:= []
var throttle_after_no_brakes:int = 0
var pending_stack_yield = {}
const yield_max_wait_time : float= 5.0
var history := {}
var pending_interaction_checksums := {}
var sync_enabled = true

var _pending_flush = {}
var _stash_pending_flush = {}

#set temporarily by callers to tag where an insertion comes from
#(used by the multiplayer insert journal)
var _insert_source := ""
#true while attempt_yielded_script re-submits a deferred script
var _draining_yielded_script := false

#Synchronization layer: single player or multiplayer version, see StackSync.gd
const StackSyncScript = preload("res://src/wc/ScriptingEngine/StackSync.gd")
const MultiplayerStackSyncScript = preload("res://src/wc/ScriptingEngine/MultiplayerStackSync.gd")
var _sync = null

#stores unique IDs for all stack events
var current_stack_uid:int = 0
var card_already_played_for_stack_uid:Dictionary = {}
var my_script_requests_pending_execution: = 0

var  _interrupt_cache = {
	"zones" : [],
	"additional_cards": [],
	"needs_refresh": true
}



func init_interruptable_cache():
	if !_interrupt_cache["needs_refresh"]:
		return	
	_interrupt_cache["zones"] = []
	_interrupt_cache["additional_cards"] = []

	if !CFConst.INTERRUPT_ALLOWED_PILES:
		_interrupt_cache["needs_refresh"] = false
		return
	
	var scriptables_array :Array =\
		cfc.get_tree().get_nodes_in_group("scriptables")
	
	scriptables_array +=\
			cfc.get_tree().get_nodes_in_group("cards")
	
	var extra_cards = {}
	
	for obj in scriptables_array:
		var all_scripts = obj.retrieve_all_scripts()
		for key in all_scripts:
			if key.begins_with("interrupt") or key.begins_with("response"):
				var script_data = all_scripts[key]
				if script_data.has("all") or script_data.has("pile"):
					extra_cards[obj] = true
					break

	_interrupt_cache["additional_cards"] = extra_cards.keys()

	_interrupt_cache["zones"] = ["board"]
	for i in gameData.get_team_size():
		var hero_id = i+1
		for zone in CFConst.INTERRUPT_ALLOWED_PILES:
			_interrupt_cache["zones"].append(zone + str(hero_id))

	_interrupt_cache["needs_refresh"] = false
	return



func get_config(entry):
	if gameData.is_multiplayer_game:
		return all_config.get("multiplayer", {}).get(entry, false)
	
	return all_config.get("single_player", {}).get(entry, false)

func _ready():
		
	scripting_bus.connect("step_started", self, "_step_started")
	scripting_bus.connect("card_script_added", self, "_card_script_added")
	scripting_bus.connect("card_script_removed", self, "_card_script_removed")
		
func _step_started(_trigger_object, details:Dictionary):
	var current_step = details["step"]
	match current_step:
		CFConst.PHASE_STEP.PLAYER_MULLIGAN, CFConst.PHASE_STEP.PLAYER_DISCARD, CFConst.PHASE_STEP.IDENTITY_SETUP:
			disable_sync()
		_:
			enable_sync()

		
func _card_script_added(_trigger_object, _details:Dictionary):
	_refresh_interrupt_cache()
	
func _card_script_removed(_trigger_object, _details:Dictionary):
	_refresh_interrupt_cache()

func _refresh_interrupt_cache():
	_interrupt_cache["needs_refresh"] = true

func add_yield_counter(name):
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

func serialize_sceng(sceng, trigger_details):
	var prepaid: Array = sceng.network_prepaid
	var prepaid_uids: Array = []

	#NOTE in some cases it is ok for prepaid to be empty. E.g. when refusing to defend

	for array in prepaid:
		var data = {"is_valid": array["is_valid"]}
		data["subjects"] =  guidMaster.array_of_objects_to_guid(array["subjects"], true)
		prepaid_uids.append(data)
	var remote_trigger_details: Dictionary = trigger_details.duplicate()
	remote_trigger_details["network_prepaid"] =  prepaid_uids
	remote_trigger_details["network_rng_state"] =  cfc.game_rng.state

	#convert stack_object and event_object to integers for network
	#TODO this should be encapsulated somewhere
	var stack_object = trigger_details.get("stack_object", null)
	if stack_object:
		remote_trigger_details["stack_object"] = stack_object.stack_uid
		var task_object = trigger_details.get("event_object", null)
		if task_object:
			var tasks = stack_object.get_tasks()
			var i = 0
			for task in tasks:
				if task == task_object:
					remote_trigger_details["event_object"] = i
				i+= 1
	
	var trigger_card_uid = guidMaster.get_guid(sceng.trigger_object)
	var owner_uid = guidMaster.get_guid(sceng.owner)
	var state_scripts = sceng.state_scripts
	
	return {
		"state_scripts": state_scripts,
		"owner_uid": owner_uid,
		"trigger_card_uid": trigger_card_uid,
		"remote_trigger_details": remote_trigger_details,
		"stored_integers": sceng.stored_integers	
	}
					
func create_and_add_script(sceng, run_type, trigger, trigger_details, action_name, checksum):
	var yield_data = {
		"sceng": sceng,
		"run_type": run_type,
		"trigger": trigger,
		"trigger_details": trigger_details,
		"action_name": action_name,
		"checksum": checksum,
		"yield_reason": "create_and_add_script",
	}
	#diagnostics only: was a flush running when this script was created?
	var flush_was_pending = !_pending_flush.empty()

	#Step 4: a script that needs no decision does not jump ahead of the local
	#scripts already waiting in the inbox. Before, a script created right after
	#a flush (no flush running any more) went straight to the stack while older
	#deferred scripts were still waiting, so its place depended on whether the
	#flush had ended yet on that client (Red Skull's stage change: the new
	#scheme's reveal before or after its self_moved_to_board).
	#Requests (a player's decision) keep their place: the other clients apply
	#them while they wait, without draining their inbox first.
	#Interrupts and responses keep their place too: they belong to the window
	#open on the stack right now, which waits for them, while the inbox only
	#drains at a marker or an idle stack (Magik's
	#response_signal_enable_magik_top_deck stayed behind two older scripts
	#forever in test_1p_magik_play_top_colossus).
	if sync_enabled and !_draining_yielded_script and inbox.has(StackInbox.LOCAL) \
			and sceng.user_interaction_status != CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER \
			and trigger != "manual" and !_is_interrupt_or_response_trigger(trigger, trigger_details):
		get_sync().record_script_created(trigger, "deferred_inbox", flush_was_pending, _draining_yielded_script)
		add_yielded_script(yield_data, "deferred_inbox")
		return null
		
	if _pending_flush and sync_enabled:
		var yield_script = true
		# a hacky check to interrupt an ongoing activity when nothing else works
		#currently used for Black Widow (Villain)'s execute_scripts for preparation
		var interrupt_parent_stack_uid = trigger_details.get("interrupt_parent_stack_uid", 0)
		if interrupt_parent_stack_uid and _pending_flush.get(interrupt_parent_stack_uid):
			yield_script = false
			_stash_pending_flush[interrupt_parent_stack_uid] = true
			_pending_flush.erase(interrupt_parent_stack_uid)
		if yield_script:
			get_sync().record_script_created(trigger, "deferred_flush", flush_was_pending, _draining_yielded_script)
			add_yielded_script(yield_data, "deferred_flush")
			#gameData.send_log_to_master("create_and_add_script yields (" + checksum + ")")
			return null
		
	if sceng.user_interaction_status == CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER:
		if trigger != "manual":	
			set_run_mode(RUN_MODE.PENDING_USER_INTERACTION)	
			#gameData.theStack.set_pending_network_interaction(interaction_authority, checksum, "authorized user ready to interact")
	
	
	if !run_mode in [RUN_MODE.NOTHING_TO_RUN, RUN_MODE.PENDING_USER_INTERACTION] :
		if trigger in ["manual"]: #todo might need interrupt in there as well?
			var _error = 1
			display_stack_error_for_card(sceng.owner)
			#gameData.send_log_to_master("create_and_add_script run_mod error")
			return null
		elif sync_enabled:
			get_sync().record_script_created(trigger, "deferred_run_mode", flush_was_pending, _draining_yielded_script)
			add_yielded_script(yield_data, "deferred_run_mode")
			#gameData.send_log_to_master("create_and_add_script yields (runmode)")
			return null
	#if the script required user interaction, we send it
	#to the master for replication on all clients
	#else, all machines are expected to run it locally
	var expected_run_mode = run_mode
	match sceng.user_interaction_status:
		CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER:
		#we deconstruct locally here to reconstruct it on all clients then add it to all stacks
		#also send GUIDs to find the right cards/targets			
			get_sync().record_script_created(trigger, "request", flush_was_pending, _draining_yielded_script)
			var serialized_sceng = serialize_sceng(sceng, trigger_details)
			if "decision_slot" in sceng and sceng.decision_slot > 0:
				serialized_sceng["decision_slot"] = sceng.decision_slot
				_log_slot("request for #" + str(sceng.decision_slot) + " '" + str(checksum) + "' (" + action_name + ")")
			my_script_requests_pending_execution += 1
			set_run_mode(RUN_MODE.PENDING_REQUEST_ACK, "create_and_add_script - "  + action_name)
			cfc._rpc_id(self,1, "master_create_and_add_script", expected_run_mode, serialized_sceng, run_type, trigger, action_name, checksum)
			#todo return something useful here
			return null
			#TODO should wait for ack from all clients before anybody can do anything further in the game
		CFConst.USER_INTERACTION_STATUS.DONE_INTERACTION_NOT_REQUIRED:
			get_sync().record_script_created(trigger, "direct", flush_was_pending, _draining_yielded_script)
			var stackEvent:StackScript = StackScript.new(sceng, run_type, trigger)
			#gameData.send_log_to_master("create_and_add_script: creating local stackEvent: " + checksum)
			stackEvent.add_log("created in GlobalScriptStack: create_and_add_script. Trigger: " + trigger)			
			stackEvent.set_display_name(action_name)
			add_script_and_run(stackEvent)
			return stackEvent
		_:
			#this shouldn't happen
			display_debug("error in create_and_add_script, invalid sceng.user_interaction_status:" +str(sceng.user_interaction_status))
			return null
			
func is_pending_flush(uid):
	return _pending_flush.get(uid) or _stash_pending_flush.get(uid)

func remove_pending_flush(uid):
	_pending_flush.erase(uid)
	_stash_pending_flush.erase(uid)	

#One decision at a time: a deferred decision (the deciding client's dialog or
#choice, or a waiting client's wait for it) is not resumed while another
#decision is still open, otherwise two decision menus show up at once
#(Cable's card_defeated dialog over the Lock and Load selection).
#Both sides stop at the same point: the open decision ends, everywhere, when
#its outcome reaches the stack.
func can_drain_local_entry() -> bool:
	var entry = inbox.first(StackInbox.LOCAL)
	if entry == null:
		return false
	if not entry.get("type", "") in ["deferred_decision", "pending_network_interaction"]:
		return true
	var open_decision = get_open_decision()
	if open_decision:
		display_debug("deferred decision " + str(entry.get("checksum", "")) + " waits for " + open_decision)
		return false
	return true

#"" if no decision is open on this client, otherwise what is open
func get_open_decision() -> String:
	if cfc.get_modal_menu():
		return "a menu"
	if my_script_requests_pending_execution > 0:
		return "my own request"
	if !pending_interaction_checksums.empty():
		return "remote decision " + str(pending_interaction_checksums.keys())
	return ""

func add_yielded_script(yield_data, reason := ""):
	add_yield_counter("yielded_script")
	inbox.add(StackInbox.LOCAL, yield_data)
	#diagnostics: when and from where each local entry joins the inbox
	var callers = []
	for frame in get_stack():
		if callers.size() >= 8:
			break
		callers.append(str(frame.get("function", "")))
	log_flow("inbox_add", str(yield_data.get("type", "script")) + " '" + str(yield_data.get("checksum", "")) \
			+ "' " + reason + " frame " + str(Engine.get_idle_frames()) + " via " + PoolStringArray(callers).join(">"))

func attempt_yielded_script():
	if !inbox.has(StackInbox.LOCAL):
		return false
	
	#failsafe in case game exited early
	if not cfc.NMAP.has("board") or not is_instance_valid(cfc.NMAP.board):
		return false
		
	var script_data = inbox.pop_first(StackInbox.LOCAL)
	remove_yield_counter("yielded_script")
	log_flow("inbox", str(script_data.get("type", "script")) + " '" + str(script_data.get("checksum", "")) + "'")

	if script_data.get("type", "") == "pending_network_interaction":
		get_sync().enter_pending_network_interaction(script_data["checksum"], script_data["reason"])
		return

	if script_data.get("type", "") == "deferred_decision":
		_resume_deferred_decision(script_data)
		return

	var previous_source = _insert_source
	_insert_source = "yielded"
	_draining_yielded_script = true
	var result = create_and_add_script(
		script_data["sceng"],
		script_data["run_type"],
		script_data["trigger"],
		script_data["trigger_details"],
		script_data["action_name"] ,
		script_data["checksum"] )
	_draining_yielded_script = false
	_insert_source = previous_source

	if result:
		result.add_log("succesful creation after yield")

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


mastersync func master_create_and_add_script(expected_run_mode, serialized_sceng,  run_type, trigger, action_name, checksum):
	var client_id = cfc.get_rpc_sender_id() 
	set_client_status(client_id, "run_mode", RUN_MODE.PENDING_REQUEST_ACK)	
	var owner_uid = serialized_sceng["owner_uid"]
	var original_details = {
		"state_scripts": serialized_sceng["state_scripts"],
		"owner_uid": owner_uid, 
		"trigger_card_uid": serialized_sceng["trigger_card_uid"],  
		"run_type": run_type, 
		"trigger": trigger,	
		"remote_trigger_details":serialized_sceng["remote_trigger_details"],
		"stored_integers": serialized_sceng["stored_integers"], 
		"action_name": action_name,
		"decision_slot": serialized_sceng.get("decision_slot", -1),
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
		cfc._rpc_id(self, client_id, "accepted_add_script_request", expected_run_mode, original_details)
		#NOTE: the RNG state travels inside original_details and is applied by each client
		#at the moment the script is inserted (see _process_incoming_network_events),
		#not on packet receipt. Applying it on receipt caused RNG divergence when a client
		#was still running local scripts while the network script waited in the queue.
		display_debug("Asking clients to add script " + action_name)
		cfc._rpc(self,"client_create_and_add_stackobject", client_id, expected_run_mode, original_details, checksum)
	else:
		cfc._rpc_id(self, client_id, "rejected_add_script_request", expected_run_mode, original_details)

func _apply_network_rng_state(new_state):
	var current_state = cfc.game_rng.state
	if current_state!= new_state:
		cfc.game_rng.state = new_state
		cfc.LOG("Game rng state sync from " + str(current_state) + " to " + str(new_state))

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



master func from_client_script_received_ack(expected_run_mode, checksum):
	var acks = _ack_received.get(checksum, {})
	var client_id = cfc.get_rpc_sender_id()
	acks[client_id] = true
	_ack_received[checksum] = acks
	if acks.size() == gameData.network_players.size():
		_ack_received.erase(checksum)
		cfc._rpc(self,"resume_operations", expected_run_mode, checksum)
	

#A network event that carries the outcome of a decision this client has not
#reached yet must not hold the game back: this client still has to move on
#to that decision point, and the event waits there for it (see
#get_network_event_wait_reason). It used to stop the encounter sequence, so
#an obligation never reached the board on the waiting client, its choice was
#never reached, and only the 5s timeout broke the circle (Eviction Notice).
func _has_network_event_blocking_idle() -> bool:
	for ev in inbox.entries(StackInbox.NETWORK):
		var slot = _get_event_decision_slot(ev)
		if slot > 0 and !inbox.is_slot_reached(slot):
			continue
		return true
	return false

func _get_event_decision_slot(ev) -> int:
	var slot = ev.get("decision_slot", -1)
	if ev.get("type", "") == "add_stack_object":
		slot = ev.get("details", {}).get("decision_slot", -1)
	if typeof(slot) != TYPE_INT and typeof(slot) != TYPE_REAL:
		return -1
	return int(slot)

func add_incoming_network_event(data):
	data["waited"] = 0.0
	inbox.add(StackInbox.NETWORK, data)

	#if I'm the requester, process instantly. 
	#TODO this might lead to errors?

	#speed run in single player mode
	if get_config("speed_run_incoming_network_event"):
		_process_incoming_network_events(0.0)
		
remotesync func client_create_and_add_stackobject( original_requester_id, expected_run_mode, details, checksum):
	var client_id = cfc.get_rpc_sender_id()
					
	display_debug(str(client_id) + " wants me to add a script - " + checksum )
	add_incoming_network_event({
		"type": "add_stack_object",
		"requester": original_requester_id,
		"expected_run_mode": expected_run_mode,
		"details": details, 
		"checksum": checksum})	
	

func _process_incoming_network_events(delta):
	var ev = inbox.first(StackInbox.NETWORK)
	if ev == null:
		return false
	var wait_reason = get_sync().get_network_event_wait_reason(ev)
	if wait_reason:
		ev.waited += delta
		display_debug("yield for " + wait_reason + " in " + ev.type)
		if ev.waited < yield_max_wait_time:
			return false  # keep waiting, and keep the order
		cfc.LOG("{desync} timeout waiting for " + wait_reason + ", inserting " + ev.type + " anyway - " + ev.checksum, true)
	#removed before it is applied: applying it can add (and, with
	#speed_run_incoming_network_event, process) further network events
	inbox.pop_first(StackInbox.NETWORK)
	match ev.type:
		"add_stack_object":
			fill_decision_slot(ev.details.get("decision_slot", -1), ev.checksum, "script")
			#Sync the RNG at the exact point the script enters the stack,
			#so every client resumes from the same RNG state from here on
			var rng_state = ev.details.get("remote_trigger_details", {}).get("network_rng_state", null)
			if rng_state != null:
				_apply_network_rng_state(rng_state)
			var stackEvent = client_create_script(ev.details)
			if stackEvent:
				stackEvent.add_log("succesful after _process_incoming_network_events")
				var previous_source = _insert_source
				_insert_source = "network"
				add_event_to_stack(stackEvent, ev.checksum)
				_insert_source = previous_source
				if ev.details.get("trigger", "") == "manual":
					emit_signal("manual_interaction_added_to_stack", ev.details)
			cfc._rpc_id(self, 1, "from_client_script_received_ack", ev.expected_run_mode, ev.checksum)
			return stackEvent
		"resume_operations":
			fill_decision_slot(ev.get("decision_slot", -1), ev.checksum, "declined")
			if get_sync().is_resume_for_unknown_manual_interaction(ev):
				display_debug("ignoring resume_operations for a manual interaction I never waited for - " + str(ev.checksum))
				return false
			if ev.expected_run_mode == RUN_MODE.PENDING_USER_INTERACTION:
				if !pending_interaction_checksums.has(ev.checksum):
					send_error_to_master("error in resume_operations, unaware of pending interaction " + ev.checksum)
				pending_interaction_checksums.erase(ev.checksum)
	
			set_run_mode(RUN_MODE.NO_BRAKES, "resume_operations")			
		"clients_pass_interrupt":
			#TODO ensure that caller network id actually controls that hero
			reset_phase_buttons()
			_heroes_passed_optional_interrupt[ev.details["hero_id"]] = true
			set_run_mode(RUN_MODE.NO_BRAKES, "clients_pass_interrupt")			
		"clients_pass_interrupt_for_card":
			add_card_already_played(ev.details["event_uid"], ev.details["card"])			
		_:
			#unsupported
			return false

func send_error_to_master(error_message):
	#todo send error message to master to attempt recovery
	display_debug(error_message)

###
### Decision slots (step 3 of the Deterministic Stack Sync design, shadow mode)
###
#Every client reserves a slot when it reaches a decision, and the master's
#broadcast of that decision fills it on every client, the deciding one included.
#Shadow mode: slots are only matched and checked ({slots} log lines); the
#existing mechanism still decides when decisions are applied.

#Player-initiated plays (manual, and plays made during an interrupt window)
#only run on the clicking client, so they must not consume a slot number.
func is_decision_slot_candidate(trigger, trigger_details) -> bool:
	if !sync_enabled:
		return false
	if str(trigger).begins_with("manual"):
		return false
	if typeof(trigger_details) == TYPE_DICTIONARY:
		if trigger_details.get("is_interrupt_or_response", false):
			return false
		if trigger_details.has("network_prepaid"):
			return false
	return true

#origin: where the decision was reached (dialog, choice, target, selection)
#authorized: whether this client is the one deciding
func reserve_decision_slot(checksum, origin := "", authorized = null) -> int:
	var result = inbox.reserve_slot(str(checksum))
	_log_slot("reserved #" + str(result["slot"]) + " '" + str(checksum) + "' at " + origin \
			+ ("" if authorized == null else (" (deciding)" if authorized else " (waiting)")) \
			+ (" during flush" if !_pending_flush.empty() else ""))
	if result["problem"]:
		cfc.LOG("{slots} " + result["problem"], true)
	return result["slot"]

#Step 4a of the Deterministic Stack Sync design: one {flow} line every time
#work starts outside the stack (inbox entry, priority script, sequence step,
#encounter step, attack, phase request, automated death, stack_idle), with
#what else was waiting at that moment, so the order can be compared across
#clients. Diagnostics, removed in step 5
func _is_interrupt_or_response_trigger(trigger, trigger_details) -> bool:
	var t = str(trigger)
	if t.begins_with("interrupt") or t.begins_with("response"):
		return true
	return typeof(trigger_details) == TYPE_DICTIONARY and trigger_details.get("is_interrupt_or_response", false)

#Step 4: local scripts waiting in the inbox go before a new unit of game flow
#(a new attack, a new encounter). Before, an attack could start while a
#deferred script still waited, on one client only (Blood to Spare: Armored
#Guard's attack vs its post_reveal sequence). Steps of an attack or an
#encounter already under way do not wait: the encounter's own reveal scripts
#are in the inbox while it moves on (test_1p_apocalypse_technological_interface)
func has_local_inbox_entries() -> bool:
	return inbox.has(StackInbox.LOCAL)

func get_local_inbox_entries() -> Array:
	return inbox.entries(StackInbox.LOCAL)

func log_flow(source: String, detail := "") -> void:
	cfc.LOG("{flow} " + source + (" " + detail if detail else "") \
			+ " | after uid " + str(current_stack_uid) \
			+ " stack=" + str(stack.size()) + " run=" + str(RUN_MODE.keys()[run_mode]) \
			+ " step=" + str(gameData.phaseContainer.get_current_phase_name()) \
			+ " | waiting " + to_json(gameData.get_flow_waiting_summary()), true)

#Diagnostics for decisions one client may skip (Daredevil's thwart_happened):
#only triggered scripts, manual plays and interrupts are expected to differ
func log_decision_path(checksum, trigger, what: String, authorized) -> void:
	var t = str(trigger)
	for prefix in ["manual", "interrupt", "response"]:
		if t.begins_with(prefix):
			return
	_log_slot("path '" + str(checksum) + "' " + what + (" (deciding)" if authorized else " (waiting)"))

#One line per reservation, fill and request, so that the logs of two clients
#can be compared side by side. Shadow mode diagnostics, removed in step 5
func _log_slot(msg: String) -> void:
	if !sync_enabled:
		return
	cfc.LOG("{slots} " + msg + " | after uid " + str(current_stack_uid) \
			+ " step=" + str(gameData.phaseContainer.get_current_phase_name()), true)

func fill_decision_slot(slot, checksum, source: String) -> void:
	if not typeof(slot) in [TYPE_INT, TYPE_REAL]:
		return
	if int(slot) < 1:
		return
	_log_slot("filled #" + str(int(slot)) + " '" + str(checksum) + "' by " + source)
	var problem = inbox.fill_slot(int(slot), str(checksum))
	if problem:
		cfc.LOG("{slots} " + problem + " (" + source + ")", true)

#A decision that ends without a script and without a resume (e.g. a cost
#payment that was cancelled or failed) still fills its slot everywhere
func fill_decision_slot_with_nothing_to_all(slot: int, checksum) -> void:
	if slot < 1:
		return
	cfc._rpc(self, "clients_fill_decision_slot_with_nothing", slot, checksum)

remotesync func clients_fill_decision_slot_with_nothing(slot, checksum):
	fill_decision_slot(slot, checksum, "nothing")

#Deciding client: a dialog or a choice reached while a flush is ongoing waits
#in the inbox like the waiting clients' wait does (see StackSync)
func should_defer_decision(exec_config: Dictionary) -> bool:
	return get_sync().should_defer_decision(exec_config)

func defer_decision(card, args: Array, decision_slot, checksum, origin: String) -> void:
	_log_slot("deferred #" + str(decision_slot) + " '" + str(checksum) + "' at " + origin)
	add_yielded_script({
		"type": "deferred_decision",
		"card": card,
		"args": args,
		"decision_slot": decision_slot,
		"checksum": checksum,
		"yield_reason": "deferred decision (" + origin + ")",
	})

func _resume_deferred_decision(script_data) -> void:
	var card = script_data["card"]
	var checksum = script_data["checksum"]
	var decision_slot = script_data["decision_slot"]
	_log_slot("resumed #" + str(decision_slot) + " '" + str(checksum) + "'")
	if !is_instance_valid(card):
		#the other clients are waiting for this decision
		resume_operations_to_all(checksum, decision_slot)
		return
	var args = script_data["args"]
	var exec_config: Dictionary = args[5].duplicate()
	exec_config["resumed_decision_slot"] = decision_slot
	var trigger = args[2]
	var result = card.choose_and_execute_scripts(args[0], args[1], trigger, args[3], args[4], exec_config)
	if result is GDScriptFunctionState and !trigger in ["manual", "manual_override"]:
		#same announce as in execute_scripts, which is not the caller anymore
		gameData.theAnnouncer.choices_menu(card, trigger, args[3].get("origin_event", null), cfc.get_modal_menu())

#Called on clients that are NOT authorized to make a choice, see StackSync.gd
func set_pending_network_interaction(interaction_authority, checksum, reason:=""):
	get_sync().set_pending_network_interaction(interaction_authority, checksum, reason)

#client asking everyone to resume
#the expectation is to call this only when it is clear that everyone is pending interaction
#decision_slot: the slot of the decision that was declined, if any (see StackInbox)
func resume_operations_to_all(checksum, decision_slot := -1):
	cfc._rpc(self,"resume_operations", RUN_MODE.PENDING_USER_INTERACTION, checksum, decision_slot)
	
remotesync func resume_operations(expected_run_mode, checksum, decision_slot := -1):
	var client_id = cfc.get_rpc_sender_id()	
#	if stack.empty() or run_mode == RUN_MODE.NO_BRAKES:
#		var _error = 1

	add_incoming_network_event({
		"type": "resume_operations",
		"requester":client_id,
		"expected_run_mode": expected_run_mode,
		"checksum": checksum,
		"decision_slot": decision_slot})	

			
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

	#retrieve objects from network integers
	#TODO this should be encapsulated somewhere
	var stack_object_uid = remote_trigger_details.get("stack_object", null)
	if stack_object_uid:
		var convert_success = false
		var stack_object = get_stack_object_by_uid(stack_object_uid)
		if stack_object:
			remote_trigger_details["stack_object"] = stack_object
			var event_object_uid = remote_trigger_details.get("event_object", null)
			if (event_object_uid != null) and stack_object.get_tasks().size() > event_object_uid:
				var event_object = 	stack_object.get_tasks()[event_object_uid]
				remote_trigger_details["event_object"] = event_object
				convert_success = true			
		if !convert_success:
			var _error = 1
			remote_trigger_details.erase("stack_object")
			remote_trigger_details.erase("event_object")
	
	var sceng = cfc.scripting_engine.new(
				state_scripts,
				owner_card,
				trigger_card,
				remote_trigger_details)
	sceng.stored_integers = stored_integers
	#we force setting the subjects here based on network_prepaid,
	#to ensure that when this sceng goes on the stack, its subjects are ready for any interrupt to check for them	
	sceng.network_prepaid_prime()	
	var stackEvent:StackScript = StackScript.new(sceng, run_type, trigger)
	stackEvent.add_log("created in GlobalScriptStack: client_create_script")
	stackEvent.set_display_name(action_name)
	return stackEvent


func add_event_to_stack(stackEvent, checksum = "", context= {}):
	#if somebody is adding a script while in interrupt mode,
	# we add the script (its owner card for now - TODO need to change?)
	# to the list of scripts that already responded to the last event
	#this prevents them from triggering infinitely to the same event 
#	if interrupt_mode == InterruptMode.HERO_IS_INTERRUPTING:
	var result = {
		"is_interrupt" : false,
		"pos": -1
	}

	var high_priority_script = 0
	var sceng = stackEvent.get_sceng()
	if sceng:
		high_priority_script = sceng.trigger_details.get("interrupt_parent_stack_uid",0)

	var priority_signal = false
	if stackEvent as SignalStackScript:
		if stackEvent.script_name in CFConst.FORCE_INTERRUPT_SIGNALS:
			priority_signal = true 
	else:
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
				add_card_already_played(script_uid, stackEvent.sceng.owner)
				display_debug("add_event_to_stack: added " + stackEvent.get_display_name())
				#reset_interrupt_states()


	if is_interrupt_mode() or priority_signal or high_priority_script:
		var buffer = StackObject.new()
		buffer.interrupt_marker = true
		insert_event_into_stack(buffer)
		if context:
			open_context(context)
		insert_event_into_stack(stackEvent)
	else:
		var pos = 0
		for i in stack.size():
			var j = stack.size() - 1 - i
			if stack[j].interrupt_marker:
				pos = j + 1
				break
			elif stack[j].context_marker:
				#if we're trying to open a new context while a conext of the same name already exists,
				#for the moment we assume it needs to start after the current context
				#Typical example is a double attack: we want the second attack lower in the stack so that it starts after the first,
				#this is to avoid playing such events in a reverse order
				#this might have to change in the future
				var existing_name = stack[j].task.get_property("context_name")
				if !context or (existing_name != context["context_name"]):
					pos = j + 1
					break	
		result["pos"] = pos
		insert_event_into_stack(stackEvent, pos)
		if context:
			open_context(context, pos)
		#stack.push_front(stackEvent)
	
	emit_signal("script_added_to_stack",stackEvent)
	display_debug("added script to stack - " + checksum + ". my current_stack_uid is " + str(current_stack_uid) )
	return result

func add_card_already_played(script_uid, card):
	if (!card_already_played_for_stack_uid.has(script_uid)):
		card_already_played_for_stack_uid[script_uid] = []
	card_already_played_for_stack_uid[script_uid].append(card)

#adds a "context" event to open a context window for the current activity (e.g. attack)
#this will allow sending a "context closed" event once the ongoing activity is finished
func open_context( context, position =-1):
	var event = context.get("stack_event", null)
	
	#if the event already exists in the stack, we open right before it
	if position == -1:
		position = find_event_id_in_stack(event)
	
	var original_script = context["original_script"]
	var context_details = context.get("details", {})
	context_details["script_history"] = [original_script]
	var definition = {
		"name": "context_closed",
		"_silent": true,
		"original_script": original_script,
		"context_name": context["context_name"],
		"context_details": context_details, 
	}
	var owner = event.get_owner() if event else original_script.owner
	var task = SimplifiedStackScript.new(definition, owner)
	task.add_log("created in globalScriptStack: open_context")
	task.context_marker = true
	var stack_uid = insert_event_into_stack(task, position)
	context["context_stack_uid"] = stack_uid
	return stack_uid

func get_context_event(stack_uid_or_context_name):
	var event = null
	if typeof(stack_uid_or_context_name) == TYPE_STRING:
		for i in stack.size():
			var j = stack.size() - 1 - i
			var potential_event = stack[j]
			if potential_event.context_marker and (potential_event.task.script_definition["context_name"] == stack_uid_or_context_name):
				event = potential_event
				break		
	else:
		event = get_stack_object_by_uid(stack_uid_or_context_name)
		if !event or !event.context_marker:
			var _error = 1
			return	null	
	return event

func get_context_event_uid(stack_uid_or_context_name):	
	var event = get_context_event(stack_uid_or_context_name)
	if !event:
		var _error = 1
		return
		
	return event.stack_uid

func remove_context_details (stack_uid_or_context_name, key):
	var event = get_context_event(stack_uid_or_context_name)
	if !event:
		var _error = 1
		return
	event.task.script_definition["context_details"].erase(key)

func get_context_details (stack_uid_or_context_name, key = ""):
	var event = get_context_event(stack_uid_or_context_name)
	if !event:
		var _error = 1
		return
	var details = event.task.script_definition["context_details"]
	if !key:
		return details
		
	return details.get(key, null)
			
				
func add_context_details (stack_uid_or_context_name, details: Dictionary):
	var event = get_context_event(stack_uid_or_context_name)
	if !event:
		var _error = 1
		return

	var context_details = event.task.script_definition["context_details"]
	event.task.script_definition["context_details"] = WCUtils.merge_dict(context_details, details, true, true)
	

func insert_event_into_stack(stackEvent, pos = -1):
	if !gameData._is_engine_ready:
		var _error = 1
		gameData.send_log_to_master("insert event into stack called but engine isn't ready " + stackEvent.get_first_task_name())
	stackEvent.set_stack_uid(get_next_stack_uid())
	get_sync().on_stack_insert(stackEvent, pos)
	if pos == -1:
		stack.append(stackEvent)
	else:
		stack.insert(pos, stackEvent)

	history[stackEvent.stack_uid] = {
		"stack_uid" : stackEvent.stack_uid,
		"stack_object": stackEvent,
		"details": stackEvent.get_display_name(),
		"class": stackEvent.get_class(),	
	}
	
	return stackEvent.stack_uid	
	

#wrapper around add_event_to_stack that also tries to restart the execution of scripts
func add_script_and_run(stackEvent, context : = {}):
	var result = add_event_to_stack(stackEvent, "", context)
	force_run(result)
	return result

func force_run(result):
	if run_mode == RUN_MODE.NOTHING_TO_RUN:
		set_run_mode(RUN_MODE.NO_BRAKES, "add_script_and_run")
	if result.get("is_interrupt", false):
		set_run_mode(RUN_MODE.NO_BRAKES, "add_script_and_run interrupt")			
	if run_mode!= RUN_MODE.NO_BRAKES:
		display_debug("error add_script: expected run mode to be NO_BRAKES, but got " + RunModeStr[run_mode])
	return result
	
func add_context_and_script(context_name, script):
	var stack_event = SimplifiedStackScript.new(script)
	stack_event.add_log("created in globalScriptStack: add_context_and_script")	
	var context = {
			"context_name": context_name,
			"original_script": script,
			"stack_event": stack_event
	}
	add_script(stack_event, context)
	return context.get("context_stack_uid", 0)

func add_script(stackEvent, context:= {}):
	add_script_and_run(stackEvent, context)




var _sent_about_to_execute_signal = {}
func _process(delta: float):
	
	if get_sync().on_process(delta):
		return
	
	if _process_incoming_network_events(delta):
		return
		
	display_debug_info()
	
	show_server_activity()
	
	if run_mode in [RUN_MODE.NOTHING_TO_RUN]: #, RUN_MODE.PENDING_USER_INTERACTION]:
		if inbox.has(StackInbox.LOCAL):
			if can_drain_local_entry():
				attempt_yielded_script()
			return
		if get_sync().on_process_idle():
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

	if cfc.game_paused:
		return

	if gameData.is_ongoing_blocking_announce():
		return

	if cfc.get_modal_menu():
		return

	var stack_object = stack.back()
	#we're giving the chance for pending scripts to execute as part of
	# an interrupt flow, before resuming normal execution
	if stack_object.interrupt_marker:
		if inbox.has(StackInbox.LOCAL):
			if !can_drain_local_entry():
				return
			#var backup_state = run_mode
			set_run_mode(RUN_MODE.PENDING_USER_INTERACTION)
			attempt_yielded_script()
			#run_mode = backup_state
			return
#		if gameData.execute_priority_scripts():
#			return
		
	#signal gameData about who's currently "playing"
	var script_identity = stack_object.owner_identity
	gameData.set_current_acting_identity(script_identity)
	
	var _interrupt_state = compute_interrupts(stack_object)
	
	if !_sent_about_to_execute_signal.has(stack_object):
		_sent_about_to_execute_signal[stack_object] = true
		var message_to_show = gameData.theAnnouncer.show_stack_announce(stack_object , _interrupt_state["interrupt_mode"])
		if message_to_show: 
			return
		
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
						emit_signal("stack_interrupt", stack_object, InterruptMode.FORCED_INTERRUPT_CHECK )
						force_play_card(interrupters, stack_object)
						return
		InterruptMode.OPTIONAL_INTERRUPT_CHECK:
			set_run_mode(RUN_MODE.PENDING_USER_INTERACTION,  "_process OPTIONAL_INTERRUPT_CHECK")			
			potential_interrupters =  _interrupt_state["potential_interrupters"]
			for i in gameData.get_team_size():
#				var hero_id = i+1
				var hero_id = gameData.get_ordered_hero_id(i)
				if potential_interrupters.get(hero_id, []):
					set_interrupting_hero(hero_id, potential_interrupters[hero_id])
					emit_signal("stack_interrupt", stack_object, InterruptMode.OPTIONAL_INTERRUPT_CHECK )
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
		var yield_wait_time = 0.0
		while (yield_wait_time < yield_max_wait_time) and get_client_status(network_id, "run_mode") != RUN_MODE.PENDING_USER_INTERACTION:
			display_debug("yield for other clients in activate_exclusive_hero")
			yield(get_tree().create_timer(0.1), "timeout")
			yield_wait_time+= 0.1
	remove_yield_counter("activate_exclusive_hero")
	
	for i in range (gameData.team.size()):
		var hero_index = i+1
		if (hero_index == hero_id):
			gameData.phaseContainer.activate_hero(hero_index)
			gameData.select_current_playing_hero(hero_index)
		else:
			gameData.phaseContainer.deactivate_hero(hero_index)	

var _interrupting_hero_data = {}
mastersync func master_set_interrupting_hero(hero_id, interrupters):
	var client_id = cfc.get_rpc_sender_id()
	_interrupting_hero_data[client_id] = hero_id
	if _interrupting_hero_data.size() == gameData.network_players.size():
		_interrupting_hero_data = {}
		cfc._rpc(self,"clients_set_interrupting_hero", hero_id, interrupters)

func set_interrupting_hero(hero_id, interrupters):
	display_debug("set interrupting hero id to " + str(hero_id) + " with interrupters " + to_json(interrupters))

	set_current_interrupting_cards(interrupters)
	interrupting_hero_id = hero_id
#	activate_exclusive_hero(hero_id)
	cfc._rpc_id(self,1, "master_set_interrupting_hero", hero_id, interrupters)

func set_current_interrupting_cards(interrupters):
	display_debug("setting current_interrupting_cards to :" + to_json(interrupters))
	_current_interrupting_cards = []
	for card_guid in interrupters:
		var card = guidMaster.get_object_by_guid(card_guid)
		_current_interrupting_cards.append(card)	

remotesync func clients_set_interrupting_hero(hero_id, _interrupters):
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
	#cfc._rpc(self,"clients_pass_interrupt", hero_id)	
	cfc._rpc(self,"clients_pass_interrupt", hero_id)

func get_current_interrupted_event():
	return _current_interrupted_event

#call to all when I've chosen to pass my opportunity to interrupt 
remotesync func clients_pass_interrupt (hero_id):
	var client_id = cfc.get_rpc_sender_id()
	display_debug(str(client_id) + " wants to pass for hero:" + str(hero_id) )

	add_incoming_network_event({
		"type": "clients_pass_interrupt",
		"requester":client_id,
		"details": {"hero_id": hero_id},
		"expected_run_mode": RUN_MODE.PENDING_USER_INTERACTION,
		"checksum": "pass_interrupt_" + str(hero_id)})	


func pass_interrupt_for_card (event, card):
	var guid = guidMaster.get_guid(card)
	cfc._rpc(self,"clients_pass_interrupt_for_card", event.stack_uid, guid)

#call to all when I've chosen to pass my opportunity to interrupt 
remotesync func clients_pass_interrupt_for_card (event_uid, card_guid):
	var client_id = cfc.get_rpc_sender_id()
	var card = guidMaster.get_object_by_guid(card_guid)
	display_debug(str(client_id) + " wants to pass for card:" + card.canonical_name )

	add_incoming_network_event({
		"type": "clients_pass_interrupt_for_card",
		"requester":client_id,
		"details": {"card": card, "card_guid": "card_guid", "event_uid": event_uid},
		"expected_run_mode": RUN_MODE.PENDING_USER_INTERACTION,
		"checksum": "pass_interrupt_for_card" + str(card_guid)	
	})


#forced activation of card for forced interrupt
func force_play_card(interrupters, stack_object):
	#TODO force interrupt mode here for security
	set_current_interrupting_cards(interrupters)
	#_current_interrupting_mode = InterruptMode.FORCED_INTERRUPT_CHECK
	
	var card = _current_interrupting_cards[0]
	
	var result = card.attempt_to_play(false, stack_object)
	if result:
		add_card_already_played(stack_object.stack_uid, card)

#Returns the synchronization layer matching the current game mode, creating
#or replacing it if needed. The stack is created when the application starts,
#before the game mode is known, hence the lazy creation.
#It is called every frame from _process, so the node exists on every client
#before any RPC can target it.
func get_sync():
	var want_multiplayer = gameData.is_multiplayer_game
	if is_instance_valid(_sync) and _sync.is_multiplayer() == want_multiplayer:
		return _sync
	if is_instance_valid(_sync):
		#remove before freeing so that the new node can use the same name
		remove_child(_sync)
		_sync.queue_free()
	_sync = MultiplayerStackSyncScript.new() if want_multiplayer else StackSyncScript.new()
	_sync.setup(self)
	add_child(_sync)
	return _sync

func enable_sync():
	sync_enabled = true

func disable_sync():
	sync_enabled = false


func flush_script(stack_object):

	if stack.empty() or (stack_object != stack.back()):
		var _error =1
		return

	var uid = stack_object.stack_uid
	
	if is_pending_flush(uid):
		var _error = 1
		display_debug("called to flush script but not allowed because I already started running it" + str(uid))
		return	
			
	_pending_flush[uid] = true
	_stash_pending_flush.erase(uid)
	
	if run_mode != RUN_MODE.NO_BRAKES:
		remove_pending_flush(uid)
		var _error = 1
		display_debug("called to flush script but not allowed because run_mode is" + RunModeStr[run_mode])
		return
	
	get_sync().record_flush_started(_pending_flush.size())

	var execute_mode = stack_object.next_execute_mode()

	var func_return = stack_object.execute()	
	if func_return is GDScriptFunctionState && func_return.is_valid():
		var id = cfc.add_debug_yielded(func_return, "step 1")
		func_return = yield(func_return, "completed")
		cfc.remove_debug_yielded(id)
		
		#script was removed under our feet at some point (e.g. game reset during tests)
		if !is_pending_flush(uid):
			var _error = 1
			return

	#attempt to fast track: if this was a cost and the stack hasn't changed + nothing to interrupt we run the second half (effects) of the script
	if execute_mode == CFInt.RunMode.COST_SCRIPTS_ONLY:
		if stack_object == stack.back():
			var _interrupt_state = compute_interrupts(stack_object)		
			var _interrupt_mode = _interrupt_state.get("interrupt_mode",InterruptMode.NONE)
			if !_interrupt_mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]:
				execute_mode = stack_object.next_execute_mode()
				if uid == 9:
					var _tmp = 1				
				func_return = stack_object.execute()	
				if func_return is GDScriptFunctionState && func_return.is_valid():
					var id = cfc.add_debug_yielded(func_return, "step 2")
					func_return = yield(func_return, "completed")
					cfc.remove_debug_yielded(id)
					
					#script was removed under our feet at some point (e.g. game reset during tests)
					if !is_pending_flush(uid):
						var _error = 1
						return

	#if either execute_both or non_costs part of the execution
	if execute_mode != CFInt.RunMode.COST_SCRIPTS_ONLY:					
		var sceng = stack_object.get_sceng()
		if sceng:
			sceng.add_update_trigger_details_recursive({"script_executed_trigger": ""})
		if stack_object.get_first_task_name() != "script_executed" and sceng: # and sceng.trigger_details.get("action_name_id", ""):
			var trigger_details = sceng.trigger_details.duplicate()
			#the trigger details of sceng might contain information about the interrupted
			#event rather than the event that was just executed
			#not sure what's a proper way to address that, for now I'm overwriting the values here
			trigger_details["stack_object"] = stack_object
			trigger_details["event_object"] = stack_object.get_first_task()
			trigger_details["script_executed_trigger"] = trigger_details.get("trigger_type", "")
			#some cards specifically target "abilities" per opposition to "default" (basic power) actions
			var tags = trigger_details.get("tags", [])
			if tags == null:
				tags = []
			var is_ability = true
			if "basic power" in tags:
				is_ability = false
			if is_ability:
				trigger_details["tags"] = WCScriptingEngine.add_tags_to_tags(tags, ["is_ability"])
			if WCUtils.is_string_in_variant(trigger_details, "preparation"):
				var _tmp = 1			
			scripting_bus.emit_signal_on_stack("script_executed", sceng.owner, trigger_details)
			
	#	var user_interaction_status = stack_object.get_user_interaction_status()
		#something todo here ???
		interrupt_mode = InterruptMode.NONE
		
	#	if run_mode != RUN_MODE.NO_BRAKES:		
	#		var _error = 1
	#		display_debug("called to flush script but not allowed because run_mode is" + RunModeStr[run_mode])
	#		return	
		
		history[stack_object.stack_uid]["done"] = true
		stack.erase(stack_object)
	#	if stack.empty():
	#		set_run_mode(RUN_MODE.NOTHING_TO_RUN, "flush_script " + stack_object.get_display_name())
		emit_signal("script_executed_from_stack", stack_object )		
	remove_pending_flush(uid)

	get_sync().on_script_flushed(stack_object)

master func master_receive_stack_event_logs(uid, logs):
	var client_id = cfc.get_rpc_sender_id()	
	cfc.LOG("Received client logs for uid: " +str(uid) +" client: " + str(client_id) , true )
	cfc.LOG(logs, true)

remotesync func get_stack_event_logs(uid):
	var stackEvent = get_stack_object_by_uid(uid)
	var logs = stackEvent.print_log()
	cfc._rpc_id(self, 1, "master_receive_stack_event_logs", uid, logs)

func compute_interrupts(script):
	if !script:
		return {}

	var script_uid = script.stack_uid	
	var current_mode = interrupt_mode
	var current_interrupting_hero = interrupting_hero_id
	var current_run_mode = run_mode
	var potential_interrupters = {}
	interrupting_hero_id = 0

	#this is a very heavy call that happens a lot
	#we need to minimize how many cards we check interrupts for
	#this is done currently by only checking for 
	# 1) Scriptables (temporary effects), 
	# 2) cards on Board & cards in hands (can be Tweaked in CFConst.INTERRUPT_ALLOWED_PILES)
	# 3) additional cards computed at runtime in init_interruptable_cache() 
	# Everything else, in particular piles, is ignored
	# OVerride: if CFConst.INTERRUPT_ALLOWED_PILES is empty, all cards are used
	var cards_to_check = get_tree().get_nodes_in_group("scriptables")

	init_interruptable_cache()
	var interrupt_zones = _interrupt_cache["zones"]	
	if interrupt_zones:
		cards_to_check += cfc.get_all_cards_from_containers(interrupt_zones)
		cards_to_check +=  _interrupt_cache["additional_cards"]
	else:
		cards_to_check +=\
				cfc.get_tree().get_nodes_in_group("cards")	
	
	for mode in [InterruptMode.FORCED_INTERRUPT_CHECK, InterruptMode.OPTIONAL_INTERRUPT_CHECK]:
		var interrupters_found = false
		
		#have to do that because can_interrupt checks for the current state of the game
		interrupt_mode = mode
		run_mode = RUN_MODE.PENDING_USER_INTERACTION
		var tasks = script.get_tasks()
		var script_execute_mode = script.next_execute_mode()
		for task in tasks:
			if (script_execute_mode == CFInt.RunMode.COST_SCRIPTS_ONLY) and !task.is_cost:
				continue
			if (script_execute_mode == CFInt.RunMode.NON_COST_SCRIPTS_ONLY) and task.is_cost:
				continue				
			_current_interrupted_event = task.script_definition.duplicate()
			_current_interrupted_event.erase("network_prepaid")
			_current_interrupted_event["event_name"] = task.script_name
			_current_interrupted_event["event_object"] = task
			_current_interrupted_event["stack_object"] = script
		
			for i in range(gameData.get_team_size()):
				var hero_id = i+1
				
				if mode == InterruptMode.OPTIONAL_INTERRUPT_CHECK and _heroes_passed_optional_interrupt.has(hero_id):
					continue


				var my_interrupters:= {}

				for card in cards_to_check :
					if !is_instance_valid(card):
						continue
					if (card in card_already_played_for_stack_uid.get(script_uid, [])):
						continue
#					if (task.script_name == CFConst.SCRIPT_BREAKPOINT_TRIGGER_NAME):
#						if (card.canonical_name == CFConst.SCRIPT_BREAKPOINT_CARD_NAME):
#							var _tmp = 1
					var can_interrupt = card.can_interrupt(hero_id,task.owner, _current_interrupted_event)
					if can_interrupt == INTERRUPT_FILTER[mode]:
						var guid = guidMaster.get_guid(card)
						my_interrupters[guid] = true
						interrupters_found = true
						
				#sort cards by guid to preserve order in network games
				var keys = my_interrupters.keys()
				keys.sort_custom(WCUtils, "sort_by_guid")
				potential_interrupters[hero_id] = keys								
			
			#we break here if we found interrupters for the current subtask
			#this ensures the _current_interrupted_event variable matches the current interruption
			if interrupters_found:
				break					
		

		if interrupters_found:
			potential_interrupters = _filter_potential_interrupters(potential_interrupters)
			#reset temp variables
			interrupt_mode = current_mode
			run_mode = current_run_mode
			interrupting_hero_id = current_interrupting_hero
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
	interrupting_hero_id = current_interrupting_hero
	return {
		"interrupt_mode": InterruptMode.NOBODY_IS_INTERRUPTING,
		"interruptmode_str": InterruptModeStr[InterruptMode.NOBODY_IS_INTERRUPTING],
		"stack_uid": script_uid
	}

#sometimes multiple heroes can react to the same card. This can lead to bugs
#here we try to determine who really has the priority
func _filter_potential_interrupters(potential_interrupters):
	var card_to_heroes = {}
	var new_interrupters = {}
	var found_duplicate = false
	
	for hero_id in potential_interrupters:
		new_interrupters[hero_id] = []
		var interrupters = potential_interrupters[hero_id]
		for interrupter in interrupters:
			if ! card_to_heroes.has(interrupter):
				card_to_heroes[interrupter] = []
			card_to_heroes[interrupter].append(hero_id)
	for card in card_to_heroes:
		var heroes = card_to_heroes[card]
		if heroes.size() > 1:
			found_duplicate = true
			var found_match = false
			for hero_id in heroes:
				if hero_id in gameData.get_currently_playing_hero_ids():
					new_interrupters[hero_id].append(card)
					found_match = true
					break
			if !found_match:
				new_interrupters[heroes[0]].append(card)
		else:
			new_interrupters[heroes[0]].append(card)
	
	if found_duplicate:
		return new_interrupters
	return potential_interrupters
			


func update_local_client_status():
	_local_status_counter += 1
	var my_network_id = cfc.get_network_unique_id()
	all_clients_status[my_network_id] ={
		"tick": _local_status_counter,
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
	
#	if run_mode == RUN_MODE.PENDING_USER_INTERACTION:
#		var _tmp =1
	gameData.game_state_changed()
	cfc._rpc(self,"client_run_mode_changed", all_clients_status[cfc.get_network_unique_id()])

remote func client_run_mode_changed (new_status):
	var client_id = cfc.get_rpc_sender_id()
	
	#We check that requests are received in order,
	#and reject any request that's older than what we currently have
	#For some reason events are not ordered correctly (I though RPC enforced order)
	#In single player mode, for some reason, this delays gameplay,
	#most likely because a "blocking" status gets set at the wrong time
	#until I figure this out, I'm deactivating this check in single player,
	#and enabling it in multiplayer
	if !get_config("disable_status_tick_security_checks"):
		var new_tick = new_status.get("tick")
		if new_tick:
			var previous_tick = get_client_status(client_id, "tick")
			if previous_tick and previous_tick > new_tick:
				var _error = 1
				return

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
		

func is_idle(level = 2):		
	if my_script_requests_pending_execution:
		return false

	#in basic mode, we stop here
	if level == 0:
		return true

	if pending_stack_yield:
		return false

	if _has_network_event_blocking_idle():
		return false	
		
	if level == 1:
		return true
			
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
	
	#cfc._rpc_id(self,1, "master_stack_object_removed", stack_uid)	
		
func stack_pop_back():
	if !stack.size():
		return null
	return stack.pop_back()

func has_script(script):
	return script in stack

func retrieve_last_event(requester:ScriptTask):
	#the requester usually doesn't want to delete themselves
	var event = null
	var max_id = find_last_event_id_before_me(requester)
	if max_id >=0:
		event = stack[max_id]

	return event

func delete_event(event, requester):
	#the requester usually doesn't want to delete themselves
	var pay_costs_anyway = requester.get_property("pay_costs_anyway", false)
	var found_id = find_event_id_in_stack(event)
	var overall_event = null
	if found_id >=0:
		overall_event = stack[found_id]
		if pay_costs_anyway:
			var sceng = overall_event.get_sceng()
			if sceng and sceng.has_cost_scripts() and sceng.has_non_cost_scripts():
				overall_event.remove_non_cost_tasks()
			else:
				#fallback: asked to prevent an event that is all costs or no costs
				pay_costs_anyway = false
		if !pay_costs_anyway:	
			stack_remove(found_id)
		#this can be sent whether the event was deleted or just modifid (with remove_non_cost) but this might bite me back later	
		scripting_bus.emit_signal("stack_event_deleted", overall_event)
	else:
		display_debug("Error: script " + requester.script_name + " asked me to delete event but I couldn't find it")
	return overall_event
		
func delete_last_event(requester:ScriptTask):
	#the requester usually doesn't want to delete themselves
	var pay_costs_anyway = requester.get_property("pay_costs_anyway", false)
	var event = null
	var max_id = find_last_event_id_before_me(requester)
	if max_id >=0:
		event = stack[max_id]
		if pay_costs_anyway:
			var sceng = event.get_sceng()
			if sceng and sceng.has_cost_scripts() and sceng.has_non_cost_scripts():
				event.remove_non_cost_tasks()
			else:
				#fallback: asked to prevent an event that is all costs or no costs
				pay_costs_anyway = false
		if !pay_costs_anyway:	
			stack_remove(max_id)
		#this can be sent whether the event was deleted or just modifid (with remove_non_cost) but this might bite me back later	
		scripting_bus.emit_signal("stack_event_deleted", event)
	else:
		display_debug("Error: script " + requester.script_name + " asked me to delete event but I couldn't find it")
	return event	

func is_script_in_stack_object(script, stack_item):
	if script == stack_item: 
		return true
	for task in stack_item.get_tasks():
		if task == script:
			return true
	return false

func get_stack_object_by_uid(stack_uid):
	for obj in stack:
		if obj.stack_uid == stack_uid:
			return obj
	
	var fallback_obj = history.get(stack_uid, null)
	if fallback_obj:
		return (fallback_obj.get("stack_object", null))
	
	return null

func find_event_id_in_stack(event):
	#the requester usually doesn't want to delete themselves
	if !event:
		return -1
	for i in stack.size():
		if is_script_in_stack_object(event, stack[i]):
			return i
	return -1

func find_last_event_id_before_me(requester:ScriptTask):
	#the requester usually doesn't want to delete themselves
	for i in stack.size():
		var j = stack.size() -1 -i
		if is_script_in_stack_object(requester, stack[j]):
			j = j-1
			while j >=0 and stack[j].interrupt_marker:
				j = j-1
			return j
	return -1
		
func find_last_event_before_me(requester:ScriptTask):
	var max_id = find_last_event_id_before_me(requester)
	if max_id < 0:
		return null
		
	var event = stack[max_id]
	return event	

func find_event(_event_details, filters, owner_card, _trigger_details):
	for event in stack:
		var task = event.get_script_by_event_details(_event_details)			
		if (!task):
			continue			
		var result = cfc.ov_utils.matches_filters( filters, owner_card, _trigger_details)
		if result:
			return {
				"event": event,
				"meta": result.get("meta", {})
			}
	return null			



#scripted replacement effects
func modify_object(stack_object, script:ScriptTask, task_object = null):
	if !stack_object:
		return false
	return stack_object.modify(script, task_object)
	
	
		

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
	if inbox.has(StackInbox.LOCAL):
		cfc.LOG("error in stack reset: yielded_scripts not empty: " + str(inbox.count(StackInbox.LOCAL)))
	if inbox.slots_reserved or inbox.describe_slots()["fills_before_reservation"]:
		cfc.LOG("{slots} end of game: " + to_json(inbox.describe_slots()), true)
	inbox.clear()
	_ack_received = {}
	
	all_clients_status = {}
	_local_status_counter = 0
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
	_pending_flush = {}
	_stash_pending_flush = {}
	_sent_about_to_execute_signal = {}
	_interrupting_hero_data = {}
	_insert_source = ""
	_draining_yielded_script = false
	get_sync().reset()
	
	_interrupt_cache["zones"] = []
	_interrupt_cache["additional_cards"] = []
	_interrupt_cache["needs_refresh"] = true


func get_current_status():
	return {
		"my_script_requests_pending_execution": my_script_requests_pending_execution,
		"pending_stack_yield" : pending_stack_yield,
		"incoming_network_events": inbox.entries(StackInbox.NETWORK),
		"run_mode":RunModeStr[run_mode],
		"interrupt_mode": InterruptModeStr[interrupt_mode],
		"interrupting_hero_id": interrupting_hero_id,
		"current_stack_uid" : current_stack_uid,
		"stack": stack,
		"_pending_flush": _pending_flush,
		"_stash_pending_flush": _stash_pending_flush	
	}

func flush_logs():
	var display_text =JSON.print(history, '\t') + "\n"
	if pending_stack_yield:
		display_text+= JSON.print(pending_stack_yield, '\t') + "\n"
	if text_edit and is_instance_valid(text_edit):
		display_text += text_edit.text + "\n"
		text_edit.text = ""
	cfc.LOG(display_text)


func display_debug_info():
	if !cfc.get_setting("enable_ingame_debug_textedit") and !gameData.testSuite:
		return
	#the expectation at this point is that
	#the announcer gives enough info to not have to show this debug panel	
	if gameData.is_announce_ongoing():
		if text_edit and is_instance_valid(text_edit):
			text_edit.visible = false
		return

	if (!text_edit):
	 create_text_edit()
	
	if (!text_edit or !is_instance_valid(text_edit)):
		return

	var display_text = ""
	if run_mode != RUN_MODE.NOTHING_TO_RUN:
		 display_text += "run mode: " + RunModeStr[run_mode] + "\n"
	if interrupt_mode != InterruptMode.NONE:
		display_text += "interrupt_mode" + InterruptModeStr[interrupt_mode] + "\n" 
		display_text += "interrupt_hero" + str(interrupting_hero_id) + "\n" 

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
	
