# Multiplayer version of the stack synchronization layer, see StackSync.gd.
#
# Desync diagnostics and recovery:
# - fingerprint check: after each stack object, every client sends the master a
#   fingerprint of its state; the master compares them and schedules a resync
#   check on mismatch
# - insert journal: each client records its stack insertions; on a mismatch the
#   master collects all journals and logs where the clients diverged
# - resync: when the stack is idle everywhere, the master compares full board
#   states (logs only for now)
# - state dump (F9): every client logs its state and sends it to the master
extends "res://src/wc/ScriptingEngine/StackSync.gd"

#Insert journal: a debug record of every stack insertion on this client.
#When the master detects a fingerprint mismatch, it collects all journals
#and logs the first insertion where clients diverged, with the source
#of that insertion (local, network, yielded, signal, sequence...)
const INSERT_JOURNAL_MAX_SIZE := 300
const STATE_DUMP_JOURNAL_TAIL := 15

var _insert_journal := []
var _journals_received := {}
var _journal_diff_requested := false
var _last_reported_divergence_uid := -1

#0: no resync, 1: scheduled, 2: board status sent to the master
var _resync_scheduled = 0
var _force_resync_timer = 0.0

#fingerprints and board statuses received by the master, by checksum then client id
var _acks := {}

#Token state (damage, threat, counters... on every card) after each of the last
#TOKEN_SNAPSHOTS_MAX stack objects, by stack uid. Only its hash goes into the
#fingerprint; the full state is sent to the master when it asks for journals, so
#the desync report can say which cards differ.
const TOKEN_SNAPSHOTS_MAX := 30
var _token_snapshots := {}
var _token_snapshot_uids := []
var _token_snapshots_received := {}

func is_multiplayer() -> bool:
	return true


###
### Hooks
###

func on_stack_insert(stack_event, pos) -> void:
	_journal_insert(stack_event, pos)

func on_process(delta: float) -> bool:
	#resync is supposed to happened but might get stuck here
	if _resync_scheduled:
		_force_resync_timer += delta
		if _force_resync_timer > 5:
			attempt_resync()
			return true
	return false

func on_process_idle() -> bool:
	#nothing on the stack and we're aware of a desync, attempt to fix
	if _resync_scheduled:
		if _resync_scheduled == 1:
			attempt_resync()
		return true
	return false

func reset() -> void:
	.reset()
	if _resync_scheduled:
		cfc.LOG("error in stack reset: resync was scheduled: " + str(_resync_scheduled))
	_resync_scheduled = 0
	_force_resync_timer = 0.0
	_acks = {}
	_token_snapshots = {}
	_token_snapshot_uids = []
	_token_snapshots_received = {}
	_insert_journal = []
	_journals_received = {}
	_journal_diff_requested = false
	_last_reported_divergence_uid = -1


###
### Incoming network events
###

#returns "" if the event can be applied now, otherwise what we're waiting for
func get_network_event_wait_reason(ev) -> String:
	if ev.requester == cfc.get_network_unique_id() or !the_stack.sync_enabled:
		return ""
	if is_resume_for_unknown_manual_interaction(ev):
		return ""
	if the_stack.run_mode != ev.expected_run_mode:
		return "run_mode " + the_stack.RunModeStr[ev.expected_run_mode]
	if ev.type == "add_stack_object" and _requires_matching_interaction_point(ev):
		if !the_stack.pending_interaction_checksums.has(ev.checksum):
			return "interaction point " + str(ev.checksum)
	return ""

#A script decided by another client (defender choice, multiple choice,
#optional confirmation, targeting...) can only be applied once this client has
#itself reached that same decision point, which it signals by registering the
#same checksum in set_pending_network_interaction.
#Matching run_mode alone is not enough: PENDING_USER_INTERACTION is also the
#run_mode of an interrupt check. Without this, Whirlwind's attack decision from
#the defending client got inserted on the master while the master was still
#resolving Whirlwind's forced interrupt, and the master later waited forever
#for a decision it had already consumed.
#
#Excluded, because the other clients never register a checksum for them:
# - player-initiated plays ("manual", "manual_override")
# - interrupts and responses played during an interrupt window: the other clients
#   are already stopped by the interrupt check itself (e.g. "interrupt - Stampede")
func _requires_matching_interaction_point(ev) -> bool:
	var trigger = str(ev.details.get("trigger", ""))
	for prefix in ["manual", "interrupt", "response"]:
		if trigger.begins_with(prefix):
			return false
	var remote_trigger_details = ev.details.get("remote_trigger_details", {})
	if typeof(remote_trigger_details) == TYPE_DICTIONARY \
			and remote_trigger_details.get("is_interrupt_or_response", false):
		return false
	return true


