extends OVUtils

func get_script_identity(script, trigger_details):
	var hero_id = 0
	
	var override_hero_id = trigger_details.get("override_hero_id", 0)
	if override_hero_id:
		hero_id = override_hero_id
	else:
		var owner:WCCard = script.owner
		hero_id = owner.get_controller_hero_id()
	
	if not hero_id:
		var _error = 1 #that's a bug?
		
	return gameData.get_identity_card(hero_id)
		
func preprocess_subject_definition(script: ScriptObject):
#	var subject = overrides.get("subject", get_property(SP.KEY_SUBJECT))
	var subject = script.get_property(SP.KEY_SUBJECT)
	var script_definition = script.script_definition.duplicate()		
	#replace targeting with selection (optional)
	if CFConst.OPTIONS.get("replace_targetting_with_selection", false):
		if subject == SP.KEY_SUBJECT_V_TARGET:
			script_definition[SP.KEY_SUBJECT] = SP.KEY_SUBJECT_V_BOARDSEEK
			script_definition[SP.KEY_SELECTION_TYPE] = "equal" 
			script_definition[SP.KEY_SELECTION_COUNT] = 1
			script_definition[SP.KEY_NEEDS_SELECTION] = true
			script_definition[SP.KEY_SUBJECT_COUNT] = "all"
			script_definition["filter_state_seek"] = script_definition["filter_state_subject"]	
	
	#more than 1 villain, need to modify some cards rules in real time
	if subject == SP.KEY_SUBJECT_V_VILLAIN:
		var villains = gameData.get_villains()
		if villains.size() > 1:
			if !script.owner.is_encounter():
				script_definition[SP.KEY_SUBJECT] = SP.KEY_SUBJECT_V_BOARDSEEK
				script_definition[SP.KEY_SELECTION_TYPE] = "equal" 
				script_definition[SP.KEY_SELECTION_COUNT] = 1
				script_definition[SP.KEY_NEEDS_SELECTION] = true
				script_definition[SP.KEY_SUBJECT_COUNT] = "all"
				script_definition["filter_state_seek"] = [
					{
						"filter_properties": {
							"type_code": "villain"
						}
					}
				]
	#more than 1 main scheme, need to modify some cards rules in real time
	if subject == SP.KEY_SUBJECT_V_MAIN_SCHEME:
		var schemes = gameData.get_main_schemes()
		if schemes.size() > 1:
			if !script.owner.is_encounter():
				script_definition[SP.KEY_SUBJECT] = SP.KEY_SUBJECT_V_BOARDSEEK
				script_definition[SP.KEY_SELECTION_TYPE] = "equal" 
				script_definition[SP.KEY_SELECTION_COUNT] = 1
				script_definition[SP.KEY_NEEDS_SELECTION] = true
				script_definition[SP.KEY_SUBJECT_COUNT] = "all"
				script_definition["filter_state_seek"] = [
					{
						"filter_properties": {
							"type_code": "main_scheme"
						}
					}
				]
						
	return script_definition 

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
		"flip_side":
			var owner:WCCard = script.owner
			var back_code = owner.get_card_back_code()
			if (back_code):
				var new_card = gameData.retrieve_from_side_or_instance(back_code,owner.get_owner_hero_id())
				if new_card:
					results.append(new_card)
		"trigger_flip_side":
			var trigger_object:WCCard = script.trigger_object
			var back_code = trigger_object.get_card_back_code() if trigger_object else ""
			if (back_code):
				var new_card = gameData.retrieve_from_side_or_instance(back_code,trigger_object.get_owner_hero_id())
				if new_card:
					results.append(new_card)					
		#when an existing subject already exists for the script
		"current_subject":
			results = script.subjects		
		SP.KEY_SUBJECT_V_HOST:
			var owner:WCCard = script.owner
			if (owner.current_host_card):
				results.append(owner.current_host_card)
		SP.KEY_SUBJECT_V_MY_HERO:
			var hero_card = get_script_identity(script, trigger_details)
			if (hero_card and hero_card.is_hero_form()):
				results.append(hero_card)
		SP.KEY_SUBJECT_V_MY_IDENTITY:
			var hero_card = get_script_identity(script, trigger_details)
			if (hero_card): #At load time it is possible the hero isn't set yet
				results.append(hero_card)
		SP.KEY_SUBJECT_V_MY_ALTER_EGO:
			var hero_card = get_script_identity(script, trigger_details)
			if (hero_card and hero_card.is_alter_ego_form()):
				results.append(hero_card)							
		SP.KEY_SUBJECT_V_VILLAIN:
			results.append(gameData.get_villain())
		SP.KEY_SUBJECT_V_MAIN_SCHEME:
			results.append(gameData.get_main_scheme())					
		SP.KEY_SUBJECT_V_GRAB_UNTIL:
			results = _grab_until_find(script, run_type)
		SP.KEY_SUBJECT_CURRENT_ACTIVATION_ENEMY:
			var activation_script = script.owner.get_current_activation_details()
			if !activation_script:
				activation_script = gameData.get_latest_activity_script()			
			if activation_script:
				results.append(activation_script.owner)
		SP.KEY_SUBJECT_CURRENT_ACTIVATION_TARGET:
			var activation_script = script.owner.get_current_activation_details()
			if !activation_script:
				activation_script = gameData.get_latest_activity_script()			
			if activation_script and activation_script.subjects:
				results+= activation_script.subjects				
		SP.KEY_SUBJECT_CURRENT_HERO_TARGET:
			results.append(gameData.get_identity_card(gameData.get_current_activity_hero_target()))							
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
		if typeof(subjects[0]) != TYPE_INT: #AskInteger passes an int, not a card, we need to skip that case
			subject_controller_hero = subjects[0].get_controller_hero_id()
			wip_definitions = WCUtils.search_and_replace(wip_definitions, "{__subject_hero_id__}", str(subject_controller_hero), false)	
			
	return wip_definitions

