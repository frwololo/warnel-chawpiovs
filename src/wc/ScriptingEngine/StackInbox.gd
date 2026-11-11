# Ordered inbox of the work waiting to enter the stack.
#
# Migration step 2 of the "Deterministic Stack Sync" design: the two queues the
# stack used to keep (yielded_scripts and _incoming_network_events) share this
# one ordered list. Each kind of entry still drains exactly as its old queue did,
# so the order in which things reach the stack is unchanged:
# - LOCAL: scripts deferred by create_and_add_script (the old yielded_scripts),
#   drained one at a time when the stack is idle or reaches an interrupt marker
# - NETWORK: events received from the master (the old _incoming_network_events),
#   applied in arrival order once their wait condition is met
#
# Every entry gets a sequence number in creation order.
#
# Step 3, shadow mode: decision SLOT entries. Every client reserves a slot when
# it reaches a decision, numbered by a counter of its own (slot numbers only
# count decisions, so they match across clients as long as decisions are
# reached in the same order). The master's broadcast of the decision fills
# the slot. In shadow mode slots are only matched and checked: they never
# hold anything back, and LOCAL / NETWORK entries drain exactly as before.
extends Reference

const LOCAL := "local"
const NETWORK := "network"
const SLOT := "slot"

var _entries := []
var _next_seq := 1

var _next_slot := 1
#fills received before this client reserved the slot: {slot: checksum}
var _early_fills := {}
var slots_reserved := 0
var slots_filled := 0

func add(kind: String, data) -> void:
	_entries.append({"kind": kind, "seq": _next_seq, "data": data})
	_next_seq += 1

#a number from the same counter as the entries, for work queued elsewhere
#(priority scripts) that must be ordered against the inbox
func take_seq() -> int:
	_next_seq += 1
	return _next_seq - 1

#the seq of the oldest entry of that kind, or -1
func first_seq(kind: String) -> int:
	var i = _find_first(kind)
	if i == -1:
		return -1
	return _entries[i]["seq"]

func has(kind: String) -> bool:
	return _find_first(kind) != -1

func count(kind: String) -> int:
	var result := 0
	for entry in _entries:
		if entry["kind"] == kind:
			result += 1
	return result

#the oldest entry of that kind, or null
func first(kind: String):
	var i = _find_first(kind)
	if i == -1:
		return null
	return _entries[i]["data"]

#removes and returns the oldest entry of that kind, or null
func pop_first(kind: String):
	var i = _find_first(kind)
	if i == -1:
		return null
	var data = _entries[i]["data"]
	_entries.remove(i)
	return data

#all entries of that kind, oldest first
func entries(kind: String) -> Array:
	var result := []
	for entry in _entries:
		if entry["kind"] == kind:
			result.append(entry["data"])
	return result

#the whole inbox in order, as kind + sequence number (diagnostics)
func describe() -> Array:
	var result := []
	for entry in _entries:
		result.append(entry["kind"] + " #" + str(entry["seq"]))
	return result

func clear() -> void:
	_entries = []
	_next_seq = 1
	_next_slot = 1
	_early_fills = {}
	slots_reserved = 0
	slots_filled = 0


###
### Decision slots (shadow mode)
###

#Reserves the next decision slot. Returns {"slot": n, "problem": ""};
#problem is set when a fill for that slot had already arrived and does not match
func reserve_slot(checksum: String) -> Dictionary:
	var slot = _next_slot
	_next_slot += 1
	slots_reserved += 1
	if _early_fills.has(slot):
		var early_checksum = _early_fills[slot]
		_early_fills.erase(slot)
		slots_filled += 1
		return {"slot": slot, "problem": _compare_slot(slot, checksum, early_checksum)}
	_entries.append({"kind": SLOT, "seq": _next_seq, "data": {"slot": slot, "checksum": checksum}})
	_next_seq += 1
	return {"slot": slot, "problem": ""}

#Fills a slot from a decision broadcast. Returns "" if it matches,
#otherwise a description of the problem
func fill_slot(slot: int, checksum: String) -> String:
	for i in range(_entries.size()):
		var entry = _entries[i]
		if entry["kind"] == SLOT and entry["data"]["slot"] == slot:
			_entries.remove(i)
			slots_filled += 1
			return _compare_slot(slot, entry["data"]["checksum"], checksum)
	if slot < _next_slot:
		return "slot #" + str(slot) + " filled twice (" + checksum + ")"
	#this client has not reached that decision yet
	_early_fills[slot] = checksum
	return ""

#true once this client has reached (reserved) that decision
func is_slot_reached(slot: int) -> bool:
	return slot < _next_slot

func _compare_slot(slot: int, reserved_checksum: String, filled_checksum: String) -> String:
	if reserved_checksum == filled_checksum:
		return ""
	return "slot #" + str(slot) + " reserved for '" + reserved_checksum + "' but filled with '" + filled_checksum + "'"

#unfilled slots and fills still waiting for their slot (diagnostics)
func describe_slots() -> Dictionary:
	var unfilled := []
	for entry in _entries:
		if entry["kind"] == SLOT:
			unfilled.append("#" + str(entry["data"]["slot"]) + " " + entry["data"]["checksum"])
	var early := []
	for slot in _early_fills:
		early.append("#" + str(slot) + " " + _early_fills[slot])
	return {
		"reserved": slots_reserved,
		"filled": slots_filled,
		"unfilled": unfilled,
		"fills_before_reservation": early,
	}

func _find_first(kind: String) -> int:
	for i in range(_entries.size()):
		if _entries[i]["kind"] == kind:
			return i
	return -1
