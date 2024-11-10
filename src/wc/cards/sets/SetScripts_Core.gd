extends Reference

const TYPECODE_TO_GRID := {
	"ally" : "allies",
	"upgrade" : "upgrade_support",
	"support" : "upgrade_support",
}

# This fuction merges text files scripts for a given card 
# with default rules for the game (rules that apply to all cards)
func get_scripts(scripts: Dictionary, card_name: String, get_modified = true) -> Dictionary:

	var card = cfc.card_definitions[card_name]
	var	cost = card["Cost"] if (card && card.has("Cost")) else 0
	
	#Grid position depending on card type
	var type_code = card["type_code"] if (card && card.has("type_code")) else ""
	var grid = TYPECODE_TO_GRID.get(type_code, "")
	
	var script:Dictionary = scripts.get(card_name,{})
	if script :
		pass
	script = script.duplicate()
	
	#Add game specific rules valid for all cards
	
	#Play From hand: discard a specific number of cards to play
	#TODO this is not specific to core set and should therefore be moved somewhere else more general
	var playFromHand: Dictionary = { }
	if (cost):
		playFromHand = {
			"manual": {
				"hand": [
					{
						"name": "pay_regular_cost",
						"is_cost": true,
						"cost" : cost,
					},
#			"manual": {
#				"hand": [
#					{
#						"name": "pay_regular_cost",
#						"is_cost": true,
#						"subject": "index",
#						"subject_count": "all",
#						"subject_index": "top",
#						SP.KEY_NEEDS_SELECTION: true,
#						SP.KEY_SELECTION_COUNT: cost,
#						"cost" : cost,
#						SP.KEY_SELECTION_TYPE: "equal",
#						SP.KEY_SELECTION_OPTIONAL: false,
#						SP.KEY_SELECTION_IGNORE_SELF: true,
#						"src_container": "hand",
#						"dest_container": "discard{current_hero}",
#					},
					{
						"name": "move_card_to_board",
						"subject": "self",
						"grid_name" : grid
					},
				]
			}
		}
	elif (card.has("Cost"))	: #Card has a cost but it's zero
		playFromHand = {
			"manual": {
				"hand": [
					{
						"name": "move_card_to_board",
						"subject": "self",
						"grid_name" : grid
					},
				]
			}
		}		
	script = WCUtils.merge_dict(script, playFromHand, true)
	return script
