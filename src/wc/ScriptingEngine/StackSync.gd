# Synchronization layer of the GlobalScriptStack.
#
# GlobalScriptStack holds the game rules: what goes on the stack, in which
# order, and how it resolves. Code that only exists because several clients
# must agree on that (network checks, desync diagnostics, resync...) lives
# behind this object instead, and the stack only calls the hooks below.
#
# This base class is the single player version: hooks do nothing, or work
# locally. MultiplayerStackSync.gd extends it with the network logic.
#
# GlobalScriptStack.get_sync() creates the version matching the game mode.
# It is a child node of the stack, always named "Sync", so that RPC paths are
# identical on every client.
extends Node

const NODE_NAME := "Sync"

var the_stack

func setup(stack_node) -> void:
	the_stack = stack_node
	name = NODE_NAME

func is_multiplayer() -> bool:
	return false


###
### Hooks called by GlobalScriptStack
###

#a stack object was just inserted at position pos (-1 = top)
func on_stack_insert(_stack_event, _pos) -> void:
	pass

#a stack object finished executing
func on_script_flushed(_stack_object) -> void:
	pass

#called first thing in the stack's _process.
#Return true to skip the rest of the stack's frame
func on_process(_delta: float) -> bool:
	return false

#called from the stack's _process when the stack is idle (NOTHING_TO_RUN,
#no deferred script). Return true to skip the rest of the stack's frame
func on_process_idle() -> bool:
	return false

#called by GlobalScriptStack.reset() (new game, between tests)
func reset() -> void:
	pass


###
### Remote decisions
###
#Kept in the base class because single player can reach them too (e.g. through
#authority errors in UserInteractionAuthority), with the same behavior.

#Called on clients that are NOT authorized to make a choice: they stop and wait
#for the authorized client's decision to arrive through the network.
#
#On the authorized client, the matching script goes through create_and_add_script,
#which defers it into yielded_scripts (FIFO) when a flush is ongoing.
#To stop at the same point on every client, this client defers its wait through
#the very same queue, under the very same condition: otherwise it enters
#PENDING_USER_INTERACTION while the authorized client keeps running its stack
#until that queue drains, and the remote decision gets inserted at a different
#point (Nick Fury / Web-Shooter, Spider-Man / Interrogation Room desyncs)
#
#This only mirrors the authorized client; it must never change the order in which
#the authorized client (or a single player game) resolves scripts.
#
#NOTE: no run_mode condition here, on purpose: the authorized client switches to
#PENDING_USER_INTERACTION right away whatever its run_mode, so this client must too,
#otherwise its stack keeps running past the decision point
func set_pending_network_interaction(_interaction_authority, checksum, reason:=""):
	if the_stack.sync_enabled and !the_stack._draining_yielded_script and the_stack._pending_flush:
		the_stack.display_debug("set_pending_network_interaction deferred behind ongoing/deferred scripts - " + checksum)
		the_stack.add_yielded_script({
			"type": "pending_network_interaction",
			"checksum": checksum,
			"reason": reason,
			"yield_reason": "set_pending_network_interaction",
		})
		return
	enter_pending_network_interaction(checksum, reason)

func enter_pending_network_interaction(checksum, reason:=""):
	if reason:
		the_stack.display_debug(reason)
	if the_stack.pending_interaction_checksums:
		the_stack.display_debug("error, assked to set to pending_interaction but pending queue not empty " + to_json(the_stack.pending_interaction_checksums))
	the_stack.pending_interaction_checksums[checksum] = true	
	the_stack.set_run_mode(the_stack.RUN_MODE.PENDING_USER_INTERACTION, "set_pending_network_interaction - " + checksum)

#A player who opens a choice on a manual play (e.g. "manual - Spider-Man") and cancels it
#sends resume_operations to everyone, but the other clients never stopped for it:
#manual plays only run on the clicking client until they're sent to the stack.
#Those clients used to wait 5s for PENDING_USER_INTERACTION, then set NO_BRAKES anyway.
func is_resume_for_unknown_manual_interaction(ev) -> bool:
	return ev.type == "resume_operations" \
			and ev.expected_run_mode == the_stack.RUN_MODE.PENDING_USER_INTERACTION \
			and str(ev.get("checksum", "")).begins_with("manual") \
			and the_stack.run_mode != the_stack.RUN_MODE.PENDING_USER_INTERACTION \
			and !the_stack.pending_interaction_checksums.has(ev.checksum)

#returns "" if an incoming network event can be applied now, otherwise what
#we're waiting for. In single player every event comes from this client.
func get_network_event_wait_reason(_ev) -> String:
	return ""


###
### State dump (deadlock diagnostics)
###
#Press F9: writes a snapshot of the stack state to the log.
#In multiplayer, every client does it and the master logs all of them together.
#Works without a debugger attached.
const STATE_DUMP_KEY := KEY_F9

func _input(event):
	if event is InputEventKey and event.pressed and !event.echo and event.scancode == STATE_DUMP_KEY:
		request_state_dump("F9 pressed on client " + str(cfc.get_network_unique_id()))

func request_state_dump(reason := "") -> void:
	cfc.LOG("{state_dump} requested: " + reason, true)
	var dump = get_state_dump()
	dump["reason"] = reason
	cfc.LOG("{state_dump} local state of client " + str(cfc.get_network_unique_id()) + ":", true)
	cfc.LOG_DICT(dump, true)

