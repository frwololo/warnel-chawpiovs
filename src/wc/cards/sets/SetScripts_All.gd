class_name SetScripts_All
extends Reference


static func has_interrupt(script:Dictionary) -> String:
	var results = []
	for _k in script.keys():
		var k:String = _k
		if (k.begins_with("interrupt")):
			results.append(k)
	return results

static func keyword_to_script(keyword, _value):
	match keyword:
		"alliance" :
			pass
		"assault" :
			pass
		"form" :
			pass 
		"hinder" :
			pass
		"incite" :
			pass
		"linked" :
			pass 
		"overkill" :
			pass 
		"patrol" :
			pass
		"peril" :
			pass 
		"permanent" :
			pass 
		"piercing" :
			pass 
		"quickstrike" :
			pass 
		"ranged" :
			pass 
		"requirement" :
			pass 
		"restricted" :
			pass 
		"setup" :
			pass 
		"stalwart" :
			pass 
		"steady" :
			pass 
		"surge" :
			pass 
		"team-up" :
			pass 
		"teamwork" :
			pass 
		"temporary" :
			pass 
		"toughness" :
			return { 
				"self_moved_to_board": {
					"board": [
						{
							"name": "mod_tokens",
							"subject": "self",
							"modification": 1,
							"token_name":  "tough",
						},					
					]
				}
			}
		"victory" :
			pass
		"villainous" :
			pass
		_:
			pass
	return null		

