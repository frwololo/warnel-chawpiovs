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
const KEY_SUBJECT_V_GRAB_UNTIL := "grab_until"
const KEY_SUBJECT_CURRENT_ACTIVATION_ENEMY:= "current_activation_enemy"

const FILTER_HOST_OF := "filter_is_host_of"
const FILTER_SAME_CONTROLLER := "filter_same_controller"
const FILTER_EVENT_SOURCE:= "filter_event_source"
const FILTER_SOURCE_CONTROLLED_BY := "filter_source_controlled_by"

const FILTER_MAX_PER_HERO := "filter_max_per_hero"
const FILTER_MAX_PER_HOST := "filter_max_per_host"

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

	# Card Host filter checks
	if is_valid and card_scripts.get(FILTER_HOST_OF):
		if !check_host_filter(trigger_card,owner_card,card_scripts.get(FILTER_HOST_OF)):
			is_valid = false

	# Same Controller filter check
	if is_valid and card_scripts.get(FILTER_SAME_CONTROLLER) \
			and !check_same_controller_filter(trigger_card,owner_card,card_scripts.get(FILTER_SAME_CONTROLLER)):
		is_valid = false
		
	if is_valid and card_scripts.get("filter_" + TRIGGER_TARGET_HERO) \
			and card_scripts.get("filter_" + TRIGGER_TARGET_HERO) != \
			trigger_details.get(TRIGGER_TARGET_HERO):
		is_valid = false		

	if is_valid and card_scripts.get(TRIGGER_SUBJECT):
		match card_scripts.get(TRIGGER_SUBJECT):
			"self":
				var subjects = trigger_details.get("subjects", [])
				if !(owner_card in (subjects)):
					is_valid = false
			_: 
				is_valid = false

	if is_valid and card_scripts.get(FILTER_SOURCE_CONTROLLED_BY) \
			and !check_source_controlled_by_filter(trigger_card,owner_card,trigger_details, card_scripts.get(FILTER_SOURCE_CONTROLLED_BY)):
		is_valid = false	
		
	if is_valid and card_scripts.get(FILTER_EVENT_SOURCE) \
			and !check_filter_event_source(trigger_card,owner_card,trigger_details, card_scripts.get(FILTER_EVENT_SOURCE)):
		is_valid = false	

	return(is_valid)

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

# Returns true if the trigger and the owner belong to the same hero, false otherwise
static func check_source_controlled_by_filter(_trigger_card, owner_card, trigger_details, expected_controller) -> bool:
	var source = trigger_details.get("source", null)
	if guidMaster.is_guid(source):
		source = guidMaster.get_object_by_guid(source)
		
	match expected_controller:
		"my_hero":
			var controller_hero_id = source.get_controller_hero_id()
			if controller_hero_id == owner_card.get_controller_hero_id():
				return true
			return false
		_: #not implemented
			pass
	return false
	
# Returns true if the trigger and the owner belong to the same hero, false otherwise
static func check_filter_event_source(_trigger_card, owner_card, trigger_details, _expected_event_source) -> bool:
	var source = trigger_details.get("source", null)
	if guidMaster.is_guid(source):
		source = guidMaster.get_object_by_guid(source)
		
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


# Check if the card is a valid subject or trigger, according to its state.
static func check_validity(card, card_scripts, type := "trigger", owner_card = null) -> bool:
	var is_valid = .check_validity(card, card_scripts, type, owner_card)
	if (!is_valid):
		return is_valid
		
	var tags = card_scripts.get("tags", [])
	
	#check for special guard conditions if card is an attack
	if ("attack" in tags) and card == gameData.get_villain():
		var all_cards = cfc.NMAP.board.get_all_cards()
		if owner_card:		
			var hero_id = owner_card.get_controller_hero_id()
			if hero_id:
				all_cards =  cfc.NMAP.board.get_enemies_engaged_with(hero_id)
		for card in all_cards:
			if card.get_keyword("guard") and card.is_faceup: #TODO better way to ignore face down cards?
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
				# We check with like this, as it allows us to provide an "AND"
				# check, by simply apprending something into the state string
				# I.e. if we have filter_properties and filter_properties2
				# It will treat these two states as an "AND"				
				if filter == FILTER_MAX_PER_HERO\
						and not check_max_per_hero(card, state_filters[filter], owner_card):
					card_matches = false
				elif filter == FILTER_MAX_PER_HOST\
						and not check_max_per_host(card, state_filters[filter], owner_card):
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
					