###
### Fingerprint check
###

#Sanity check: every client sends the master a fingerprint of the state after
#each stack object it executes, the master compares them.
#tokens_hash catches state that diverges while the event order stays identical
#(e.g. a card dying on one client only because its damage already differed)
func on_script_flushed(stack_object) -> void:
	var uid = stack_object.stack_uid
	var owner_guid = 0
	var owner_name = ""
	var owner = stack_object.get_owner()
	if owner:
		owner_guid = guidMaster.get_guid(owner)
		owner_name = owner.canonical_name
	var fingerprint = {
		"uid": uid, 
		"task_name": stack_object.get_first_task_name(),
		"rng": cfc.game_rng.state,
		"owner_guid": owner_guid,
		"owner_name": owner_name,
		"all_guids_hash": guidMaster.get_guids_check_data(true)
	}
	var tokens_state = _get_tokens_state()
	_store_token_snapshot(uid, tokens_state)
	fingerprint["tokens_hash"] = WCUtils.ordered_hash(tokens_state)
	cfc._rpc_id(self, 1, "master_check_fingerprint", fingerprint)

#{guid: {token_name: count}} for every card that currently has tokens
func _get_tokens_state() -> Dictionary:
	var state := {}
	for guid in guidMaster.guid_to_object:
		var object = guidMaster.guid_to_object[guid]
		if typeof(object) != TYPE_OBJECT or !is_instance_valid(object) or !("tokens" in object):
			continue
		var drawer = object.tokens
		if !is_instance_valid(drawer) or !drawer.has_method("get_all_tokens"):
			continue
		var card_tokens := {}
		var all_tokens = drawer.get_all_tokens()
		for token_name in all_tokens:
			var count = all_tokens[token_name].get_count()
			if count:
				card_tokens[token_name] = count
		if card_tokens:
			state[guid] = card_tokens
	return state

func _store_token_snapshot(uid, tokens_state:Dictionary) -> void:
	_token_snapshots[uid] = tokens_state
	_token_snapshot_uids.append(uid)
	while _token_snapshot_uids.size() > TOKEN_SNAPSHOTS_MAX:
		_token_snapshots.erase(_token_snapshot_uids.pop_front())

master func master_check_fingerprint(fingerprint):
	var uid = fingerprint.uid
	var checksum = "fingerprint_" + str(uid)
	var acks = _acks.get(checksum, {})
	var client_id = cfc.get_rpc_sender_id()
	acks[client_id] = fingerprint
	_acks[checksum] = acks
	if acks.size() == gameData.network_players.size():
		var my_network_id = cfc.get_network_unique_id()
		var my_status = acks[my_network_id]
		var mismatch = false
		for k in acks:
			var other_status = acks[k]
			if !(WCUtils.json_equal(my_status, other_status)):
				mismatch = true
				cfc.LOG("{error} Desync at fingerprint Step", true)
				cfc.LOG("My Status:", true)
				cfc.LOG_DICT(my_status, true)
				cfc.LOG("Their Status:{" +str(k) +"}", true)
				cfc.LOG_DICT(other_status, true)
				cfc._rpc(self,"clients_schedule_resync")
		_acks.erase(checksum)
		if mismatch:
			master_request_insert_journals(uid)


###
### Resync
###

remotesync func clients_schedule_resync():
	_resync_scheduled = 1

#a desync happened, we're going to try and fix it when the stack is idle everywhere
func attempt_resync():
	var board_status = gameData.save_gamedata()	
	_resync_scheduled =  2
	cfc._rpc_id(self, 1, "master_resync", board_status)

remotesync func clients_resync_attempted():
	_resync_scheduled = 0
	_force_resync_timer = 0.0
	_journal_diff_requested = false

