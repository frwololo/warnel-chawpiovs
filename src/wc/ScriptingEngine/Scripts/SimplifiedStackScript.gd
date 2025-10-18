# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

#a quick and dirty script container for simple tasks to go on the stack
#this cannot handle cost payment and the like, so targets/subjects need to be extremely simple (self, etc...)

class_name SimplifiedStackScript
extends StackScript

var task_name
var task

func _init(_name, _task):
	task_name = _name
	task = _task
	#hard modify the name here because at least for damaged received I'm passing "undefedn" as the name
	# maybe that needs to be modifed there instead of here
	task.script_name = task_name
	task.script_definition["name"] = task_name
	
	#enforce some values for filter matching
	if (task.subjects):
		task.script_definition["target"] = task.subjects[0]

	#convoluted way to recreate a sceng from a task... is there something cleaner?
	sceng = cfc.scripting_engine.new([task.script_definition], task.owner,task.trigger_object, task.trigger_details)
	run_type = CFInt.RunType.NORMAL
	trigger = "" #TODO something better ?
	tasks = [task]

func get_tasks() -> Array:
	return tasks
	
func execute():
	if (!task.is_primed):
		task.prime([],run_type,0)
	
	var _retcode = sceng.call(task_name, task)

func get_script_by_event_details(event_details):
	
	#TODO should this be on a per task basis ?
	var _type = event_details["event_type"]
	if (_type):
		if !(("trigger_" + _type) in (task.trigger_details["tags"])):
			return null

	var _name = event_details["event_name"]		
	if _name and (task_name != _name):
		return null
	
	return task		

	

