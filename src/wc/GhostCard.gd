class_name GhostCard
extends WCCard

var _real_card: WCCard setget set_real_card, get_real_card

# Declare member variables here. Examples:
# var a = 2
# var b = "text"

func set_real_card(card):
	_real_card = card

func get_real_card():
	return _real_card
		
func execute_scripts(
		trigger_card: Card = self,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):
	var passthrough_trigger = trigger_card
	if passthrough_trigger == self:
		passthrough_trigger = _real_card
	
	trigger_details["override_controller_id"] = self.get_controller_hero_id()	
	return _real_card.execute_scripts(passthrough_trigger, trigger, trigger_details, run_type)


#
#Not sure if these functions need to be overridden
#

func get_state_scripts(card_scripts, trigger_card, trigger_details):
	return .get_state_scripts(card_scripts, trigger_card, trigger_details)



# Retrieves the card scripts either from those defined on the card
# itself, or from those defined in the script definition files
#
# Returns a dictionary of card scripts for this specific card
# based on the current trigger.
func retrieve_scripts(trigger: String, filters:={}) -> Dictionary:
	return _real_card.retrieve_scripts(trigger, filters)

# Retrieves the card scripts either from those defined on the card
# itself, or from those defined in the script definition files
#
# Returns a dictionary of card scripts for this specific card
# (based on the current trigger.all triggers)
func retrieve_all_scripts() -> Dictionary:
	return _real_card.retrieve_all_scripts()

# Determines which play position (board, pile or hand)
# a script should look for to find card scripts
# based on the card's state.
#
# Returns either "board", "hand", "pile" or "NONE".
func get_state_exec() -> String:
	return .get_state_exec()


# This function can be overriden by any class extending Card, in order to provide
# a way of checking if a card can be played before dragging it out of the hand.
#
# This method will be called while the card is being focused by the player
# If it returns true, the card will be highlighted as normal and the player
# will be able to drag it out of the hand
#
# If it returns false, the card will be highlighted with a red tint, and the
# player will not be able to drag it out of the hand.
func check_play_costs() -> Color:
	var result = .check_play_costs()
	return result

# Returns true is the card has hand_drag_starts_targeting set to true
# is currently in hand, and has a targetting task.
#
# This is used by the _on_Card_gui_input to determine if it should fire
# scripts on the card during an attempt to drag it from hand.
func _has_targeting_cost_hand_script() -> bool:
	return _real_card._has_targeting_cost_hand_script()


# Ensures that all filters requested by the script are respected
#
# Will set is_valid to false if any filter does not match reality
func _filter_signal_trigger(card_scripts, trigger_card: Card) -> bool:
	return ._filter_signal_trigger(card_scripts, trigger_card)




