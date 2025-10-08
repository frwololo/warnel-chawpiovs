# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name SimplifiedStackScript
extends Node

var task_name
var task

func _init(_name, _task):
	task_name = _name
	task = _task
	#hard modify the name here because at least for damaged received I'm passing "undefedn" as the name
	# maybe that needs to be modifed there instead of here
	task.script_name = task_name
	
	#enforce some values for filter matching
	if (task.subjects):
		task.script_definition["target"] = task.subjects[0]

func execute():
	var sceng = cfc.scripting_engine.new([task], task.owner,task.trigger_object, task.trigger_details)
	var _retcode = sceng.call(task_name, task)

func get_tasks() -> Array:
	return [task]

func get_script_by_event_name(_name):
	if task_name == _name:
		return task
	return null
	
func added_to_global_stack():
	#scripting_bus.emit_signal("before_" + get_event_name())	
	return	

func matches_filters(script, filters:Dictionary, owner_card):
	var owner_hero_id = owner_card.get_owner_hero_id()
	if (owner_hero_id > 0):
		for v in ["my_hero"]:
			#TODO move to const
			WCUtils.search_and_replace(filters, v, gameData.get_hero_card(owner_hero_id), true)

	if (filters):
		var _tmp = 0	
	var script_details = script.script_definition
	var result = WCUtils.is_element1_in_element2(filters, script_details)

	return result