master func master_resync(board_status):
	var checksum = "resync"
	var acks = _acks.get(checksum, {})
	var client_id = cfc.get_rpc_sender_id()
	acks[client_id] = board_status
	_acks[checksum] = acks
	var error_msg = ""
	if acks.size() == gameData.network_players.size():
		var my_network_id = cfc.get_network_unique_id()
		var my_status = acks[my_network_id]
		var needs_reload = false
		for k in acks:
			var other_status = acks[k]
			if !(WCUtils.json_equal(my_status, other_status)):
				error_msg = JSON.print({"my_status": my_status, "their_status" : other_status})
				needs_reload = true					
		_acks.erase(checksum)

		if needs_reload:
			cfc.LOG("{error} desync confirmed, should attempt to resync, but not doing it because of bugs", true)
#			if gameData.testSuite:
#				gameData.testSuite.force_fail_current_test("clients out of sync" + error_msg )
#			else:			
#				gameData.load_gamedata(my_status)	
		else:
			cfc.LOG("{warning} There was a desync but everything seems in order right now, won't do anything", true)
			
		cfc._rpc(self,"clients_resync_attempted")


###
### Insert journal
###


#records one stack insertion. Only "key" and "pos" are compared between clients,
#the rest is context to help understand why the insertion happened when it did
func _journal_insert(stackEvent, pos):
	var owner = stackEvent.get_owner()
	var owner_guid = ""
	var owner_name = ""
	if is_instance_valid(owner):
		owner_guid = guidMaster.get_guid(owner)
		var canonical_name = owner.get("canonical_name")
		if canonical_name:
			owner_name = str(canonical_name)

	var task_name = ""
	if stackEvent.interrupt_marker:
		task_name = "<interrupt_marker>"
	elif stackEvent.context_marker:
		task_name = "<context:" + str(_journal_context_name(stackEvent)) + ">"
	else:
		task_name = str(stackEvent.get_first_task_name())

	var step_name = ""
	if gameData.phaseContainer and is_instance_valid(gameData.phaseContainer):
		step_name = gameData.phaseContainer.get_current_phase_name()

	var entry = {
		#compared between clients
		"uid": stackEvent.stack_uid,
		"key": task_name + "@" + owner_guid,
		"pos": pos,
		#context, for humans
		"owner_name": owner_name,
		"trigger": str(stackEvent.get_trigger()),
		"source": _journal_source(stackEvent),
		"stack_size": the_stack.stack.size(),
		"run_mode": the_stack.RunModeStr[the_stack.run_mode],
		"interrupt_mode": the_stack.InterruptModeStr[the_stack.interrupt_mode],
		"step": step_name,
		"frame": Engine.get_frames_drawn(),
	}
	_insert_journal.append(entry)
	if _insert_journal.size() > INSERT_JOURNAL_MAX_SIZE:
		_insert_journal.pop_front()

func _journal_context_name(stackEvent):
	if "task" in stackEvent and stackEvent.task and stackEvent.task.has_method("get_property"):
		return stackEvent.task.get_property("context_name")
	return ""

#where an insertion comes from: "local" (triggered by this client's own simulation),
#"network" (script received from the master), "yielded" (deferred by create_and_add_script),
#with "/signal" or "/sequence" suffixes when relevant
func _journal_source(stackEvent) -> String:
	if stackEvent.interrupt_marker or stackEvent.context_marker:
		return "marker"
	var source = the_stack._insert_source if the_stack._insert_source else "local"
	if stackEvent is SignalStackScript:
		return source + "/signal"
	var sceng = stackEvent.get_sceng()
	if sceng:
		var details = sceng.trigger_details
		if typeof(details) == TYPE_DICTIONARY:
			var additional = details.get("additional_script_definition", {})
			if typeof(additional) == TYPE_DICTIONARY and additional.get("is_sequence", false):
				return source + "/sequence"
	return source

#master only: ask all clients for their journal, once per desync
func master_request_insert_journals(fingerprint_uid):
	if _journal_diff_requested:
		return
	_journal_diff_requested = true
	_journals_received = {}
	cfc._rpc(self, "clients_send_insert_journal", fingerprint_uid)

