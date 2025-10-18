# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

#a quick and dirty script container for simple tasks to go on the stack
#this cannot handle cost payment and the like, so targets/subjects need to be extremely simple (self, etc...)

class_name SignalStackScript
extends StackObject

var owner
var script_name
var script_definition:={}


func _init(_name = "", _owner = null, _details = {}):
	script_name = _name
	owner = _owner
	script_definition = _details
	tasks = [self]
	
func execute():
	scripting_bus.emit_signal(script_name, owner, script_definition)

func get_tasks():
	return [self]

func get_class() -> String:
	return("SignalStackScript")

func get_script_by_event_details(event_details):
	
	#Doesn't support type for now
	var _type = event_details["event_type"]
	if (_type):
		return null

	var _name = event_details["event_name"]		
	if _name and (script_name != _name):
		return null
	
	return self	

