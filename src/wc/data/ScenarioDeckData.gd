# Data that represents the Scenario / Villain Deck
class_name ScenarioDeckData
extends Reference

#card definitions
var _villains:= []
var _villains_by_level:= {}


var scheme_card_id:= ""
var schemes:Array
var modular_sets:=[]
var is_expert_mode:= false
var encounter_deck:Array
var scenario_options:= {}
var extra_decks: = []
var grid_setup:= {}
var scenario_data: = {}
var set_aside := []

const all_scenarios:= []
const primitives:= {}

func _init():
	pass


static func _get_corrected_scheme_card_id(key):
	if !cfc.get_card_by_id(key):
		key = key + "a"
		if !cfc.get_card_by_id(key):
			key = ""
			var _error = 1
	return key	

#eg: "get_primitive_by_attribute("name", "The Break-In!")
static func get_primitive_by_attribute(attribute, value):
	if !primitives:
		_load_card_scenarios()	
	if typeof(value) == TYPE_STRING:
		value = value.to_lower()
		
	for key in primitives:
		var primitive = primitives[key]
		var to_compare = primitive.get(attribute, null)
		if !to_compare:
			continue
		if typeof(to_compare) != typeof(value):
			continue
		if typeof(to_compare) == TYPE_STRING:
			to_compare = to_compare.to_lower()
		if to_compare == value:
			return primitive
	return {}

static func get_scenario_display_name(scenario_id):
	if !primitives:
		_load_card_scenarios()	
	
	var scheme_primitive = primitives.get(scenario_id, {})	
	if !scheme_primitive:
		return ""
	var display_name = scheme_primitive.get("scenario_display_name", "")
	return display_name

static func _load_card_scenarios():
	var json_card_data : Dictionary
	json_card_data = WCUtils.read_json_file_with_user_override("Sets/_scenarios.json")	
	for key in json_card_data:
		var card_data = json_card_data[key]
		#error correction
		key = _get_corrected_scheme_card_id(key)
		if !key:
			continue
		var card_code = _get_corrected_scheme_card_id(card_data["code"])
		if !card_code:
			continue		
		primitives[card_code] = card_data;
		all_scenarios.append(key)
	

static func get_array_data(scheme_id, key):
	var scheme_primitive = primitives.get(scheme_id, {})
	if !scheme_primitive:
		return []
	
	var data: Array = scheme_primitive.get(key, [])
	if typeof(data) == TYPE_ARRAY:
		return data
	return []
	
static func get_recommended_modular_encounters(scheme_id):
	return get_array_data(scheme_id,"modular_default")

static func get_scenario_options(scheme_id):
	return get_array_data(scheme_id,"options")		

static func get_first_villain_from_scheme(scheme_id, expert_mode:= false):
	var villains = get_villains_from_scheme(scheme_id, expert_mode)
	if !villains or !villains[0]:
		return null
	return villains[0][0]
	
static func get_villains_from_scheme(scheme_id, expert_mode:= false):
	var villain_groups = get_villain_id_groups_from_scheme (scheme_id, expert_mode)

	var results = []
	#get villains in order, split strings to get name and stage.
	for villain_ids in villain_groups:
		var result = []
		for villain_id in villain_ids:
			result.append(cfc.card_definitions[villain_id])
		results.append(result)
		
	return results

#returns an array of arrays, representing multiple stages of several villains
#[["1234", "2345"], ["a234", "b234"]]	
#the typical use case is just one villain though, with multiple stages
#[["1234", "2345"]]
static func get_villain_id_groups_from_scheme(scheme_id, expert_mode:= false):
	var scheme_primitive = primitives.get(scheme_id, {})
	if !scheme_primitive:
		return []
		
	var villain_data : Array = scheme_primitive["villains"]
	if expert_mode and scheme_primitive.has("expert"):		
		villain_data = scheme_primitive["expert"].get("villains", villain_data)
		
	if (not villain_data or villain_data.empty()):
		print_debug("villains missing in ScenarioDeckData")
		return []			
	
	var check = villain_data[0]
	if typeof(check) == TYPE_STRING:
		villain_data = [villain_data]
	
	var results = []
	#get villains in order, split strings to get name and stage.
	for villain_strings in villain_data:
		var result = []
		for villain_string in villain_strings:
				var card_id = cfc.get_corrected_card_id(villain_string)
				if card_id:
					result.append(card_id)
					
		results.append(result)

	return results	

