class_name WCAlterantEngine
extends AlterantEngine

# Sets the owner of this Scripting Engine
func _init(
		trigger_object: Card,
		alterant_object,
		scripts_queue: Array,
		task_details: Dictionary,
		_subject).(trigger_object,
		alterant_object,
		scripts_queue,
		task_details,
		_subject) -> void:
	pass

func common_pre_run(scripts_queue, trigger_object):
	var new_scripts_queue = []
	
	for script in scripts_queue:
		 new_scripts_queue.append(WCScriptingEngine.static_pre_task_prime(script, trigger_object))
	
	return new_scripts_queue
