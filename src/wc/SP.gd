# SP stands for "ScriptProperties".
#
# This dummy class exists to allow games to extend 
# the core [ScriptProperties] class provided by CGF, with their own requirements.
# 
# This is particularly useful when needing to adjust filters for the game's needs.
class_name SP
extends ScriptProperties

# A demonstration filter setup. If you specify this value in your
# card script definition for a filter, then it will look for the same key
# in the trigger dictionary. If it does not, or the value does not match
# then it will consider this trigger invalid for execution.
#TODO delete
const FILTER_DEMONSTRATION = "is_demonstration"

const KEY_SUBJECT_V_HOST := "host"
const KEY_SUBJECT_V_MY_HERO := "my_hero"
const KEY_SUBJECT_V_MY_ALTER_EGO := "my_alter_ego"
const KEY_SUBJECT_V_MY_IDENTITY := "my_identity"
const KEY_SUBJECT_V_A_IDENTITY := "identity_"
const KEY_SUBJECT_V_VILLAIN := "villain"
const KEY_SUBJECT_V_MAIN_SCHEME := "main_scheme"
const KEY_SUBJECT_V_GRAB_UNTIL := "grab_until"
const KEY_SUBJECT_CURRENT_ACTIVATION_ENEMY:= "current_activation_enemy"
const KEY_SUBJECT_CURRENT_ACTIVATION_TARGET:= "current_activation_target"
const KEY_SUBJECT_CURRENT_HERO_TARGET:= "current_hero_target"
const KEY_SUBJECT_EVENT_SOURCE_HERO:= "event_source_hero"
const KEY_SUBJECT_V_ATTACHMENTS:= "attachments"
const KEY_ATTACHMENTS_HOST:= "attachments_host"

const FILTER_HOST_OF := "filter_is_host_of"
const FILTER_HOSTED_BY  := "filter_is_hosted_by"
const FILTER_SAME_CONTROLLER := "filter_same_controller"
const FILTER_EVENT_SOURCE:= "filter_event_source"
const FILTER_SOURCE_CONTROLLED_BY := "filter_source_controlled_by"
const FILTER_SHARES_TRAIT_WITH_IDENTITY := "filter_shares_trait_with_identity"
const FILTER_EXHAUSTED := "filter_is_exhausted"
const FILTER_MAX_PER_HERO := "filter_max_per_hero"
const FILTER_MAX_PER_HOST := "filter_max_per_host"
const FILTER_FUNC := "filter_func"

const TRIGGER_TARGET_HERO = "target_hero"
const TRIGGER_SUBJECT = "trigger_subject"

#stack subjects
const KEY_SUBJECT_V_CURRENT_ACTIVATION := "current_activation"
const KEY_SUBJECT_V_INTERUPTED_EVENT := "interrupted_event"

