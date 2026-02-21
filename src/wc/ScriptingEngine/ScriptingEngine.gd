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
	if !script.subjects:
		var _tmp = 1
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
	
	return retcode	

#override for parent
func move_card_to_board(script: ScriptTask) -> int:

	if !script.subjects:
		return CFConst.ReturnCode.FAILED

	if (costs_dry_run()): 
		return .move_card_to_board(script)

	#TODO might be better to be able to duplicate scriptTasks ?
	#var modified_script:ScriptTask = script.duplicate

	var backup:Dictionary = script.script_definition.duplicate()
	var subjects = script.subjects.duplicate()
	
	var result = CFConst.ReturnCode.FAILED

	for card in subjects:
	
		script.script_definition = backup.duplicate()

		if card.canonical_name == "Garm":
			var _tmp =1

		var override_properties = script.get_property("set_properties", {})
	
		var subject = card
		script.subjects = [subject]
		#we force a grid container in all cases
		if !script.get_property("grid_name"):
			var type_code = override_properties.get("type_code", subject.get_property("type_code"))
			if CFConst.TYPECODE_TO_GRID.has(type_code):
				script.script_definition["grid_name"] = CFConst.TYPECODE_TO_GRID[type_code]

	
		#Replace all occurrences of un_numberd "discard", etc... with the actual id
		#This ensures we use e.g. the correct discard pile, etc...
		var owner_hero_id = script.trigger_details.get("override_controller_id")
		if !owner_hero_id and subject:
			owner_hero_id = subject.get_controller_hero_id()
		if !owner_hero_id:
			owner_hero_id = script.owner.get_owner_hero_id()
		if !owner_hero_id:
			owner_hero_id = gameData.get_villain_current_hero_target()
		
		var replacements = {}	
		for zone in CFConst.HERO_GRID_SETUP:
			replacements[zone] = zone+str(owner_hero_id)

#		var zone_replacements = [
#	#		{"from":"_my_hero" , "to": controller_hero_id },
#			{"from":"_first_player" , "to": gameData.first_player_hero_id() },		
#	#		{"from":"_previous_subject" , "to": previous_hero_id},
#	#		{"from":"_current_hero_target" , "to": current_hero_target},
#	#		{"from":"_event_source_hero" , "to": event_source_hero_id},					
#		]
#
#		for zone in ["hand"] + CFConst.HERO_GRID_SETUP.keys() + CFConst.ALL_TYPE_GROUPS:
#			for replacement in zone_replacements:
#				var from_str = replacement["from"]
#				var to = replacement["to"]
#				if !to:
#					continue
#				replacements[zone + from_str] = zone+str(to)

			
		script.script_definition = WCUtils.search_and_replace_multi(script.script_definition, replacements, true)
	
		if card.is_boost():
			card.set_is_boost(false)
			card._clear_attachment_status()
			script.script_definition[SP.KEY_TAGS] = ["force_emit_card_moved_signal"] +  script.get_property(SP.KEY_TAGS)

		result = .move_card_to_board(script)
		if override_properties:
			var tags: Array = ["emit_signal"] + script.get_property(SP.KEY_TAGS)
			script.script_definition[SP.KEY_TAGS] = tags
			modify_properties(script)
	
	script.script_definition = backup
	return result


func shuffle_container(script) -> int:
	var dest_container_str = script.get_property(SP.KEY_DEST_CONTAINER).to_lower()
	var dest_container: CardContainer = cfc.NMAP.get(dest_container_str, null)
	if not dest_container:
		var _error = 1
		return CFConst.ReturnCode.FAILED

	if (costs_dry_run()): 
		return CFConst.ReturnCode.CHANGED		
		
	dest_container.shuffle_cards()
	return CFConst.ReturnCode.CHANGED
	
func shuffle_card_into_container(script:ScriptTask) -> int:
	var result = move_card_to_container(script)
	shuffle_container(script)
	
	return result
	
#override for parent
func move_card_to_container(script: ScriptTask) -> int:
	#TODO might be better to be able to duplicate scriptTasks ?
	#var modified_script:ScriptTask = script.duplicate
	var backup:Dictionary = script.script_definition.duplicate()
	
	var owner = script.owner
	var owner_hero_id = owner.get_owner_hero_id()
	var controller_hero_id = owner.get_controller_hero_id()
	
	var previous_hero = script.prev_subjects[0] if script.prev_subjects else null
	var previous_hero_id = 0
	if previous_hero:
		previous_hero_id = previous_hero.get_controller_hero_id()
	
	var enemy_target_hero_id = gameData.get_villain_current_hero_target()
	var _replacements = [
		{"from":"" , "to": owner_hero_id },
		{"from":"_my_hero" , "to": controller_hero_id },
		{"from":"_first_player" , "to": gameData.first_player_hero_id() },
		{"from":"_previous_subject" , "to": previous_hero_id},
		{"from":"_current_hero_target" , "to": enemy_target_hero_id},			
	]

	var more_replacements = script.get_property("zone_name_replacement", {})
	for replacement in more_replacements:
		var key = replacement
		var value = script.retrieve_integer_subproperty(key, more_replacements, 0)
		_replacements.append ({"from" : "_" + key, "to": value})


	var replacements = {}

	for zone in ["hand"] + CFConst.HERO_GRID_SETUP.keys():
		for replacement in _replacements:
			var from_str = replacement["from"]
			var to = replacement["to"]
			if !to:
				to = enemy_target_hero_id
			replacements[zone + from_str] = zone+str(to)
			
	script.script_definition = WCUtils.search_and_replace_multi(script.script_definition, replacements, true)	
	
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

	if script.owner.get_property("cannot_play", 0, true):
		return CFConst.ReturnCode.FAILED

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

	var stackEvent:SignalStackScript = SignalStackScript.new("card_played", script.owner, {})
	gameData.theStack.add_script(stackEvent)		
