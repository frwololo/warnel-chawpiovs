# Data that represents the Scenario / Villain Deck
class_name ScenarioDeckData
extends Reference

#card definitions
var villains:Array


var schemes:Array
var modular_sets:=[]
var is_expert_mode:= false
var encounter_deck:Array

func _init():
	pass


static func get_recommended_modular_encounter(scheme_id):
	var scheme_primitive = cfc.primitives.get(scheme_id, {})
	if !scheme_primitive:
		return ""
	
	var modular_defaults: Array = scheme_primitive.get("modular_default", [])
	if modular_defaults:
		return modular_defaults[0]
	return ""
	
static func get_villains_from_scheme(scheme_id, expert_mode:= false):
	var scheme_primitive = cfc.primitives.get(scheme_id, {})
	if !scheme_primitive:
		return []
		
	var villain_strings : Array = scheme_primitive["villains"]
	if expert_mode and scheme_primitive.has("expert"):		
		villain_strings = scheme_primitive["expert"].get("villains", villain_strings)
		
	if (not villain_strings or villain_strings.empty()):
		print_debug("villains missing in ScenarioDeckData")
		return []			
	
	var results = []
	#get villains in order, split strings to get name and stage.
	for villain_string in villain_strings:
		var card_id = cfc.get_corrected_card_id(villain_string)
		results.append(cfc.card_definitions[card_id])

	return results	

#		"scheme_id" : "01097", 
#		"modular_encounter": "bomb_scare",
#		"expert_mode": true,false	
func load_from_dict(_scenario:Dictionary):
	var scheme_card_id = _scenario.get("scheme_id")
	if !scheme_card_id:
		var _error =1
		print_debug("Scheme ID not set in load_from_dict")
		return
	
	schemes = cfc.get_schemes(scheme_card_id)
	
	is_expert_mode =  _scenario.get("expert_mode", false)
	modular_sets = _scenario.get("modular_encounters", [])
	
	#Preload
	get_villains()
	get_encounter_deck()

func get_villains():
	if (schemes.empty()):
		print_debug("data not loaded in ScenarioDeckData")
		return []
	if (not villains.empty()):
		return villains
		
	var first_scheme = schemes[0]
	villains = get_villains_from_scheme(first_scheme["_code"], is_expert_mode)
		
func get_encounter_deck():
	if (not encounter_deck.empty()):
		return encounter_deck
		
	if (schemes.empty()):
		print_debug("data not loaded in ScenarioDeckData")
		return []

	encounter_deck = []
		
	var first_scheme = schemes[0]
	var first_scheme_name = first_scheme["Name"]
	var scheme_primitive = cfc.primitives[first_scheme_name]
	var encounter_sets : Array = scheme_primitive["encounter_sets"]		

	if is_expert_mode and scheme_primitive.has("expert"):		
		encounter_sets = scheme_primitive["expert"].get("encounter_sets", encounter_sets)

	
	# Add sets (from scenario, standard + modular sets)
	var modular_set_count = 0
	for encounter_set_code in encounter_sets:
		if (encounter_set_code.to_lower() == "modular"): #special case for modular sets
			encounter_set_code = modular_sets[modular_set_count]
			modular_set_count += 1
		var encounter_set : Array = cfc.get_encounter_cards(encounter_set_code)
		for card_data in encounter_set:
			var card_type = card_data["type_code"]
			if (card_type != "main_scheme" and card_type != "villain"): #skip villain and schemes from the deck
				if (1): #card_type == "Minion" or card_type == "Side_scheme"): #TODO debug
					encounter_deck.push_back(card_data)
				
	#add hero obligations
	#for all heroes in game data, add hero's obligation
	for hero in gameData.team.values():
		var hero_data = hero["hero_data"]
		var obligation_card = cfc.get_hero_obligation(hero_data.get_hero_id())
		encounter_deck.push_back(obligation_card)
	return encounter_deck
