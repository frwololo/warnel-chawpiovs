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

#Scripting functions 

#Abilities that add energy	
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

func deal_damage(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	
	return retcode	
	
func deal_thwart(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	
	return retcode		

func attack(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var token_name = "damage" #TODO move to const
	
	var damage = script.script_definition.get("amount", 0)
	if not damage:
		var owner_properties = script.owner.properties
		damage = owner_properties.get("attack", 0)
	
	var token_diff = damage
	
	for card in script.subjects:
		var current_tokens = card.tokens.get_token_count(token_name)
		#if current_tokens - modification < 0:
		#	token_diff = current_tokens
		retcode = card.tokens.mod_token(token_name,
				token_diff,false,costs_dry_run(), tags)

	consequential_damage(script)

	return retcode	

func receive_damage(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.script_definition["amount"]
	
	for card in script.subjects:
		retcode = card.tokens.mod_token("damage",
				amount,false,costs_dry_run(), tags)	
	
	#TODO face damage consequences e.g. death

	return retcode
				

func defend(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		for card in script.subjects:
			if (not card.can_defend()):
				return CFConst.ReturnCode.FAILED
		return retcode
		
	var attacker = script.owner
	var amount = attacker.properties["attack"]
	var defender = null
	if (not script.subjects.empty()):
		defender = script.subjects[0]
	
	if defender:
		defender.exhaustme()
		var damage_reduction = defender.properties.get("defense", 0)
		amount = max(amount-damage_reduction, 0)
	else:
		var my_hero:Card = gameData.get_current_target_hero()
		script.subjects.append(my_hero)
		#TODO add variable stating attack was undefended

	script.script_definition["amount"] = amount
	return receive_damage(script)
	
func consequential_damage(script: ScriptTask) -> int:	
	var retcode: int = CFConst.ReturnCode.OK
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?

	var owner_properties = script.owner.properties
	var damage = owner_properties.get("attack_cost", 0)
	
	match script.script_name:
		"thwart":
			damage = owner_properties.get("thwart_cost",0)

	var additional_task := ScriptTask.new(
		script.owner,
		{"name": "receive_damage", "amount" : damage, "subject" : "self"}, #TODO more advanced
		script.trigger_object,
		script.trigger_details)
	additional_task.prime([], CFInt.RunType.NORMAL,0) #TODO gross
	retcode = receive_damage(additional_task)
	
	return retcode

	
func thwart(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var token_name = "threat" #TODO move to const
	var owner_properties = script.owner.properties
	var modification = owner_properties["thwart"]
	var token_diff = modification
	
	for card in script.subjects:
		var current_tokens = card.tokens.get_token_count(token_name)
		if current_tokens - modification < 0:
			token_diff = current_tokens
		retcode = card.tokens.mod_token(token_name,
				-token_diff,false,costs_dry_run(), tags)


	consequential_damage(script)
	return retcode	

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
		
