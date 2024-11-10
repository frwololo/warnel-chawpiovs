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

#Compatible with IS_COST (obviously?)
func pay_from_manapool(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()):
		return retcode
	
	var manapool:ManaPool = gameData.get_current_team_member()["manapool"]

	#Manapool gets emptied after paying for a cost
	#TODO something more subtle than that?
	manapool.reset()	
	return retcode	
	
func add_mana(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var counter_name: String = script.get_property(SP.KEY_COUNTER_NAME)
	#TODO the scripting engine has better ways to handle alterations, etc... need to mimic that? See mod_counter
	var modification: int  = script.get_property(SP.KEY_MODIFICATION)
	# var set_to_mod: bool = script.get_property(SP.KEY_SET_TO_MOD)

	var manapool:ManaPool = gameData.get_current_team_member()["manapool"]
	manapool.add_resource(counter_name, modification)
	return retcode		
	
#func pay_regular_cost(script: ScriptTask) -> int:
#	#TODO might be better to be able to duplicate scriptTasks ?
#	#var modified_script:ScriptTask = script.duplicate
#	var backup:Dictionary = script.script_definition.duplicate()
#
#	#Replace all occurrences of "current_hero" with the actual id
#	#This ensures we use e.g. the correct discard pile, etc...
#	var current_hero_id = gameData.get_current_hero_id()
#	search_and_replace(script.script_definition, "{current_hero}", str(current_hero_id))
#
#	var manapool:ManaPool = gameData.get_current_team_member()["manapool"]
#	var manacost:ManaCost = ManaCost.new()
#	manacost.init_from_expression(script.script_definition["cost"]) #TODO better name?
#	var missing_mana:ManaCost = manapool.compute_missing(manacost)
#
#	var result = CFConst.ReturnCode.CHANGED #IS this correct???
#	#Manapool not enough, need to discard cards
#	if missing_mana.is_negative() :
#		#Replace the script with a move condition
#		script.script_definition[SP.KEY_SELECTION_COUNT] = -missing_mana.pool[ManaCost.Resource.UNCOLOR] #TODO put real missing cost here
#		result = .move_card_to_container(script)
#
#	if not costs_dry_run(): #IS this correct? Should we check result ?
#		manapool.reset()
#
#	script.script_definition = backup
#	return result	

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
		
