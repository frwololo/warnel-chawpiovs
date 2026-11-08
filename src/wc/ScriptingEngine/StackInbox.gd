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
# Every entry gets a sequence number in creation order. Nothing uses it yet:
# it is what the decision slots of step 3 will be matched on.
extends Reference

const LOCAL := "local"
const NETWORK := "network"

var _entries := []
var _next_seq := 1

func add(kind: String, data) -> void:
	_entries.append({"kind": kind, "seq": _next_seq, "data": data})
	_next_seq += 1

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

func _find_first(kind: String) -> int:
	for i in range(_entries.size()):
		if _entries[i]["kind"] == kind:
			return i
	return -1
