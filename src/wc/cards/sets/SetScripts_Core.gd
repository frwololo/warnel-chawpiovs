extends Reference



# This fuction merges text files scripts for a given card 
# with default rules for the game (rules that apply to all cards)
# Specifically, it converts card keywords (cost, threat,...) into actual scripts for the engine
func get_scripts(scripts: Dictionary, card_name: String, get_modified = true) -> Dictionary:

	var card = cfc.card_definitions[card_name]
	var	cost = card["Cost"] if (card && card.has("Cost")) else 0
	
	#Grid position depending on card type
	var type_code:String = card["type_code"] if (card && card.has("type_code")) else ""
	var grid = CFConst.TYPECODE_TO_GRID.get(type_code, "")
	var move_after_play : Dictionary = {
		"name": "move_card_to_board",
		"subject": "self",
		"grid_name" : grid
	}	
	if CFConst.TYPECODE_TO_PILE.has(type_code):
		move_after_play  = {
		"name": "move_card_to_container",
		"subject": "self",
		"dest_container" : CFConst.TYPECODE_TO_PILE[type_code]
	}

	
	var script:Dictionary = scripts.get(card_name,{})
	if script :
		pass
	script = script.duplicate()
	
	#Add game specific rules valid for all cards
	
	#Play From hand: discard a specific number of cards to play
	#TODO limit to player cards ?
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
					move_after_play
				]
			}
		}
	elif (card.has("Cost"))	: #Card has a cost but it's zero
		playFromHand = {
			"manual": {
				"hand": [
					move_after_play
				]
			}
		}		
	script = WCUtils.merge_dict(script, playFromHand, true)
	
	if "scheme" in type_code:
		var base_threat = card.get("base_threat", 0)
		var scheme_comes_to_play: Dictionary = { 
			"card_moved_to_board": {
				"trigger": "self",
				"board": [
					{
						"name": "mod_tokens",
						"subject": "self",
						"modification": base_threat,
						"token_name":  "threat",
					},					
				]
			}
		}
		
		script = WCUtils.merge_dict(script,scheme_comes_to_play, true)

	if card.get("_horizontal", false):
		var horizontal_comes_to_play: Dictionary = { 
			"card_moved_to_board": {
				"trigger": "self",
				"board": [
					{
						"name": "rotate_card",
						"subject": "self",
						"degrees": 90,
					},					
				]
			}
		}
		script = WCUtils.merge_dict(script,horizontal_comes_to_play, true)
	
	if type_code == "ally":
		var base_threat = card.get("base_threat", 0)
		var ally_actions: Dictionary = { 
			"manual": {
				"board": {
					"thwart": [
						{
							"name": "rotate_card",
							"subject": "self",
							"degrees": 90,
							"is_cost" : true,
						},						
						{
							"name": "thwart",
							"subject": "target",
							"needs_subject": true,
							"filter_state_subject": [{
								"filter_group": "schemes"
							},],						
						},					
					],
					"attack" :[
						{
							"name": "rotate_card",
							"subject": "self",
							"degrees": 90,
							"is_cost" : true,
						},						
						{
							"name": "attack",
							"subject": "target",
							"needs_subject": true,
							"filter_state_subject": [{
								"filter_group" : "enemies"
							},],						
						},					
					],
				}
			}
		}
		
		script = WCUtils.merge_dict(script,ally_actions, true)
	
	return script
