# Card Gaming Framework Control Singleton
#
# Add it to your autoloads with the name 'cfc'
class_name CFControlExtended
extends CFControl

#cache variables
var known_types : Dictionary
var unknown_types : Dictionary
var next_scene_params : Dictionary
var idx_card_id_to_name : Dictionary
var idx_hero_to_deck_ids : Dictionary

var obligations : Dictionary
var schemes: Dictionary 
var cards_by_set: Dictionary

var primitives: Dictionary
var scenarios : Array

#Hero deck data identified by integer id (marvelcdb id)
var deck_definitions : Dictionary

func get_card_by_id(id):
	if (not id):
		WCUtils.debug_message("no id passed to get_card_by_id")
		return null	
	var card_name = idx_card_id_to_name[id]
	if (not card_name):
		WCUtils.debug_message("no matching data for " + str(id))
		return null
	return card_definitions[card_name]

func _is_type_known(type) -> bool:
	if known_types.has(type):
		return true
	if unknown_types.has(type):
		return false
	#attempt to load matching template to see if type is known
	var template = load(CFConst.PATH_CARDS
			+ type + ".tscn")
	if template:
		known_types[type] = true
		return true
	unknown_types[type] = true
	return false
	

func _setup():
	._setup() #This loads the cards
	deck_definitions = load_deck_definitions()
	

func load_card_primitives():
	var json_card_data : Array
	json_card_data = WCUtils.read_json_file("user://Sets/_primitives.json")	
	for card_data in json_card_data:
		#creating entries for both id and name so I never have to remember which one to use...
		primitives[card_data["code"]] = card_data;
		primitives[card_data["name"]] = card_data;

# Returns a Dictionary with the combined Card definitions of all set files
# loaded in card_definitions variable by core engine
func load_card_definitions() -> Dictionary:
	if (primitives.empty()):
		load_card_primitives()
	var combined_sets := .load_card_definitions(); #TODO Remove the call to parent eventually ?
	# Load from external user files as well	
	var loaded_definitions : Array
	var set_files = CFUtils.list_files_in_directory(
			"user://Sets/", CFConst.CARD_SET_NAME_PREPEND)
	WCUtils.debug_message(set_files.size())		
	for set_file in set_files:
		var json_card_data : Array
		json_card_data = WCUtils.read_json_file("user://Sets/" + set_file)
		for card_data in json_card_data:
			#Fixing missing Data
			if not card_data.has("Tags"):
				card_data["Tags"] = []			

			var card_type:String = card_data[CardConfig.SCENE_PROPERTY]
			
			#enriching data
			var lc_card_type = card_type.to_lower()
			var force_horizontal = CFConst.FORCE_HORIZONTAL_CARDS.get(lc_card_type, false)
			card_data["_horizontal"] = force_horizontal

			#TODO 2024/10/30 is this error new?
			if not card_data.has("card_set_name"):
				card_data["card_set_name"] = "ERROR"	
				

			var set_name = card_data["card_set_name"]
			var lc_set_name = set_name.to_lower()
			
			#Villains: multiple cards have the same name.
			#Hack to "fix" this by adding stage number
			#e.g. "Rhino_2"
			if (card_type == "Villain"):
				card_data["Name"] = card_data["Name"] + "_" + String(card_data["stage"])
			
			var card_id = card_data["_code"]
			#caching and indexing
			idx_card_id_to_name[card_id] = card_data["Name"]
			
			
			#scenarios cache
			if (card_type == "Main_scheme"):
				if (not schemes.has(lc_set_name)):
					schemes[lc_set_name] = []
				schemes[lc_set_name].push_back(card_data)	
				if(card_data["stage"] == 1):
					scenarios.push_back(card_id)
			
			#obligations cache
			if (card_type == "Obligation"):
				obligations[lc_set_name] = card_data
				
			#encounter/set cache
			if (not cards_by_set.has(lc_set_name)):
				cards_by_set[lc_set_name] = []
			cards_by_set[lc_set_name].push_back(card_data)				
				
			#Unknown types get assigned a generic template.
			#They most likely won't work in game
			if not _is_type_known(card_type):
				card_data[CardConfig.SCENE_PROPERTY] = "Unknown"	
			combined_sets[card_data["Name"]] = card_data
			
			
	return(combined_sets)

# Returns a Dictionary with the Decks
func load_deck_definitions() -> Dictionary:
	var combined_decks := {}
	# Load from external user files as well	
	var loaded_definitions : Array
	var deck_files = CFUtils.list_files_in_directory("user://Decks/")
	WCUtils.debug_message(deck_files.size())		
	for deck_file in deck_files:
		var json_deck_data : Dictionary = WCUtils.read_json_file("user://Decks/" + deck_file)
		#Fixing missing Data
		#nothing for now
		if (_is_deck_valid(json_deck_data)):
			var deck_id: int = json_deck_data["id"]
			var hero_id = json_deck_data["investigator_code"]
			combined_decks[deck_id] = json_deck_data
			if (not idx_hero_to_deck_ids.has(hero_id)):
				idx_hero_to_deck_ids[hero_id] = []
			idx_hero_to_deck_ids[hero_id].push_back(deck_id)	
	return(combined_decks)