func get_villain_family(current_villain):
	if !current_villain:
		return []
	var the_name = current_villain.get_property("Name", "")
	for villain_data in _villains:
		for villain in villain_data:
			if villain.get("Name", "") == the_name:
				return villain_data
	
	return []

func get_villains(index = 0):
	if (!scenario_data):
		print_debug("data not loaded in ScenarioDeckData")
		return []
	if (_villains.empty()):
		load_villains()


	if !_villains_by_level:
		for villains_data in _villains:
			var i = 0
			for villain_data in villains_data:
				if !_villains_by_level.has(i):
					_villains_by_level[i] = []
				_villains_by_level[i].append(villain_data)
				i+= 1
		
	if _villains_by_level.size() < index+1:
		return []
			
	return _villains_by_level[index]


static func get_scheme_from_villain(villain_id):
	if !primitives:
		_load_card_scenarios()	
			
	if !villain_id:
		return {}
	for scheme_id in primitives:
		for expert in [false, true]:
			var villain_groups = get_villain_id_groups_from_scheme(scheme_id, expert)
			for villain_ids in villain_groups:
				if villain_id in villain_ids:
					return {
						"scheme_id": scheme_id,
						"expert": expert
					}
	
	return {}
	
func load_from_villain(villain_id):
	var scheme_info = get_scheme_from_villain(villain_id) 
	if !scheme_info:
		var _error = 1
		return

	var scheme_id = scheme_info["scheme_id"]
	var expert = scheme_info["expert"]

	return load_from_dict(
		{
			"scheme_id": scheme_id,
			"modular_encounters": get_recommended_modular_encounters(scheme_id),
			"expert_mode": expert
		}
	)


func load_from_dict(_scenario:Dictionary):
	reset()
	if !primitives:
		_load_card_scenarios()
	grid_setup = CFConst.GRID_SETUP.duplicate(true)	
	scheme_card_id = _scenario.get("scheme_id")
	if !scheme_card_id:
		var _error =1
		print_debug("Scheme ID not set in load_from_dict")
		return
	
	schemes = get_schemes(scheme_card_id)
	if !schemes:
		var _error =1
		print_debug("Can't find schemes for " + scheme_card_id)
		return	
		
	scenario_data = primitives[scheme_card_id].duplicate(true)
	
	is_expert_mode =  _scenario.get("expert_mode", false)
	scenario_options["expert_mode"] = is_expert_mode
	
	modular_sets = _scenario.get("modular_encounters", [])
	scenario_options = _scenario.get("scenario_options", {})
	
	#Preload
	_villains = []
	load_villains()
	
	set_aside = []
	encounter_deck = []
	get_encounter_deck()
	_load_extra_rules_from_encounters()
	setup_grid()
	gameData.theGameObserver.setup(self)	

#returns all schemes belonging to the same collection as scheme_id,
#sorted in expected appearance order		
static func get_schemes(scheme_id):	
	#todo error handling
	var scheme = cfc.get_card_by_id(scheme_id)
	#error correction
	if !scheme:
		scheme = cfc.get_card_by_id(scheme_id + "b")
	if !scheme:
		return []
	 
	var set_name = scheme["card_set_code"]
	if !set_name:
		return []
		
	var my_schemes = cfc.schemes.get(set_name.to_lower(), [])
	my_schemes.sort_custom(WCUtils, "sort_stage")
	return my_schemes

func get_setting(key, default = null):
	return scenario_data.get("settings", {}).get(key, default)	

func get_value(key):
	return scenario_data.get(key, "")

func get_scenario_option(key):
	return scenario_options.get(key, 0)

func get_description():
	var description = get_value("description")
	if !description:
		description = []
		var a_side_code = _get_corrected_scheme_card_id(scheme_card_id)
		var a_side_data = cfc.get_card_by_id(a_side_code)
		if a_side_data:
			var flavor = a_side_data.get("flavor", "")
			if flavor:
				description.append(flavor)
			var b_side_code = a_side_data.get("back_card_code", "")
			if b_side_code:
				var b_side_data = cfc.get_card_by_id(b_side_code)
				var flavor_b = b_side_data.get("flavor", "")
				if flavor_b:
					description.append(flavor_b)
	
	if !description:
		return ""
						
	match typeof(description):
		TYPE_ARRAY:
			var compiled_name: PoolStringArray = description
			var result = compiled_name.join("\n\n")
			return result
		TYPE_STRING:
			return description
		_:
			return ""

