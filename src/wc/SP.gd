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
const KEY_SUBJECT_V_VILLAIN := "villain"
const FILTER_HOST_OF := "filter_is_host_of"
const FILTER_SAME_CONTROLLER := "filter_same_controller"

const TRIGGER_TARGET_HERO = "target_hero"
const TRIGGER_SUBJECT = "trigger_subject"

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
	if is_valid and card_scripts.get(FILTER_HOST_OF) \
			and !check_host_filter(trigger_card,owner_card,card_scripts.get(FILTER_HOST_OF)):
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

	return(is_valid)

# Returns true if the trigger is the host of the owner, false otherwise
static func check_host_filter(trigger_card, owner_card, host_description : String) -> bool:
	var card_matches := false
	if !is_instance_valid(trigger_card): return false
	if !is_instance_valid(owner_card): return false
	
	match host_description:
		"self":
			if owner_card.current_host_card == trigger_card: 
				card_matches = true
	return(card_matches)
	
# Returns true if the trigger and the owner belong to the same hero, false otherwise
static func check_same_controller_filter(trigger_card, owner_card, true_false : bool) -> bool:
	var same_controller: bool = (owner_card.get_controller_hero_id() == trigger_card.get_controller_hero_id())
	if (same_controller and true_false): return true
	if ((not same_controller) and (not true_false)): return true
	return false


# Check if the card is a valid subject or trigger, according to its state.
static func check_validity(card, card_scripts, type := "trigger") -> bool:
	var is_valid = .check_validity(card, card_scripts, type)
	if (!is_valid):
		return is_valid
		
	var tags = card_scripts.get("tags", [])
	
	#check for special guard conditions if card is an attack
	if ("attack" in tags) and card == gameData.get_villain():
		var all_cards = cfc.NMAP.board.get_all_cards()
		for card in all_cards:
			if card.get_keyword("guard") and card.is_faceup: #TODO better way to ignore face down cards?
				return false
	
	return is_valid	
