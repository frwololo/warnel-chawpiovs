# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name StackScript
extends StackObject

var sceng
var run_type
var trigger
var trigger_details


func _init(_sceng = null, _run_type = 0, _trigger = "", _trigger_details = {}):
	sceng = _sceng
	run_type = _run_type
	trigger = _trigger
	trigger_details = _trigger_details

func get_sceng():
	return sceng

#replacement task
func replace_subjects(new_subjects:Array, task_object = null):
	for task in get_tasks():
		if task_object and task != task_object:
			continue		
		task.subjects = new_subjects
		#TODO hack force select...
		#not sure why I have to do this but
		#this is being called beofre prime in some cases
		task.is_primed = true

#replacement task
func replace_ability(new_ability:String, task_object = null):
	for task in get_tasks():
		if task_object and task != task_object:
			continue		
		task.script_name = new_ability
		task.script_definition["name"] = new_ability
	var _tmp = sceng	

func prevent_value(property, amount_prevented, task_object = null):
	var prevented = 0
	for task in get_tasks():
		if task_object and task != task_object:
			continue		
		var script_definition = task.script_definition
		if script_definition.has(property):
			var value = task.retrieve_integer_property(property)
			prevented = min(value, amount_prevented)
			value = value-prevented
			script_definition[property] = value
		else:
			#if the script doesn't have the expected property, we try to pass it along
			var prevent = "prevent_" + property
			var value = task.retrieve_integer_property(prevent, 0)
			script_definition[prevent] = value + amount_prevented			
			#todo what if zero
	return prevented


func is_silent():
	for task in get_tasks():
		if task.trigger_details.get("_silent", false):
			return true
	if sceng.trigger_details.get("_silent", false):
		return true
	return false

func execute():
	cfc.add_ongoing_process(self)
	var owner = sceng.owner

	if !is_instance_valid(owner):
		var _error = 1
		cfc.remove_ongoing_process(self)
		return
	#we re-run some pre-execution scripts here to set everything right
	owner.common_pre_run(sceng)
	# In case the script involves targetting, we need to wait on further
	# execution until targetting has completed
	sceng.execute(CFInt.RunType.COST_CHECK)
	if not sceng.all_tasks_completed:
		#TODO this shouldn't happen because at this stage all costs should have been prepaid
		var _error = 1
		yield(sceng,"tasks_completed")	
	
	if sceng.can_all_costs_be_paid:

		#1.5) We run the script in "prime" mode again to choose targets
		# for all tasks that aren't costs but still need targets
		# (is_cost = false and needs_subject = false)
		sceng.execute(CFInt.RunType.PRIME_ONLY)
		if not sceng.all_tasks_completed:
			yield(sceng,"tasks_completed")
	
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
	cfc.remove_ongoing_process(self)

func get_tasks() -> Array:
	return sceng.scripts_queue

func get_script_by_event_details(event_details):
	
	#TODO should this be on a per task basis ?
	var _type = event_details["event_type"]
	if (_type):
		if !(("trigger_" + _type) in (trigger_details["tags"])):
			return null

	var _names = event_details["event_name"]		
	if typeof(_names) == TYPE_STRING:
		_names = [_names]
	for _name in _names:
		for task in get_tasks():
			var my_name = task.script_name
			if _name and (my_name != _name):
				continue
			return task		
		return null
	

