# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name StackObject
extends Reference

var stack_uid:int = 0

#task elements, generally speaking, should be ScriptTask objects
#at the very least, they need a script_definition and a script_name value
var tasks:= []

#can be overriden by children classes
func get_tasks():
	return tasks

#can be overriden by children classes
func get_script_by_event_name(_name):
	return null

#can be overriden by children classes
func execute():
	pass

#TODO this function shouldn't be here? doesn't use any of its data
func matches_filters(task, filters:Dictionary, owner_card):
	var owner_hero_id = owner_card.get_owner_hero_id()
	if (owner_hero_id > 0):
		for v in ["my_hero"]:
			#TODO move to const
			WCUtils.search_and_replace(filters, v, gameData.get_identity_card(owner_hero_id), true)

	if (filters):
		var _tmp = 0	
	var script_details = task.script_definition
	var result = WCUtils.is_element1_in_element2(filters, script_details)

	return result