func get_display_name():
	var display_name = get_value("scenario_display_name")
	if !display_name:
		var villain = _villains[0][0]
		var shortname = villain["shortname"]
		display_name = get_value("name") + " - " + shortname
	return display_name

func _load_extra_rules_from_encounters():
	var the_deck: Array = get_encounter_deck()
	the_deck += get_aside_deck()
	for card_data in the_deck:
		var canonical_id = card_data["code"]
		var encounter_extra_decks = cfc.set_scripts.get(canonical_id,{}).get("extra_decks",{}).duplicate(true)
		if encounter_extra_decks:
			if ! scenario_data.has("extra_decks"):
				scenario_data["extra_decks"] = []
			scenario_data["extra_decks"] += encounter_extra_decks
			
		var extra_rules = cfc.set_scripts.get(canonical_id,{}).get("extra_rules",{}).duplicate(true)
		if extra_rules:
			if ! scenario_data.has("extra_rules"):
				scenario_data["extra_rules"] = []
			scenario_data["extra_rules"] += extra_rules			

func setup_grid():
	if (!scenario_data):
		print_debug("data not loaded in ScenarioDeckData")
		return []	
	var extra_decks_data = scenario_data.get("extra_decks", [])

	var spacing = 120
	var villain_space = 250
	#shift everything to the right if there are additional villains
	var count_villains = get_villains().size()
	if count_villains > 1:
		if count_villains > 3:
			spacing = 0
			villain_space = 70
		var villain_x = grid_setup["villain"]["x"]
		var displacement = villain_space * (count_villains -1) *  cfc.hardcoded_positions_modifier.x
		for key in grid_setup: 
			if grid_setup[key].has("x"):
				#if it's on the left we don't move it
				if grid_setup[key]["x"] <= villain_x:
					continue
				#we don't want to push stuff outside of the screen
				if grid_setup[key]["x"] + displacement > cfc.screen_resolution.x - ((villain_space + spacing) *  cfc.hardcoded_positions_modifier.x):
					pass
				else:
					grid_setup[key]["x"] += displacement	
	
	var coord_source = grid_setup["discard_villain"]
	var x = 0
	var y = coord_source.get("y", 20)
	var scale = coord_source.get("scale", 1)
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
				if grid_setup[key]["x"] > cfc.screen_resolution.x - ((villain_space + spacing) *  cfc.hardcoded_positions_modifier.x):
					pass
				else:
					grid_setup[key]["x"] += spacing *  cfc.hardcoded_positions_modifier.x
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
		
func load_villains():
	if (!scenario_data):
		print_debug("data not loaded in ScenarioDeckData")
		return []
	if (not _villains.empty()):
		return _villains
		
	var first_scheme = schemes[0]
	_villains = get_villains_from_scheme(first_scheme["_code"], is_expert_mode)
	return _villains

func villain_is_in_scenario(villain_data):
	if _villains.empty():
		var _error = 1
		return false
	for villain_group in _villains:
		for villain in villain_group:
			if villain["Name"] == villain_data["Name"]:
				return true
	return false

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
			var code = card_data["code"]		
			var added_to_scenario = true
			var card_type = card_data["type_code"]
			if (card_type == "main_scheme"): #skip villain and schemes from the deck
				if card_data in set_aside:
					added_to_scenario = false
				else:
					set_aside.append(card_data)
			elif(card_type == "villain"):
				if villain_is_in_scenario(card_data) and ! card_data in set_aside:
					set_aside.append(card_data)	
				else:
					added_to_scenario = false			
			else:
				var add_to_encounter_deck = true
				var card_set_position = card_data["set_position"]
				if positions.has(card_set_position):
					#conflict e.g. android efficiency
					var existing_card_data = positions[card_set_position]
					var existing_code = existing_card_data["code"]
					if code.begins_with(existing_code): #we have the more precise
						result_deck.erase(existing_card_data)
					else:
						if card_data["Name"] == existing_card_data["Name"]:
							add_to_encounter_deck = false
				if add_to_encounter_deck:
					#permanent cards are set aside in setup
					if card_data.get("permanent", false):
						set_aside.append(card_data)
					else:
						result_deck.push_back(card_data)
					positions[card_set_position] = card_data
				else:
					added_to_scenario = false	
			if added_to_scenario:
				get_extra_cards_aside(code)	
	return result_deck

