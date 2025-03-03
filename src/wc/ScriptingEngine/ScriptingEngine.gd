class_name WCScriptingEngine
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
func move_card_to_board(script: ScriptTask) -> int:
	#TODO might be better to be able to duplicate scriptTasks ?
	#var modified_script:ScriptTask = script.duplicate
	var backup:Dictionary = script.script_definition.duplicate()
	
	#Replace all occurrences of "current_hero" with the actual id
	#This ensures we use e.g. the correct discard pile, etc...
	var current_hero_id = gameData.get_current_hero_id()
	var owner_hero_id = script.owner.get_owner_hero_id()
	#Not needed anymore ?
	WCUtils.search_and_replace(script.script_definition, "{current_hero}", str(current_hero_id))
	
	for v in ["encounters_facedown","deck" ,"discard","enemies","identity","allies","upgrade_support"]:
		#TODO move to const
		WCUtils.search_and_replace(script.script_definition, v, v+str(owner_hero_id), true)
	
	var result = .move_card_to_board(script)
	script.script_definition = backup
	return result
	
#override for parent
func move_card_to_container(script: ScriptTask) -> int:
	#TODO might be better to be able to duplicate scriptTasks ?
	#var modified_script:ScriptTask = script.duplicate
	var backup:Dictionary = script.script_definition.duplicate()
	
	#Replace all occurrences of "current_hero" with the actual id
	#This ensures we use e.g. the correct discard pile, etc...
	var current_hero_id = gameData.get_current_hero_id()
	var owner_hero_id = script.owner.get_owner_hero_id()
	#Not needed anymore ?
	WCUtils.search_and_replace(script.script_definition, "{current_hero}", str(current_hero_id))
	
	for v in ["encounters_facedown","deck" ,"discard","enemies","identity","allies","upgrade_support"]:
		#TODO move to const
		WCUtils.search_and_replace(script.script_definition, v, v+str(owner_hero_id), true)
	
	var result = .move_card_to_container(script)
	script.script_definition = backup
	return result

#play card and move it either to a pile or a container
# more importantly, sends the signal "card played" to the scripting engine
func play_card(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	
	
	var definition:Dictionary =  script.script_definition
	if (definition.has("grid_name")):
		definition.name="move_card_to_board"
		retcode =  move_card_to_board(script)
	else:
		definition.name="move_card_to_container"
		retcode = move_card_to_container(script)		
	
	#if (retcode == CFConst.ReturnCode.FAILED):
	#	return retcode
		
	scripting_bus.emit_signal("card_played", script.owner, script.script_definition)		
	return retcode	

#Compatible with IS_COST (obviously?)
func pay_from_manapool(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()):
		return retcode
	
	var owner = script.owner
	var owner_hero_id = owner.get_owner_hero_id()
	var manapool:ManaPool = gameData.get_team_member(owner_hero_id)["manapool"]

	#Manapool gets emptied after paying for a cost
	#TODO something more subtle than that?
	manapool.reset()	
	return retcode	


func attack(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var token_name = "damage" #TODO move to const
	
	var damage = script.script_definition.get("amount", 0)
	if not damage:
		var owner = script.owner
		damage = owner.get_property("attack", 0)
	
	script.script_definition["amount"] = damage 
	receive_damage(script)
	consequential_damage(script)

	return retcode	

func receive_damage(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.script_definition["amount"]
	
	#TODO BUG sometimes subjects contains a null card?
	for card in script.subjects:
		var damageScript:DamageScript = DamageScript.new(card, amount, script.script_definition, tags)
		gameData.theStack.add_script(damageScript)
		
#		scripting_bus.emit_signal("damage_incoming", card, script.script_definition)	
#
#		retcode = card.tokens.mod_token("damage",
#				amount,false,costs_dry_run(), tags)	
#
#		scripting_bus.emit_signal("card_damaged", card, script.script_definition)
#
#		var total_damage:int =  card.tokens.get_token_count("damage")
#		var health = card.get_property("health", 0)
#
#		if total_damage >= health:
#			card.die()		
	

	return retcode

func prevent_damage(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	
	
	#Find the damage on the stack and remove it
	var result = gameData.theStack.delete_next_by_class("DamageScript")
	
	return retcode				

func defend(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		for card in script.subjects:
			if (not card.can_defend()):
				return CFConst.ReturnCode.FAILED
		return retcode
		
	var attacker = script.owner
	var amount = attacker.get_property("attack", 0)
	var defender:WCCard = null
	if (not script.subjects.empty()):
		defender = script.subjects[0]
	
	if defender:
		defender.exhaustme()
		var damage_reduction = defender.get_property("defense", 0)
		amount = max(amount-damage_reduction, 0)
	else:
		var my_hero:Card = gameData.get_current_target_hero()
		script.subjects.append(my_hero)
		#TODO add variable stating attack was undefended

	script.script_definition["amount"] = amount
	var result = receive_damage(script)
	
	if (!defender):
		#reset subjects to avoid side effect...
		script.subjects = []
		
	return result

func undefend(script: ScriptTask) -> int:
	return defend(script)
	
func consequential_damage(script: ScriptTask) -> int:	
	var retcode: int = CFConst.ReturnCode.OK
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?

	var owner:WCCard = script.owner
	var damage = owner.get_property("attack_cost", 0)
	
	match script.script_name:
		"thwart":
			damage = owner.get_property("thwart_cost",0)

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
	var owner:WCCard = script.owner
	var modification = owner.get_property("thwart")
	var token_diff = modification
	
	for card in script.subjects:
		var current_tokens = card.tokens.get_token_count(token_name)
		if current_tokens - modification < 0:
			token_diff = current_tokens
		retcode = card.tokens.mod_token(token_name,
				-token_diff,false,costs_dry_run(), tags)


	consequential_damage(script)
	return retcode	

func move_to_player_zone(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?

	var this_card:WCCard = script.owner
	
	for subject in script.subjects:
		retcode = CFConst.ReturnCode.FAILED
		var hero:WCCard = subject
		
		#Get my current zone
		var current_grid_name = this_card.get_grid_name()
		if (current_grid_name):
			#hack to new zone
			var new_grid_name = current_grid_name.left(current_grid_name.length() -1)
			new_grid_name = new_grid_name + str(hero.get_owner_hero_id())
			var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(new_grid_name)
			var slot: BoardPlacementSlot
			if grid:
				slot = grid.find_available_slot()			
				this_card.move_to(cfc.NMAP.board, -1, slot)
				retcode = CFConst.ReturnCode.CHANGED	
			pass

	return retcode
			



	consequential_damage(script)
	return retcode	