# This fuction merges text files scripts for a given card 
# with default rules for the game (rules that apply to all cards)
# Specifically, it converts card keywords (cost, threat,...) into actual scripts for the engine
static func get_scripts(scripts: Dictionary, card_id: String, _get_modified = true) -> Dictionary:
	if !_get_modified:
		return scripts.get(card_id,{})

	var card = cfc.card_definitions[card_id]
	var	cost = card["Cost"] if (card && card.has("Cost")) else 0
	

	var type_code:String = card.get("type_code", "") 
	var play_action : Dictionary = {
		"name": "play_card",
		"subject": "self",
		"is_cost" : true,
	}	


	
	var script:Dictionary = scripts.get(card_id,{})
	if script :
		pass #debug location for breakpoints
	script = script.duplicate()
	
	#Add game specific rules valid for all cards

	var post_play_actions = []
	var hand_constraints = []

	var play_only_if_traits =  card.get("play_only_if_traits", [])
	if play_only_if_traits:
		hand_constraints.append(
				{
					"name": "constraints",
					"is_cost": true,
					"constraints": [
						{
							"func_name": "identity_has_trait",
							"func_params": {
								"trait": play_only_if_traits
							}
						}
					]
				}			
		)		
	if (type_code == "event"):
		if card.get("max 1 per phase"):
				hand_constraints.append(
					{	
						"name": "constraints",
						"is_cost": true,
						"max_per_phase": 1
					}			
				)	
		if card.get("max 1 per round"):
				hand_constraints.append(
					{	
						"name": "constraints",
						"is_cost": true,
						"max_per_round": 1
					}			
				)							
		var is_defense = card.get("trait_defense", 0)
		if is_defense:
			post_play_actions.append(
				{
					"name": "set_defender",
					"subject": "my_identity"
				}
			)
			
		for trait in ["defense", "thwart", "attack"]:
			var has_trait = card.get("trait_" + trait, 0)
			if has_trait:
				hand_constraints.append(
					{	
						"name": "constraints",
						"is_cost": true,
						"tags": [trait + "_ability"]
					}			
				)			
	#interrupt or response replacements
	var interrupt_scripts = has_interrupt(script)
	var has_manual_hand = script.get("manual", {}).get("hand", {})
	var process_manual_cost = true
	if (type_code == "event" && interrupt_scripts):
		if !has_manual_hand:
			process_manual_cost = false
			
		var playFromHand: Array = hand_constraints
		if (cost):
			playFromHand +=  [
				{
					"name": "pay_regular_cost",
					"is_cost": true,
					"cost" : "card_cost", #keyword here to retrieve cost realtime
				},
				play_action
			]	
		elif (card.has("Cost"))	: #Card has a cost but it's zero
			playFromHand += [
				play_action
			]
		
		playFromHand += post_play_actions
					
		var playInterrupt: Dictionary = {}
		for interrupt_script in interrupt_scripts:			
			#TODO add trigger filters + interrupt data
			playInterrupt[interrupt_script] =  {
				"hand" : playFromHand
			} 
		script = WCUtils.merge_dict(script, playInterrupt, true)
	if process_manual_cost: #Regular cards
		#Play From hand: discard a specific number of cards to play
		#TODO limit to player cards ?
		var has_overpaid_check = WCUtils.is_string_in_variant(script, "overpaid")
		var playFromHand: Dictionary = { }
		if (cost or has_overpaid_check):
			playFromHand = {
				"manual": {
					"hand": hand_constraints + [
						{	
							"name": "constraints",
							"is_cost": true,
							"tags": ["as_action"]
						},	
						{
							"name": "pay_regular_cost",
							"is_cost": true,
							"cost" : "card_cost", #keyword here to retrieve cost realtime
						},
						play_action
					] + post_play_actions
				}
			}
		elif (card.has("Cost"))	: #Card has a cost but it's zero
			playFromHand = {
				"manual": {
					"hand": hand_constraints +[
						{	
							"name": "constraints",
							"is_cost": true,
							"tags": ["as_action"]
						},						
						play_action
					] + post_play_actions
				}
			}
		#existing scripts are occasionally a dictionary instead of 
		#array. e.g. Flora and Fauna. In this case the merge is a bit more complicated	
		var hand_script = script.get("manual", {}).get("hand", [])
		if typeof(hand_script) == TYPE_DICTIONARY:
			var to_merge = playFromHand["manual"]["hand"]
			for key in hand_script.keys():
				hand_script[key] = to_merge + hand_script[key]
		else:	
			#note: order matters here in some cases. generally speaking
			# we want cost to be paid first, therefore be at the top of the array			
			script = WCUtils.merge_dict( playFromHand, script, true)
		if "scheme" in type_code:
			var scheme_comes_to_play: Dictionary = { 
				"self_moved_to_board": {
					"board": [
						{
							"name": "scheme_base_threat",
						},					
					]
				}
			}
			
			script = WCUtils.merge_dict(script,scheme_comes_to_play, true)
	
	if type_code == "ally" or type_code == "hero":
		var actions = {}
		for action in ["thwart", "attack"]:
			if !card["can_" + action]:
				continue
			var target = "schemes" if action == "thwart" else "enemies"
			var action_script = [
				{	
					"name": "constraints",
					"is_cost": true,
					"tags": ["as_action"]
				},						
				{
					"name": "exhaust_card",
					"subject": "self",
					"is_cost" : true,
				},						
				{
					"name": action,
					"subject": "target",
					"is_cost": true,
					"needs_subject": true,
					"tags": [action, "basic power"],
					"filter_state_subject": [{
						"filter_group": "group_" + target
					},],						
				},					
			]
			actions[action] = action_script
		if actions:
			var ally_actions: Dictionary = { 
				"manual": {
					"board": actions
				}
			}		
			script = WCUtils.merge_dict(script,ally_actions, true)

	if type_code == "alter_ego": 
		var alter_ego_actions: Dictionary = { 
			"manual": {
				"board": {
					"recover": [
						{	
							"name": "constraints",
							"is_cost": true,
							"tags": ["as_action"]
						},						
						{
							"name": "exhaust_card",
							"subject": "self",
							"is_cost" : true,
						},							
						{
							"name": "recovery",
							"subject": "self",
							"is_cost": true,	
							"needs_subject": true,
							"tags": ["basic power"]
						}				
					]
				}
			}			
		}		
		script = WCUtils.merge_dict(script,alter_ego_actions, true)

	if type_code == "hero"  or type_code == "alter_ego":
		var identity_actions: Dictionary = { 			
			"ally_limit_rule": {
				"board": [
					{
						"is_cost": true,
						"subject_index": "top",
						SP.KEY_SELECTION_OPTIONAL: false,
						"name": "move_card_to_container",
						"dest_container": "discard",
						"subject":"boardseek",
						"subject_count": "all",
						"selection_count": 1,
						"selection_type": "equal",					
						"needs_selection": true,
						"filter_state_seek": [{
							"filter_group" : "group_allies_my_hero"
						}],
						"display_title": "Ally limit"
					}				
				]
			},
			"restricted_limit_rule": {
				"board": [
					{
						"is_cost": true,
						"subject_index": "top",
						SP.KEY_SELECTION_OPTIONAL: false,
						"name": "move_card_to_container",
						"dest_container": "discard",
						"subject":"boardseek",
						"subject_count": "all",
						"selection_count": 1,
						"selection_type": "equal",					
						"needs_selection": true,
						"filter_state_seek": [{
							"filter_group" : "play_area_my_hero",
							"filter_properties" : {"restricted" : 1}
						}],
						"display_title": "Restricted limit"
					}				
				]
			},			
			"mulligan": {
				"board": [
					{
						"name": "move_card_to_container",
						"is_cost": true,
						"subject": "index",
						"subject_count": "all",
						"subject_index": "top",
						SP.KEY_NEEDS_SELECTION: true,
						SP.KEY_SELECTION_COUNT:0, 
						SP.KEY_SELECTION_TYPE: "min",
						SP.KEY_SELECTION_OPTIONAL: true,
						"hide_ok_on_zero": true,
						"src_container": "hand",
						"dest_container": "discard",						
						"display_title": "__mulligan__"
					},
					{
						"name" : "draw_to_hand_size",
					}				
				]
			},			
			"end_phase_discard": {
				"board": [
					{
						"name": "end_phase_discard",
						"is_cost": true,
						"subject": "index",
						"subject_count": "all",
						"subject_index": "top",
						SP.KEY_NEEDS_SELECTION: true,
						SP.KEY_SELECTION_COUNT:0, 
						SP.KEY_SELECTION_TYPE: "min",
						SP.KEY_SELECTION_OPTIONAL: true,
						"hide_ok_on_zero": true,
						"src_container": "hand",						
						"display_title": "__end_phase_discard__"
					}				
				]
			}						
		}
		
		#adding change form script as needed
		var change_form_script =  {
			"manual": {
				"board": {
					"Change Form": [
						{	
							"name": "constraints",
							"is_cost": true,
							"tags": ["as_action"]
						},						
						{
							"name": "change_form",
							"subject": "self",
							"is_cost" : true,
							"tags": ["player_initiated"]
						}	
					]			
				}
			}
		}		
		#if the card has its own change form scripts (e.g. Ant-Man), we don't use the default one
		var existing_manual_board_scripts = script.get("manual", {}).get("board", [])	
		if typeof(existing_manual_board_scripts) == TYPE_DICTIONARY:
			for key in existing_manual_board_scripts:
				if key.to_lower().begins_with("change form"):
					change_form_script = {}
					break		
		if change_form_script:
			identity_actions = WCUtils.merge_dict(identity_actions, change_form_script)
					
		script = WCUtils.merge_dict(script,identity_actions, true)


	
	if type_code == "villain" or type_code == "minion":
		var enemy_scripts = get_enemy_scripts()
		script = WCUtils.merge_dict(script,enemy_scripts, true)
	var keywords:Dictionary = card.get("keywords", {})
	for keyword in keywords.keys():
		if !keywords[keyword]:
			continue
		var k_script = keyword_to_script(keyword, keywords[keyword])
		if (k_script):
			script = WCUtils.merge_dict(script,k_script, true)
	
	if type_code == "attachment":
		var alterants = []
		for action in ["attack", "scheme", "thwart"]:
			var mod = card.get(action, 0)
			if mod:
				alterants.append(
					{
						"filter_task": "get_property",
						"filter_property_name": action,
						"trigger": "host",
						"alteration": mod
					}
				)
		if alterants:
			var a_script = {
				"alterants": {
					"board": alterants
				}
			}
			script = WCUtils.merge_dict(script,a_script, true)
	
#	if card["Name"] == "Rapid Growth":
#		var string = JSON.print(script, '\t')			
#		var _tmp = 1
	
	return script

static func get_enemy_scripts():
	var enemy_scripts: Dictionary = { 
		"enemy_attack": {
			"board": [
				{
					"name": "enemy_attack",
					"subject": "boardseek",	
					"subject_count": "all",
					"hide_ok_on_zero": true,
					SP.KEY_NEEDS_SELECTION: true,
					SP.KEY_SELECTION_COUNT: 1,
					SP.KEY_SELECTION_TYPE: "max",
					SP.KEY_SELECTION_OPTIONAL: true,
					"filter_state_seek": [{
						"filter_group": "group_defenders"
					},],
				}					
			]
		},
		"commit_scheme": {
			"board": [
				{
					"name": "commit_scheme",
				}					
			]
		}			
	}
	return enemy_scripts		