# This call has been setup to call the original, and allow futher extension
# simply create new filter
static func filter_trigger(
		card_scripts,
		trigger_card,
		owner_card,
		trigger_details) -> bool:
	var is_valid := .filter_trigger(card_scripts,
		trigger_card,
		owner_card,
		trigger_details)

	if !is_valid:
		return false
	# Here we check that the trigger matches the _request_ for trigger
	# A trigger which requires "another" card, should not trigger
	# when itself causes the effect.
	# For example, a card which rotates itself whenever another card
	# is rotated, should not automatically rotate when itself rotates.
	if !subject_matches(trigger_card, card_scripts.get("trigger"), owner_card):
		return false

	# Card Host filter checks
	if card_scripts.get(FILTER_HOST_OF):
		if !check_host_filter(trigger_card,owner_card,card_scripts.get(FILTER_HOST_OF)):
			return false

	if card_scripts.get(FILTER_HOSTED_BY):
		if !check_hosted_by_filter(trigger_card,owner_card,card_scripts.get(FILTER_HOSTED_BY)):
			return false

	# Same Controller filter check
	if card_scripts.get(FILTER_SAME_CONTROLLER) \
			and !check_same_controller_filter(trigger_card,owner_card,card_scripts.get(FILTER_SAME_CONTROLLER)):
		return false
		
	if card_scripts.get("filter_" + TRIGGER_TARGET_HERO):
		var expected_hero = _get_subjects_simplified(card_scripts.get("filter_" + TRIGGER_TARGET_HERO), owner_card)
		var actual_target = find_hero_by_name(trigger_details.get(TRIGGER_TARGET_HERO))
		if expected_hero != actual_target:
			return false		

	if card_scripts.get(TRIGGER_SUBJECT):
		match card_scripts.get(TRIGGER_SUBJECT):
			"self":
				var subjects = trigger_details.get("subjects", [])
				if !(owner_card in (subjects)):
					return false
			_: 
				return false

	if card_scripts.get(FILTER_SOURCE_CONTROLLED_BY) \
			and !check_source_controlled_by_filter(trigger_card,owner_card,trigger_details, card_scripts.get(FILTER_SOURCE_CONTROLLED_BY)):
		return false	

	if card_scripts.get(FILTER_SHARES_TRAIT_WITH_IDENTITY) \
			and !check_trigger_shares_trait_with_identity(trigger_card,owner_card,trigger_details):
		return false	
		
	if card_scripts.get(FILTER_EVENT_SOURCE) \
			and !check_filter_event_source(trigger_card,owner_card,trigger_details, card_scripts.get(FILTER_EVENT_SOURCE)):
		return false	
	
	for key in card_scripts:
		if key.ends_with("_same_as_identity"):
			var property = key.replace("filter_", "").replace("_same_as_identity", "")
			if !check_trigger_shares_property_with_identity(trigger_card,owner_card,property):
				return false

	return true

static func find_hero_by_name(hero_name):
	return cfc.NMAP.board.find_card_by_name(hero_name, false, false, {"type_code": "hero"})
	
static func subject_matches(card, string_value, owner_card):
	if !string_value:
		return true
			
	match string_value:			
		"another":
			if card == owner_card:
				return false		
		_:
			#anything else we try to compare it to the found subject(s)
			var potential_matches = _get_subjects_simplified(string_value, owner_card)
			if typeof(potential_matches) == TYPE_ARRAY:
				return card in potential_matches
			else:
				return card == potential_matches		
	return true

static func _get_subjects_simplified(string_value, owner_card):
	if !string_value:
		return null
		
	match string_value:
		KEY_SUBJECT_V_MY_HERO:
			return owner_card.get_controller_hero_card()
		KEY_SUBJECT_V_MY_IDENTITY:
			#todo there should be a difference here, need to work it out
			return owner_card.get_controller_hero_card()			
		KEY_SUBJECT_V_VILLAIN:
			return gameData.get_villains()
		KEY_SUBJECT_V_MAIN_SCHEME:
			return gameData.get_main_schemes()
		"self":
			return owner_card
		"first_player":
			return gameData.get_first_player()			
		"host":
			return owner_card.current_host_card			
		_:
			#anything else we try to find a card by that name on the board
			return cfc.NMAP.board.find_card_by_name(string_value)

static func check_trigger_shares_property_with_identity(trigger_card,owner_card,property) -> bool:
	if !is_instance_valid(trigger_card): return false
	if !is_instance_valid(owner_card): return false

	var identity = owner_card.get_controller_hero_card()
	if  !is_instance_valid(identity): return false
	
	var value1 = str(trigger_card.get_property(property, "", true)).to_lower()
	var value2 = str(identity.get_property(property, "", true)).to_lower()
	
	return value1 == value2

static func check_trigger_shares_trait_with_identity(trigger_card,owner_card,_trigger_details) -> bool:
	if !is_instance_valid(trigger_card): return false
	if !is_instance_valid(owner_card): return false

	var identity = owner_card.get_controller_hero_card()
	if  !is_instance_valid(identity): return false

	var trigger_traits = trigger_card.get_all_traits()	
	var identity_traits = identity.get_all_traits()
	for trait in trigger_traits:
		if identity_traits.has(trait):
			return true
	return false
				
