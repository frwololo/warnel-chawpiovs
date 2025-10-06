class_name GlobalScriptStack
extends Node2D

#Action stack (similar to the MTG stack) where actions get piled, waiting for user input if needed


var stack:Array = []
var waitOneMoreTick = 0
var check_interrupts:= true

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
	var can_proceed = !check_interrupts or \
		send_before_trigger(next_script)
	
	if (can_proceed):
		check_interrupts = true
		next_script = stack.pop_back()
		next_script.execute()		
	return	

func gets_one_pass():
	check_interrupts = false;

func send_before_trigger(script:StackScript):
	scripting_bus.emit_signal("before_" + script.get_event_name(), script.script_details)
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
		var event:StackScript = stack[-x-1]
		var event_name = event.get_event_name()
		if (event_name != _name):
			continue			
		if event.matches_filters(details, owner_card):
			return event
	return null			
