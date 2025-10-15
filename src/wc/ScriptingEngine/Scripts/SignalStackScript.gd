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

func get_script_by_event_name(_name):
	if script_name == _name:
		return self
	return null
