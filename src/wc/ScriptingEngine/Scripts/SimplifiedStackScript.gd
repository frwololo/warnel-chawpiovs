# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

#a quick and dirty script container for simple tasks to go on the stack
#this cannot handle cost payment and the like, so targets/subjects need to be extremely simple (self, etc...)

class_name SimplifiedStackScript
extends StackScript

var task_name
var task

func _init(_task, _owner = null, _trigger_object = null, _trigger_details = {}):
	if typeof(_task) == TYPE_DICTIONARY:
		init_task_from_script_definition(_task, _owner, _trigger_object, _trigger_details)
	else:
		task = _task
	
	if _owner:
		task.owner = _owner	
		if _trigger_object:
			_trigger_object = _owner
	
	if _trigger_object:
		task.trigger_object = _trigger_object

	if _trigger_details:
		task.trigger_details = _trigger_details
	
	task_name = task.script_name
		
	task.script_definition["name"] = task_name
	
	#enforce some values for filter matching
	if (task.subjects):
		task.script_definition["target"] = task.subjects[0]

	if !task.trigger_details.has("tags"):
		task.trigger_details["tags"] = []

	#convoluted way to recreate a sceng from a task... is there something cleaner?
	sceng = cfc.scripting_engine.new([task.script_definition], task.owner,task.trigger_object, task.trigger_details)
	run_type = CFInt.RunType.NORMAL
	trigger = "" #TODO something better ?
	tasks = [task]
	# Seems to be required to avoid re-targeting... ?
	task.is_primed = true
	
func init_task_from_script_definition(definition:Dictionary, _owner, _trigger_object, _trigger_details = {}):
	task = ScriptTask.new(_owner, definition, _trigger_object, _trigger_details)

func get_tasks() -> Array:
	return tasks


	
func execute():
	if (!task.is_primed):
		task.prime([],run_type,0, [])
	
	var _retcode = sceng.call(task_name, task)

#replacement task
func replace_ability(new_ability:String, task_object = null):
	.replace_ability(new_ability, task_object)
	task_name = new_ability

#replacement task
func replace_subjects(new_subjects:Array, task_object = null):
	.replace_subjects(new_subjects, task_object)
	task.set_subjects(new_subjects)

	if (task.subjects):
		task.script_definition["target"] = task.subjects[0]

#	#recreate sceng	
#	sceng = cfc.scripting_engine.new([task.script_definition], task.owner,task.trigger_object, task.trigger_details)


func get_script_by_event_details(event_details):
	
	#TODO should this be on a per task basis ?
	var _type = event_details["event_type"]
	if (_type):
		if !(("trigger_" + _type) in (task.trigger_details["tags"])):
			return null

	var _names = event_details["event_name"]		
	if typeof(_names) == TYPE_STRING:
		_names = [_names]
	for _name in _names:
		var my_name = task_name
		if _name and (my_name != _name):
			continue
		return task		
	return null


	

