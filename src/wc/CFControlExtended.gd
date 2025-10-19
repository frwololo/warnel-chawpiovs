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
var lowercase_card_name_to_name : Dictionary
var shortname_to_name : Dictionary
var idx_hero_to_deck_ids : Dictionary

var obligations : Dictionary
var schemes: Dictionary 
var cards_by_set: Dictionary

var primitives: Dictionary
var scenarios : Array

#Hero deck data identified by integer id (marvelcdb id)
var deck_definitions : Dictionary

var _ongoing_processes:= {}

func get_card_name_by_id(id):
	if (not id):
		WCUtils.debug_message("no id passed to get_card_by_id")
		return null	
	return idx_card_id_to_name.get(id,"")

func get_card_by_id(id):
	var card_name = get_card_name_by_id(id)
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


func parse_keywords(text:String) -> Dictionary:
	var result:= {}
	
	var lc_text:String = text.to_lower()
	for _keyword in CFConst.AUTO_KEYWORDS.keys():
		var keyword:String = _keyword.to_lower()
		var type = CFConst.AUTO_KEYWORDS[keyword]
		

		
		match type:
			"bool":		
				var position = lc_text.find(keyword + ".")
				if  position >=0:
					result[keyword] = true
			"int":
				var position = lc_text.find(keyword + " ")
				if  position >=0:
					var value = lc_text.substr(position + keyword.length() + 1, 1)
					result[keyword] = int(value)
			"string":
				#TODO
				var position = lc_text.find(keyword + ".")
				if  position >=0:
					result[keyword] = true
				pass
			_:
				#error
				pass
	return result

func _load_one_card_definition(card_data):
	#converting "real" numbers to "int"
	for key in card_data.keys():
		var value = card_data[key]
		if typeof(value) == TYPE_REAL:
			var new_value:int = value
			card_data[key] = new_value
		
		#replaces "null" with "0" for resources	
		if key.begins_with("resource") and !value:
			card_data[key] = 0

	#Fixing missing Data
	if not card_data.has("Tags"):
		card_data["Tags"] = []			

	if not card_data.has("Requirements"):
		card_data["Requirements"] = ""
		
	if not card_data.has("Abilities"):
		card_data["Abilities "] = ""		

	#linked cards might be missing preprocessing data
	if not card_data.has("_code"):
		card_data["_code"] = card_data.get("code", "")


	if not card_data.has(CardConfig.SCENE_PROPERTY):
		var type_code = card_data["type_code"]
		type_code = type_code[0].to_upper() + type_code.substr(1)
		card_data[CardConfig.SCENE_PROPERTY] = type_code

	if not card_data.has("back_card_code"):
		card_data["back_card_code"] = ""
	
	if not card_data.has("_set"):
		card_data["_set"] = card_data.get("pack_code", "")	

	###END Fixing missing data

	var card_type:String = card_data[CardConfig.SCENE_PROPERTY]
	
	#enriching data
	var lc_card_type = card_type.to_lower()
	var force_horizontal = CFConst.FORCE_HORIZONTAL_CARDS.get(lc_card_type, false)
	card_data["_horizontal"] = force_horizontal

	if (!card_data.has("keywords")) and card_data.get("text", ""):
		card_data["keywords"] = parse_keywords(card_data["text"])


	#TODO 2024/10/30 is this error new?
	if not card_data.has("card_set_name"):
		card_data["card_set_name"] = "ERROR"	
	if not card_data.has("card_set_code"):
		card_data["card_set_code"] = "ERROR"	

		

	var set_code = card_data["card_set_code"]
	var lc_set_code = set_code.to_lower()
	
	var set_name = card_data["card_set_name"]
	var lc_set_name = set_name.to_lower()	

	if not card_data.has("Name"):
		card_data["Name"] = card_data.get("name", "")
	
	#name alone isn't enough as a unique identifier, so we're adding
	#subname
	card_data["shortname"] = card_data["Name"]
	if (card_data.get("subname", "")):
		card_data["Name"] += " - " + card_data["subname"]	
		var _tmp = card_data["Name"]
		var _error = 0
	#Villains: multiple cards have the same name.
	#Hack to "fix" this by adding stage number
	#e.g. "Rhino_2"
	if (card_type == "Villain"):
		card_data["Name"] = card_data["Name"] + " - " + String(card_data["stage"])
	
	card_data.erase("name")
	
	var card_id = card_data["_code"]
	var card_name:String = card_data["Name"]
	
	#caching and indexing
	shortname_to_name[card_data["shortname"].to_lower()] = card_name
	idx_card_id_to_name[card_id] = card_name
	lowercase_card_name_to_name[card_name.to_lower()] = card_name
	
	
	#scenarios cache
	if (card_type == "Main_scheme"):
		if (not schemes.has(lc_set_code)):
			schemes[lc_set_code] = []
		schemes[lc_set_code].push_back(card_data)	
		if(card_data["stage"] == 1):
			scenarios.push_back(card_id)
	
	#obligations cache
	if (card_type == "Obligation"):
		obligations[lc_set_code] = card_data
		obligations[lc_set_name] = card_data
		
	#encounter/set cache
	if (not cards_by_set.has(lc_set_code)):
		cards_by_set[lc_set_code] = []
	cards_by_set[lc_set_code].push_back(card_data)				
		
	#Unknown types get assigned a generic template.
	#They most likely won't work in game
	if not _is_type_known(card_type):
		card_data[CardConfig.SCENE_PROPERTY] = "Unknown"	
		
		
