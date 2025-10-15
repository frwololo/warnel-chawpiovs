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

func execute():
	var owner = sceng.owner

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
	