# Returns true if the trigger is the host of the owner, false otherwise
static func check_host_filter(trigger_card, owner_card, host_description : String) -> bool:
	var card_matches := false
	if !is_instance_valid(trigger_card): return false
	if !is_instance_valid(owner_card): return false
	
	#TODO more advanced targeting
	match host_description:
		"self":
			if owner_card.current_host_card == trigger_card: 
				card_matches = true
	return(card_matches)
	
static func check_hosted_by_filter(trigger_card, owner_card, host_description : String) -> bool:
	return check_host_filter(owner_card, trigger_card, host_description) 	

# Returns true if the trigger and the owner belong to the same hero, false otherwise
static func check_source_controlled_by_filter(_trigger_card, owner_card, trigger_details, expected_controller) -> bool:
	var source = trigger_details.get("source", null)
	if guidMaster.is_guid(source):
		source = guidMaster.get_object_by_guid(source)
	
	if !is_instance_valid(source):
		return false
		
	#unfortunately "source" is overused and can sometimes be used to designate a container name
	if typeof(source) != TYPE_OBJECT: 
		return false
		
	match expected_controller:
		"my_hero":
			var controller_hero_id = source.get_controller_hero_id()
			if controller_hero_id == owner_card.get_controller_hero_id():
				return true
			return false
		_: #not implemented
			pass
	return false
	
# Returns true if
static func check_filter_event_source(_trigger_card, owner_card, trigger_details, _expected_event_source) -> bool:
	var source = trigger_details.get("source", null)
	if guidMaster.is_guid(source):
		source = guidMaster.get_object_by_guid(source)
		
	if !source:
		return false	

	#unfortunately "source" is overused and can sometimes be used to designate a container name
	if typeof(source) != TYPE_OBJECT: 
		return false
		
	match _expected_event_source:
		"self":
			if source == owner_card:
				return true
			return false
		"my_hero":
			if source == owner_card.get_controller_hero_card():
				return true
			return false			
		_: #not implemented
			pass
	return false	
	
# Returns true if the trigger and the owner belong to the same hero, false otherwise
static func check_same_controller_filter(trigger_card, owner_card, true_false : bool) -> bool:
	var same_controller: bool = (owner_card.get_controller_hero_id() == trigger_card.get_controller_hero_id())
	if (same_controller and true_false): return true
	if ((not same_controller) and (not true_false)): return true
	return false

#checks if owner_card already exists equal_or_more than max_value times
# under the control 
# of target_card's hero id
static func check_max_per_hero(target_card, max_value, owner_card) -> bool:
	var hero_id = target_card.get_controller_hero_id()
	var count = cfc.NMAP.board.count_card_per_player_in_play(owner_card, hero_id, true)
	if count >= max_value:
		return false
	return true

#checks if target_card already hosts equal_or_more than max_value a card named like owner_card
static func check_max_per_host(target_card, max_value, owner_card) -> bool:
	var attachments = target_card.attachments
	var count = 0
	for card in attachments:
		if card.get_unique_name() == owner_card.get_unique_name():
			count+=1
	if count >= max_value:
		return false
	return true

static func check_func_filter(card, owner_card, filter_details) -> bool:
	var func_name = filter_details["func_name"]
	var func_params = filter_details["func_params"]
			
	var check = cfc.ov_utils.dummy_func_name_run(owner_card, card, func_name, func_params)
	return check	
			