static func func_name_run(object, func_name, func_params, script = null):
	var reverse_result = false
	if func_name.begins_with("!"):
		func_name = func_name.substr(1)
		reverse_result = true
	var result = object.call(func_name, func_params, script)

	if typeof(result) == TYPE_BOOL:
		if result:
			result = 1
		else:
			result = 0

	var multiplier = func_params.get("multiplier", 1)
	if typeof(result) in [TYPE_INT]:
		result = result * multiplier
	
	if typeof(result) in [TYPE_INT, TYPE_BOOL] and reverse_result:
		if result:
			result = 0
		else:
			result = 1

	var prefix = func_params.get("prefix", "")
	var suffix = func_params.get("suffix", "")
	if typeof(result) in [TYPE_STRING] and prefix or suffix:
		result = prefix + result + suffix	
	
	if typeof(result) == TYPE_INT:
		var max_value =  func_params.get("max", null)
		if max_value != null:
			result = min(result, max_value)
		var min_value =  func_params.get("min", null)
		if min_value != null:
			result = max(result, min_value)		
		
	return result
	

#TODO all calls to this method are in core which isn't good
#Need to move something, somehow
func confirm(
		owner,
		script: Dictionary,
		card_name: String,
		task_name: String,
		type := "task") -> bool:
	cfc.add_ongoing_process(owner, "confirm")
	var is_accepted := true
	# We do not use SP.KEY_IS_OPTIONAL here to avoid causing cyclical
	# references when calling CFUtils from SP
	if script.get("is_optional_" + type):
		cfc.game_paused = true
		gameData._acquire_user_input_lock(owner.get_controller_player_network_id())
		var my_network_id = cfc.get_network_unique_id()
		var is_master:bool =  (owner.get_controller_player_network_id() == my_network_id)
		var confirm = _OPTIONAL_CONFIRM_SCENE.instance()