#	scripting_bus.emit_signal("card_played", script.owner, script.script_definition)		
	return retcode	

func attack(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED

	var owner = script.owner	

	var type = owner.get_property("type_code", "")
	if !type in ["hero", "ally"]:
		owner = _get_identity_from_script(script)	
	
	if (costs_dry_run()):
		if owner.get_property("cannot_attack", 0, true):
			return CFConst.ReturnCode.FAILED 
		return retcode	


	
	var damage = 0
	if script.script_definition.has("amount"):
		damage = script.retrieve_integer_property("amount")
	else:
		damage = owner.get_property("attack", 0)

	if (owner.is_stunned()):
		owner.hint("Stunned!", Color8(50,200,50))
		owner.remove_stun()
		
	else:
		if (damage):	
			var script_modifications = {
				"additional_tags" : ["attack", "Scripted"],
			}
			_add_receive_damage_on_stack (damage, script, script_modifications)	
		
		var overkill = owner.get_property("overkill", 0, true) or (script.retrieve_integer_property("overkill"))	
		if overkill:
			var defender = script.subjects[0]
			var defender_type = defender.get_property("type_code")
			if defender_type in ["minion"]:
				var overkill_amount = damage - defender.get_remaining_damage()
				overkill_amount = max(0, overkill_amount)
				if overkill_amount:

					var script_modifications = {
						"tags" : ["Scripted", "overkill"], #notably, overkill isn't an attack
						"subjects": [gameData.get_villain()]
					}
					_add_receive_damage_on_stack (overkill_amount, script, script_modifications)
	
				
		consequential_damage(script)

	return retcode	

func character_died(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	
	for card in script.subjects:
		var type = card.get_property("type_code", "")
		if type:
			var stackEvent:SignalStackScript = SignalStackScript.new(type + "_died", card, script.trigger_details)
			gameData.theStack.add_script(stackEvent)			
		if type in ["minion", "villain"]: #TODO more generic way to handle this?
			var stackEvent:SignalStackScript = SignalStackScript.new("enemy_died", card, script.trigger_details)
			gameData.theStack.add_script(stackEvent)			

		card.post_death_move()
	
	return retcode

func deal_damage(script:ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.FAILED

	#I've had issues where computing the damage afterwards leads to inconsistency
	#calculating it now
	var base_amount = script.retrieve_integer_property("amount")

	if costs_dry_run():
		if !script.subjects:
			return CFConst.ReturnCode.FAILED
		if !base_amount:
			return CFConst.ReturnCode.FAILED
		return CFConst.ReturnCode.CHANGED
	#we split the damage into multiple "receive_damage" events, one per subject


	
	#consolidate subjects. If the same subject is chosen multiple times, we'll multipy the damage
	# e.g. Spider man gets 3*1 damage = 3 damage
	var consolidated_subjects:= {}
	#TODO BUG sometimes subjects contains a null card?
	for card in script.subjects:
		if !consolidated_subjects.has(card):
			consolidated_subjects[card] = 0
		consolidated_subjects[card] += 1
	
	for card in consolidated_subjects.keys():
		var multiplier = consolidated_subjects[card]
		var amount = base_amount * multiplier
		
		#it's ok to modify directly script here because 
		# _add_receive_damage_on_stack creates a copy
		script.subjects = [card]
	
		_add_receive_damage_on_stack(amount, script)
		retcode = CFConst.ReturnCode.CHANGED
#	return receive_damage(script)
	return retcode

func scheme_base_threat(script:ScriptTask) -> int:
	var scheme = script.owner
	var tags = script.get_property("tags", [])
	var base_threat = scheme.get_property("base_threat", 0)
	var retcode = scheme.tokens.mod_token("threat", base_threat, false,costs_dry_run(), tags)
	return retcode


func return_attachments_to(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	var host = script.owner
	
	if script.subjects:
		host = script.subjects[0]
	
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
		host.remove_attachment(card)
		card.current_host_card = null
		var destination = destination_prefix
		if script.get_property("return_to", "") == "owner":		
			var card_owner = card.get_owner_hero_id()
			if card_owner < 0:
				card_owner = 1 #TODO hack to avoid crashes
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
	
func return_attachments_to_owner(script: ScriptTask) -> int:
	script.script_definition["return_to"] = "owner"
	return return_attachments_to(script)	


func card_dies(script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.FAILED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
		
	for card in script.subjects:		
		card.die(script)
		retcode = CFConst.ReturnCode.CHANGED

	return retcode

static func calculate_damage(script:ScriptTask) -> int:
	if script.script_name != "receive_damage":
		return 0
		
	if !script.subjects:
		return 0

	#damages don't always come from an attacker, but it's easier to compute it here
	var attacker = script.owner
	var type = attacker.get_property("type_code", "")
	if !type in ["hero", "ally", "minion", "villain"]:
		attacker = _get_identity_from_script(script)
		
	var base_amount = script.retrieve_integer_property("amount")
	
	#consolidate subjects. If the same subject is chosen multiple times, we'll multipy the damage
	# e.g. Spider man gets 3*1 damage = 3 damage
	var consolidated_subjects:= {}
	for card in script.subjects:
		if !consolidated_subjects.has(card):
			consolidated_subjects[card] = 0
		consolidated_subjects[card] += 1
	
	#this is a for loop but in reality we return at the first iteration
	for card in consolidated_subjects.keys():
		var multiplier = consolidated_subjects[card]
		var amount = base_amount * multiplier
		
		if !amount:
			return 0
		
		if card.get_property("invincible", 0):
			return 0

		var tough = card.tokens.get_token_count("tough")
		if (amount and script.has_tag("piercing") or script.has_tag("ignore_tough")):
			tough = 0
		if tough: 
			return 0
			
		return amount
		
	return 0	
		

func receive_damage(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	

	#damages don't always come from an attacker, but it's easier to compute it here
	var attacker = script.owner
	var type = attacker.get_property("type_code", "")
	if !type in ["hero", "ally", "minion", "villain"]:
		attacker = _get_identity_from_script(script)
		
	var tags: Array = script.get_property(SP.KEY_TAGS) 
	var base_amount = script.retrieve_integer_property("amount")
	
	#consolidate subjects. If the same subject is chosen multiple times, we'll multipy the damage
	# e.g. Spider man gets 3*1 damage = 3 damage
	var consolidated_subjects:= {}
	#TODO BUG sometimes subjects contains a null card?
	for card in script.subjects:
		if !consolidated_subjects.has(card):
			consolidated_subjects[card] = 0
		consolidated_subjects[card] += 1
	
	for card in consolidated_subjects.keys():
		var multiplier = consolidated_subjects[card]
		var damage_happened = 0
		var amount = base_amount * multiplier
		if card.get_property("invincible", 0):
			continue

		if (amount and script.has_tag("piercing")):
			var tough = card.tokens.get_token_count("tough")
			card.tokens.mod_token("tough", 0, true)
			if tough:
				card.hint("Piercing!", Color8(255,50,50))
		var tough = card.tokens.get_token_count("tough")
		
		if script.has_tag("ignore_tough"):
			tough = 0

			
		if (amount and tough):
			card.tokens.mod_token("tough", -1)
			card.hint("Tough!", Color8(50,50,255))
		else:	
			retcode = card.tokens.mod_token("damage",
					amount,false,costs_dry_run(), tags)	
			if amount:
				card.hint(str(amount), Color8(255,50,50))
				damage_happened = amount
				if amount == 1:
					gameData.play_sfx("small_damage*")	
				elif amount > 6:
					gameData.play_sfx("massive_damage*")					
				elif amount > 3:
					gameData.play_sfx("large_damage*")
				else:
					gameData.play_sfx("damage*")	
				
				if ("stun_if_damage" in tags):
					card.tokens.mod_token("stunned",
						1,false,costs_dry_run(), tags)
				if ("exhaust_if_damage" in tags):
					card.exhaustme()
				if ("run_post_damage_script" in tags):
					script.owner.execute_scripts(script.owner, "post_damage_script", {})
						
				if ("1_threat_on_main_scheme_if_damage" in tags):
					var main_scheme = gameData.get_main_scheme()
					var task = ScriptTask.new(script.owner, {"name": "add_threat", "amount": 1}, card, {})
					task.subjects= [main_scheme]
					var stackEvent = SimplifiedStackScript.new(task)
					gameData.theStack.add_script(stackEvent)
				
				var if_damage: Dictionary = script.get_property("if_damage", {})
				if if_damage:
					var post_damage_trigger = if_damage["trigger"]
					var params = if_damage.get("func_params", {})
					params = WCUtils.search_and_replace(params, "damage", amount, true)
					var trigger_details = {}
					if params:
						trigger_details["additional_script_definition"] = params
					script.owner.execute_scripts(script.owner, post_damage_trigger, trigger_details)
		
		if ("attack" in tags):
			var signal_details = {
				"attacker": attacker,
				"target": card,
				"damage": damage_happened,
				"tags": tags,
			}
			gameData.theStack.add_script(SignalStackScript.new("attack_happened",  attacker,  signal_details))			
#			scripting_bus.emit_signal("attack_happened", script.owner, signal_details)
						
			if ("basic power" in tags):
				gameData.theStack.add_script(SignalStackScript.new("basic_attack_happened",  attacker,  signal_details))				
#				scripting_bus.emit_signal("basic_attack_happened", script.owner, signal_details)
		
			var stackEvent:SignalStackScript = SignalStackScript.new("defense_happened", card,  signal_details)
			gameData.theStack.add_script(stackEvent)
			#scripting_bus.emit_signal("defense_happened", card, signal_details)
			
		#check for death
		var lethal = false
		if damage_happened:
			scripting_bus.emit_signal("card_damaged", card, script.script_definition)

			lethal = card.check_death(script)

		if ("attack" in tags) and !lethal:
			#retaliate against an attack only if I didn't die
			var retaliate = card.get_property("retaliate", 0)
			if retaliate:
				if script.has_tag("ranged"):
					attacker.hint("Ranged!", Color8(50,50,255))
				else:
					card.hint("Retaliate!", Color8(255,50,50))
					var script_modifications = {
						"tags" : ["retaliate", "Scripted"],
						"subjects": [attacker],
						"owner": card,
					}
					_add_receive_damage_on_stack(retaliate, script, script_modifications)
							
	return retcode

func _receive_threat(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.retrieve_integer_property("amount")

	if (costs_dry_run()): 
		if !script.subjects:
			return CFConst.ReturnCode.FAILED
		if !amount:
			return CFConst.ReturnCode.FAILED
		return retcode
	
	#consolidate subjects. If the same subject is chosen multiple times, we'll multipy the damage
	# e.g. Spider man gets 3*1 damage = 3 damage
	var consolidated_subjects:= {}
	for card in script.subjects:
		if !consolidated_subjects.has(card):
			consolidated_subjects[card] = 0
		consolidated_subjects[card] += 1
	
	for card in consolidated_subjects.keys():
		var multiplier = consolidated_subjects[card]
		var threat_amount = amount * multiplier
		retcode = card.tokens.mod_token("threat",
				threat_amount,false,costs_dry_run(), tags)	
		if threat_amount:
			card.warning()				
			if "villain_step_one_threat" in script.get_property(SP.KEY_TAGS):
#			if gameData.phaseContainer.current_step == CFConst.PHASE_STEP.VILLAIN_THREAT:
				scripting_bus.emit_signal_on_stack("villain_step_one_threat_added", card, {"amount" : threat_amount})
					
			var if_threat: Dictionary = script.get_property("if_threat", {})
			if if_threat:
				var post_threat_trigger = if_threat["trigger"]
				var params = if_threat.get("func_params", {})
				params = WCUtils.search_and_replace(params, "threat", threat_amount, true)
				var trigger_details = {}
				if params:
					trigger_details["additional_script_definition"] = params
				script.owner.execute_scripts(script.owner, post_threat_trigger, trigger_details)
					
						
	return retcode

func add_threat(script: ScriptTask) -> int:
	return _receive_threat(script)

func tuck_under_card(script: ScriptTask) -> int:
	script.script_definition["tags"] = ["as_inactive_attachment"] + script.get_property(SP.KEY_TAGS)
	return attach_to_card(script)

func tuck_card_under_me(script: ScriptTask) -> int:
	script.script_definition["tags"] = ["as_inactive_attachment"] + script.get_property(SP.KEY_TAGS)
	return host_card(script)


func detach(script: ScriptTask) -> int:	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
	if costs_dry_run():
		return CFConst.ReturnCode.CHANGED
	
	var result = CFConst.ReturnCode.CHANGED
	for subject in script.subjects:
		result = subject.detach_self()
	
	return result
	
func attach_to_card(script: ScriptTask) -> int:
	#TOOD: disable_attach_trigger is a hack to address a card such as Zola's Mutate
	#which attaches an attachment to itself, overriding the attachment's own rules
	#for now we do this by "hiding" the attachment's "card_moved_to_board" script
	#temporarily while it's being attached, but that feels like it could lead to bugs	
	var backup = null

	if !script.subjects:
		return CFConst.ReturnCode.FAILED

	var host = script.subjects[0]
	if host.get_property("cannot_have_attachments", 0, true):
		return CFConst.ReturnCode.FAILED
	
	if !costs_dry_run():
		if script.has_tag("disable_attach_trigger"):
			backup = script.owner.scripts.get("card_moved_to_board", null)
			script.owner.scripts["card_moved_to_board"] = { "NOP": "NOP"}
	
	var result = .attach_to_card(script)
	
	if !costs_dry_run() and script.has_tag("disable_attach_trigger"):
		if backup:
			script.owner.scripts["card_moved_to_board"] = backup
		else:
			script.owner.scripts.erase("card_moved_to_board")
	
	return result

func host_card(script: ScriptTask) -> int:
	var backup = []
	#TOOD: disable_attach_trigger is a hack to address a card such as Zola's Mutate
	#which attaches an attachment to itself, overriding the attachment's own rules
	#for now we do this by "hiding" the attachment's "card_moved_to_board" script
	#temporarily while it's being attached, but that feels like it could lead to bugs
	if !costs_dry_run():
		if script.has_tag("disable_attach_trigger"):
			for subject in script.subjects:
				backup.append(subject.scripts.get("card_moved_to_board", null))
				subject.scripts["card_moved_to_board"] = { "NOP": "NOP"}
	
	var result = .host_card(script)
	
	if !costs_dry_run() and script.has_tag("disable_attach_trigger"):
		var i = 0
		for subject in script.subjects:
			var backup_value = backup[i]
			if backup_value:
				subject.scripts["card_moved_to_board"] = backup_value
			else:
				subject.scripts.erase("card_moved_to_board")
			i+= 1
	
	return result

func set_active_villain(script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
	if (costs_dry_run()): 
		return retcode	
		
	var villain = script.subjects[0]
	if villain.get_property("type_code") != "villain":
		villain = villain.get_associated_villain()
	
	gameData.set_active_villain(villain)
	return CFConst.ReturnCode.CHANGED
	
func conditional_script(script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	if (costs_dry_run()): 
		return retcode	

	var options = script.get_property("options")

	#erase inconvenient variables temporarily
	var backup = {
		"trigger_details": script.trigger_details
	}
	script.trigger_details = {}
	
	var at_least_one_condition_met = false
	
	for option in options:
		var subscript = script.get_sub_property("nested_tasks", option, {})
		var condition = script.retrieve_integer_subproperty("condition", option, 0)
		if condition:
			at_least_one_condition_met = true
			script.script_definition["nested_tasks"] = subscript
			nested_script(script)
	
	if !at_least_one_condition_met:
		var else_script = script.get_property("else")
		if else_script:
			script.script_definition["nested_tasks"] = else_script
			nested_script(script)
			
	script.trigger_details = backup["trigger_details"]
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
		script.script_definition["amount"] = amount
		return attack(script)
	else:
		target.tokens.mod_token(token_name, amount)
						
	return retcode


func prevent(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	

	if script.script_definition.has("amount"): #this is a partial prevention effect
		if typeof(script.script_definition["amount"]) == TYPE_STRING:
			if script.script_definition["amount"] == "all":
				script.script_definition["amount"] = 999 #TODO hack		
			else: #unsupported values
				script.script_definition["amount"] = 0 

	var subject_target = script.script_definition.get("subject")
	var amount_prevented = 0
	match subject_target:
		"current_activation":
			if script.script_definition.has("amount"): #this is a partial prevention effect		
				gameData.apply_mods_to_current_activity_script(script)	
			else:	
				#TODO
				#unsupported
				return CFConst.ReturnCode.FAILED
		_:
			if script.script_definition.has("amount"): #this is a partial prevention effect
				var stack_object = gameData.theStack.find_last_event_before_me(script)
				if (!stack_object):	
					return CFConst.ReturnCode.FAILED
				
				var results = gameData.theStack.modify_object(stack_object, script)
				if results.has("amount_prevented"):
					amount_prevented = results["amount_prevented"]		
			else:	
				#Find the event on the stack and remove it
				#TOdo take into action subject, etc...
				var _event = gameData.theStack.delete_last_event(script)
				#todo find amount prevented
			if amount_prevented:
				var trigger_details = script.trigger_details.duplicate()
				trigger_details["amount_prevented"] =  amount_prevented
				scripting_bus.emit_signal_on_stack("event_prevented", script.owner, trigger_details )
		
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
			var stack_object = script.trigger_details.get("stack_object", null) 
			var task_object = script.trigger_details.get("event_object", null)
			#var stack_object = gameData.theStack.find_last_event_before_me(script)
			if (!stack_object):	
				return CFConst.ReturnCode.FAILED
			
			gameData.theStack.modify_object(stack_object, script, task_object)
		SP.KEY_SUBJECT_V_CURRENT_ACTIVATION:
			var activation_script = script.owner.get_current_activation_details()
			if !activation_script:
				activation_script = gameData.get_latest_activity_script()
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
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
		
	# We inject the tags from the script into the tags sent by the signal
	var tags: Array = ["Scripted"] + script.get_property(SP.KEY_TAGS)
	for card in script.subjects:
		if card.get_property("cannot_ready_by_player_card", 0, true):
			retcode = CFConst.ReturnCode.FAILED
			continue
		retcode = card.readyme(false, true, costs_dry_run(), tags)
	return(retcode)

func exhaust_card(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
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

#adds attackers against you
func enemy_attacks_you(script: ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.FAILED

	#here we try to predict if the attack will actually happen, but we'll need something better,
	#signal based... (e.g. for Titania's Fury
	if (costs_dry_run()):
		if !script.subjects:
			return CFConst.ReturnCode.FAILED
		for card in script.subjects:
			if (!card.is_stunned()):
				retcode = CFConst.ReturnCode.CHANGED
		return retcode	

	var target_id = get_hero_id_from_script(script)

	for card in script.subjects:
		gameData.add_enemy_activation(card, "attack", script, target_id)
		retcode = CFConst.ReturnCode.CHANGED
	return retcode
	
func enemy_attacks_engaged_hero(script: ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.FAILED

	#here we try to predict if the attack will actually happen, but we'll need something better,
	#signal based... (e.g. for Titania's Fury
	
	var subjects = script.subjects
	var to_remove = []
	for card in subjects:
		var target = card.get_controller_hero_card()
		if !target:
			cfc.LOG("subject error in enemy_attacks_engaged_hero, no engaged hero for " + card.canonical_name)
			to_remove.append(card)
			continue
		if !target.is_hero_form():
			to_remove.append(card)

	for c in to_remove:
		subjects.erase(c)

	if !subjects:
		return CFConst.ReturnCode.FAILED
	
	if (costs_dry_run()):
		for card in script.subjects:
			if (!card.is_stunned()):
				return CFConst.ReturnCode.CHANGED
		return retcode	

	for card in subjects:
		var target_id = card.get_controller_hero_id()
		gameData.add_enemy_activation(card, "attack", script, target_id)
		retcode = CFConst.ReturnCode.CHANGED
	return retcode	
	
#adds one attacker against multiple heroes
func i_attack(script: ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.FAILED

	var attacker = script.owner

	#here we try to predict if the attack will actually happen, but we'll need something better,
	#signal based... (e.g. for Titania's Fury
	if (costs_dry_run()):
		if !script.subjects:
			return CFConst.ReturnCode.FAILED
		return CFConst.ReturnCode.CHANGED	

	for card in script.subjects:
		gameData.add_enemy_activation(attacker, "attack", script, card.get_controller_hero_id())
		retcode = CFConst.ReturnCode.CHANGED
	return retcode

func swap_villain(script:ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		retcode = CFConst.ReturnCode.FAILED

	if (costs_dry_run()):
		return retcode		
	
	var options = script.get_property("options", {})	
	var subject = script.subjects[0]
	gameData.swap_villain(gameData.get_active_villain(), subject.get_property("_code"), options)
	return retcode

func draw_boost_card(script:ScriptTask) ->int:
	var retcode = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		retcode = CFConst.ReturnCode.FAILED

	#TODO
	if (costs_dry_run()):
		return retcode	
	
	var amount = 1
	var script_amount = script.retrieve_integer_property("amount")
	if script_amount:
		amount = script_amount

	var src_container = script.get_property(SP.KEY_SRC_CONTAINER, "")
	
	for card in script.subjects:
		for i in amount:
			card.draw_boost_card(src_container )
			retcode = CFConst.ReturnCode.CHANGED
	return retcode
	
func villain_attacks_you(script:ScriptTask) ->int:
	script.subjects = [ gameData.get_villain()]
	return enemy_attacks_you(script)

func villain_and_enemies_attack_you(script:ScriptTask) ->int:
	var hero = _get_identity_from_script(script)
	script.subjects = [ gameData.get_villain()] + gameData.get_minions_engaged_with_hero(hero.get_controller_hero_id())
	return enemy_attacks_you(script)

	
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

	
	attacker.set_activity_script(script)
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

	var func_return = boost_card.execute_scripts(boost_card, "boost")
	if func_return is GDScriptFunctionState && func_return.is_valid():
		yield(func_return, "completed")	
	
	var boost_amount = boost_card.get_property("boost",0, true)
	boost_amount += cfc.NMAP.board.count_amplify_icons()
	if boost_amount:
		boost_card.hint("+" + str(boost_amount), Color8(100,255,150), {"position": "bottom_right"})
	script_definition["boost"].append(boost_amount)
	

	return retcode

#assigns defender to attack
#this only works if there isn't a defender chosen already,
#or if the defender was already the same as the one requested
func set_defender(script: ScriptTask) -> int:
	if !script.subjects:
		return CFConst.ReturnCode.FAILED

	var attack_script = gameData.get_latest_activity_script()
	if !attack_script:
		return CFConst.ReturnCode.FAILED

	var defender = script.subjects[0]
	
	if attack_script.subjects:
		if attack_script.subjects[0] != defender:
			return CFConst.ReturnCode.FAILED
		
	if costs_dry_run():
		return CFConst.ReturnCode.CHANGED
	
	attack_script.subjects[0] = defender
	return CFConst.ReturnCode.CHANGED
	


func enemy_attack_damage(_script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	var attacker = _script.owner
	var target_hero_id = _script.get_property("target_hero_id")	
	#the _script passed here is not super useful,
	#except to retrieve the attacker's ongoing real attack script
	var script = attacker.activity_script

	var defender = script.subjects[0] if script.subjects else null
	var my_hero:Card

	if target_hero_id:
		my_hero = gameData.get_identity_card(target_hero_id)
	else:
		my_hero = gameData.get_current_target_hero()
	
	var amount = attacker.get_property("attack", 0)
	var boost_data = script.get_property("boost", [])
	for boost_amount in boost_data:
		amount+= boost_amount	

	var prevent = script.retrieve_integer_property("prevent_amount", 0)	
	if prevent:
		amount-= prevent
	
	amount = 0 if amount <0 else amount

			
	if defender:
		var damage_reduction = defender.get_property("defense", 0)
		amount = max(amount-damage_reduction, 0)
		if damage_reduction and (amount == 0):
			gameData.play_sfx("hint_tough")	
	else:
		script.subjects.append(my_hero)
		script.script_definition["tags"].append("undefended")
		
	var overkill_amount = 0
	
#	if amount: #we want to send the damage even if zero, to trigger retaliate, etc...
	if true:
		var script_modifications = {
			"additional_tags" : ["attack", "Scripted"],
		}
		_add_receive_damage_on_stack (amount, script, script_modifications)
	
	if defender and (script.has_tag("overkill") or attacker.get_property("overkill", 0, true)):
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
	attacker.set_activity_script(null)		
	return retcode


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
			"source": original_script.get_property("source", owner),
			"tags": modifications.get("tags", original_script.get_property("tags", []))
		}
		
		modifications["script_definition"] =  receive_damage_script_definition	
		var receive_damage_script = _modify_script(original_script, modifications, "replace")
	
	
		var task_event = SimplifiedStackScript.new(receive_damage_script)
		gameData.theStack.add_script(task_event)	

func _add_remove_threat_on_stack(amount, original_script, modifications:Dictionary = {}):		
		var remove_threat_script_definition = {
			"name": "remove_threat",
			"amount": amount,
		}
		modifications["script_definition"] =  remove_threat_script_definition	
		var remove_threat_script = _modify_script(original_script, modifications, "replace")
	
		var task_event = SimplifiedStackScript.new(remove_threat_script)
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
		"thwart", "remove_threat":
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
			
	var owner = script.owner
	
	var main_scheme = gameData.find_main_scheme()
	if (!main_scheme):
		return CFConst.ReturnCode.FAILED

	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode

	script.subjects = [main_scheme]

	owner.set_activity_script(script)
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
	attacker.set_activity_script(null)
	
	return retcode

func enemy_activates(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
		
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
	retcode = CFConst.ReturnCode.FAILED
	for card in script.subjects:
		retcode = CFConst.ReturnCode.CHANGED
		gameData.add_enemy_activation(card, "activate")
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

	var amount = script.retrieve_integer_property("amount")

	for card in script.subjects:
		retcode = card.remove_threat(amount, script)
	
		if "side_scheme" == card.properties.get("type_code", "false"):
			card.check_scheme_defeat(script)


	consequential_damage(script)
	if (script.has_tag("basic power")):
		var signal_details = {
			"source": owner,
			"amount": amount,
		}
		gameData.theStack.add_script(SignalStackScript.new("basic_thwart_happened",  owner,  signal_details))				
		scripting_bus.emit_signal("thwarted", owner, {"amount" : amount, "target" : script.subjects[0]})

		

	return retcode	
	
func thwart(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	var owner = script.owner
	#we can provide a thwart amount in the script,
	#otherwise we use the thwart property if the script owner is a friendly character
	var amount = script.retrieve_integer_property("amount")
	if !amount:
		amount = owner.get_property("thwart", 0)

	if !amount:
		amount = 0

	var type = owner.get_property("type_code", "")
	if !type in ["hero", "ally"]:
		owner = _get_identity_from_script(script)
	
	if (costs_dry_run()):
		if owner.get_property("cannot_thwart", 0, true):
			return CFConst.ReturnCode.FAILED 
		return retcode	
	
	var confused = owner.tokens.get_token_count("confused")
	if (confused):
		owner.tokens.mod_token("confused", -1)
		owner.hint("Confused!", Color8(240,110,255))
	else:
		for card in script.subjects:
			var script_modifications = {
				"additional_tags" : ["thwart"],
				"subjects": [card],
			}			
			_add_remove_threat_on_stack(amount, script, script_modifications )
			retcode = CFConst.ReturnCode.CHANGED

	return retcode	


func add_properties_from(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.FAILED

	if !script.subjects:
		return CFConst.ReturnCode.FAILED	

	var properties_list= script.get_property("properties", [])
	if !properties_list:
		return CFConst.ReturnCode.FAILED	
	
	if (costs_dry_run()):
		return CFConst.ReturnCode.CHANGED
	
	if typeof(properties_list) == TYPE_STRING:
		properties_list = [properties_list]
	
	var target = script.owner
	
	var subjects = script.subjects
	for subject in subjects:
		var properties_to_copy = compile_property_list(subject, properties_list)
		for property in properties_to_copy:
			#we're intentionally not using get_properties here to not copy an altered value
			var value = subject.properties.get(property)
			match typeof(value):
				TYPE_INT:
					var v1 = target.properties.get(property, 0)
					target.properties[property] = v1 + value
				_:
					target.properties[property] = value					
				
	return retcode
	
func subtract_properties_from(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.FAILED

	if !script.subjects:
		return CFConst.ReturnCode.FAILED	

	var properties_list= script.get_property("properties", [])
	if !properties_list:
		return CFConst.ReturnCode.FAILED	
	
	if (costs_dry_run()):
		return CFConst.ReturnCode.CHANGED
	
	if typeof(properties_list) == TYPE_STRING:
		properties_list = [properties_list]
	
	var target = script.owner
	
	var subjects = script.subjects
	for subject in subjects:
		var properties_to_copy = compile_property_list(subject, properties_list)
		for property in properties_to_copy:
			#we're intentionally not using get_properties here to not copy an altered value
			var value = subject.properties.get(property)
			match typeof(value):
				TYPE_INT:
					var v1 = target.properties.get(property, 0)
					target.properties[property] = v1 - value
				TYPE_STRING:	
					target.properties[property] = "value"	
				_:
					target.properties.erase(property)					
				
	return retcode			

func compile_property_list(subject, properties_list):
	var properties_to_copy = []
	for property_name in properties_list:
		if property_name.ends_with("*"):
			property_name = property_name.substr(0, property_name.length() - 1)
			for property in subject.properties:
				if property.begins_with(property_name):
					properties_to_copy.append(property)
		else:
			if subject.properties.has(property_name):
				properties_to_copy.append(property_name)
	return properties_to_copy	
		
# Task for executing nested tasks
# This task will execute internal non-cost cripts accordin to its own
# nested cost instructions.
# Therefore if you set this task as a cost,
# it will modify the board, even if other costs of this script
# could not be paid.
# You can use [SP.KEY_ABORT_ON_COST_FAILURE](SP#KEY_ABORT_ON_COST_FAILURE)
# to control this behaviour better
func nested_script(script: ScriptTask) -> int:
	cfc.add_ongoing_process(self, "nested_script")
	var retcode : int = CFConst.ReturnCode.CHANGED
	var nested_task_list: Array = script.get_property(SP.KEY_NESTED_TASKS)
	
	var exec_config = {
		"trigger": "",
		"checksum": "nested_script",
		"rules": {},
		"action_name": "nested_script",
		"force_user_interaction_required": false
	}
	var card = script.owner
	var sceng = card.execute_chosen_script(nested_task_list, script.trigger_object, script.trigger_details, CFInt.RunType.NORMAL, exec_config)
	if sceng is GDScriptFunctionState && sceng.is_valid():		
		yield(sceng,"completed")
		
	cfc.remove_ongoing_process(self, "nested_script")	

	return(retcode)


func heal(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.FAILED
	if (costs_dry_run()):
		retcode = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
	var amount = script.retrieve_integer_property("amount")	
	var set_to_mod = script.get_property("set_to_mod", false)
		
	for subject in script.subjects:
		if (costs_dry_run()): #healing as a cost can be used for "is_else" conditions, when saying "if no healing happened,..."
			if (!subject.can_heal(amount)):
				return CFConst.ReturnCode.FAILED #if at least one subject can't pay, we fail it
		else:		
			var result = subject.heal(amount, set_to_mod)
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
	
	if !script.subjects:
		return retcode


	if (costs_dry_run()): 
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
			"hero", "alter_ego": #subject is a hero, we deal them an encounter from the deck
				gameData.deal_one_encounter_to(subject.get_controller_hero_id(), immediate_reveal)
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

	var amount = 1
	if script.script_definition.has("amount"):
		amount = script.retrieve_integer_property("amount")

	if !amount:
		return CFConst.ReturnCode.FAILED

	if (costs_dry_run()): #not allowed ?
		return retcode
	var owner = script.owner
	var hero_id = owner.get_controller_hero_id()
		
	for _i in amount:
		owner.hint("Surge", Color8(255,50,50))
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


func victory(script: ScriptTask) -> int:
	if (costs_dry_run()):
		return CFConst.ReturnCode.CHANGED	
	
	gameData.victory()
	return CFConst.ReturnCode.CHANGED

func defeat(script: ScriptTask) -> int:
	if (costs_dry_run()):
		return CFConst.ReturnCode.CHANGED	
	
	gameData.defeat()
	return CFConst.ReturnCode.CHANGED	

func flip_doublesided_card(script: ScriptTask) -> int:

		if (!script.subjects):	
			return CFConst.ReturnCode.FAILED
			
		if (costs_dry_run()):
			return CFConst.ReturnCode.CHANGED
		
		for subject in script.subjects:
			subject.flip_doublesided_card()
		
		return CFConst.ReturnCode.CHANGED


func change_secondary_form(script: ScriptTask) -> int:	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
		
	if costs_dry_run():
		return CFConst.ReturnCode.CHANGED

	var hero = null
	var my_hero_id = get_hero_id_from_script(script)
	if my_hero_id:
		hero = gameData.get_identity_card(my_hero_id)	
			
	var new_form = script.subjects[0] #the form to change to
		
	var family = new_form.get_property("form_family", "")
	if !family:
		return CFConst.ReturnCode.FAILED

	#get current form if any
	var current_form = cfc.NMAP.board.find_card_by_property("form_family", family, my_hero_id)
	
	if current_form == new_form:
		#no change
		return CFConst.ReturnCode.OK

	var signal_details = {
		"before": "",
		"after": new_form.canonical_name,
		"form_family": family,
	}
	
	#remove current form card
	if current_form:
		signal_details["before"] =  current_form.canonical_name
		current_form.move_to(cfc.NMAP["set_aside"])
	
	move_card_to_board(script)
	#new_form.move_to(cfc.NMAP.board)

	scripting_bus.emit_signal_on_stack("identity_changed_form", hero, signal_details)	

	return CFConst.ReturnCode.CHANGED
		
					
func change_form(script: ScriptTask) -> int:

	var form_family:String = script.get_property("form_family", "")
	if form_family:
		return change_secondary_form(script)

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

func remove_card_from_game (script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	
	if !script.subjects:
		return CFConst.ReturnCode.FAILED
	
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
		
	var set_aside = script.get_property("set_aside", true)
	for card in script.subjects:
		if set_aside:
			gameData.set_aside(card)
		else:
			card.get_parent().remove_child(card)
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
			var type_code = card.get_property("type_code")
			if type_code == "minion" and card.get_property("is_unique", false):
				my_nemesis = card
			elif type_code == "side_scheme":
				my_nemesis_scheme = card
			else:
				other_nemesis_cards.append(card)			
	
	
	if (my_nemesis_scheme):
		gameData.deal_one_encounter_to(my_hero_id, true, my_nemesis_scheme)	

	if (my_nemesis):
		gameData.deal_one_encounter_to(my_hero_id, true, my_nemesis)	
	else:
		do_surge = true

		
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
	"hero_response": ["hero_form", "interrupt_ability"],	
	"hero_resource": ["hero_form", "resource_ability"],
	"alter_ego_action": ["alter_ego_form", "action_ability"], 
	"alter_ego_interrupt": ["alter_ego_form", "interrupt_ability"], 
	"alter_ego_response": ["alter_ego_form", "interrupt_ability"],	
	"alter_ego_resource": ["alter_ego_form", "resource_ability"],
	"as_action": ["action_ability"] 	
}

#used only as a cost, checks a series of constraints to see if a card can be played or not
func constraints(script: ScriptTask) -> int:
	var retcode = CFConst.ReturnCode.CHANGED	
	

	var this_card = script.owner
	var my_hero_id = this_card.get_controller_hero_id()
	if !my_hero_id:
		#trying to activate on a villain card
		my_hero_id = gameData.get_current_local_hero_id()
	
	if script.subjects:
		my_hero_id = script.subjects[0]
		
		
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

	#Max per player rule to play with "play under any player's control"
	var max_per_hero_any = script.get_property("max_per_hero_any", 0)
	if max_per_hero_any:
		var already_in_play = cfc.NMAP.board.count_card_per_player_in_play(this_card)
		if already_in_play >= max_per_hero_any * gameData.get_team_size():
			return 	CFConst.ReturnCode.FAILED		

	var constraints: Array = script.get_property("constraints", [])
	for constraint in constraints:
		var result = cfc.ov_utils.func_name_run(this_card, constraint["func_name"], constraint["func_params"], script)
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
	var fetch_script = script.get_property("fetch_script", {})
	var end_condition = script.get_property("end_condition", "")
	var subjects = script.subjects
		
	var this_card = script.owner
	var my_hero_id = this_card.get_controller_hero_id()
	
	for subject in subjects:
		if fetch_script:
			var fetched_script = subject.retrieve_script_by_path(fetch_script["script_path"])
			subscript = fetch_script["result"]
			subscript = WCUtils.search_and_replace (subscript, "__fetched_script__", fetched_script, true)
			
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
static func _get_identity_from_script(script):
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
func _pre_task_prime(script: ScriptTask, prev_subjects:= []) -> void:
	if script.prev_subjects:
		prev_subjects = script.prev_subjects
	
	script.script_definition = static_pre_task_prime(script.script_definition, script.owner, script, prev_subjects)


static func get_event_source_hero_id(trigger_details):
	var event_source_hero_id = 1
	if trigger_details.has("event_object"):
		var event_object = trigger_details.get("event_object")		
		if "trigger_details" in event_object and event_object.trigger_details.has("source"):
			var source = event_object.trigger_details.get("source", null)
			if guidMaster.is_guid(source):
				source = guidMaster.get_object_by_guid(source)
			if source and typeof(source) == TYPE_OBJECT:
				var hero_id = source.get_controller_hero_id()
				if hero_id > 0:
					event_source_hero_id = hero_id
	return event_source_hero_id
	
static func static_pre_task_prime(script_definition, owner, script = null, prev_subjects:= []):
	var previous_hero = prev_subjects[0] if prev_subjects else null
	#previous_subjects can sometimes contain ints (for ask_integer) instead of cards
	if typeof(previous_hero) == TYPE_INT:
		previous_hero = 0
		
	var previous_hero_id = 0
	if previous_hero:
		previous_hero_id = previous_hero.get_controller_hero_id()
	
	var controller_hero_id = owner.get_controller_hero_id()
	
	var current_hero_target = gameData.get_villain_current_hero_target()

	var event_source_hero_id = get_event_source_hero_id(script.trigger_details) if script else 1

	var replacements = {}
			
	var _replacements = [
		{"from":"_my_hero" , "to": controller_hero_id },
		{"from":"_first_player" , "to": gameData.first_player_hero_id() },
		{"from":"_previous_subject" , "to": previous_hero_id},
		{"from":"_current_hero_target" , "to": current_hero_target},
		{"from":"_event_source_hero" , "to": event_source_hero_id},					
	]

	if script:
		var more_replacements = script.get_property("zone_name_replacement", {})
		for replacement in more_replacements:
			var key = replacement
			var value = script.retrieve_integer_subproperty(key, more_replacements, 0)
			_replacements.append ({"from" : "_" + key, "to": value})


	for zone in ["hand"] + CFConst.HERO_GRID_SETUP.keys() + CFConst.ALL_TYPE_GROUPS:
		for replacement in _replacements:
			var from_str = replacement["from"]
			var to = replacement["to"]
			if !to:
				to = current_hero_target
			replacements[zone + from_str] = zone+str(to)
	script_definition = WCUtils.search_and_replace_multi(script_definition, replacements, true)	
	

	return script_definition
	
