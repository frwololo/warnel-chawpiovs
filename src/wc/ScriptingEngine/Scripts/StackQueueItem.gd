class_name StackQueueItem
extends Reference

enum STACK_STATUS {
	NONE,
	PENDING_UID,
	PENDING_CLIENT_ACK,
	READY_TO_EXECUTE,
	DONE,	
	PENDING_REMOVAL,
}

const StackStatusStr := [
	"NONE",
	"PENDING_UID",
	"PENDING_CLIENT_ACK",
	"READY_TO_EXECUTE",
	"DONE",	
	"PENDING_REMOVAL",	
]

var stack_uid:= 0
var status:= {}
var status_str:={}
var time_since_last_change:={}
var script_details
var requester_client_id
var local_uid
var checksum
var human_readable:=""

func _init(_stack_uid, _script_details, _requester_client_id = 0, starting_status=STACK_STATUS.PENDING_CLIENT_ACK, _local_uid=0, _checksum= ""):
	for network_id in gameData.network_players:
		status[network_id] = starting_status
		status_str[network_id] = StackStatusStr[starting_status]
		time_since_last_change[network_id] = 0.0
	
	requester_client_id =  _requester_client_id
	script_details = _script_details
	stack_uid = _stack_uid 
	local_uid =  _local_uid
	checksum = _checksum
	human_readable = str(stack_uid)

func _process(delta:float):
	for network_id in gameData.network_players:	
		time_since_last_change[network_id] += delta
	
func get_status(client_id):
	return status[client_id]
	
func get_stack_uid():
	return stack_uid	
	
func get_local_uid():
	return local_uid	
		
func get_script_details():
	return script_details	
	
func get_time_since_last_change(client_id):
	return time_since_last_change[client_id]

#resets timer, useful when doing resync attempts	
func reset_time_since_last_change(client_id:int = 0):
	#if client_id is not set we reset everyone
	if client_id:	
		time_since_last_change[client_id] = 0.0
	else:
		for network_id in gameData.network_players:
			time_since_last_change[network_id] = 0.0
				
func get_requester_id():
	return requester_client_id
	
func set_human_readable(string):
	human_readable = string

func get_human_readable():
	return human_readable

func change_queue_item_state(client_id, new_state, caller):
	var current_state = status[client_id]
	var expected_state = STACK_STATUS.NONE
	#error check
	var _error = ""
	match new_state:
		STACK_STATUS.DONE:
			expected_state = STACK_STATUS.READY_TO_EXECUTE
			#pending_removal is an ok use case here because we sometimes remove the scrpt before receiving this signal
			if ! current_state in [STACK_STATUS.READY_TO_EXECUTE, STACK_STATUS.PENDING_REMOVAL]:
				_error = "state"
		STACK_STATUS.READY_TO_EXECUTE:
			expected_state = STACK_STATUS.PENDING_CLIENT_ACK
			if !current_state in [STACK_STATUS.PENDING_CLIENT_ACK, STACK_STATUS.PENDING_UID]:
				_error = "state"					
	
	if _error:
		match _error:
			"state":
				display_status_error( client_id,stack_uid, expected_state, current_state , caller)	
	
	if status[client_id] == STACK_STATUS.PENDING_REMOVAL:
		pass
		#it's never ok to go back from a deleted state
	else:	
		status[client_id] = new_state
		status_str[client_id] = StackStatusStr[new_state]
		display_debug(str(client_id) + " Went from " + StackStatusStr[current_state] + " to " + StackStatusStr[new_state] + " for script " +  human_readable)
	
	#reset wait counter
	time_since_last_change[client_id] = 0.0
	
	return status[client_id]
	
func some_players_are_state(state):
	var count = count_item_state(state)
	if count > 0:
		return true
	return false	

func all_players_are_state(state):
	var count = count_item_state(state)
	if count == gameData.network_players.size():
		return true
	return false
	
func all_players_same_state():
	var _status = -1
	for network_id in gameData.network_players:
		if _status ==-1:
			_status = status[network_id]
		if status[network_id] != _status:
			return false
	return true


func count_item_state(state):		
	var count = 0	
	for network_id in gameData.network_players:
		if status[network_id] == state:
			count+=1
	return count

func display_status_error(client_id, stack_uid, expected, actual, calling_function = ""):
	display_debug("{error}()" + calling_function +")" + str(client_id) + " (uid: " + str(stack_uid) +") was expecting " +  StackStatusStr[expected] + ", but got " + StackStatusStr[actual])

func display_debug(msg):
	gameData.display_debug("{stack_qi} " + msg, "")


func debug_queue_status_msg():
	var dict = {
		"stack_uid": stack_uid,
		"status_str":status_str,
		"requester_client_id": requester_client_id,
		"local_uid" : local_uid,	
		"checksum" : checksum,
		"human_readable" : human_readable	
	}
	return to_json(dict)