#Showing this menu here has led to weird side effects such as non trigger of some ability, need to dig
#		if task_name != "manual":
#			var announcer_data = script.get("announcer_data", {})
#			if announcer_data:
#				gameData.theAnnouncer.choices_menu(owner, announcer_data["origin_event"] ,confirm ,announcer_data["interacting_hero"] )			
					
		cfc.add_modal_menu(confirm)
		confirm.prep(card_name,task_name, is_master)
		# We have to wait until the player has finished selecting an option
		yield(confirm,"selected")
		# If the player selected "No", we don't execute anything
		if not confirm.is_accepted:
			is_accepted = false
		# Garbage cleanup
		confirm.hide()
		cfc.remove_modal_menu(confirm)
		confirm.queue_free()
		if is_instance_valid(owner):
			gameData._release_user_input_lock(owner.get_controller_player_network_id())
		cfc.game_paused = false
	cfc.remove_ongoing_process(owner, "confirm")	
	return(is_accepted)
	
func select_card(
		card_list: Array, 
		selection_params: Dictionary,
		parent_node,
		script : ScriptObject = null,
		run_type:int = CFInt.RunType.NORMAL,
		stored_integer: int = 0,
		card_select_scene = _CARD_SELECT_SCENE):
	
	cfc.add_ongoing_process(self)
	if parent_node == cfc.NMAP.get("board")  and (run_type != CFInt.RunType.BACKGROUND_COST_CHECK):
		cfc.game_paused = true
	var selected_cards
	# This way we can override the card select scene with a custom one
	var selection = card_select_scene.instance()
	selection.init(selection_params, script, stored_integer)
	if (run_type == CFInt.RunType.BACKGROUND_COST_CHECK):
		selection.dry_run(card_list)	
	else:
		gameData.attempt_user_input_lock()
		cfc.NMAP.board.add_child_to_top_layer(selection)		
		cfc.add_modal_menu(selection) #keep a pointer to the variable for external cleanup if needed
		selection.call_deferred("initiate_selection", card_list)
		# We have to wait until the player has finished selecting their cards
		yield(selection,"confirmed")
		cfc.remove_modal_menu(selection)
		gameData.attempt_user_input_unlock()	
	if selection.is_cancelled:
		selected_cards = false
	else:
		selected_cards = selection.selected_cards			
	selection.queue_free()
		
	if parent_node == cfc.NMAP.get("board"):
		cfc.game_paused = false
		
	cfc.remove_ongoing_process(self)	
	return(selected_cards)


# Additional filter for triggers,
# also see core/ScriptProperties.gd
func filter_trigger(
		trigger:String,
		card_scripts,
		trigger_card,
		owner_card,
		_trigger_details) -> bool:

	#Generally speaking I don't want to trigger
	#on facedown cards such as boost cards
	#(e.g. bug with Hawkeye, Charge, and a bunch of others)
	if trigger_card and is_instance_valid(trigger_card):
		#facedown cards won't have a type_code unless they are used on the board (e.g. facedown ultron drones)
		if !trigger_card.get_property("type_code", null):
			return false
		if trigger_card.is_boost(): 
			if trigger!= "boost":
				return false
			if trigger_card!= owner_card:
				return false


	#from this point this is only checks for interrupts

	#if this is not an interrupt, I let it through
	if (!trigger.begins_with("interrupt")):
		var trigger_filters = card_scripts.get("event_filters", {})
		if trigger_filters:
			return matches_filters(trigger_filters, owner_card, _trigger_details)
		return true
	
	#If this *is* an interrupt but I don't have an answer, I'll fail it
	
	#if this card has no scripts to handle interrupts, we fail
	if !card_scripts:
		return false

	var event_name = _trigger_details["event_name"]
	
	if event_name == "receive_damage":
		var _tmp = 1
	
	var expected_trigger_type = card_scripts.get("event_type", "")
	if expected_trigger_type and (expected_trigger_type != _trigger_details.get("trigger_type", "")):
		return false;	
	
	var expected_trigger_names = card_scripts.get("event_name", "")
	if typeof(expected_trigger_names) == TYPE_STRING:
		expected_trigger_names = [expected_trigger_names]
	for expected_trigger_name in expected_trigger_names:
	#skip if we're expecting an interrupt but not this one
		if expected_trigger_name and (expected_trigger_name != event_name):
			continue;
		

		
		var event_details = {
			"event_name":  expected_trigger_name,
			"event_type": expected_trigger_type
		}	
			
		var trigger_filters = card_scripts.get("event_filters", {})
		var event = (gameData.theStack.find_event(event_details, trigger_filters, owner_card, _trigger_details))

		if event:
			return event #note: force conversion from stack event to bool
	return false



