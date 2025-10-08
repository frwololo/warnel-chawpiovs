class_name StackScript
extends Node

var sceng
var run_type
var trigger

func _init(_sceng, _run_type, _trigger):
	sceng = _sceng
	run_type = _run_type
	trigger = _trigger

func execute():
	var owner = sceng.owner
	if sceng.can_all_costs_be_paid:
		#print("DEBUG:" + str(state_scripts))
		# The ScriptingEngine is where we execute the scripts
		# We cannot use its class reference,
		# as it causes a cyclic reference error when parsing
		
		sceng.execute(run_type)
		if not sceng.all_tasks_completed:
			yield(sceng,"tasks_completed")
		# warning-ignore:void_assignment
		var func_return = owner.common_post_execution_scripts(trigger)
		# We make sure this function does to return until all
		# custom post execution scripts have also finished
		if func_return is GDScriptFunctionState: # Still working.
			func_return = yield(func_return, "completed")
	# This will only trigger when costs could not be paid, and will
	# execute the "is_else" tasks
	else:
		#print("DEBUG:" + str(state_scripts))
		sceng.execute(CFInt.RunType.ELSE)
		if not sceng.all_tasks_completed:
			yield(sceng,"tasks_completed")	

func get_tasks() -> Array:
	return sceng.scripts_queue

func get_script_by_event_name(_name):
	for task in sceng.scripts_queue:
		var my_name = task.script_name
		if my_name == _name:
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
		var tmp = 0	
	var script_details = script.script_definition
	var result = WCUtils.is_element1_in_element2(filters, script_details)

	return result