remotesync func clients_send_insert_journal(fingerprint_uid):
	#always a dictionary (never null) so that cfc._rpc_id doesn't drop the argument
	var tokens = {
		"available": _token_snapshots.has(fingerprint_uid),
		"state": _token_snapshots.get(fingerprint_uid, {}),
	}
	cfc._rpc_id(self, 1, "master_receive_insert_journal", fingerprint_uid, _insert_journal, tokens)

master func master_receive_insert_journal(fingerprint_uid, journal, tokens := {}):
	var client_id = cfc.get_rpc_sender_id()
	_journals_received[client_id] = journal
	_token_snapshots_received[client_id] = tokens
	if _journals_received.size() < gameData.network_players.size():
		return
	var journals = _journals_received
	var token_snapshots = _token_snapshots_received
	_journals_received = {}
	_token_snapshots_received = {}
	var report = _diff_insert_journals(fingerprint_uid, journals)
	cfc.LOG(report, true)
	cfc.LOG(_diff_token_snapshots(fingerprint_uid, token_snapshots), true)

#lists the cards whose tokens differ between clients after stack object uid
func _diff_token_snapshots(uid, snapshots:Dictionary) -> String:
	var reference_id = cfc.get_network_unique_id()
	if !snapshots.has(reference_id):
		reference_id = snapshots.keys()[0]
	var ref = snapshots[reference_id]
	if !ref.get("available", false):
		return "{desync} tokens at uid " + str(uid) + ": snapshot no longer available on client " + str(reference_id)
	var lines = []
	for client_id in snapshots:
		if client_id == reference_id:
			continue
		var other = snapshots[client_id]
		if !other.get("available", false):
			lines.append("   snapshot no longer available on client " + str(client_id))
			continue
		var ref_state = ref.get("state", {})
		var other_state = other.get("state", {})
		var guids = {}
		for guid in ref_state:
			guids[guid] = true
		for guid in other_state:
			guids[guid] = true
		var sorted_guids = guids.keys()
		sorted_guids.sort()
		for guid in sorted_guids:
			var a = ref_state.get(guid, {})
			var b = other_state.get(guid, {})
			if !WCUtils.json_equal(a, b):
				lines.append("   " + str(guid) + " (" + str(guidMaster.guid_to_name.get(guid, "?")) + "): client " \
					+ str(reference_id) + " " + to_json(a) + " vs client " + str(client_id) + " " + to_json(b))
	if !lines:
		return "{desync} tokens at uid " + str(uid) + ": identical on all clients"
	return "{desync} TOKEN DIFFERENCES after uid " + str(uid) + ":\n" + PoolStringArray(lines).join("\n")

#finds the first uid where clients inserted a different event (or the same event
#at a different stack position) and returns a printable report around that point
func _diff_insert_journals(fingerprint_uid, journals:Dictionary) -> String:
	var reference_id = cfc.get_network_unique_id()
	if !journals.has(reference_id):
		reference_id = journals.keys()[0]

	var by_uid := {}
	var max_uid := {}
	var lo = -1
	var hi = -1
	for client_id in journals:
		var journal = journals[client_id]
		var map = {}
		for entry in journal:
			map[int(entry["uid"])] = entry
		by_uid[client_id] = map
		var client_min = int(journal.front()["uid"]) if journal else 0
		var client_max = int(journal.back()["uid"]) if journal else 0
		max_uid[client_id] = client_max
		lo = client_min if lo == -1 else int(max(lo, client_min))
		hi = client_max if hi == -1 else int(min(hi, client_max))

	var lines = []
	lines.append("{desync} insert journal diff (fingerprint uid " + str(fingerprint_uid) \
		+ "), comparing uids " + str(lo) + ".." + str(hi) + " against client " + str(reference_id))

	#find the first divergent uid that starts a new divergence run after the ones
	#already reported (a swap of 2 events makes 2 consecutive uids diverge)
	var divergence_uid = -1
	var reason = ""
	var previous_uid_diverged = false
	for uid in range(lo, hi + 1):
		var uid_reason = _journal_uid_divergence(by_uid, reference_id, uid)
		if uid_reason and !previous_uid_diverged and uid > _last_reported_divergence_uid:
			divergence_uid = uid
			reason = uid_reason
			break
		previous_uid_diverged = (uid_reason != "")

	if divergence_uid == -1 and _last_reported_divergence_uid >= lo:
		return "{desync} insert journal: no new divergence since uid " + str(_last_reported_divergence_uid) + " (already reported)"

	if divergence_uid == -1:
		lines.append("No insertion divergence in the common window. Last insert uid per client: " + to_json(max_uid))
		lines.append("If last uids match, the mismatch likely comes from state changed outside the stack (RNG, guids, direct calls)")
		lines.append("If they differ, one client inserted extra events after uid " + str(hi))
		if lo > 1:
			lines.append("(the divergence could also be older than the journal window of " + str(INSERT_JOURNAL_MAX_SIZE) + " entries)")
		return PoolStringArray(lines).join("\n")

	_last_reported_divergence_uid = divergence_uid

	lines.append("DIVERGENCE at uid " + str(divergence_uid) + ": " + reason)
	for client_id in by_uid:
		var label = " (master)" if client_id == cfc.get_network_unique_id() else ""
		lines.append("-- client " + str(client_id) + label)
		var start = int(max(lo, divergence_uid - 3))
		var end = int(min(divergence_uid + 5, max_uid[client_id]))
		for uid in range(start, end + 1):
			var e = by_uid[client_id].get(uid, null)
			if e:
				var marker = ">> " if uid == divergence_uid else "   "
				lines.append(marker + _format_journal_entry(e))
	return PoolStringArray(lines).join("\n")