#additional entries for the state dump, see MultiplayerStackSync
func get_extra_state_dump() -> Dictionary:
	return {}

func get_state_dump() -> Dictionary:
	var stack_dump = []
	for event in the_stack.stack:
		stack_dump.append(_dump_stack_object(event))

	var yielded_dump = []
	for data in the_stack.yielded_scripts:
		var entry = {
			"type": data.get("type", "script"),
			"yield_reason": data.get("yield_reason", ""),
			"checksum": data.get("checksum", ""),
		}
		if data.has("sceng"):
			entry["action_name"] = str(data.get("action_name", ""))
			entry["trigger"] = str(data.get("trigger", ""))
			var sceng = data["sceng"]
			if is_instance_valid(sceng) and "owner" in sceng and is_instance_valid(sceng.owner):
				entry["owner"] = str(sceng.owner.get("canonical_name"))
				entry["user_interaction_status"] = sceng.get("user_interaction_status")
		else:
			entry["reason"] = data.get("reason", "")
		yielded_dump.append(entry)

	var incoming_dump = []
	for ev in the_stack._incoming_network_events:
		incoming_dump.append({
			"type": ev.get("type", ""),
			"requester": ev.get("requester", 0),
			"expected_run_mode": _run_mode_str(ev.get("expected_run_mode", -1)),
			"waited": ev.get("waited", 0.0),
			"checksum": ev.get("checksum", ""),
		})

	var clients_status = {}
	for client_id in the_stack.all_clients_status:
		var status = the_stack.all_clients_status[client_id].duplicate()
		if status.has("run_mode"):
			status["run_mode"] = _run_mode_str(status["run_mode"])
		clients_status[str(client_id)] = status

	var ongoing_processes = []
	for object in cfc._ongoing_processes:
		var descriptions = cfc._ongoing_processes[object]
		for description in descriptions:
			if descriptions[description]:
				var object_name = "<dictionary>"
				if typeof(object) == TYPE_OBJECT:
					if !is_instance_valid(object):
						object_name = "<freed>"
					elif object.get("canonical_name"):
						object_name = str(object.get("canonical_name"))
					else:
						object_name = str(object)
				ongoing_processes.append(object_name + ": " + str(description) + " x" + str(descriptions[description]))

	var dump = {
		"network_id": cfc.get_network_unique_id(),
		"frame": Engine.get_frames_drawn(),
		"my_heroes": gameData.get_my_heroes(),
		"run_mode": the_stack.RunModeStr[the_stack.run_mode],
		"interrupt_mode": the_stack.InterruptModeStr[the_stack.interrupt_mode],
		"interrupting_hero_id": the_stack.interrupting_hero_id,
		"sync_enabled": the_stack.sync_enabled,
		"stack": stack_dump,
		"yielded_scripts": yielded_dump,
		"incoming_network_events": incoming_dump,
		"pending_interaction_checksums": the_stack.pending_interaction_checksums.keys(),
		"pending_flush": the_stack._pending_flush.keys(),
		"stash_pending_flush": the_stack._stash_pending_flush.keys(),
		"pending_stack_yield": the_stack.pending_stack_yield.duplicate(),
		"my_script_requests_pending_execution": the_stack.my_script_requests_pending_execution,
		"all_clients_status": clients_status,
		"ongoing_processes": ongoing_processes,
		"game_paused": cfc.game_paused,
		"modal_menu": str(cfc.get_modal_menu()) if cfc.get_modal_menu() else "",
		"blocking_announce": gameData.is_ongoing_blocking_announce(),
	}

	#GameData / PhaseContainer queues that gate progress outside the stack
	var attackers_dump = []
	for attacker in gameData.attackers:
		var subject = attacker.get("subject")
		attackers_dump.append({
			"subject": str(subject.get("canonical_name")) if is_instance_valid(subject) else "<freed>",
			"type": attacker.get("type", ""),
			"target_id": attacker.get("target_id", 0),
		})
	dump["gamedata"] = {
		"attackers": attackers_dump,
		"immediate_encounters": gameData.immediate_encounters.size(),
		"scripted_play_sequence": gameData.scripted_play_sequence.size(),
		"scripted_play_sequence_low_priority": gameData.scripted_play_sequence_low_priority.size(),
		"priority_scripts": gameData._priority_scripts.size(),
		"villain_current_hero_target": gameData._villain_current_hero_target,
	}
	if gameData.phaseContainer and is_instance_valid(gameData.phaseContainer):
		dump["gamedata"]["step"] = gameData.phaseContainer.get_current_phase_name()
		dump["gamedata"]["current_step_complete"] = gameData.phaseContainer.current_step_complete
	#network-specific state
	var extra = get_extra_state_dump()
	for key in extra:
		dump[key] = extra[key]
	return dump

func _dump_stack_object(event) -> Dictionary:
	var owner = event.get_owner()
	return {
		"uid": event.stack_uid,
		"name": str(event.get_display_name()),
		"task": "<interrupt_marker>" if event.interrupt_marker else ("<context>" if event.context_marker else str(event.get_first_task_name())),
		"owner": str(owner.get("canonical_name")) if is_instance_valid(owner) else "",
		"trigger": str(event.get_trigger()),
	}

func _run_mode_str(value) -> String:
	if typeof(value) == TYPE_INT and value >= 0 and value < the_stack.RunModeStr.size():
		return the_stack.RunModeStr[value]
	return str(value)

