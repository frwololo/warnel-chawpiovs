extends OVUtils


func get_subjects(script: ScriptObject, _subject_request, _stored_integer : int = 0, run_type = CFInt.RunType.NORMAL, trigger_details :={}) -> Array:
	var results = []
	if _subject_request.begins_with("trigger_details_"):
		if !trigger_details:
			return results
		var property = _subject_request.substr(16)
		var value = trigger_details.get(property, null)
		if value:
			if typeof(value) == TYPE_ARRAY:
				return value
			results.append(value)
		return results
	
	if _subject_request.begins_with(SP.KEY_SUBJECT_V_A_IDENTITY):
		var hero_id = _subject_request.substr(SP.KEY_SUBJECT_V_A_IDENTITY.length())
		var hero_card = gameData.get_identity_card(int(hero_id))
		results.append(hero_card)	
		return results		
			
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
		SP.KEY_SUBJECT_V_GRAB_UNTIL:
			results = _grab_until_find(script, run_type)
		SP.KEY_SUBJECT_CURRENT_ACTIVATION_ENEMY:
			var activation_script = script.owner.get_current_activation_details()
			if activation_script:
				results.append(activation_script.owner)
									
	return results

func _grab_until_find(script: ScriptObject, _run_type) -> Dictionary:
	var subjects_array := []
	var src_container = script.get_property(SP.KEY_SRC_CONTAINER)
	src_container = cfc.NMAP.get(src_container, null)
	if !src_container:
		return{"subjects" : [], "stored_integer" : 0}
		
	var dest_container = script.get_property(SP.KEY_DEST_CONTAINER)
	dest_container = cfc.NMAP.get(dest_container, null)	
	if !dest_container:
		return{"subjects" : [], "stored_integer" : 0}
	
	var src_cards:Array = src_container.get_all_cards()
	var found_index = 0
	var found = false
	while found_index < src_cards.size() and !found:
		var card = src_cards[src_cards.size() - 1 - found_index]
		var is_valid = SP.check_validity(card, script.script_definition, "grab_until", script.owner)
		if !is_valid:
			subjects_array.append(card)
			found_index +=1
		else:
			found = true
			

	return{"subjects" : subjects_array, "stored_integer" :  src_cards.size() - 1 - found_index}


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
		wip_definitions = WCUtils.search_and_replace(wip_definitions, "{__subject_hero_id__}", str(subject_controller_hero), false)	
			
	return wip_definitions

static func func_name_run(object, func_name, func_params, script = null):
	var reverse_result = false
	if func_name.begins_with("!"):
		func_name = func_name.substr(1)
		reverse_result = true
	var result = object.call(func_name, func_params, script)

	var multiplier = func_params.get("multiplier", 1)
	if typeof(result) in [TYPE_INT]:
		result = result * multiplier
	
	if typeof(result) in [TYPE_INT, TYPE_BOOL] and reverse_result:
		result = !result
	
		
	return result