func matches_filters(_filters:Dictionary, owner_card, _trigger_details):
	var filters = _filters #.duplicate(true)

	var controller_hero_id = _trigger_details.get("override_hero_id", 	owner_card.get_controller_hero_id())

	var replacements = {
		"villain": gameData.get_villain(),
		"self": owner_card,
		"host": owner_card.current_host_card,
		"current_hero_target": gameData.get_identity_card(gameData.get_current_activity_hero_target())
	}	
	if (controller_hero_id > 0):
		replacements["my_hero"] = gameData.get_identity_card(controller_hero_id)
	else:
		replacements["my_hero"] = gameData.get_identity_card(gameData.get_current_activity_hero_target())

	var trigger_details = guidMaster.replace_guids_to_objects(_trigger_details)
	var event_source_hero_id = WCScriptingEngine.get_event_source_hero_id(trigger_details)

	var zone_replacements = [
		{"from":"_my_hero" , "to": controller_hero_id },
		{"from":"_first_player" , "to": gameData.first_player_hero_id() },		
#		{"from":"_previous_subject" , "to": previous_hero_id},
#		{"from":"_current_hero_target" , "to": current_hero_target},
		{"from":"_event_source_hero" , "to": event_source_hero_id},					
	]

	for zone in ["hand"] + CFConst.HERO_GRID_SETUP.keys() + CFConst.ALL_TYPE_GROUPS:
		for replacement in zone_replacements:
			var from_str = replacement["from"]
			var to = replacement["to"]
			if !to:
				continue
			replacements[zone + from_str] = zone+str(to)


	filters = WCUtils.search_and_replace_multi(filters, replacements, true)

	

	
	if filters.has("filter_state_event_source"):
		var script = trigger_details.get("event_object")
		if !script:
			return false
		var owner = script.owner
		if !owner:
			return false		
		var is_valid = SP.check_validity(owner, filters, "event_source")
		if !is_valid:
			return false
		filters.erase("filter_state_event_source")

	for filter_key in filters.keys():
		var value = filters[filter_key]
		var compared_to_str = trigger_details.get(filter_key, "")
		var compared_to_int = 0
		match typeof(compared_to_str):
			TYPE_STRING, TYPE_INT:
				compared_to_int = int(compared_to_str)		
		
		if typeof(value) == TYPE_STRING:
			if value.begins_with(">="):
				value = int(value.substr(2))
				if compared_to_int >= value:
					filters.erase(filter_key)
				else:
					return false
			elif value.begins_with("<="):
				value = int(value.substr(2))
				if compared_to_int <= value:
					filters.erase(filter_key)
				else:
					return false				
			elif value.begins_with(">"):
				value = int(value.substr(1))
				if compared_to_int > value:
					filters.erase(filter_key)	
				else:
					return false								
			elif value.begins_with("<"):
				value = int(value.substr(1))
				if compared_to_int < value:
					filters.erase(filter_key)
				else:
					return false									
				

	if (filters):
		var _tmp = 0	
	#var script_details = task.script_definition
	var result = WCUtils.is_element1_in_element2(filters, trigger_details, ["tags"])

	return result
