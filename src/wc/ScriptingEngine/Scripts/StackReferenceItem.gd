class_name StackReferenceItem
extends Reference


var stack_uid:= 0
var status
var status_str:=""
var local_uid
var checksum
var human_readable:=""
var desc:=""

func _init(object, _stack_uid, starting_status = StackQueueItem.STACK_STATUS.PENDING_CLIENT_ACK, _local_uid=0, _checksum= ""):
	status = starting_status
	status_str = StackQueueItem.StackStatusStr[starting_status]
	
	stack_uid = _stack_uid 
	local_uid =  _local_uid
	checksum = _checksum
	human_readable = str(stack_uid)
	desc = object.get_display_name()

func get_status():
	return status
	
func get_stack_uid():
	return stack_uid	
	
func get_local_uid():
	return local_uid			

func set_human_readable(string):
	human_readable = string
	
func set_desc(string):
	desc = string	

func change_reference_item_state(new_state, caller):		
	var current_state = status
	var expected_states = [StackQueueItem.STACK_STATUS.NONE]
	var _error = ""
	#error check
	match new_state:
		StackQueueItem.STACK_STATUS.DONE:
			expected_states = [StackQueueItem.STACK_STATUS.READY_TO_EXECUTE, StackQueueItem.STACK_STATUS.PENDING_REMOVAL]
			#pending_removal is an ok use case here because we sometimes remove the scrpt before receiving this signal
			if ! current_state in expected_states:
				_error = "state"
		StackQueueItem.STACK_STATUS.READY_TO_EXECUTE:
			expected_states = [StackQueueItem.STACK_STATUS.PENDING_CLIENT_ACK, StackQueueItem.STACK_STATUS.PENDING_UID]
			if !current_state in expected_states:
				_error = "state"					
	
	if _error:
		match _error:
			"state":
				display_status_error( 1,stack_uid, expected_states[0], current_state , caller)	
	
	status = new_state
	status_str = StackQueueItem.StackStatusStr[new_state]
	return status


func display_status_error(client_id, stack_uid, expected, actual, calling_function = ""):
	display_debug("{error}()" + calling_function +")" + str(client_id) + " (uid: " + str(stack_uid) +") was expecting " +  StackQueueItem.StackStatusStr[expected] + ", but got " + StackQueueItem.StackStatusStr[actual])

func display_debug(msg):
	gameData.display_debug("{stack_ref_item} " + msg, "")

func debug_queue_status_msg():
	var dict = {
		"stack_uid": stack_uid,
		"status_str":status_str,
		"local_uid" : local_uid,	
		"checksum" : checksum,
		"human_readable" : human_readable	
	}
	return to_json(dict)
