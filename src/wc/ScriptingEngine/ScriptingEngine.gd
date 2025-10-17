# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

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

func draw_cards (script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	
	
	var amount = script.script_definition.get("amount", 1)
	var owner = script.owner
	
	var controller_id = owner.get_controller_hero_id()
	var hand:Hand = cfc.NMAP["hand" + str(controller_id)]
	var deck = cfc.NMAP["deck" + str(controller_id)]
	for i in range (amount):
		hand.draw_card(deck)
	return retcode

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

	var tags: Array = ["attack", "Scripted"] + script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?

	var owner = script.owner	
	var damage = script.script_definition.get("amount", 0)
	if not damage:
		damage = owner.get_property("attack", 0)

	var stunned = owner.tokens.get_token_count("stunned")
	if (stunned):
		owner.tokens.mod_token("stunned", -1)
		
	else:		
		script.script_definition["tags"] = tags
		script.script_definition["amount"] = damage 
		receive_damage(script)
		consequential_damage(script)

	return retcode	

func receive_damage(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.script_definition["amount"]
	
	#TODO BUG sometimes subjects contains a null card?
	for card in script.subjects:
#		var damageScript:DamageScript = DamageScript.new(card, amount, script.script_definition, tags)
#		gameData.theStack.add_script(damageScript)
		
		#scripting_bus.emit_signal("damage_incoming", card, script.script_definition)	

		var tough = card.tokens.get_token_count("tough")
		if (tough):
			card.tokens.mod_token("tough", -1)
		else:	
			retcode = card.tokens.mod_token("damage",
					amount,false,costs_dry_run(), tags)	

			scripting_bus.emit_signal("card_damaged", card, script.script_definition)

			var total_damage:int =  card.tokens.get_token_count("damage")
			var health = card.get_property("health", 0)

			if total_damage >= health:
				card.die()		
	

	return retcode

func prevent(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	
	
	#Find the event on the stack and remove it
	#TOdo take into action subject, etc...
	var _result = gameData.theStack.delete_last_event()
	
	return retcode				

static func simple_discard_task(target_card):
	var dest_container = "discard_villain"
	var hero_id = target_card.get_owner_hero_id()
	if (hero_id > 0):
		dest_container = "discard" + String(hero_id)
		
	var discard_script  = {
				"name": "move_card_to_container",
				"subject": "self",
				"needs_subject" : true,
				"dest_container" : dest_container
			}
	var discard_task = ScriptTask.new(target_card, discard_script, target_card, {})	
	var task_event = SimplifiedStackScript.new("move_card_to_container", discard_task)
	return task_event

#the ability that is triggered by enemy_attack
func enemy_attack(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		for card in script.subjects:
			if (not card.can_defend()):
				return CFConst.ReturnCode.FAILED
		return retcode
		
	var attacker = script.owner
	var amount = attacker.get_property("attack", 0)
	var defender = null
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

	#reveal boost cards
	#todo should go on stack?
	for boost_card in attacker.attachments:
		if (!boost_card.is_boost):
			continue
		boost_card.set_is_faceup(true)
		amount = amount + boost_card.get_property("boost",0)
		#add an event on the stack to discard this card.
		#Note that the discard will happen *after* receive_damage below 
		#because we add it to the stack first
		var discard_event = simple_discard_task(boost_card)
		gameData.theStack.add_script(discard_event)

	var receive_damage_definition = {
		"name": "receive_damage",
		"amount": amount,
		"tags": ["attack", "Scripted"] + script.get_property(SP.KEY_TAGS)
	}
	var receive_damage_script:ScriptTask = ScriptTask.new(script.owner, receive_damage_definition, script.trigger_object, script.trigger_details)
	receive_damage_script.subjects = script.subjects.duplicate()
	receive_damage_script.is_primed = true #fake prime it since we already gave it subjects	
	
	var task_event = SimplifiedStackScript.new("receive_damage", receive_damage_script)
	gameData.theStack.add_script(task_event)
	
#	if (!defender):
		#reset subjects to avoid side effect...
#		script.subjects = []
		
	return retcode

func undefend(script: ScriptTask) -> int:
	return enemy_attack(script)
	
func consequential_damage(script: ScriptTask) -> int:	
	var retcode: int = CFConst.ReturnCode.OK
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var owner = script.owner
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

	var owner = script.owner
	var modification = owner.get_property("thwart")

	var confused = owner.tokens.get_token_count("confused")
	if (confused):
		owner.tokens.mod_token("confused", -1)
	else:
		for card in script.subjects:
			retcode = card.remove_threat(modification)
		consequential_damage(script)
	return retcode	

func heal(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	var amount = script.script_definition["amount"]
	
	for subject in script.subjects: #should be really one subject only, generally
		subject.heal(amount)

	return CFConst.ReturnCode.CHANGED

func recovery(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	for subject in script.subjects: #should be really one subject only, generally
		var hero = subject
		
		hero.heal(hero.get_property("recover", 0))

	return CFConst.ReturnCode.CHANGED

func change_form(script: ScriptTask) -> int:

	var tags: Array = script.get_property(SP.KEY_TAGS)
	var is_manual = "player_initiated" in tags
	
	for subject in script.subjects: #should be really one subject only, generally
		var hero = subject
		
		if is_manual and !hero.can_change_form():
			return CFConst.ReturnCode.FAILED
		
		if (!costs_dry_run()):
		#Get my current zone
			if (is_manual):
				hero._can_change_form = false
			cfc.NMAP.board.flip_doublesided_card(hero)

	return CFConst.ReturnCode.CHANGED
	
func move_to_player_zone(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var this_card= script.owner
	
	for subject in script.subjects:
		retcode = CFConst.ReturnCode.FAILED
		var hero = subject
		
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

#used only as a cost, checks a series of constraints to see if a card can be played or not
func constraints(script: ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.CHANGED	
	
	var this_card = script.owner
	var my_hero_id = this_card.get_controller_hero_id()
	var my_hero_card = gameData.get_identity_card(my_hero_id)
	
	var tags: Array = script.get_property(SP.KEY_TAGS)
	
	for tag in tags:
		match tag:
			"hero_action":
				if !my_hero_card.is_hero_form():
					return CFConst.ReturnCode.FAILED
			"alter_ego_action":
				if !my_hero_card.is_alter_ego_form():
					return CFConst.ReturnCode.FAILED					
			"hero_resource":
				if !my_hero_card.is_hero_form():
					return CFConst.ReturnCode.FAILED					

	return retcode
