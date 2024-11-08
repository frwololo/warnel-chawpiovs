extends ScriptingEngine



# Just calls the parent class.
func _init(state_scripts: Array,
		owner,
		_trigger_object: Node,
		_trigger_details: Dictionary).(state_scripts,
		owner,
		_trigger_object,
		_trigger_details) -> void:
	pass


#override for parent
func move_card_to_container(script: ScriptTask) -> int:
	#TODO might be better to be able to duplicate scriptTasks ?
	#var modified_script:ScriptTask = script.duplicate
	var backup:Dictionary = script.script_definition.duplicate()
	
	#Replace all occurrences of "current_hero" with the actual id
	#This ensures we use e.g. the correct discard pile, etc...
	var current_hero_id = gameData.get_current_hero_id()
	search_and_replace(script.script_definition, "{current_hero}", str(current_hero_id))
	
	
	var result = .move_card_to_container(script)
	script.script_definition = backup
	return result

# TODO move to a utility file
# we operate directly on the dictionary without suplicate for speed reasons. Make a copy prior if needed
func search_and_replace (script_definition : Dictionary, from: String, to:String) -> Dictionary:
	for key in script_definition.keys():
		var value = script_definition[key]
		if typeof(value) == TYPE_STRING:
			script_definition[key] = value.replace(from, to)
		elif typeof(value) == TYPE_ARRAY:
			for x in value:
				search_and_replace(x,from, to)
		elif typeof(value) == TYPE_DICTIONARY:
			search_and_replace(value,from, to)	
	return script_definition;
		
