class_name WCOVUtils
extends Reference

const _CARD_SELECT_SCENE_FILE = CFConst.PATH_CORE + "SelectionWindow.tscn"
const _CARD_SELECT_SCENE = preload(_CARD_SELECT_SCENE_FILE)

# The path to the optional confirm scene. This has to be defined explicitly
# here, in order to use it in its preload, otherwise the parser gives an error
const _OPTIONAL_CONFIRM_SCENE_FILE = CFConst.PATH_CORE + "OptionalConfirmation.tscn"
const _OPTIONAL_CONFIRM_SCENE = preload(_OPTIONAL_CONFIRM_SCENE_FILE)

# Populates the info panels under the card, when it is shown in the
# viewport focus or deckbuilder
func populate_info_panels(card: Card, focus_info: DetailPanels) -> void:
	focus_info.hide_all_info()
	var card_illustration = card.get_property("_illustration")
	if card_illustration:
		focus_info.show_illustration("Illustration by: " + card_illustration)
	else:
		focus_info.hide_illustration()
	for tag in card.get_property("Tags"):
		if CardConfig.EXPLANATIONS.has(tag):
			focus_info.add_info(tag, CardConfig.EXPLANATIONS[tag])
	var card_keywords = card.get_property("_keywords")
	if card_keywords:
		for keyword in card_keywords:
			if CardConfig.EXPLANATIONS.has(keyword):
				focus_info.add_info(keyword, CardConfig.EXPLANATIONS[keyword])

# Goes through the card pool of the game and checks each card against the provided list of filters
# Then returns all card names matching the filters.
func filter_card_pool(filters_list: Array, card_pool := _get_card_pool()) -> Array:
	var matching_card_defs := []
	for card_name in card_pool:
		var matching_def := true
		# Each filter should be a CardFilter class
		for filter in filters_list:
			if not filter.check_card(card_pool[card_name]):
				matching_def = false
				break
		if matching_def:
			matching_card_defs.append(card_name)
	return(matching_card_defs)


# Overridable function to return the card pool of the game
# Games might decide to change how this is used for their own purposes.
func _get_card_pool() -> Dictionary:
	return(cfc.card_definitions)


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
			if (hero_card and hero_card.is_hero_form()):
				results.append(hero_card)
		SP.KEY_SUBJECT_V_MY_IDENTITY:
			var owner:WCCard = script.owner
			var hero_card = gameData.get_identity_card(owner.get_controller_hero_id())
			if (hero_card): #At load time it is possible the hero isn't set yet
				results.append(hero_card)
		SP.KEY_SUBJECT_V_MY_ALTER_EGO:
			var owner:WCCard = script.owner
			var hero_card = gameData.get_identity_card(owner.get_controller_hero_id())
			if (hero_card and hero_card.is_alter_ego_form()):
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
		gameData._acquire_user_input_lock(owner.get_controller_player_network_id())
		var my_network_id = cfc.get_network_unique_id()
		var is_master:bool =  (owner.get_controller_player_network_id() == my_network_id)
		var confirm = _OPTIONAL_CONFIRM_SCENE.instance()
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
		gameData._release_user_input_lock(owner.get_controller_player_network_id())
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
		parent_node.add_child(selection)
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
	if (trigger != "interrupt"):
		return true

	#If this *is* an interrupt but I don't have an answer, I'll fail it

	#if this card has no scripts to handle interrupts, we fail
	if !card_scripts:
		return false

	var event_name = _trigger_details["event_name"]

	if event_name == "receive_damage":
		var _tmp = 1

	var expected_trigger_name = card_scripts.get("event_name", "")

	#skip if we're expecting an interrupt but not this one
	if expected_trigger_name and (expected_trigger_name != event_name):
		return false;

	var expected_trigger_type = card_scripts.get("event_type", "")
	if expected_trigger_type and (expected_trigger_type != _trigger_details.get("trigger_type", "")):
		return false;

	var event_details = {
		"event_name":  expected_trigger_name,
		"event_type": expected_trigger_type
	}

	var trigger_filters = card_scripts.get("event_filters", {})
	var event = (gameData.theStack.find_event(event_details, trigger_filters, owner_card, _trigger_details))

	return event #note: force conversion from stack event to bool