# Returns a Dictionary with the combined Card definitions of all set files
# loaded in card_definitions variable by core engine
func load_card_definitions() -> Dictionary:
	if (primitives.empty()):
		load_card_primitives()
	var combined_sets := .load_card_definitions(); #TODO Remove the call to parent eventually ?
	# Load from external user files as well	
	var set_files = CFUtils.list_files_in_directory(
			"user://Sets/", CFConst.CARD_SET_NAME_PREPEND)
	WCUtils.debug_message(set_files.size())		
	for set_file in set_files:
		var json_card_data : Array
		json_card_data = WCUtils.read_json_file("user://Sets/" + set_file)
		for card_data in json_card_data:			
			_load_one_card_definition(card_data)	
			combined_sets[card_data["Name"]] = card_data
			
			var linked_card_data = card_data.get("linked_card", {})
			if (linked_card_data):
				_load_one_card_definition(linked_card_data)
				linked_card_data["back_card_code"] = card_data["_code"]
				card_data["back_card_code"] = linked_card_data["_code"]
				combined_sets[linked_card_data["Name"]] = linked_card_data
				cfc.LOG_DICT(linked_card_data)
				cfc.LOG_DICT(card_data)			

			var double_sided = card_data.get("double_sided", false)
			if (double_sided):
				var back_side_data = card_data.duplicate()
				back_side_data["_code"] = card_data["_code"] + "b"
				back_side_data["code"] = back_side_data["_code"]
				back_side_data["text"] = back_side_data["back_text"]
				
				back_side_data["back_card_code"] = card_data["_code"]
				card_data["back_card_code"] = back_side_data["_code"]				
				#TODO more changes needed ?
				_load_one_card_definition(back_side_data)
			
	return(combined_sets)

# Returns a Dictionary with the Decks
func load_deck_definitions() -> Dictionary:
	var combined_decks := {}
	# Load from external user files as well	
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

func replace_text_macro (replacements, macro_value):
	var text = to_json(macro_value)
	for key in replacements.keys():
		var value = replacements[key]
		var to_replace = key
		if (typeof(value) == TYPE_REAL or typeof(value) == TYPE_INT):
			to_replace = "\"" + key + "\""
		text = text.replace(to_replace, replacements[key])
	
	return parse_json(text)

func replace_one_macro(script_definition, macro_key, macro_value):
	var result = null
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				if (key == macro_key):
					var replacements = script_definition[key]
					var dict = replace_text_macro(replacements, macro_value)
					for replaced_key in dict.keys():
						result[replaced_key] = dict[replaced_key]
				else:
					result[key] = replace_one_macro(script_definition[key], macro_key, macro_value)
		TYPE_ARRAY:	
			result = []
			for value in script_definition:
				result.append(replace_one_macro(value, macro_key, macro_value))
		_:
			result = script_definition
	return result;	

func replace_macros(json_card_data, json_macro_data):
	var result = json_card_data
	for macro_key in json_macro_data.keys():
		result = replace_one_macro(result, macro_key, json_macro_data[macro_key])
	return result
	
