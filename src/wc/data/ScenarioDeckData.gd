# Data that represents the Scenario / Villain Deck
class_name ScenarioDeckData
extends Reference

#card definitions
var villains:Array


var scheme_card_id:= ""
var schemes:Array
var modular_sets:=[]
var is_expert_mode:= false
var encounter_deck:Array
var extra_decks: = []
var grid_setup:= {}
var scenario_data

func _init():
	pass


static func get_recommended_modular_encounters(scheme_id):
	var scheme_primitive = cfc.primitives.get(scheme_id, {})
	if !scheme_primitive:
		return []
	
	var modular_defaults: Array = scheme_primitive.get("modular_default", [])
	if modular_defaults:
		return modular_defaults
	return []
	
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
#		"modular_encounters": ["bomb_scare"],
#		"expert_mode": true,false	
func load_from_dict(_scenario:Dictionary):
	grid_setup = CFConst.GRID_SETUP.duplicate(true)	
	scheme_card_id = _scenario.get("scheme_id")
	if !scheme_card_id:
		var _error =1
		print_debug("Scheme ID not set in load_from_dict")
		return
	
	schemes = cfc.get_schemes(scheme_card_id)
	if !schemes:
		var _error =1
		print_debug("Can't find schemes for " + scheme_card_id)
		return	
		
	scenario_data = cfc.primitives[scheme_card_id]
	
	is_expert_mode =  _scenario.get("expert_mode", false)
	modular_sets = _scenario.get("modular_encounters", [])
	
	#Preload
	villains = []
	get_villains()
	
	encounter_deck = []
	get_encounter_deck()
	
	setup_extra_decks()

func setup_extra_decks():
	if (!scenario_data):
		print_debug("data not loaded in ScenarioDeckData")
		return []	
	var extra_decks_data = scenario_data.get("extra_decks", [])
	
	var coord_source = grid_setup["discard_villain"]
	var x = 0
	var y = coord_source.get("y", 20)
	var scale = coord_source.get("scale", 1)
	var spacing = 120
	#we invert the deck as we add items to the beginning of the screen,
	#pushing the previous, this way it makes more sense when reading the _scenarios.json file
	extra_decks_data.invert() 
	for extra_deck_data in extra_decks_data:
		var name = extra_deck_data.get("name", "deck_unknown")
		var sets = extra_deck_data.get("encounter_sets", [])
		var deck = get_simple_encounter_deck(sets)
		extra_decks.append(
			{ "name": name,
			  "deck_contents": deck
			}
		)
		
#	"deck_villain" :{
#		"x" : 0,
#		"y" : 20,
#		"type" : "pile",
#		"scale" : 0.5			
#	},		
		
		for key in grid_setup: 
			if grid_setup[key].has("x"):
				#we don't want to push stuff outside of the screen
				if grid_setup[key]["x"] > cfc.screen_resolution.x - ((250 + spacing) * cfc.screen_scale.x):
					pass
				else:
					grid_setup[key]["x"] += spacing * cfc.screen_scale.x
		grid_setup[name] = {
			"x" : x,
			"y" : y,
			"scale": scale,
			"type": "pile",
		} 
		for key in ["faceup", "auto_extend", "focusable"]:
			if extra_deck_data.has(key):
				grid_setup[name][key] = extra_deck_data[key] 

func get_extra_decks():
	return extra_decks		
		
func get_villains():
	if (!scenario_data):
		print_debug("data not loaded in ScenarioDeckData")
		return []
	if (not villains.empty()):
		return villains
		
	var first_scheme = schemes[0]
	villains = get_villains_from_scheme(first_scheme["_code"], is_expert_mode)

func get_simple_encounter_deck(encounter_sets):
	var result_deck = []
	# Add sets (from scenario, standard + modular sets)
	var modular_set_count = 0
	for encounter_set_code in encounter_sets:
		var positions = {}
		if (encounter_set_code.to_lower() == "modular"): #special case for modular sets
			encounter_set_code = modular_sets[modular_set_count]
			modular_set_count += 1
		var encounter_set : Array = cfc.get_encounter_cards(encounter_set_code)
		for card_data in encounter_set:
			var card_type = card_data["type_code"]
			if (card_type != "main_scheme" and card_type != "villain"): #skip villain and schemes from the deck
				var add_to_encounter_deck = true
				var card_set_position = card_data["set_position"]
				if positions.has(card_set_position):
					#conflict e.g. android efficiency
					var existing_card_data = positions[card_set_position]
					var code = card_data["code"]
					var existing_code = existing_card_data["code"]
					if code.begins_with(existing_code): #we have the more precise
						result_deck.erase(existing_card_data)
					else:
						add_to_encounter_deck = false
				if add_to_encounter_deck:
					result_deck.push_back(card_data)
					positions[card_set_position] = card_data	
	return result_deck
		
func get_encounter_deck():
	if (not encounter_deck.empty()):
		return encounter_deck
		
	if (!scenario_data):
		print_debug("data not loaded in ScenarioDeckData")
		return []

	encounter_deck = []
		

	var encounter_sets : Array = scenario_data["encounter_sets"]		

	if is_expert_mode and scenario_data.has("expert"):		
		encounter_sets = scenario_data["expert"].get("encounter_sets", encounter_sets)

	encounter_deck = get_simple_encounter_deck(encounter_sets)
				
	#add hero obligations
	#for all heroes in game data, add hero's obligation
	for hero in gameData.team.values():
		var hero_data = hero["hero_data"]
		var obligation_card = cfc.get_hero_obligation(hero_data.get_hero_id())
		encounter_deck.push_back(obligation_card)
	return encounter_deck

#		"scheme_id" : "01097", 
#		"modular_encounters": ["bomb_scare"],
#		"expert_mode": true,false	
func save_to_json():
	return {
		"scheme_id" : scheme_card_id,
		"modular_encounters" : self.modular_sets,
		"expert_mode": self.is_expert_mode
	}
	
