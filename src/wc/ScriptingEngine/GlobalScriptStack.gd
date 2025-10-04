class_name GlobalScriptStack
extends Node2D

#Action stack (similar to the MTG stack) where actions get piled, waiting for user input if needed


var stack:Array = []
var waitOneMoreTick = 0

func add_script(object):
	stack.append(object)
	object.added_to_global_stack()
	return
	
func process(_delta: float):
	if stack.empty(): 
		return
		
	#check if any user input is requested/happening. If so, we wait
	if (gameData.user_input_ongoing):
		waitOneMoreTick = 2; #TODO MAGIC NUMBER. Why do we have to wait 2 passes before damage gets prevented?
		return
	
	if waitOneMoreTick:
		waitOneMoreTick -= 1
		return		
	
	var next_script = stack.pop_back()
	if (! next_script):
		return
	
	next_script.execute()		
	return	

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

		
