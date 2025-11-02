extends OVUtils


func get_subjects(script: ScriptObject, _subject_request, _stored_integer : int = 0) -> Array:
	var results: Array = []
	match _subject_request:
		SP.KEY_SUBJECT_V_HOST:
			var owner:WCCard = script.owner
			if (owner.current_host_card):
				results.append(owner.current_host_card)
		SP.KEY_SUBJECT_V_MY_HERO:
			var owner:WCCard = script.owner
			var hero_card = gameData.get_identity_card(owner.get_controller_hero_id())
			if (hero_card.is_hero_form()):
				results.append(hero_card)
		SP.KEY_SUBJECT_V_MY_IDENTITY:
			var owner:WCCard = script.owner
			var hero_card = gameData.get_identity_card(owner.get_controller_hero_id())
			results.append(hero_card)
		SP.KEY_SUBJECT_V_MY_ALTER_EGO:
			var owner:WCCard = script.owner
			var hero_card = gameData.get_identity_card(owner.get_controller_hero_id())
			if (hero_card.is_alter_ego_form()):
				results.append(hero_card)							
		SP.KEY_SUBJECT_V_VILLAIN:
			results.append(gameData.get_villain())					
	return results


func can_pay_as_resource(to_pay:Dictionary, resource_cards:Array, script = null):
	var total_resources: ManaPool= ManaPool.new()
	for card in resource_cards:
		total_resources.add_manacost(card.get_resource_value_as_mana(script))
	
	var to_pay_as_cost : ManaCost = ManaCost.new()
	to_pay_as_cost.init_from_dictionary(to_pay)
	if total_resources.can_pay_total_cost(to_pay_as_cost):
		return true
	return false

func parse_post_prime_replacements(script_task:ScriptObject) -> Dictionary:
	if !script_task.is_primed:
		var _error = 1
		#TODO error handling
		return script_task.script_definition

	var wip_definitions := script_task.script_definition.duplicate(true)
	var subjects = script_task.subjects
	if !subjects and script_task.owner.has_method("get_parent_script"):
		subjects = script_task.owner.parent_script.subjects
	var subject_controller_hero = 0
	if subjects:
		subject_controller_hero = subjects[0].get_controller_hero_id()
		var _result = WCUtils.search_and_replace(wip_definitions, "{__subject_hero_id__}", str(subject_controller_hero), false)	
			
	return wip_definitions