# Returns a Dictionary with the combined Script definitions of all set files
func load_script_definitions() -> void:
			
	var script_overrides = load(CFConst.PATH_SETS + "SetScripts_Core.gd").new()
	var json_macro_data : Dictionary = WCUtils.read_json_file("user://Sets/_macros.json")
	
	var combined_scripts := {}
	var script_definition_files := CFUtils.list_files_in_directory(
				"user://Sets/", CFConst.SCRIPT_SET_NAME_PREPEND)
	WCUtils.debug_message("Found " + str(script_definition_files.size()) + " script files")			
	for script_file in script_definition_files:
		var json_card_data : Dictionary
		json_card_data = WCUtils.read_json_file("user://Sets/" + script_file)
		json_card_data = replace_macros(json_card_data, json_macro_data)
		#bugfix: replace "floats" to "ints"
		json_card_data = WCUtils.replace_real_to_int(json_card_data)
		var _text = to_json(json_card_data)
		for card_name in json_card_data.keys():
			if not combined_scripts.get(card_name):
				var card_data = json_card_data[card_name]
				combined_scripts[card_name]	= card_data	
					

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
	var forced_title = script_definitions.get("display_title", "")
	var owner = script.owner
	
	if (forced_title):
		result = forced_title + " - " + result
	else:
	
		result = owner.canonical_name + " - " + result
	
	match script_name:
		"enemy_attack":
			result = owner.canonical_name + " attacks. Choose at most 1 defender, cancel for undefended" 

	return result;

#A poor man's mechanism to pass parameters betwen scenes
func set_next_scene_params(params : Dictionary):
	next_scene_params = params.duplicate()
	
func get_next_scene_params() -> Dictionary:
	return next_scene_params

#
# These functions live here for lack of a better place. Todo create classes?
func get_img_filename(card_id, alternate_code = "") -> String:
	if (not card_id):
		print_debug("CFCExtended: no id passed to get_img_filename")
		return ""
	var card = get_card_by_id(card_id)
	if (not card):
		print_debug("CFCExtended: couldn't find card matching id" + card_id)
		return ""	
	var card_code = alternate_code if alternate_code else card["_code"]
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

func instance_card(card_name_or_id: String, owner_id:int) -> Card:
	var card_name = card_name_or_id
	if (!card_definitions.has(card_name)):
		card_name = self.get_card_name_by_id(card_name_or_id)
		
	var card = ._instance_card(card_name)
	#TODO We set GUID here in the hope that all clients create their cards in the exact 
	#same order. This might be a very flawed assertion could need a significant overhaul	
	var _tmp = guidMaster.set_guid(card)
	card.set_owner_hero_id(owner_id)
	card.set_controller_hero_id(owner_id)
	return card
#
# Network related functions
func is_game_master() -> bool:
	return get_tree().is_network_server() #Todo: return something more specific to handle case where game master isn't server, for headless mode

func INIT_LOG():
	var file = File.new()
	var network_id = get_tree().get_network_unique_id() if get_tree().has_network_peer() else 0
	network_id = str(network_id)
	var filename = "user://log_" + network_id +".txt"
	if (file.file_exists(filename)):
		return
	file.open(filename, File.WRITE)
	file.close() 	
	
func LOG(to_print:String):
	INIT_LOG()
	var file = File.new()
	var network_id = get_tree().get_network_unique_id() if get_tree().has_network_peer() else 0
	network_id = str(network_id)
	file.open("user://log_" + network_id +".txt", File.READ_WRITE)
	file.seek_end()
	file.store_string(to_print + "\n")
	file.close() 
	
func LOG_DICT(to_print:Dictionary):
	var my_json_string = to_json(to_print)
	LOG(my_json_string)
	
func add_ongoing_process(object, description:String = ""):
	if (!description):
		description = object.get_class()
		
	if (!_ongoing_processes.has(object)):
		_ongoing_processes[object] = {}
	if (!_ongoing_processes[object].has(description)):
		_ongoing_processes[object][description] = 0	

	_ongoing_processes[object][description] +=1
	return _ongoing_processes[object][description]
	
func remove_ongoing_process(object, description:String = ""):
	if (!description):
		description = object.get_class()
		
	if (!_ongoing_processes.has(object)):
		return 0
		
	if (!_ongoing_processes[object].has(description)):
		return 0
				
	_ongoing_processes[object][description] -=1
	if (!_ongoing_processes[object][description]):
		_ongoing_processes[object].erase(description)
		if !_ongoing_processes[object]:
			_ongoing_processes.erase(object)
		return 0
	return _ongoing_processes[object][description]
	
func is_process_ongoing() -> int:
	return _ongoing_processes.size()	

func reset_ongoing_process_stack():
	_ongoing_processes = {}
