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
	
#override for parent
func move_card_to_container(script: ScriptTask) -> int:
	#TODO might be better to be able to duplicate scriptTasks ?
	#var modified_script:ScriptTask = script.duplicate
	var backup:Dictionary = script.script_definition.duplicate()
	
	var owner_hero_id = script.owner.get_owner_hero_id()

	for zone in CFConst.HERO_GRID_SETUP:
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
	
	return retcode

func deal_damage(script:ScriptTask) -> int:
	return receive_damage(script)

func card_dies(script:ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.FAILED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode
		
	for card in script.subjects:		
		card.die()
		retcode = CFConst.ReturnCode.CHANGED

	return retcode

func receive_damage(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
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
		
		var tough = card.tokens.get_token_count("tough")
		if (tough):
			card.tokens.mod_token("tough", -1)
		else:	
			retcode = card.tokens.mod_token("damage",
					amount * multiplier,false,costs_dry_run(), tags)	

			if ("stun_if_damage" in tags) and amount:
				card.tokens.mod_token("stunned",
					1,false,costs_dry_run(), tags)

			scripting_bus.emit_signal("card_damaged", card, script.script_definition)

			var total_damage:int =  card.tokens.get_token_count("damage")
			var health = card.get_property("health", 0)

			if total_damage >= health:
				var card_dies_definition = {
					"name": "card_dies",
					"tags": ["receive_damage", "Scripted"] + script.get_property(SP.KEY_TAGS)
				}
				var card_dies_script:ScriptTask = ScriptTask.new(card, card_dies_definition, script.trigger_object, script.trigger_details)
				card_dies_script.subjects = [card]
				card_dies_script.is_primed = true #fake prime it since we already gave it subjects	
	
				var task_event = SimplifiedStackScript.new("card_dies", card_dies_script)
				gameData.theStack.add_script(task_event)
						
	return retcode

func prevent(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	

	if script.script_definition.has("amount"): #this is a partial prevention effect
		var stack_object = gameData.theStack.find_last_event()
		if (!stack_object):	
			return CFConst.ReturnCode.FAILED
		
		gameData.theStack.modify_object(stack_object, script)		
	else:	
		#Find the event on the stack and remove it
		#TOdo take into action subject, etc...
		var _result = gameData.theStack.delete_last_event()
		
	return retcode		
	

func replacement_effect(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED
	if (costs_dry_run()): #Shouldn't be allowed as a cost?
		return retcode	
	
	#Find the event on the stack and modifiy it
	#TOdo take into action subject, etc...
	var stack_object = gameData.theStack.find_last_event()
	if (!stack_object):	
		return CFConst.ReturnCode.FAILED
	
	gameData.theStack.modify_object(stack_object, script)
		
	
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
	for card in script.subjects:
		card.discard()
		retcode = CFConst.ReturnCode.CHANGED
	return retcode	

static func simple_discard_task(target_card):	
	var discard_script  = {
				"name": "discard",
				"subject": "self",
			}
	var discard_task = ScriptTask.new(target_card, discard_script, target_card, {})	
	var task_event = SimplifiedStackScript.new("discard", discard_task)
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
		
		return output

func _add_receive_damage_on_stack(amount, original_script, modifications:Dictionary = {}):		
		var receive_damage_script_definition = {
			"name": "receive_damage",
			"amount": amount,
		}
		modifications["script_definition"] =  receive_damage_script_definition	
		var receive_damage_script = _modify_script(original_script, modifications, "replace")
		
		receive_damage_script.is_primed = true #fake prime it since we already gave it subjects	
		
		var task_event = SimplifiedStackScript.new("receive_damage", receive_damage_script)
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
	var amount = attacker.get_property("attack", 0)
	var defender = null
	if (not script.subjects.empty()):
		defender = script.subjects[0]
	
	var overkill_amount = 0
	var my_hero:Card = gameData.get_current_target_hero()
	
	if defender:
		defender.exhaustme()
		var damage_reduction = defender.get_property("defense", 0)
		amount = max(amount-damage_reduction, 0)
		
	else:
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

	if amount:
		var script_modifications = {
			"additional_tags" : ["attack", "Scripted"],
		}
		_add_receive_damage_on_stack (amount, script, script_modifications)
	
	if defender and attacker.get_property("overkill", 0):
		overkill_amount = amount - defender.get_remaining_damage()
		overkill_amount = max(0, overkill_amount)

		var script_modifications = {
			"additional_tags" : ["attack", "Scripted", "overkill"],
			"subjects": [my_hero]
		}
		_add_receive_damage_on_stack (overkill_amount, script, script_modifications)
		
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
		{"name": "receive_damage", "amount" : damage, "subject" : "self"}, #TODO more advanced
		script.trigger_object,
		script.trigger_details)
	additional_task.prime([], CFInt.RunType.NORMAL,0) #TODO gross
	retcode = receive_damage(additional_task)
	
	return CFConst.ReturnCode.CHANGED


func scheme(script: ScriptTask) -> int:
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
		retcode = card.remove_threat(modification)

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
		modification = owner.get_property("thwart")

	var confused = owner.tokens.get_token_count("confused")
	if (confused):
		owner.tokens.mod_token("confused", -1)
	else:
		for card in script.subjects:
			retcode = card.remove_threat(modification)
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

func reveal_encounter(script: ScriptTask) -> int:
	var retcode: int = CFConst.ReturnCode.CHANGED

	if (costs_dry_run()): #not allowed ?
		return retcode
	var owner = script.owner
	var hero_id = owner.get_controller_hero_id()

	gameData.reveal_current_encounter(hero_id)

	return CFConst.ReturnCode.CHANGED
	
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
# there are unfortunately cases where the scrip itself is causing the stakc to not be empty
#removing this check until I can figure out a safer way 					
#				if !gameData.theStack.is_empty():
#					return CFConst.ReturnCode.FAILED
				if cfc.is_modal_event_ongoing():
					return 	CFConst.ReturnCode.FAILED			
				

	var constraints: Array = script.get_property("constraints", [])
	for constraint in constraints:
		var func_name = constraint["name"]
		var func_params = constraint["params"]
		var result = this_card.call(func_name, func_params)
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