#card database related functions
func get_hero_obligation(hero_id:String):
	#todo error handling
	var hero_data = get_card_by_id(hero_id)
	var hero_name = hero_data["Name"]
	var obligation = obligations[hero_name.to_lower()]
	return obligation
		
func get_schemes(set_name:String):	
	#todo error handling
	var my_schemes = schemes[set_name.to_lower()]
	my_schemes.sort_custom(WCUtils, "sort_stage")
	return my_schemes

func get_encounter_cards(set_name:String):
	var encounters = cards_by_set[set_name.to_lower()]
	return encounters

#check if a given deck is valid (we must own all cards)
func _is_deck_valid(deck) -> bool:
	if OS.has_feature("debug") and (not idx_card_id_to_name or idx_card_id_to_name.empty()):
		print_debug(
			"DEBUG INFO:CFControlExtended: warning, called _is_deck_valid with empty verification data")
		return false
	var hero_code = deck["investigator_code"]
	if (not idx_card_id_to_name.has(hero_code)):
		return false
	var slots: Dictionary = deck["slots"]
	if (not slots or slots.empty()):
		return false
	for slot in slots:
		if (not idx_card_id_to_name.has(slot)):
			return false		
	return true
	
# Returns a Dictionary with the combined Script definitions of all set files
func load_script_definitions() -> void:
	var set_files = CFUtils.list_files_in_directory(
			"user://Sets/", CFConst.CARD_SET_NAME_PREPEND)
			
	for set_file in set_files:
		var json_card_data : Array
		json_card_data = WCUtils.read_json_file("user://Sets/" + set_file)
		for card_data in json_card_data:
			#Fixing missing Data
			if not card_data.has("Tags"):
				card_data["Tags"] = []			
	
	var script_overrides = load(CFConst.PATH_SETS + "SetScripts_Core.gd").new()
	
	var combined_scripts := {}
	var script_definition_files := CFUtils.list_files_in_directory(
				"user://Sets/", CFConst.SCRIPT_SET_NAME_PREPEND)
	WCUtils.debug_message("Found " + str(script_definition_files.size()) + " script files")			
	for script_file in script_definition_files:
		var json_card_data : Dictionary
		json_card_data = WCUtils.read_json_file("user://Sets/" + script_file)
		for card_name in json_card_data.keys():
			if not combined_scripts.get(card_name):
				combined_scripts[card_name]	= json_card_data[card_name]	
					

	for card_name in card_definitions.keys():
		var card_script = script_overrides.get_scripts(combined_scripts, card_name)
		var unmodified_card_script = script_overrides.get_scripts(combined_scripts, card_name, false)
#		print(unmodified_card_script)
		if not card_script.empty():
			combined_scripts[card_name] = card_script
			set_scripts[card_name] = card_script
			unmodified_set_scripts[card_name] = unmodified_card_script
	emit_signal("scripts_loaded")
	scripts_loading = false	

func enrich_window_title(script:ScriptObject, title:String) -> String:
	var result:String = title
	var script_definitions = script.script_definition
	var script_name = script_definitions.name
	var owner = script.owner
	
	match script_name:
		"defend":
			result = owner.name + " attacks. Choose at most 1 defender, cancel for undefended" 

	return result;

#A poor man's mechanism to pass parameters betwen scenes
func set_next_scene_params(params : Dictionary):
	next_scene_params = params.duplicate()
	
func get_next_scene_params() -> Dictionary:
	return next_scene_params

#
# These functions live here for lack of a better place. Todo create classes?
func get_img_filename(card_id) -> String:
	if (not card_id):
		print_debug("CFCExtended: no id passed to get_img_filename")
		return ""
	var card = get_card_by_id(card_id)
	if (not card):
		print_debug("CFCExtended: couldn't find card matching id" + card_id)
		return ""	
	var card_code = card["_code"]
	var card_set = card["_set"]
	if card_code and card_set:
		return "user://Sets/" + card_set + "/" + card_code + ".png"
	return "" #todo return graceful fallback
	
func get_hero_portrait(card_id) -> Image:
	var filename = get_img_filename(card_id)
	var img_data: Image = WCUtils.load_img(filename)
	if (not img_data):
		return null
	var area = 	Rect2 ( 60, 40, 170, 180 )
	var sub_img = img_data.get_rect(area) #Todo more flexible?
	return sub_img	


#
# Network related functions
func is_game_master() -> bool:
	return get_tree().is_network_server() #Todo: return something more specific to handle case where game master isn't server, for headless mode
	 
