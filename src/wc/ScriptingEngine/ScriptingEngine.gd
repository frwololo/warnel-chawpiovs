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

func pay_as_resource(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var resources_paid := []
	for subject in script.subjects:
		var resource = subject.pay_as_resource(script)
		resources_paid.append(resource)
	
	script.owner.set_last_paid_with(resources_paid)
	return retcode		

#empty ability, used for filtering and script failure
# see KEY_FAIL_COST_ON_SKIP
func nop(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	return retcode


#Abilities that add energy	
func add_resource(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var counter_name: String = script.get_property("resource_name")
	#TODO the scripting engine has better ways to handle alterations, etc... need to mimic that? See mod_counter
	var modification: int  = script.retrieve_integer_property("amount")
	# var set_to_mod: bool = script.get_property(SP.KEY_SET_TO_MOD)


	if run_type == CFInt.RunType.PRECOMPUTE:
		var pre_result:ManaCost = ManaCost.new()
		pre_result.add_resource(counter_name, modification)
		script.process_result = pre_result	
		return retcode
	
	#there is no manapool anymore
	#manapool.add_resource(counter_name, modification)
	return retcode	

#override for parent
func move_card_to_board(script: ScriptTask) -> int:
	#TODO might be better to be able to duplicate scriptTasks ?
	#var modified_script:ScriptTask = script.duplicate
	var backup:Dictionary = script.script_definition.duplicate()

	#we force a grid container in all cases
	if script.subjects and !script.get_property("grid_name"):
		var subject = script.subjects[0]
		var type_code = subject.get_property("type_code")
		if CFConst.TYPECODE_TO_GRID.has(type_code):
			script.script_definition["grid_name"] = CFConst.TYPECODE_TO_GRID[type_code]

	
	#Replace all occurrences of un_numberd "discard", etc... with the actual id
	#This ensures we use e.g. the correct discard pile, etc...
	var owner_hero_id = script.trigger_details.get("override_controller_id", script.owner.get_owner_hero_id())
	
	for zone in CFConst.HERO_GRID_SETUP:
		#TODO move to const
		script.script_definition = WCUtils.search_and_replace(script.script_definition, zone, zone+str(owner_hero_id), true)
	

	var result = .move_card_to_board(script)
	script.script_definition = backup
	return result

func shuffle_card_into_container(script:ScriptTask) -> int:
	var result = move_card_to_container(script)
	var dest_container_str = script.get_property(SP.KEY_DEST_CONTAINER).to_lower()
	var dest_container: CardContainer = cfc.NMAP[dest_container_str]
	dest_container.shuffle_cards()
	
	return result
	
#override for parent
func move_card_to_container(script: ScriptTask) -> int:
	#TODO might be better to be able to duplicate scriptTasks ?
	#var modified_script:ScriptTask = script.duplicate
	var backup:Dictionary = script.script_definition.duplicate()
	
	var owner_hero_id = script.owner.get_owner_hero_id()

	for zone in ["hand"] + CFConst.HERO_GRID_SETUP.keys():
		#TODO move to const
		script.script_definition = WCUtils.search_and_replace(script.script_definition, zone, zone+str(owner_hero_id), true)
	
	var result = .move_card_to_container(script)
	script.script_definition = backup
	return result

func draw_cards (script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	var amount = script.retrieve_integer_property("amount")
	if !amount:
		return CFConst.ReturnCode.FAILED
	
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode			
	
	var subjects = [script.owner]	
	if script.subjects:
		subjects = script.subjects

	for subject in subjects:
		var controller_id = subject.get_controller_hero_id()
		if controller_id <= 0:
			cfc.LOG("{ScriptingEngine}{error}, attempt to draw cards for villain")
			cfc.LOG_DICT(script.serialize_to_json())

		var hand:Hand = cfc.NMAP["hand" + str(controller_id)]
		var deck = cfc.NMAP["deck" + str(controller_id)]
		for _i in range (amount):
			hand.draw_card(deck)
	return retcode
	
func draw_to_hand_size (script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	
	
	var my_hero_id = owner.get_controller_hero_id()
	var my_hero_card = gameData.get_identity_card(my_hero_id)	
	var hand_size = my_hero_card.get_max_hand_size()
	
	var hand:Hand = cfc.NMAP["hand" + str(my_hero_id)]
	var current_cards = hand.get_card_count()
	
	var amount = hand_size - current_cards
	if (amount < 0):
		return CFConst.ReturnCode.FAILED

	script.script_definition["amount"] = amount
	return draw_cards(script)

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

func attack(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
	if (costs_dry_run()):
		return retcode

	var owner = script.owner	

	var type = owner.get_property("type_code", "")
	if !type in ["hero", "ally"]:
		owner = _get_identity_from_script(script)	
	
	var damage = script.retrieve_integer_property("amount")
	if not damage:
		damage = owner.get_property("attack", 0)

	var stunned = owner.tokens.get_token_count("stunned")
	if (stunned):
		owner.tokens.mod_token("stunned", -1)
		
	else:
		if (damage):	
			var script_modifications = {
				"additional_tags" : ["attack", "Scripted"],
			}
			_add_receive_damage_on_stack (damage, script, script_modifications)		
		consequential_damage(script)

	return retcode	

func character_died(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	for card in script.subjects:
#		var damageScript:DamageScript = DamageScript.new(card, amount, script.script_definition, tags)
#		gameData.theStack.add_script(damageScript)
		
		#scripting_bus.emit_signal("damage_incoming", card, script.script_definition)	
		var owner_hero_id = card.get_owner_hero_id()
		if owner_hero_id > 0:
			card.move_to(cfc.NMAP["discard" + str(owner_hero_id)])
		else:
			card.move_to(cfc.NMAP["discard_villain"])
		var type = card.get_property("type_code", "")
		if type:
			scripting_bus.emit_signal(type + "_died", card, script.trigger_details)
	
	return retcode

func deal_damage(script:ScriptTask) -> int:
#	if script.owner.canonical_name == "Energy Daggers":
#		var _tmp = 1
#
	_add_receive_damage_on_stack(script.script_definition["amount"], script)
	return CFConst.ReturnCode.CHANGED
#	return receive_damage(script)

func scheme_base_threat(script:ScriptTask) -> int:
	var scheme = script.owner
	var tags = script.get_property("tags", [])
	var base_threat = scheme.get_property("base_threat", 0)
	var retcode = scheme.tokens.mod_token("threat", base_threat, false,costs_dry_run(), tags)
	return retcode
	
func return_attachments_to_owner(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	var host = script.owner
	if !host.attachments:
		return 	CFConst.ReturnCode.FAILED
	

	var tags = script.get_property("tags", [])
	var destination_prefix = script.get_property("dest_container")
	if !destination_prefix:
		destination_prefix = "discard"	
	
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	

	var to_move = []
	for card in host.attachments:
		if "facedown" in tags:
			if card.is_faceup:
				continue
		to_move.append(card)
		
	for card in to_move:
		host.attachments.erase(card)
		card.current_host_card = null
		var card_owner = card.get_owner_hero_id()
		var destination = destination_prefix
		#TODO bit of a hack here
		#unfortunately my code already added a suffix number priori to this, so I have to be sneaky :(
		var zones = ["hand"] + CFConst.HERO_GRID_SETUP.keys()
		for zone in zones:
			if zone in destination:
				destination = zone
				break
		if !card_owner:
			destination += "_villain"
		else:
			destination += str(card_owner)

		var pile_or_grid = cfc.pile_or_grid(destination)
		match pile_or_grid:
			"pile":
				card.move_to(cfc.NMAP[destination])
			_:
				card.move_to(cfc.NMAP.board, -1, destination)		


	return retcode	


func card_dies(script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.FAILED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
		
	for card in script.subjects:		
		card.die(script)
		retcode = CFConst.ReturnCode.CHANGED

	return retcode

func receive_damage(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var base_amount = script.retrieve_integer_property("amount")
	
	#consolidate subjects. If the same subject is chosen multiple times, we'll multipy the damage
	# e.g. Spider man gets 3*1 damage = 3 damage
	var consolidated_subjects:= {}
	#TODO BUG sometimes subjects contains a null card?
	for card in script.subjects:
		if !consolidated_subjects.has(card):
			consolidated_subjects[card] = 0
		consolidated_subjects[card] += 1
	
	#TODO BUG sometimes subjects contains a null card?
	for card in consolidated_subjects.keys():
		var multiplier = consolidated_subjects[card]
		var damage_happened = 0
		var amount = base_amount * multiplier
		var tough = card.tokens.get_token_count("tough")
		if (amount and tough):
			card.tokens.mod_token("tough", -1)
		else:	
			retcode = card.tokens.mod_token("damage",
					amount,false,costs_dry_run(), tags)	
			if amount:
				card.hint(str(amount), Color8(255,50,50))
				damage_happened = amount	
				
				if ("stun_if_damage" in tags):
					card.tokens.mod_token("stunned",
						1,false,costs_dry_run(), tags)
				if ("exhaust_if_damage" in tags):
					card.exhaust_me()
				if ("1_threat_on_main_scheme_if_damage" in tags):
					var main_scheme = gameData.get_main_scheme()
					var task = ScriptTask.new(script.owner, {"name": "add_threat", "amount": 1}, card, {})
					task.subjects= [main_scheme]
					var stackEvent = SimplifiedStackScript.new(task)
					gameData.theStack.add_script(stackEvent)
		
		if ("attack" in tags):
			var retaliate = card.get_property("retaliate", 0)
			if retaliate:
				var owner = script.owner
				var type = owner.get_property("type_code", "")
				if !type in ["hero", "ally", "minion", "villain"]:
					owner = _get_identity_from_script(script)
				var script_modifications = {
					"tags" : ["retaliate", "Scripted"],
					"subjects": [owner],
					"owner": card,
				}
				_add_receive_damage_on_stack(retaliate, script, script_modifications)
			var signal_details = {
				"attacker": script.owner,
				"target": card,
				"damage": damage_happened,
			}
			scripting_bus.emit_signal("attack_happened", script.owner, signal_details)
						
			if ("basic power" in tags):
				scripting_bus.emit_signal("basic_attack_happened", script.owner, signal_details)
		
			var stackEvent:SignalStackScript = SignalStackScript.new("defense_happened", card,  signal_details)
			gameData.theStack.add_script(stackEvent)
			#scripting_bus.emit_signal("defense_happened", card, signal_details)
			
		#check for death
		if damage_happened:
			scripting_bus.emit_signal("card_damaged", card, script.script_definition)

			var total_damage:int =  card.tokens.get_token_count("damage")
			var health = card.get_property("health", 0)

			if total_damage >= health:
				var card_dies_definition = {
					"name": "card_dies",
					"tags": ["receive_damage", "Scripted"] + script.get_property(SP.KEY_TAGS)
				}
				var trigger_details = script.trigger_details.duplicate(true)
				trigger_details["source"] = guidMaster.get_guid(script.owner)

				var card_dies_script:ScriptTask = ScriptTask.new(card, card_dies_definition, script.trigger_object, trigger_details)
				card_dies_script.subjects = [card]
				var task_event = SimplifiedStackScript.new(card_dies_script)
				gameData.theStack.add_script(task_event)
						
	return retcode

func _receive_threat(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): 
		if !script.subjects:
			return CFConst.ReturnCode.FAILED
		return retcode
	
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.retrieve_integer_property("amount")
	
	#consolidate subjects. If the same subject is chosen multiple times, we'll multipy the damage
	# e.g. Spider man gets 3*1 damage = 3 damage
	var consolidated_subjects:= {}
	#TODO BUG sometimes subjects contains a null card?
	for card in script.subjects:
		if !consolidated_subjects.has(card):
			consolidated_subjects[card] = 0
		consolidated_subjects[card] += 1
	
	#TODO BUG sometimes subjects contains a null card?
	for card in consolidated_subjects.keys():
		var multiplier = consolidated_subjects[card]
		
		retcode = card.tokens.mod_token("threat",
				amount * multiplier,false,costs_dry_run(), tags)	
						
	return retcode

func move_token_to(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
	if (costs_dry_run()): 
		return retcode
	
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.retrieve_integer_property("amount")
	var token_name = script.get_property("token_name")
	
	var target = script.subjects[0]
	
	var source_str = script.get_property("source", "")
	var sources = SP.retrieve_subjects(source_str, script)	
	var source = sources[0] if sources else null
	if !source:
		return CFConst.ReturnCode.FAILED
		
	var tokens_amount = source.tokens.get_token_count(token_name)
	amount = min(tokens_amount, amount)
	
	source.tokens.mod_token(token_name, -amount)
	
	if token_name == "damage" and ("attack" in tags):
		return attack(script)
	else:
		target.tokens.mod_token(token_name, amount)
						
	return retcode

func add_threat(script: ScriptTask) -> int:
	return _receive_threat(script)

func prevent(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	

	if script.script_definition.has("amount"): #this is a partial prevention effect
		var stack_object = gameData.theStack.find_last_event_before_me(script)
		if (!stack_object):	
			return CFConst.ReturnCode.FAILED
		
		gameData.theStack.modify_object(stack_object, script)		
	else:	
		#Find the event on the stack and remove it
		#TOdo take into action subject, etc...
		var _result = gameData.theStack.delete_last_event(script)
		
	return retcode		
	

func replacement_effect(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	
	
	var subject = script.get_property("subject", SP.KEY_SUBJECT_V_INTERUPTED_EVENT)
	#Find the event on the stack and modifiy it
	#TOdo take into action subject, etc...
	match subject:
		SP.KEY_SUBJECT_V_INTERUPTED_EVENT:
			var stack_object = gameData.theStack.find_last_event_before_me(script)
			if (!stack_object):	
				return CFConst.ReturnCode.FAILED
			
			gameData.theStack.modify_object(stack_object, script)
		SP.KEY_SUBJECT_V_CURRENT_ACTIVATION:
			var activation_script = script.owner.get_current_activation_details()
			if !activation_script:
				return CFConst.ReturnCode.FAILED
			var stack_object = SimplifiedStackScript.new(activation_script)	
			if (!stack_object):	
				return CFConst.ReturnCode.FAILED
			#this works because SimplifiedStackScript does not create a copy of the script
			#so it lets us manipulate it directly
			gameData.theStack.modify_object(stack_object, script)		
		_: #unsupported
			pass
		
	
	return retcode					

func ready_card(script: ScriptTask) -> int:
	var retcode: int
	# We inject the tags from the script into the tags sent by the signal
	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS)
	for card in script.subjects:
		retcode = card.readyme(false, true, costs_dry_run(), tags)
	return(retcode)

func exhaust_card(script: ScriptTask) -> int:
	var retcode: int
	# We inject the tags from the script into the tags sent by the signal
	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS)
	for card in script.subjects:
		retcode = card.exhaustme(false, true, costs_dry_run(), tags)
	return(retcode)

func discard(script: ScriptTask):
	var retcode = CFConst.ReturnCode.FAILED

	if (costs_dry_run()): #Shouldn't be allowed as a cost?	
		if script.subjects:
			return CFConst.ReturnCode.CHANGED
		return CFConst.ReturnCode.FAILED
	
	for card in script.subjects:
		card.discard()
		retcode = CFConst.ReturnCode.CHANGED
	return retcode	

static func simple_discard_task(target_card):	
	var discard_script  = {
				"name": "discard",
	}
	var discard_task = ScriptTask.new(target_card, discard_script, target_card, {})	
	discard_task.subjects = [target_card]
	var task_event = SimplifiedStackScript.new(discard_task)
	return task_event

#adds an attacker
func enemy_attacks_you(script: ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.FAILED


	for card in script.subjects:
		gameData.add_enemy_activation(card, "attack", script)
		retcode = CFConst.ReturnCode.CHANGED
	return retcode

func villain_attacks_you(script:ScriptTask) ->int:
	script.subjects = [ gameData.get_villain()]
	return enemy_attacks_you(script)

func villain_and_enemies_attack_you(script:ScriptTask) ->int:
	var hero = _get_identity_from_script(script)
	script.subjects = [ gameData.get_villain()] + gameData.get_minions_engaged_with_hero(hero.get_controller_hero_id())
	return enemy_attacks_you(script)

func _modify_script(script, modifications:Dictionary = {}, script_definition_replacement_mode = "add"):
		var output = duplicate_script(script)
		var modified_script_definition = modifications.get("script_definition", {})

		if (script_definition_replacement_mode == "add"):
			for k in modified_script_definition.keys():
				output.script_definition[k] = modified_script_definition[k]			
		else: #replace entirely
			output.script_definition = modified_script_definition

		var add_tags = modifications.get("additional_tags", [])
		if add_tags:
			output.script_definition["tags"] = script.script_definition.get("tags", []) + add_tags
			
		output.subjects = modifications.get("subjects", output.subjects)
		output.owner =  modifications.get("owner", output.owner)	
		
		if modified_script_definition.has("name"):
			output.script_name = modified_script_definition["name"]
			
		return output

func _add_receive_damage_on_stack(amount, original_script, modifications:Dictionary = {}):		
		var receive_damage_script_definition = {
			"name": "receive_damage",
			"amount": amount,
		}
		modifications["script_definition"] =  receive_damage_script_definition	
		var receive_damage_script = _modify_script(original_script, modifications, "replace")
	
		var task_event = SimplifiedStackScript.new(receive_damage_script)
		gameData.theStack.add_script(task_event)	

func _add_receive_threat_on_stack(amount, original_script, modifications:Dictionary = {}):		
		var receive_threat_script_definition = {
			"name": "add_threat",
			"amount": amount,
		}
		modifications["script_definition"] =  receive_threat_script_definition	
		var receive_threat_script = _modify_script(original_script, modifications, "replace")
	
		var task_event = SimplifiedStackScript.new(receive_threat_script)
		gameData.theStack.add_script(task_event)
	
#the ability that is triggered by enemy_attack
func enemy_attack(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		for card in script.subjects:
			if (not card.can_defend()):
				return CFConst.ReturnCode.FAILED
		return retcode
		
	var attacker = script.owner
	var defender = script.subjects[0] if script.subjects else null
		
	if defender:
		defender.exhaustme()

	
	attacker.activity_script = script
	return retcode

func enemy_boost(boost_script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	#reveal one boost card
	var attacker = boost_script.owner
	#the boost_script passed here is not super useful,
	#except to retrieve the attacker's ongoing real attack script
	var script = attacker.activity_script
	
	var script_definition = script.script_definition
	if !script_definition.has("boost"):
		script_definition["boost"] = []
	
	
	var boost_card = attacker.next_boost_card_to_reveal()
	
	if !boost_card:
		return CFConst.ReturnCode.OK
		
	boost_card.set_current_activation(script)	
	boost_card.set_is_faceup(true)
	var boost_amount = boost_card.get_property("boost",0)
	if boost_amount:
		boost_card.hint("+" + str(boost_amount), Color8(100,255,150), {"position": "bottom_right"})
	script_definition["boost"].append(boost_amount)
	
	var func_return = boost_card.execute_scripts(boost_card, "boost")
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()	
	return retcode

func enemy_attack_damage(_script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	var attacker = _script.owner
	#the _script passed here is not super useful,
	#except to retrieve the attacker's ongoing real attack script
	var script = attacker.activity_script

	var defender = script.subjects[0] if script.subjects else null
	var my_hero:Card = gameData.get_current_target_hero()
	
	var amount = attacker.get_property("attack", 0)
	var boost_data = script.get_property("boost", [])
	for boost_amount in boost_data:
		amount+= boost_amount	
			
	if defender:
		var damage_reduction = defender.get_property("defense", 0)
		amount = max(amount-damage_reduction, 0)		
	else:
		script.subjects.append(my_hero)
		#TODO add variable stating attack was undefended
		
	var overkill_amount = 0
	
	if amount:
		var script_modifications = {
			"additional_tags" : ["attack", "Scripted"],
		}
		_add_receive_damage_on_stack (amount, script, script_modifications)
	
	if defender and attacker.get_property("overkill", 0):
		var defender_type = defender.get_property("type_code")
		if defender_type in ["minion", "ally"]:
			overkill_amount = amount - defender.get_remaining_damage()
			overkill_amount = max(0, overkill_amount)

			var script_modifications = {
				"tags" : ["Scripted", "overkill"], #notably, overkill isn't an attack
				"subjects": [my_hero]
			}
			_add_receive_damage_on_stack (overkill_amount, script, script_modifications)
	
	#We're done, cleanup attacker script
	attacker.activity_script = null		
	return retcode

func undefend(script: ScriptTask) -> int:
	return enemy_attack(script)
	
func consequential_damage(script: ScriptTask) -> int:	
	var retcode: int = CFConst.ReturnCode.OK
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var tags = script.get_property(SP.KEY_TAGS, [])
	if !("basic power" in tags):
		return CFConst.ReturnCode.OK

	var owner = script.owner
	var damage = owner.get_property("attack_cost", 0)
	
	match script.script_name:
		"thwart":
			damage = owner.get_property("thwart_cost",0)

	var additional_task := ScriptTask.new(
		script.owner,
		{"name": "receive_damage", "amount" : damage, "subject" : "self"}, 
		script.trigger_object,
		script.trigger_details)
	additional_task.prime([], CFInt.RunType.NORMAL,0, []) #TODO gross
	retcode = receive_damage(additional_task)
	
	return CFConst.ReturnCode.CHANGED

func commit_scheme(script: ScriptTask):
	var retcode: int = CFConst.ReturnCode.CHANGED
			
	#TODO special case villain needs to receive a boost card
	var owner = script.owner
	
	var main_scheme = gameData.find_main_scheme()
	if (!main_scheme):
		return CFConst.ReturnCode.FAILED

	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	script.subjects = [main_scheme]

	owner.activity_script = script
	return retcode

func enemy_scheme_threat(_script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	var attacker = _script.owner
	#the _script passed here is not super useful,
	#except to retrieve the attacker's ongoing real attack script
	var script = attacker.activity_script


	var scheme_amount = attacker.get_property("scheme", 0)
	var boost_data = script.get_property("boost", [])
	for boost_amount in boost_data:
		scheme_amount+= boost_amount	
				
	var prevent = script.retrieve_integer_property("prevent_amount", 0)	
	if prevent:
		scheme_amount-= prevent
	
	scheme_amount = 0 if scheme_amount <0 else scheme_amount
	if !scheme_amount:
		return CFConst.ReturnCode.OK
	
	if costs_dry_run():
		return retcode
		
	var script_modifications = {
		"additional_tags" : ["scheme", "Scripted"],
	}
	_add_receive_threat_on_stack (scheme_amount, script, script_modifications)
	attacker.activity_script = null
	
	return retcode

func enemy_schemes(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	retcode = CFConst.ReturnCode.FAILED
	for card in script.subjects:
		retcode = CFConst.ReturnCode.CHANGED
		gameData.add_enemy_activation(card, "scheme")
	return retcode	

func remove_threat(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var modification = script.retrieve_integer_property("amount")

	for card in script.subjects:
		retcode = card.remove_threat(modification, script)
	
		if "side_scheme" == card.properties.get("type_code", "false"):
			if card.get_current_threat() == 0:
				#card.die(script)
	
				var card_dies_definition = {
					"name": "card_dies",
					"tags": ["remove_threat", "Scripted"] + script.get_property(SP.KEY_TAGS)
				}
				var trigger_details = script.trigger_details.duplicate(true)
				trigger_details["source"] = guidMaster.get_guid(script.owner)

				var card_dies_script:ScriptTask = ScriptTask.new(card, card_dies_definition, script.trigger_object, trigger_details)
				card_dies_script.subjects = [card]

				var task_event = SimplifiedStackScript.new( card_dies_script)
				gameData.theStack.add_script(task_event)		

	return retcode	
	
func thwart(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var owner = script.owner
	#we can provide a thwart amount in the script,
	#otherwise we use the thwart property if the script owner is a friendly character
	var modification = script.retrieve_integer_property("amount")
	if !modification:
		modification = owner.get_property("thwart", 0)

	if !modification:
		modification = 0

	var type = owner.get_property("type_code", "")
	if !type in ["hero", "ally"]:
		owner = _get_identity_from_script(script)


	var confused = owner.tokens.get_token_count("confused")
	if (confused):
		owner.tokens.mod_token("confused", -1)
	else:
		for card in script.subjects:
			retcode = card.remove_threat(modification)
			if "side_scheme" == card.properties.get("type_code", "false"):
				if card.get_current_threat() == 0:
					#card.die(script)
		
					var card_dies_definition = {
						"name": "card_dies",
						"tags": ["remove_threat", "Scripted"] + script.get_property(SP.KEY_TAGS)
					}
					var trigger_details = script.trigger_details.duplicate(true)
					trigger_details["source"] = guidMaster.get_guid(script.owner)

					var card_dies_script:ScriptTask = ScriptTask.new(card, card_dies_definition, script.trigger_object, trigger_details)
					card_dies_script.subjects = [card]

					var task_event = SimplifiedStackScript.new(card_dies_script)
					gameData.theStack.add_script(task_event)
		consequential_damage(script)
		scripting_bus.emit_signal("thwarted", owner, {"amount" : modification, "target" : script.subjects[0]})
	
	return retcode	

func heal(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.FAILED
	if (costs_dry_run()):
		retcode = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
	var amount = script.script_definition["amount"]	
		
	for subject in script.subjects:
		if (costs_dry_run()): #healing as a cost can be used for "is_else" conditions, when saying "if no healing happened,..."
			if (!subject.can_heal(amount)):
				return CFConst.ReturnCode.FAILED #if at least one subject can't pay, we fail it
		else:		
			var result = subject.heal(amount)
			if (result == CFConst.ReturnCode.CHANGED): #if at least one healing happened, the result is a change
				retcode = CFConst.ReturnCode.CHANGED

	return retcode

func cancel_current_encounter(script: ScriptTask) -> int:
	if (costs_dry_run()): #not allowed ?
		return CFConst.ReturnCode.CHANGED
			
	gameData.cancel_current_encounter()
	return CFConst.ReturnCode.CHANGED

func deal_encounter(script: ScriptTask) -> int:

	var retcode: int = CFConst.ReturnCode.FAILED

	if (costs_dry_run()): #not allowed ?
		return CFConst.ReturnCode.CHANGED

	var owner = script.owner
	var owner_hero_id = owner.get_controller_hero_id()

	#TODO
	#If not specified, Probably need to deal to the first player instead of hero #1
	if !owner_hero_id:
		owner_hero_id = 1
	
	var immediate_reveal = script.script_definition.get("immediate_reveal", false)
	
	for subject in script.subjects:
		match subject.get_property("type_code", ""):
			"hero": #subject is a hero, we deal them an encounter from the deck
				gameData.deal_one_encounter_to(subject.get_controller_hero_id, immediate_reveal)
			_: #other uses cases, we assume that's the card we want to reveal
				gameData.deal_one_encounter_to(owner_hero_id, immediate_reveal, subject)
		
		retcode = CFConst.ReturnCode.CHANGED

	return retcode

func sequence(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	var ability = script.get_property("sequence_ability", "")
	if !ability:
		return CFConst.ReturnCode.FAILED
				
	if !script.subjects:
		return CFConst.ReturnCode.FAILED

	if (costs_dry_run()): #not allowed ?
		return retcode

	gameData.start_play_sequence(script.subjects, ability, self)


	
	return retcode	

func reveal_encounter(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	if (costs_dry_run()): #not allowed ?
		return retcode
	var owner = script.owner
	var hero_id = owner.get_controller_hero_id()
	
	#If we passed a subject card, that's what we try to reveal
	if script.subjects:
		gameData.deal_one_encounter_to(hero_id, true, script.subjects[0])
		return  CFConst.ReturnCode.CHANGED
	
	#else if there is a source container, we get the top card from that	
	var src_container = script.get_property(SP.KEY_SRC_CONTAINER)
	src_container = cfc.NMAP.get(src_container, null)
	if src_container:
		var card = src_container.get_top_card()
		if card:
			gameData.deal_one_encounter_to(hero_id, true, card)
			return  CFConst.ReturnCode.CHANGED
		return  CFConst.ReturnCode.FAILED
		
	#finally, if nothing is specified, we get a regular encounter from the
	#villain deck
	gameData.reveal_current_encounter(hero_id)

	return CFConst.ReturnCode.CHANGED

func reveal_encounters(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	if !script.subjects:
		return CFConst.ReturnCode.FAILED

	if (costs_dry_run()): #not allowed ?
		return retcode
	var owner = script.owner
	var hero_id = owner.get_controller_hero_id()
	
	for subject in script.subjects:
		gameData.deal_one_encounter_to(hero_id, true, subject)
	return  CFConst.ReturnCode.CHANGED
	
func surge(script: ScriptTask) -> int:

	var retcode: int = CFConst.ReturnCode.CHANGED

	if (costs_dry_run()): #not allowed ?
		return retcode
	var owner = script.owner
	var hero_id = owner.get_controller_hero_id()
	gameData.deal_one_encounter_to(hero_id, true)

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
	
	if (!script.subjects):
		script.subjects =  [_get_identity_from_script(script)]
	
	for subject in script.subjects: #should be really one subject only, generally
		var hero = subject
		#todo check that subject is indeed a hero
		if is_manual and !hero.can_change_form():
			return CFConst.ReturnCode.FAILED
		
		if (!costs_dry_run()):
		#Get my current zone
			hero.change_form(is_manual)

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
			if (new_grid_name == current_grid_name):
				continue
			var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(new_grid_name)
			var slot: BoardPlacementSlot
			if grid:
				slot = grid.find_available_slot()			
				this_card.move_to(cfc.NMAP.board, -1, slot)
				retcode = CFConst.ReturnCode.CHANGED	

	return retcode

#temporarily change controller id of a card
#useful for obligations
func change_controller_hero(script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	var new_controller_id = 0;
		
	var target_identity = script.get_property("target_identity", "")
	if (typeof(target_identity) == TYPE_STRING):
		var new_hero = cfc.NMAP.board.find_card_by_name(target_identity, true)
		if new_hero:
			new_controller_id = new_hero.get_controller_hero_id()
	else:
		#not supported yet
		retcode = CFConst.ReturnCode.FAILED
	
	if new_controller_id <= 0:
		retcode = CFConst.ReturnCode.FAILED
	else:
		for card in script.subjects:
			card.set_controller_hero_id(new_controller_id)
		retcode = CFConst.ReturnCode.CHANGED
		
	return retcode	

func reveal_nemesis (script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var my_hero_card = _get_identity_from_script(script)
	var my_hero_id = my_hero_card.get_controller_hero_id()	
	var my_nemesis_set = my_hero_card.get_property("card_set_code","") + "_nemesis"

	var my_nemesis = null
	var my_nemesis_scheme = null
	var other_nemesis_cards = []	
	var do_surge = false
	
	for card in cfc.NMAP["set_aside"].get_all_cards():
		if card.get_property("card_set_code", "") == my_nemesis_set:
			match card.get_property("type_code"):
				"minion":
					my_nemesis = card
				"side_scheme":
					my_nemesis_scheme = card
				_:
					other_nemesis_cards.append(card)			
	
	if (my_nemesis):
		gameData.deal_one_encounter_to(my_hero_id, true, my_nemesis)	
	else:
		do_surge = true
	
	if (my_nemesis_scheme):
		gameData.deal_one_encounter_to(my_hero_id, true, my_nemesis_scheme)	
		
	for card in other_nemesis_cards:
		card.move_to(cfc.NMAP["deck_villain"])
	
	cfc.NMAP["deck_villain"].shuffle_cards()	
	
	if (do_surge):
		return surge(script)

	return retcode	

#action can only be played during player turn, while nothing is on the stack
#interrupt can be played pretty much anytime
#resource can only be used to pay for something
const _tags_to_tags: = {
	"hero_action" : ["hero_form", "action_ability"],
	"hero_interrupt": ["hero_form", "interrupt_ability"],
	"hero_resource": ["hero_form", "resource_ability"],
	"alter_ego_action": ["alter_ego_form", "action_ability"], 
	"alter_ego_interrupt": ["alter_ego_form", "interrupt_ability"], 
	"alter_ego_resource": ["alter_ego_form", "resource_ability"],
	"as_action": ["action_ability"] 	
}

#used only as a cost, checks a series of constraints to see if a card can be played or not
func constraints(script: ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.CHANGED	
	
	var this_card = script.owner
	var my_hero_id = this_card.get_controller_hero_id()
	var my_hero_card = gameData.get_identity_card(my_hero_id)
	
	if !my_hero_card:
		cfc.LOG("{scriptEngine}{error}: missing hero card in constraints check")
		cfc.LOG_DICT(script.serialize_to_json())
	
	var _tags: Array = script.get_property(SP.KEY_TAGS)
	
	var tags = []
	for i in range (_tags.size()):
		if _tags_to_tags.has(_tags[i]):
			tags += _tags_to_tags[_tags[i]]
		else:
			tags.append(_tags[i])
	
	for tag in tags:
		match tag:
			"hero_form" :
				if !my_hero_card or !my_hero_card.is_hero_form():
					return CFConst.ReturnCode.FAILED
			"alter_ego_form":
				if !my_hero_card or !my_hero_card.is_alter_ego_form():
					return CFConst.ReturnCode.FAILED
			"action_ability":
				if gameData.phaseContainer.current_step != CFConst.PHASE_STEP.PLAYER_TURN:
					return 	CFConst.ReturnCode.FAILED
				if cfc.is_modal_event_ongoing():
					return 	CFConst.ReturnCode.FAILED			
	
	#Max per player rule to play
	var max_per_hero = script.get_property("max_per_hero", 0)
	if max_per_hero:
		var already_in_play = cfc.NMAP.board.count_card_per_player_in_play(this_card, my_hero_id)
		if already_in_play >= max_per_hero:
			return 	CFConst.ReturnCode.FAILED			

	var constraints: Array = script.get_property("constraints", [])
	for constraint in constraints:
		var result = cfc.ov_utils.func_name_run(this_card, constraint["func_name"], constraint["func_params"])
		if !result:
			return CFConst.ReturnCode.FAILED

	return retcode

func temporary_effect(script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var temporary_script = script.get_property("effect", {})
	var end_condition = script.get_property("end_condition", "")

	gameData.theGameObserver.add_script(script, temporary_script, end_condition)
	
	return retcode


func add_script(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	var subscript = script.get_property("script", {})
	var end_condition = script.get_property("end_condition", "")
	var subjects = script.subjects
	
	var this_card = script.owner
	var my_hero_id = this_card.get_controller_hero_id()
	
	for subject in subjects:
		var subscript_id = subject.add_extra_script( subscript, my_hero_id)
		if (end_condition):
				gameData.theGameObserver.add_script_removal_effect(script, subject, subscript_id, end_condition)
	
	return retcode		

func message(script: ScriptTask) -> int:
	var message = script.script_definition["message"]
	var msg_dialog:AcceptDialog = AcceptDialog.new()
	msg_dialog.window_title = message
	cfc.NMAP.board.add_child(msg_dialog)
	msg_dialog.popup_centered()	
	
	return CFConst.ReturnCode.OK


#returns thecurrent hero id based on a script.
#typically that's the hero associated to the script owner
static func get_hero_id_from_script(script):
	var this_card = script.owner
	var my_hero_id = this_card.get_controller_hero_id()
	return my_hero_id	
	
#returns thecurrent hero card based on a script.
#typically that's the hero associated to the script owner
func _get_identity_from_script(script):
	var my_hero_id = get_hero_id_from_script(script)
	if my_hero_id:
		var my_hero_card = gameData.get_identity_card(my_hero_id)	
		return my_hero_card
	return null
	
static func duplicate_script(script):
	var result = ScriptTask.new(script.owner, script.script_definition, script.trigger_object, script.trigger_details)

	if (script.subjects):
		result.subjects = script.subjects.duplicate()

	result.is_primed = script.is_primed
	result.is_valid = script.is_valid

	result.requested_subjects = script.requested_subjects

	if (script.prev_subjects):
		result.prev_subjects = script.prev_subjects.duplicate()

	result.is_accepted = script.is_accepted
	result.is_skipped = script.is_skipped
	if (script.process_result):
		result.process_result = script.process_result.duplicate
	
	return result



# Extendable function to perform extra checks on the script
# according to game logic
func _pre_task_prime(script: ScriptTask) -> void:
	var previous_hero = script.prev_subjects[0] if script.prev_subjects else null
	var script_definition = script.script_definition	
	var previous_hero_id = 0
	if previous_hero:
		previous_hero_id = previous_hero.get_controller_hero_id()
	
	var owner = script.owner
	var controller_hero_id = owner.get_controller_hero_id()
	
		
	for group in CFConst.ALL_GROUPS:
		script_definition = WCUtils.search_and_replace(script_definition, group + "_my_hero", group+str(controller_hero_id), true)		
		script_definition = WCUtils.search_and_replace(script_definition, group + "_first_player", group+str(gameData.first_player_hero_id()), true)	
		script_definition = WCUtils.search_and_replace(script_definition, group + "_previous_subject", group+str(previous_hero_id), true)	