func get_aside_deck():
	if (encounter_deck.empty()):
		get_encounter_deck()
		
	return set_aside

func get_extra_cards_aside(card_id):
	var extra_cards_str = "additional_cards_set_aside"		
	var extra_cards = cfc.set_scripts.get(card_id,{}).get(extra_cards_str,[]).duplicate(true)

	for card in extra_cards:
		var card_id_or_name = card.get("card", "")
		if !card_id_or_name:
			continue
		var extra_card_id = cfc.get_corrected_card_id(card_id_or_name)
		var card_data = cfc.get_card_by_id(extra_card_id)
		set_aside.append(card_data)
		
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
		if obligation_card:
			encounter_deck.push_back(obligation_card)
		else:
			print_debug("missing obligation card for " + hero_data.get_hero_card_data()["Name"])
	
	#add extra cards from the scenario
	var additional_cards = scenario_data.get("additional_cards", [])
	for card_id in additional_cards:
		var card = cfc.get_card_by_id(card_id)
		if card:
			encounter_deck.push_back(card)
			
	return encounter_deck
			
#
# Adventure mode functions
#

static func _get_corrected_scenario_ids(settings_key = "unlocked_villains"):
	var _unlocked_scenarios_ids = cfc.game_settings.get(settings_key, [])

	var unlocked_scenarios_ids = []
	for key in _unlocked_scenarios_ids:
		key = _get_corrected_scheme_card_id(key)
		if !key:
			continue
		unlocked_scenarios_ids.append(key)
	
	return 	unlocked_scenarios_ids

static func get_unlocked_scenarios():
	if !all_scenarios:
		_load_card_scenarios()
		
	if !cfc.is_adventure_mode():
		return all_scenarios
	
	var unlocked_scenarios_ids = _get_corrected_scenario_ids()
	
	if !unlocked_scenarios_ids:
		var _scenario_id = adventure_unlock_next_scenario()
		unlocked_scenarios_ids = cfc.game_settings.get("unlocked_villains", [])
	
	return unlocked_scenarios_ids

static func get_locked_scenarios():
	var unlocked_scenarios = get_unlocked_scenarios()

	var result = all_scenarios.duplicate()
	for scenario_id in unlocked_scenarios:
			result.erase(scenario_id)
	return result

static func adventure_unlock_next_scenario():
	if !cfc.game_settings.has("unlocked_villains"):
		cfc.game_settings["unlocked_villains"] = []
		
	var unlocked_scenario_ids = _get_corrected_scenario_ids()

		
	var all_scenario_ids = 	all_scenarios.duplicate()
	for scenario_id in unlocked_scenario_ids:
		all_scenario_ids.erase(scenario_id)

	#nothing left to unlock
	if !all_scenario_ids:
		return ""
		
#	var selected_scenario_id = all_scenario_ids[randi() % all_scenario_ids.size()]
	var selected_scenario_id = all_scenario_ids[0]
	cfc.game_settings["unlocked_villains"].append(selected_scenario_id)
	cfc.save_settings()
	return selected_scenario_id	


#
# Utility functions
#

func reset():
	scheme_card_id= ""
	schemes = []
	modular_sets=[]
	is_expert_mode = false
	encounter_deck = []
	set_aside = []
	extra_decks = []
	_villains = []
	grid_setup = {}
	scenario_data = {}
	_villains_by_level = {}
	scenario_options = {}

#		"scheme_id" : "01097", 
#		"modular_encounters": ["bomb_scare"],
#		"expert_mode": true,false	
func save_to_json():
	return {
		"scheme_id" : scheme_card_id,
		"modular_encounters" : self.modular_sets,
		"expert_mode": self.is_expert_mode,
		"scenario_options": self.scenario_options
	}
	
