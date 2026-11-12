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
const StackInbox = preload("res://src/wc/ScriptingEngine/StackInbox.gd")

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
	_log_and_reset_stats()


###
### Ordering statistics (diagnostics only, see the design doc's investigation)
###
#How often flushes overlap, how often scripts are deferred and why, and which
#triggers create scripts while no flush is running (those are ordered by
#timing rather than by game actions). Shown in the F9 dump, and logged once
#per game or test when the stack is reset.
const STATS_MAX_TRIGGERS := 40

var _stats := {}

func _new_stats() -> Dictionary:
	return {
		"flushes": 0,
		"overlapping_flushes": 0,
		"max_concurrent_flushes": 0,
		"created": {"direct": 0, "request": 0, "deferred_flush": 0, "deferred_run_mode": 0, "deferred_inbox": 0},
		"resubmitted": {"direct": 0, "request": 0, "deferred_flush": 0, "deferred_run_mode": 0, "deferred_inbox": 0},
		"deferred_by_trigger": {},
		"created_outside_flush_by_trigger": {},
	}

func _get_stats() -> Dictionary:
	if !_stats:
		_stats = _new_stats()
	return _stats

#concurrent = number of flushes running, this one included
func record_flush_started(concurrent: int) -> void:
	var stats = _get_stats()
	stats["flushes"] += 1
	if concurrent > 1:
		stats["overlapping_flushes"] += 1
	stats["max_concurrent_flushes"] = int(max(stats["max_concurrent_flushes"], concurrent))

#outcome: "direct", "request", "deferred_flush", "deferred_run_mode" or "deferred_inbox"
#resubmitted: the script comes back from yielded_scripts (already counted once)
func record_script_created(trigger, outcome: String, flush_was_pending: bool, resubmitted: bool) -> void:
	var stats = _get_stats()
	if resubmitted:
		stats["resubmitted"][outcome] += 1
		return
	stats["created"][outcome] += 1
	if outcome.begins_with("deferred"):
		_count_trigger(stats["deferred_by_trigger"], trigger)
	if !flush_was_pending:
		_count_trigger(stats["created_outside_flush_by_trigger"], trigger)

func _count_trigger(counts: Dictionary, trigger) -> void:
	var key = str(trigger)
	if !counts.has(key) and counts.size() >= STATS_MAX_TRIGGERS:
		key = "<other>"
	counts[key] = counts.get(key, 0) + 1

func get_stats() -> Dictionary:
	return _get_stats().duplicate(true)

func _log_and_reset_stats() -> void:
	#step 5: verbose only; the counters stay in the F9 dump (ordering_stats)
	if _stats and _stats.get("flushes", 0) and gameData.theStack.VERBOSE_SYNC_LOGS:
		cfc.LOG("{sync_stats} " + to_json(_stats), true)
	_stats = _new_stats()


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
#The deciding client defers the decision itself (dialog or choice, see
#should_defer_decision) under the very same condition, so both sides reach it
#at the same drain point: before, the deciding client showed its dialog in the
#middle of the flush and inserted the outcome there, while the waiting client
#deferred its wait (Tigra heal desync).
#
#NOTE: no run_mode condition here, on purpose: the authorized client switches to
#PENDING_USER_INTERACTION right away whatever its run_mode, so this client must too,
#otherwise its stack keeps running past the decision point
func set_pending_network_interaction(_interaction_authority, checksum, reason:=""):
	if _decision_must_wait_for_flush():
		the_stack.display_debug("set_pending_network_interaction deferred behind ongoing/deferred scripts - " + checksum)
		the_stack.add_yielded_script({
			"type": "pending_network_interaction",
			"checksum": checksum,
			"reason": reason,
			"yield_reason": "set_pending_network_interaction",
		})
		return
	enter_pending_network_interaction(checksum, reason)

#The one condition under which a decision reached now waits for the drain
#point, on the deciding client as well as on the waiting ones
func _decision_must_wait_for_flush() -> bool:
	return the_stack.sync_enabled and !the_stack._draining_yielded_script and !the_stack._pending_flush.empty()

#deciding client side: exec_config carries resumed_decision_slot when the
#decision was already deferred once and is now being resumed
func should_defer_decision(exec_config: Dictionary) -> bool:
	if exec_config.get("resumed_decision_slot", -1) > 0:
		return false
	return _decision_must_wait_for_flush()

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
	for data in the_stack.inbox.entries(StackInbox.LOCAL):
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
	for ev in the_stack.inbox.entries(StackInbox.NETWORK):
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
		"inbox_order": the_stack.inbox.describe(),
		"decision_slots": the_stack.inbox.describe_slots(),
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
		#an entry can be a marker string ("load_minions") instead of a dictionary
		if typeof(attacker) != TYPE_DICTIONARY:
			attackers_dump.append(str(attacker))
			continue
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
		"sequence_ready": gameData._ready_for_next_sequence,
		"sequence_step_waiting": gameData._sequence_step_waiting,
		"sequence_wait_reason": gameData.get_sequence_wait_reason(),
		"next_work": gameData.next_work(),
		"next_ready_work": gameData.next_ready_work(),
		"next_work_stats": gameData.next_work_stats,
		"priority_scripts": gameData._priority_scripts.size(),
		"villain_current_hero_target": gameData._villain_current_hero_target,
	}
	if gameData.phaseContainer and is_instance_valid(gameData.phaseContainer):
		dump["gamedata"]["step"] = gameData.phaseContainer.get_current_phase_name()
		dump["gamedata"]["current_step_complete"] = gameData.phaseContainer.current_step_complete
	dump["ordering_stats"] = get_stats()
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

