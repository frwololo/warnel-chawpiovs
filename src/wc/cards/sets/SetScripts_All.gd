class_name SetScripts_All
extends Reference


func has_interrupt(script:Dictionary) -> String:
	for _k in script.keys():
		var k:String = _k
		if (k=="interrupt"):
			return k
	return ""

func keyword_to_script(keyword, _value):
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
				"card_moved_to_board": {
					"trigger": "self",
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
func get_scripts(scripts: Dictionary, card_id: String, _get_modified = true) -> Dictionary:
	if !_get_modified:
		return scripts.get(card_id,{})

	var card = cfc.card_definitions[card_id]
	var	cost = card["Cost"] if (card && card.has("Cost")) else 0
	
	#Grid position depending on card type
	var type_code:String = card["type_code"] if (card && card.has("type_code")) else ""
	var grid = CFConst.TYPECODE_TO_GRID.get(type_code, "")
	var move_after_play : Dictionary = {
		"name": "play_card",
		"subject": "self",
		"needs_subject" : true,
		"grid_name" : grid
	}	
	if CFConst.TYPECODE_TO_PILE.has(type_code):
		move_after_play  = {
		"name": "play_card",
		"subject": "self",
		"needs_subject" : true,
		"dest_container" : CFConst.TYPECODE_TO_PILE[type_code]
	}

	
	var script:Dictionary = scripts.get(card_id,{})
	if script :
		pass #debug location for breakpoints
	script = script.duplicate()
	
	#Add game specific rules valid for all cards
	
	#interrupt or response replacements
	var interrupt_script = has_interrupt(script)
	if (type_code == "event" && interrupt_script):
		var playFromHand: Array = []
		if (cost):
			playFromHand =  [
				{
					"name": "pay_regular_cost",
					"is_cost": true,
					"cost" : "card_cost", #keyword here to retrieve cost realtime
				},
				move_after_play
			]	
		elif (card.has("Cost"))	: #Card has a cost but it's zero
			playFromHand = [
				move_after_play
			]
					
		var playInterrupt: Dictionary = {
			#TODO add trigger filters + interrupt data
			interrupt_script: {
				"hand" : playFromHand
			} 
		}
		script = WCUtils.merge_dict(script, playInterrupt, true)
		script = script
	else: #Regular cards
		#Play From hand: discard a specific number of cards to play
		#TODO limit to player cards ?
		var playFromHand: Dictionary = { }
		if (cost):
			playFromHand = {
				"manual": {
					"hand": [
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
						move_after_play
					]
				}
			}
		elif (card.has("Cost"))	: #Card has a cost but it's zero
			playFromHand = {
				"manual": {
					"hand": [
						{	
							"name": "constraints",
							"is_cost": true,
							"tags": ["as_action"]
						},						
						move_after_play
					]
				}
			}
		#note: order matters here in some cases. generally speaking
		# we want cost to be paid first, therefore be at the top of the array			
		script = WCUtils.merge_dict( playFromHand, script, true)
		
		if "scheme" in type_code:
			var scheme_comes_to_play: Dictionary = { 
				"card_moved_to_board": {
					"trigger": "self",
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
					"recovery": [
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
							"needs_subject": true,
							"tags": ["basic power"]
						}				
					]
				}
			}			
		}		
		script = WCUtils.merge_dict(script,alter_ego_actions, true)

	if type_code == "hero"  or type_code == "alter_ego": 
		var hero_actions: Dictionary = { 
			"manual": {
				"board": {
					"change form": [
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
			},
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
							"filter_group" : "group_allies"
						}],
						"display_title": "Ally limit"
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
						"dest_container": "discard",						
						"display_title": "__end_phase_discard__"
					}				
				]
			}						
		}		
		script = WCUtils.merge_dict(script,hero_actions, true)


	
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
	
	return script

static func get_enemy_scripts():
	var enemy_scripts: Dictionary = { 
		"enemy_attack": {
			"board": [
				{
					"name": "enemy_attack",
					"subject": "boardseek",	
					"is_cost": true,
					"subject_count": "all",
					"hide_ok_on_zero": true,
					SP.KEY_NEEDS_SELECTION: true,
					SP.KEY_SELECTION_COUNT: 1,
					SP.KEY_SELECTION_TYPE: "max",
					SP.KEY_SELECTION_OPTIONAL: true,
					"filter_state_seek": [{
						"filter_group": "group_defenders"
					},],
				},
				{
					"name": "undefend",	
					"is_else": true,
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
