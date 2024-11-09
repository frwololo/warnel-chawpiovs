# Data that represents the Scenario / Villain Deck
class_name ScenarioDeckData
extends Reference

var villains:Array
var schemes:Array
var encounter_deck:Array

func _init():
	pass


func load_from_dict(_scenario:Dictionary):
	var set_name = _scenario["card_set_name"]
	schemes = cfc.get_schemes[set_name]

func get_villains():
	if (schemes.empty()):
		print_debug("data not loaded in ScenarioDeckData")
		return []
	if (not villains.empty()):
		return villains
		
	var first_scheme = schemes[0]
	var first_scheme_name = first_scheme["name"]
	var scheme_primitive = cfc.primitives[first_scheme_name]
	var villain_strings : Array = scheme_primitive["villains"]
	if (not villain_strings or villain_strings.empty()):
		print_debug("villains missing in ScenarioDeckData")
		return []			
	#get villains in order, split strings to get name and stage.
	for villain_string in villain_strings:
		villains.push_back(cfc.card_definitions[villain_string])
		#var villain_data = villain_string.split("_")
		#var villain_name = villain_data[0]
		#var villain_stage = int(villain_data[1])
	return villains
		
func get_encounter_deck():
	if (not encounter_deck.empty()):
		return encounter_deck
		
	if (schemes.empty()):
		print_debug("data not loaded in ScenarioDeckData")
		return []

	encounter_deck = []
		
	var first_scheme = schemes[0]
	var first_scheme_name = first_scheme["name"]
	var scheme_primitive = cfc.primitives[first_scheme_name]
	var encounter_sets : Array = scheme_primitive["encounter_sets"]		
	var default_modular_sets : Array = scheme_primitive["modular_default"]
	
	# Add sets (from scenario, standard + modular sets)
	var modular_set_count = 0
	for encounter_set_name in encounter_sets:
		if (encounter_set_name.to_lower() == "modular"): #special case for modular sets
			encounter_set_name = default_modular_sets[modular_set_count]
			modular_set_count += 1
		var encounter_set : Array = cfc.get_encounter_cards(encounter_set_name)
		for card_data in encounter_set:
			var card_type = card_data[CardConfig.SCENE_PROPERTY]
			if (card_type != "Main_Scheme" and card_type != "Villain"): #skip villain and schemes from the deck
				encounter_deck.push_back(card_data)
				
	#add hero obligations
	#for all heroes in game data, add hero's obligation
	for hero_data in gameData.team.values():
		var obligation_card = cfc.get_hero_obligation(hero_data.hero_id)
		encounter_deck.push_back(obligation_card)
	return encounter_deck