# Check if the card is a valid subject or trigger, according to its state.
static func check_validity(card, card_scripts, type := "trigger", owner_card = null) -> bool:
	var is_valid = .check_validity(card, card_scripts, type, owner_card)
	if (!is_valid):
		return is_valid

	var tags = card_scripts.get("tags", [])
	var script_name = card_scripts.get("name", "")

	var action_character = null
	if owner_card:
		action_character = owner_card
		var owner_type = owner_card.get_property("type_code", "")
		if !owner_type in ["hero", "ally", "minion", "villain"]:
			action_character = owner_card.get_controller_hero_card()

	#more complex handling of validity for some cards that define additional filters
	var validity_extra_scripts = card.get_potential_scripts("is_valid_target_filters") 
	if validity_extra_scripts:
		for key in [script_name] + tags:
			if validity_extra_scripts.has(key):
				validity_extra_scripts = validity_extra_scripts[key]
				break
				
		if validity_extra_scripts:
			var source_validity_script = validity_extra_scripts.get("source_condition", {})
			if !check_func_filter(owner_card,owner_card,source_validity_script):
				return false			
	
	#For certain effects,
	#permanent cards cannot be targeted by cards of a different set code
	#this is a hardcoded blacklist approach for now. Not great but...
	if card.get_property("permanent", 0):
		var check_required = false
		if script_name in ["move_card_to_container", "discard", "shuffle_card_into_container", "tuck_under_card", "tuck_card_under_me"]:
			check_required = true
		if script_name in ["attach_to_card", "host_card", "move_card_to_board"]:
			if "facedown" in tags:
				check_required = true
				
		if check_required:		
			var set_code = card.get_property("card_set_code", "")
			var owner_set_code = owner_card.get_property("card_set_code", "")
			if set_code != owner_set_code:
				return false

	
	#generally speaking, boost cards are not valid targets...
	if card.is_boost() and !card_scripts.get("force_valid_boost_target", false):
		#...but we want them to be able to target themselves ("put this card into play")
		if card != owner_card:
			return false	

	#I've had countless bugs with Odin in Hela's scenario
	# so this is a preventive measure: inactive attachments can only
	#be targeted by their set (like permanents)
	#or the card that attached them
	if card.is_inactive_attachment():
		var set_code = card.get_property("card_set_code", "")
		var owner_set_code = owner_card.get_property("card_set_code", "")
		if (set_code == owner_set_code) or (owner_card == card.current_host_card):
			pass
		else:
			return false	
				
	#check for special conditions if card is an attack
	if ((script_name == "attack") or ("attack" in tags)):			
		if action_character:
			#Check for "can only attack this card" restriction (e.g. Encased in Ice)	
			var can_only_attack =  action_character.get_property("can_only_attack_card", "")
			if can_only_attack:
				var valid_targets = _get_subjects_simplified(can_only_attack, action_character)
				if not card in valid_targets:
					return false
		
		var bypass_guard = action_character.get_property("bypass_guard", 0, true) if action_character else 0
		#check for "Guard" keyword			
		if card in gameData.get_villains():
			var all_cards = cfc.NMAP.board.get_all_cards()
			
			#guard_all keyword
			for other_card in all_cards:
				if other_card == card:
					continue
				if other_card.get_property("guard_all", 0, true) and other_card.is_faceup: #TODO better way to ignore face down cards?
					return false
			
			#guard keyword				
			if owner_card:		
				var hero_id = owner_card.get_controller_hero_id()
				if hero_id:
					all_cards =  cfc.NMAP.board.get_enemies_engaged_with(hero_id)
			for other_card in all_cards:
				if other_card == card:
					continue
				if other_card.get_property("guard", 0, true) and other_card.is_faceup: #TODO better way to ignore face down cards?
					var other_type_code = other_card.get_property("type_code", "")
					if other_type_code == "villain":
						#if another villain has "guard" and I don't have it myself,
						#it means that other villain is protecting me
						if !card.get_property("guard", 0, true):
							return false
					else:
						if bypass_guard:
							scripting_bus.emit_signal_on_stack("bypass_guard_happened", action_character, {"target": other_card})
						else:
							return false

	#check for condition preventing thwart
	if ((script_name == "thwart") or ("thwart" in tags)):
		if card.get_property("cannot_be_thwarted", 0, true):
			return false
		if owner_card and owner_card.get_property("cannot_thwart_side_schemes", 0, true):
			if card.get_property("type_code", "") == "side_scheme":
				return false
		
		var bypass_patrol = action_character.get_property("bypass_patrol", 0, true) if action_character else 0		
		#check for special patrol condition	on thwart	
		if card in gameData.get_main_schemes():
			var all_cards = cfc.NMAP.board.get_all_cards()
			if owner_card:		
				var hero_id = owner_card.get_controller_hero_id()
				if hero_id:
					all_cards =  cfc.NMAP.board.get_enemies_engaged_with(hero_id)
			for other_card in all_cards:
				if other_card == card:
					continue
				if other_card.get_property("patrol", 0, true) and other_card.is_faceup: #TODO better way to ignore face down cards?
					if card in other_card.get_active_main_schemes(): #last verification to make sure that the patrol card considers this main scheme as an active main scheme
						if bypass_patrol:
							scripting_bus.emit_signal_on_stack("bypass_patrol_happened", action_character, {"target": other_card})
						else:
							return false

	var type_code = card.get_property("type_code", "")
	#cannot thwart side schemes
	if ((script_name == "thwart") or ("thwart" in tags)):
		if owner_card.get_property("cannot_thwart_" + type_code, 0, true):
			return false	

	var card_matches = true
	if is_instance_valid(card) and card_scripts.get(ScriptProperties.FILTER_STATE + type):
		# each "filter_state_" FILTER is an array.
		# Each element in this array is dictionary of "AND" conditions
		# The filter will fail, only if ALL the or elements in this array
		# fail to match.
		var state_filters_array : Array = card_scripts.get(ScriptProperties.FILTER_STATE + type)
		# state_limits is the variable which will hold the dictionary
		# detailing which card state which the subjects must match
		# to satisfy this filter
		for state_filters in state_filters_array:
			card_matches = true
			for filter in state_filters:
				var state_filter = preprocess_numbers(state_filters[filter], card, owner_card)

				# We check with like this, as it allows us to provide an "AND"
				# check, by simply apprending something into the state string
				# I.e. if we have filter_properties and filter_properties2
				# It will treat these two states as an "AND"				
				if filter == FILTER_MAX_PER_HERO\
						and not check_max_per_hero(card, state_filter, owner_card):
					card_matches = false
				elif filter == FILTER_MAX_PER_HOST\
						and not check_max_per_host(card, state_filter, owner_card):
					card_matches = false
				elif filter == FILTER_EXHAUSTED and (card.is_exhausted() != state_filter):
					card_matches = false
				elif filter == FILTER_HOSTED_BY:
					if !check_hosted_by_filter(card,owner_card,state_filter):
						card_matches =  false	
				elif filter == FILTER_FUNC:
					if !check_func_filter(card,owner_card,state_filter):
						card_matches =  false							
				if filter.ends_with("_same_as_identity"):
					var property = filter.replace("filter_", "").replace("_same_as_identity", "")
					if !check_trigger_shares_property_with_identity(card,owner_card,property):
						card_matches = false								
			if card_matches:
				break
	return(card_matches)


#todo in the future this needs to redo targeting, etc...
static func retrieve_subjects(value:String, script):
	match value:
		"self":
			return [script.owner]
		"my_hero":
			return [script.owner.get_controller_hero_card()]			
		_:
			#not implemented
			pass
	
	if value.begins_with("identity_"):
		var hero_id = int(value.substr(9))
		return [gameData.get_identity_card(hero_id)]
	
	return null
					

static func card_matches_properties (card, filter_properties = {}):
	for key in filter_properties:
		var value
		if typeof(card) == TYPE_DICTIONARY:
			value = card.get(key, "")
		else:
			value = card.get_property(key)
			
		if value != filter_properties[key]:
			return false 

	return true
