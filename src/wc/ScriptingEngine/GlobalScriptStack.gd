class_name GlobalScriptStack
extends Node2D

#Action stack (similar to the MTG stack) where actions get piled, waiting for user input if needed


var stack:Array = []
var waitOneMoreTick = 0

# bool to tell whether we need to check for player interrupts or if we got a pass
var _check_interrupts:= true

#stores data relevant to the ongoing interrupt signal
var _current_interrupted_event: Dictionary = {}

func add_script(object):
	stack.append(object)
	object.added_to_global_stack()
	return
	
func process(_delta: float):
	if stack.empty(): 
		return
		
	#check if any user input is requested/happening. If so, we wait
	if (gameData.is_interrupt_mode()):
		return 
			
	if (gameData.user_input_ongoing):
		waitOneMoreTick = 2; #TODO MAGIC NUMBER. Why do we have to wait 2 passes before damage gets prevented?
		return
	
	if waitOneMoreTick:
		waitOneMoreTick -= 1
		return		
	
	var next_script = stack.back()
	if (! next_script):
		return
	
	#give opportunity for cards to interrupt event by sending a "before" signal
	var can_proceed = !_check_interrupts or \
		send_before_trigger(next_script)
	
	if (can_proceed):
		_check_interrupts = true
		_current_interrupted_event = {}
		next_script = stack.pop_back()
		var func_return = next_script.execute()	
		while func_return is GDScriptFunctionState && func_return.is_valid():
			func_return = func_return.resume()
		
		var sceng = next_script.sceng
		var trigger_details = sceng.trigger_details
		var is_network_call = trigger_details.has("network_prepaid")
#		if (!is_network_call):
#			#Call other clients to run the script
#			var trigger_card = sceng.trigger_object
#			var trigger = next_script.trigger
#			var run_type = next_script.run_type
#			sceng.owner.network_execute_scripts(trigger_card, trigger, trigger_details, run_type, sceng)		

			
	return	

func gets_one_pass():
	_check_interrupts = false

func get_current_interrupted_event():
	return self._current_interrupted_event

func send_before_trigger(script):
	var tasks = script.get_tasks()
	for task in tasks:
		_current_interrupted_event = {"event_name": task.script_name, "details": task.script_definition}
		scripting_bus.emit_signal("interrupt", task.owner, _current_interrupted_event)
	if (gameData.is_interrupt_mode()):
		return false
	else:
		return true

func delete_next_by_class(classname):
	var variant = _find_next_by_class(classname)
	return _delete_object(variant)
	
func _find_next_by_class(classname):
	for x in stack.size():
		var value = stack[-x-1]
		var theclass = value.get_class()
		if (theclass == classname):
			return value
	return null
	
func _delete_object(variant):
	if (!variant):
		return false				
	var index:int = stack.rfind(variant)
	stack.remove(index)
	return true
	
func delete_last_event():
	stack.pop_back()

func find_event(_name, details, owner_card):
	for x in stack.size():
		var event = stack[-x-1]
		var task = event.get_script_by_event_name(_name)
		if (!task):
			continue			
		if event.matches_filters(task, details, owner_card):
			return event
	return null			