#returns "" if all clients agree on this uid, otherwise a short reason
func _journal_uid_divergence(by_uid:Dictionary, reference_id, uid) -> String:
	var ref = by_uid[reference_id].get(uid, null)
	for client_id in by_uid:
		if client_id == reference_id:
			continue
		var other = by_uid[client_id].get(uid, null)
		if !ref or !other:
			return "missing entry"
		if ref["key"] != other["key"]:
			#most common case: two events inserted in opposite order
			var ref_next = by_uid[reference_id].get(uid + 1, null)
			var other_next = by_uid[client_id].get(uid + 1, null)
			if ref_next and other_next and ref_next["key"] == other["key"] and other_next["key"] == ref["key"]:
				return "two events swapped (" + str(ref["source"]) + " vs " + str(other["source"]) + ")"
			return "different event"
		if ref["pos"] != other["pos"]:
			return "same event, different stack position"
	return ""

func _format_journal_entry(e) -> String:
	return "uid " + str(e["uid"]) + " pos " + str(e["pos"]) + "/" + str(e["stack_size"]) \
		+ " | " + str(e["key"]) + " (" + str(e["owner_name"]) + ")" \
		+ " | src=" + str(e["source"]) + " trigger=" + str(e["trigger"]) \
		+ " | run=" + str(e["run_mode"]) + " int=" + str(e["interrupt_mode"]) + " step=" + str(e["step"]) \
		+ " | frame " + str(e["frame"])


###
### State dump (F9): broadcast to every client, collected by the master
###

func request_state_dump(reason := "") -> void:
	cfc.LOG("{state_dump} requested: " + reason, true)
	cfc._rpc(self, "clients_dump_state", reason)

remotesync func clients_dump_state(reason := ""):
	var dump = get_state_dump()
	dump["reason"] = reason
	cfc.LOG("{state_dump} local state of client " + str(cfc.get_network_unique_id()) + ":", true)
	cfc.LOG_DICT(dump, true)
	cfc._rpc_id(self, 1, "master_receive_state_dump", dump)

master func master_receive_state_dump(dump):
	var client_id = cfc.get_rpc_sender_id()
	if client_id == cfc.get_network_unique_id():
		return #already logged locally
	cfc.LOG("{state_dump} received from client " + str(client_id) + ":", true)
	cfc.LOG_DICT(dump, true)

func get_extra_state_dump() -> Dictionary:
	var journal_tail = []
	for i in range(max(0, _insert_journal.size() - STATE_DUMP_JOURNAL_TAIL), _insert_journal.size()):
		journal_tail.append(_format_journal_entry(_insert_journal[i]))
	return {
		"resync_scheduled": _resync_scheduled,
		"journal_tail": journal_tail,
	}
