# Card Gaming Framework Control Singleton
#
# Add it to your autoloads with the name 'cfc'
class_name CFControlExtended
extends CFControl

#cache variables
var all_loaded := false
var known_types : Dictionary
var unknown_types : Dictionary
var next_scene_params : Dictionary
var lowercase_card_name_to_name : Dictionary
var shortname_to_name : Dictionary
var idx_hero_to_deck_ids : Dictionary
var box_contents_by_name: Dictionary
var all_traits: Dictionary = {}
var duplicates: Dictionary = {}

var obligations : Dictionary
var schemes: Dictionary 
var modular_encounters: Dictionary = {}
var cards_by_set: Dictionary

var primitives: Dictionary
var scenarios : Array

#Hero deck data identified by integer id (marvelcdb id)
var deck_definitions : Dictionary

var _ongoing_processes:= {}
var _total_cards:int = 0
var _cards_loaded: int = 0

var _card_texture_cache:= {}
var _cropped_texture_cache:= {}
var fonts = {}
#var focused_shader = null

#performance check data
var ping_data: = {}
var last_ping_time:= 0
var fps = 0
var low_fps = false

#a variable used to compare the scale of the screen to a 1920*1080 screen
var screen_scale = 1.0
var screen_resolution = Vector2(1920, 1080)

# warning-ignore:unused_signal
signal json_parse_error(msg)

func _ready():
#	focused_shader = preload("res://src/wc/shaders/focused.tres")
	screen_resolution = get_viewport().size
	screen_scale = screen_resolution / Vector2(1920, 1080)
	scale_grids()

func scale_grids():
	for config in [CFConst.GRID_SETUP, CFConst.HERO_GRID_SETUP]:
		for grid_name in config:
			var grid_info = config[grid_name]
			for key in ["x", "y", "scale"]:
				if grid_info.has(key):
					grid_info[key] = grid_info[key] * screen_scale.x 
				else:
					match key:
						"scale":
							grid_info[key] = screen_scale.x 					
	scale_grid_layout_recursive(CFConst.HERO_GRID_LAYOUT)

func scale_grid_layout_recursive(config):
	match typeof(config):
		TYPE_DICTIONARY:
			if !config.has("scale"):
				if config.get("type", "") in ["grid", "pile"]:
					config["scale"] = 1.0
			for k in config:
				if k in ["x", "y", "scale", "max_width", "max_height"]:
					config[k] = config[k] * screen_scale.x
				else:
					scale_grid_layout_recursive(config[k])
		TYPE_ARRAY:
			for v in config:
				scale_grid_layout_recursive(v)
		_:
			pass

	
	#todo reorganizers?
	
func get_card_texture(card, force_if_facedown: = true):
	var filename = card.get_art_filename(force_if_facedown)
	return get_external_texture(filename)
	
func get_external_texture(filename):
	if !_card_texture_cache.has(filename):
		_card_texture_cache[filename] = get_external_texture_no_cache(filename)
	return _card_texture_cache[filename]

func get_external_texture_no_cache(filename):	
	var new_img = WCUtils.load_img(filename)
	if not new_img:
		return	null

	var imgtex = ImageTexture.new()	
	imgtex.create_from_image(new_img)	
	return imgtex

func get_cropped_card_texture(card, force_if_facedown: = true):
	var filename = card.get_art_filename(force_if_facedown)
	if !_cropped_texture_cache.has(filename):
		_cropped_texture_cache[filename] = get_cropped_card_texture_no_cache(card, filename)
	return _cropped_texture_cache[filename]

func get_cropped_card_texture_no_cache(card, filename):
	var new_img = WCUtils.load_img(filename)
	if not new_img:
		return	null

	var type_code = card.get_property("type_code", 0)
	
	if card._horizontal:
		new_img = WCUtils.rotate_90(new_img)	
		
	var imgtex = ImageTexture.new()
	
	imgtex.create_from_image(new_img)	
	var width = imgtex.get_width()
	var height = imgtex.get_height()	
	var region := Rect2(0, 0, width, width)
	if card._horizontal:
		match type_code:
			"main_scheme":
				region = Rect2(width/2,0, width/2, height)
			_:
				region = Rect2(0, 0, height, height)
	var texture = _get_cropped_texture(imgtex, region)	
	return texture

func _get_cropped_texture(texture : Texture, region : Rect2) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.set_atlas(texture)
	atlas_texture.set_region(region)
	return atlas_texture

func get_font(path, size) -> DynamicFont:
	if fonts.has(path):
		fonts[path].size = size
		return fonts[path]
		
	var cache_dynamic_font = DynamicFont.new()
	cache_dynamic_font.font_data = load(path)
	cache_dynamic_font.size = size
	cache_dynamic_font.set_use_filter(true)
	fonts[path] = cache_dynamic_font
	return cache_dynamic_font

var _process_period = 0
var _process_counter = 0
func _process(_delta:float):
	_process_counter +=1
	if _process_counter > _process_period:
		_process_counter = 0

	if low_fps:
		_process_period = 10
	else:
		_process_period = 0

func throttle_process_for_performance():
	return (_process_counter < _process_period)

#
# Adventure Mode related functions
#
func is_adventure_mode():
	var adventure_mode = game_settings.get("adventure_mode", false)
	return (!gameData.is_multiplayer_game) and adventure_mode

func get_unlocked_heroes():
	if !is_adventure_mode():
		return idx_hero_to_deck_ids
	
	var unlocked_hero_ids = game_settings.get("unlocked_heroes", [])
	if !unlocked_hero_ids:
		var _hero_id = adventure_unlock_random_hero()
		unlocked_hero_ids = game_settings.get("unlocked_heroes", [])
	
	var result = {}
	for hero_id in unlocked_hero_ids:
		if idx_hero_to_deck_ids.has(hero_id):
			result[hero_id] = idx_hero_to_deck_ids[hero_id]
	return result

func get_locked_heroes():
	var unlocked_heroes = get_unlocked_heroes()

	var result = idx_hero_to_deck_ids.duplicate()
	for hero_id in unlocked_heroes:
			result.erase(hero_id)
	return result
	

func get_unlocked_scenarios():
	if !is_adventure_mode():
		return self.scenarios
	
	var unlocked_scenarios_ids = game_settings.get("unlocked_villains", [])
	if !unlocked_scenarios_ids:
		var _scenario_id = adventure_unlock_next_scenario()
		unlocked_scenarios_ids = game_settings.get("unlocked_villains", [])
	
	return unlocked_scenarios_ids

func get_locked_scenarios():
	var unlocked_scenarios = get_unlocked_scenarios()

	var result = scenarios.duplicate()
	for scenario_id in unlocked_scenarios:
			result.erase(scenario_id)
	return result

func adventure_unlock_random_hero():
	if !game_settings.has("unlocked_heroes"):
		game_settings["unlocked_heroes"] = []
		
	var unlocked_hero_ids = game_settings.get("unlocked_heroes", [])
	var all_hero_ids = 	idx_hero_to_deck_ids.keys().duplicate()
	for hero_id in unlocked_hero_ids:
		all_hero_ids.erase(hero_id)

	#nothing left to unlock
	if !all_hero_ids:
		return ""
		
	var random_hero_id = all_hero_ids[randi() % all_hero_ids.size()]
	game_settings["unlocked_heroes"].append(random_hero_id)
	save_settings()
	return random_hero_id
	
func adventure_unlock_next_scenario():
	if !game_settings.has("unlocked_villains"):
		game_settings["unlocked_villains"] = []
		
	var unlocked_scenario_ids = game_settings.get("unlocked_villains", [])
	var all_scenario_ids = 	self.scenarios.duplicate()
	for scenario_id in unlocked_scenario_ids:
		all_scenario_ids.erase(scenario_id)

	#nothing left to unlock
	if !all_scenario_ids:
		return ""
		
#	var selected_scenario_id = all_scenario_ids[randi() % all_scenario_ids.size()]
	var selected_scenario_id = all_scenario_ids[0]
	game_settings["unlocked_villains"].append(selected_scenario_id)
	save_settings()
	return selected_scenario_id	

#disable focus_mode for all children of a node,
#return an array of children that had focus mode and lost it
func disable_focus_mode(container) -> Dictionary:
	var result = {}
	if "focus_mode" in container:
		result[container] = container.focus_mode
		container.focus_mode = Control.FOCUS_NONE		
	for child in container.get_children():
		var child_data = disable_focus_mode(child)
		for key in child_data:
			result[key] = child_data[key]
	return result
	
func enable_focus_mode(list:Dictionary):
	for node in list:
		if is_instance_valid(node) and "focus_mode" in node: 
			node.focus_mode = list[node]

#grab focus for the first (visible and enabled) button in a container
func default_button_focus(container) -> bool:
	for maybe_button in container.get_children():
		if maybe_button.has_signal('pressed') and !maybe_button.disabled and maybe_button.visible:
				maybe_button.grab_focus()
				return true
		var found = default_button_focus(maybe_button)
		if found:
			return true
	return false

func _setup() -> void:
	._setup()
	delete_log_files()
	preload_pck()

func get_ping(client_id):
	var ping_info =  ping_data.get(client_id, {})
	if !ping_info:
		return 0
	return ping_info["last_ping"]

func get_avg_ping(client_id):
	var ping_info =  ping_data.get(client_id, {})
	if !ping_info:
		return 0
	return ping_info["avg"]
	
remote func ping_ack(start_time):	
	var client_id = cfc.get_rpc_sender_id() 
	var end_time = Time.get_ticks_msec()
	var last_ping = end_time - start_time
		
	var ping_avg = last_ping
	if ping_data.has(client_id):
		ping_avg = ping_data[client_id]["avg"]

	ping_data[client_id] = {
		"last_ping": last_ping,
		"avg" : ((3 * ping_avg) + last_ping) / 4
	} 

func ping():
	if !get_tree():
		return
	if !get_tree().network_peer:
		return
		
	var new_ping_time = Time.get_ticks_msec()
	#ping every 2 seconds at most
	if new_ping_time - last_ping_time < 2000:
		return
	last_ping_time = new_ping_time
	rpc_unreliable("receive_ping_request", last_ping_time)


func performance_checks():
	ping()
	fps = Performance.get_monitor(Performance.TIME_FPS)
	if fps < 25:
		low_fps = true
	else:
		low_fps = false

remote func receive_ping_request(start_time):
	var client_id = cfc.get_rpc_sender_id() 
	rpc_unreliable_id(client_id, "ping_ack", start_time)

func delete_log_files():
	var dir:Directory = Directory.new()
	var log_dir = "user://"
	var log_files = CFUtils.list_files_in_directory(log_dir, "log_" )
	for file in log_files:
		if file.ends_with(".txt"):
			# warning-ignore:return_value_discarded
			dir.remove(log_dir + file)

func init_settings_from_file() -> void:
	.init_settings_from_file()
	#Settings default values
	game_settings = WCUtils.merge_dict(CFConst.DEFAULT_SETTINGS, game_settings,  true)
	save_settings() #will generate settings file on disc if not exist yet

func get_card_name_by_id(id):
	var card_data = get_card_by_id(id)
	if !card_data or !card_data.has("Name"):
		return ""
					
	return card_data["Name"]


func get_card_by_id(id):
	if (not id):
		WCUtils.debug_message("no id passed to get_card_by_id")
		return null		
	var card_data = card_definitions.get(id, {})
	
	if not card_data:
		WCUtils.debug_message("no data matching get_card_by_id " + str(id))
		return null	
	
	return card_data

	

func load_card_scenarios():
	var json_card_data : Dictionary
	json_card_data = WCUtils.read_json_file_with_user_override("Sets/_scenarios.json")	
	for key in json_card_data:
		var card_data = json_card_data[key]
		#creating entries for both id and name so I never have to remember which one to use...
		primitives[card_data["code"]] = card_data;
		primitives[card_data["name"]] = card_data;
		scenarios.append(key)

func stage_variant_to_int(stage):
	if typeof(stage) == TYPE_INT:
		return stage
	if typeof(stage) == TYPE_STRING:
		match stage.to_upper():
			"I":
				return 1
			"II":
				return 2
			"III":
				return 3
			_:
				return int (stage.substr(0,1))
			
	#todo error
	var _error = 1
	return 0

func parse_keywords(text:String) -> Dictionary:
	var result:= {}
	
	var lc_text:String = text.to_lower()
	for _keyword in CFConst.AUTO_KEYWORDS.keys():
		var keyword:String = _keyword.to_lower()
		var type = CFConst.AUTO_KEYWORDS[keyword]
		

		
		match type:
			"bool":
				result[keyword] = false		
				var position = lc_text.find(keyword + ".")
				if  position >=0:
					result[keyword] = true
			"int":
				result[keyword] = 0
				var position = lc_text.find(keyword + " ")
				if  position >=0:
					var value = lc_text.substr(position + keyword.length() + 1, 1)
					result[keyword] = int(value)
			"string":
				#TODO
				result[keyword] = ""
				var position = lc_text.find(keyword + ".")
				if  position >=0:
					result[keyword] = true
				pass
			_:
				#error
				pass
	return result

func _split_traits(traits:String) -> Array:
	var result = []
	var a_traits = traits.split(". ")
	for trait in a_traits:
		trait = trait.to_lower().trim_suffix(".")
		trait = trait.replace(" ", "_")		
		result.append(trait)
	
	return result

func setup_traits_as_alterants():
	for trait in self.all_traits:

		CardConfig.PROPERTIES_NUMBERS.append("trait_" + trait)
	for keyword in CFConst.AUTO_KEYWORDS:
		if keyword =="guard":
			var _tmp=1		
		if CFConst.AUTO_KEYWORDS[keyword] in ["int", "bool"]:
			CardConfig.PROPERTIES_NUMBERS.append(keyword)

#we skip some cards from the marvelcdb database,
#when they are redundant or not useful for this game
func dont_load_this_card(card_data:Dictionary):
	var stage = card_data.get("stage", "").to_upper()
	if (stage.ends_with("A") or stage.ends_with("B")):
		return true
	return false

func cleanup_bb_code(text):
	var result = text
	var replacements = {
		"[[": "[i]",
		"]]": "[/i]",
		"[star]": "*",	
		"→": "-->",	
	}
	for key in replacements:
		result = result.replace(key, replacements[key])
	return result

func convert_to_bbcode(text):
	var result = text
	result = result.replace("<", "[")
	result = result.replace (">", "]")
	result = cleanup_bb_code(result)	
	return result

var _seen_images:= {}
func _load_one_card_definition(card_data, box_name:= "core"):
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
	card_data["box_name"] = box_name
	
	#linked cards might be missing preprocessing data
	if not card_data.has("_code"):
		card_data["_code"] = card_data.get("code", "")
	var card_id = card_data["_code"]	

	#hardcoded patches
	var patches = CFConst.HARDCODED_DEF_PATCHES.get(card_id, {})
	for key in patches:
		card_data[key] = patches[key]

	
	if not card_data.has("Tags"):
		card_data["Tags"] = []			

	if not card_data.has("Requirements"):
		card_data["Requirements"] = ""
		
	if not card_data.has("Abilities"):
		card_data["Abilities "] = ""		

	if not card_data.has("back_card_code"):
		card_data["back_card_code"] = ""
	
	if not card_data.has("_set"):
		card_data["_set"] = card_data.get("pack_code", "")	

	if not card_data.has("Name"):
		card_data["Name"] = card_data.get("name", "")

	if card_data.get("stage", ""):
		card_data["original_stage"] = str(card_data["stage"])
		card_data["stage"] = stage_variant_to_int(card_data["stage"])
		
	#Are those still needed?
	if not card_data.has("Power"):
		card_data["Power"] = card_data.get("attack")	#can be a string

	if not card_data.has("Health"):
		card_data["Health"] = card_data.get("health", 0)	

	#TODO more generically have a backup for printed_values?
	card_data["printed_health"] = card_data.get("health", 0)

	if not card_data.has("Cost") and card_data.has("cost"):
		card_data["Cost"] = card_data.get("cost")
	
	for action in ["attack","thwart", "scheme"]:	
		if card_data.has(action) and (card_data[action] != null):
			card_data["can_" + action] = true
			if card_data[action] < 0: #e.g. Titania gets "-1" in marvelcdb which is a problem for alterants
				 card_data[action] = 0
		else:
			card_data["can_" + action] = false	

	card_data["text"] = convert_to_bbcode(card_data.get("real_text", ""))

	###END Fixing missing data

	var card_type:String = card_data["type_code"]
	
	#enriching data
	var lc_card_type = card_type.to_lower()
	var force_horizontal = CFConst.FORCE_HORIZONTAL_CARDS.get(lc_card_type, false)
	card_data["_horizontal"] = force_horizontal

	var default_properties = CFConst.DEFAULT_PROPERTIES_BY_TYPE.get(lc_card_type, {})
	for k in default_properties:
		card_data[k] = default_properties[k] 
	

	#Keywords parsing
	if (!card_data.has("keywords")):
		card_data["keywords"] = parse_keywords(card_data.get("text", ""))
	#flatten it out to allow access through alterants and get_property
	for k in card_data["keywords"].keys():
		card_data[k] = card_data["keywords"][k]
	
	if (card_data.has("traits") and typeof(card_data["traits"]) == TYPE_STRING):
		var traits = _split_traits(card_data["traits"])
		for trait in traits:
			card_data["trait_" + trait] = 1
			all_traits[trait] = true
	

	#TODO 2024/10/30 is this error new?
	if not card_data.has("card_set_name"):
		card_data["card_set_name"] = "ERROR"	
	if not card_data.has("card_set_code"):
		card_data["card_set_code"] = "ERROR"	

		

	var set_code = card_data["card_set_code"]
	var lc_set_code = set_code.to_lower()
	
	var set_name = card_data["card_set_name"]
	var lc_set_name = set_name.to_lower()	

	
	#name alone isn't enough as a unique identifier (for the "unique" rule), so we're adding
	#subname
	card_data["shortname"] = card_data["Name"]
	if (card_data.get("subname", "")):
		card_data["Name"] += " - " + card_data["subname"]	
		var _tmp = card_data["Name"]
		var _error = 0
	#Villains: multiple cards have the same name.
	#Hack to "fix" this by adding stage number
	#e.g. "Rhino_2"
	if (lc_card_type == "villain"):
		card_data["Name"] = card_data["Name"] + " - " + String(card_data["stage"])
	
	card_data.erase("name")
	
		
	if !box_contents_by_name.has(box_name):
		box_contents_by_name[box_name] = {}
	#the same card name can happen multiple times in a single box with a different ID, 
	#for example "Wakanda Forever"
	if !box_contents_by_name[box_name].has(card_data["Name"]):
		box_contents_by_name[box_name][card_data["Name"]] = []
	box_contents_by_name[box_name][card_data["Name"]].append(card_data)	

	var card_name:String = card_data["Name"]
	
	#caching and indexing
	shortname_to_name[card_data["shortname"].to_lower()] = card_name
	lowercase_card_name_to_name[card_name.to_lower()] = card_name
	
	#schemes cache
	if (lc_card_type == "main_scheme"):
		var full_stage_id = card_data["original_stage"]	
		#skip the weird "1A", "1B" cards for now...
		if (!full_stage_id.ends_with("A") and !full_stage_id.ends_with("B")):
			if (not schemes.has(lc_set_code)):
				schemes[lc_set_code] = []
			schemes[lc_set_code].push_back(card_data)
		
	var card_set_type_name_code = card_data.get("card_set_type_name_code", "")
	if card_set_type_name_code == "modular":
		if not modular_encounters.has(lc_set_code):
			modular_encounters[lc_set_code] = []
		modular_encounters[lc_set_code].append(card_data)
	
	#obligations cache
	if (lc_card_type == "obligation"):
		obligations[lc_set_code] = card_data
		obligations[lc_set_name] = card_data
		
	#encounter/set cache
	if (not cards_by_set.has(lc_set_code)):
		cards_by_set[lc_set_code] = []
	cards_by_set[lc_set_code].push_back(card_data)				
		

	card_data[CardConfig.SCENE_PROPERTY] = "CardTemplate"	

	if card_data.get("duplicate_of_code", ""):
		duplicates[card_id] = card_data["duplicate_of_code"]

			
# Returns a Dictionary with the combined Card definitions of all set files
# loaded in card_definitions variable by core engine
func load_card_definitions() -> Dictionary:
	cards_loading = true	
	if (primitives.empty()):
		load_card_scenarios()
	var combined_sets := {} #.load_card_definitions(); #TODO Remove the call to parent eventually ?
	# Load from external user files
	var the_files = CFUtils.list_files_in_directory(
			"user://Sets/", CFConst.CARD_SET_NAME_PREPEND)
	#load from "res://" as well
	the_files += CFUtils.list_files_in_directory(
			"res://Sets/", CFConst.CARD_SET_NAME_PREPEND)
	var set_files = {}
	for file in the_files:
		set_files[file] = true				
	WCUtils.debug_message(set_files.size())	
	var json_card_data : Dictionary = {}
	_total_cards = 0	
	for set_file in set_files:
		var prefix_length = CFConst.CARD_SET_NAME_PREPEND.length()
		var extension_idx = set_file.find(".")
		var box_name = set_file.substr(prefix_length, extension_idx-prefix_length)
		var json_array = WCUtils.read_json_file_with_user_override	("Sets/" + set_file)
		_total_cards += json_array.size() 
		json_card_data[box_name] = json_array
		
	var i = 0
	for box_name in json_card_data.keys():	
		for card_data in (json_card_data[box_name]):
			i+=1
			if dont_load_this_card(card_data):
				continue			
			_load_one_card_definition(card_data, box_name)	
			combined_sets[card_data["_code"]] = card_data
			
			var linked_card_data = card_data.get("linked_card", {})
			if (linked_card_data):
				_load_one_card_definition(linked_card_data, box_name)
				linked_card_data["back_card_code"] = card_data["_code"]
				card_data["back_card_code"] = linked_card_data["_code"]
				combined_sets[linked_card_data["_code"]] = linked_card_data

#			var double_sided = card_data.get("double_sided", false)
#			if (double_sided):
#				var back_side_data = card_data.duplicate()
#				back_side_data["_code"] = card_data["_code"] + "b"
#				back_side_data["code"] = back_side_data["_code"]
#				back_side_data["text"] = back_side_data.get("back_text", "")
#
#				back_side_data["back_card_code"] = card_data["_code"]
#				card_data["back_card_code"] = back_side_data["_code"]				
#				#TODO more changes needed ?
#				_load_one_card_definition(back_side_data)
#				#yield(get_tree().create_timer(0.01), "timeout")
			_cards_loaded = i
	card_definitions = combined_sets
	
	#post load cleanup and config
	setup_traits_as_alterants()
	
	#done!
	cards_loading = false			
	emit_signal("card_definitions_loaded")
	return(combined_sets)

func save_one_deck_to_file(json_deck_data):
	if !(_is_deck_valid(json_deck_data)):
		return
	var deck_id: int = json_deck_data["id"]
	var filename = "user://Decks/" + str(deck_id) + ".json"
	var file = File.new()
	file.open(filename, File.WRITE)
	file.store_string(JSON.print(json_deck_data, '\t'))
	file.close()


func load_one_deck(json_deck_data):
	if !(_is_deck_valid(json_deck_data)):
		return
	var deck_id: int = json_deck_data["id"]
	var hero_id = json_deck_data.get("hero_code",json_deck_data.get("investigator_code", ""))
	deck_definitions[deck_id] = json_deck_data
	if (not idx_hero_to_deck_ids.has(hero_id)):
		idx_hero_to_deck_ids[hero_id] = []
	if not deck_id in (idx_hero_to_deck_ids[hero_id]):
		idx_hero_to_deck_ids[hero_id].push_back(deck_id)	

# Returns a Dictionary with the Decks
func load_deck_definitions():
	#copy default decks from Res: just in case they are missing
	var res_deck_files = CFUtils.list_files_in_directory("res://Decks/")
	# Load from external user files as well	for comparison
	var deck_files = CFUtils.list_files_in_directory("user://Decks/")

	var need_reload = false
	for deck_file in res_deck_files:
		if !deck_file.ends_with(".json"):
			continue
		if !deck_file in deck_files:
			var json_deck_data : Dictionary = WCUtils.read_json_file("res://Decks/" + deck_file)
			save_one_deck_to_file(json_deck_data)
			need_reload = true

	if need_reload:
		deck_files = CFUtils.list_files_in_directory("user://Decks/")
	
	WCUtils.debug_message(deck_files.size())		
	for deck_file in deck_files:
		var json_deck_data : Dictionary = WCUtils.read_json_file("user://Decks/" + deck_file)
		#Fixing missing Data
		#nothing for now
		load_one_deck(json_deck_data)
	return

#card database related functions
func get_hero_obligation(hero_id:String):
	#todo error handling
	var hero_data = get_card_by_id(hero_id)
	var hero_name = hero_data["Name"]
	var obligation = obligations[hero_name.to_lower()]
	return obligation

#returns all schemes belonging to the same collection as scheme_id,
#sorted in expected appearance order		
func get_schemes(scheme_id):	
	#todo error handling
	var scheme = get_card_by_id(scheme_id)
	var set_name = scheme["card_set_code"]
	var my_schemes = schemes[set_name.to_lower()]
	my_schemes.sort_custom(WCUtils, "sort_stage")
	return my_schemes

func get_encounter_cards(set_name:String):
	var encounters = cards_by_set.get(set_name.to_lower(), [])
	if !encounters:
		cfc.LOG("encounters missing for set name " + set_name.to_lower() )
	return encounters

#check if a given deck is valid (we must own all cards)
var _last_deck_error_msg := ""
func _is_deck_valid(deck) -> bool:
	_last_deck_error_msg = ""
	var hero_code = deck.get("hero_code", "")
	if !hero_code:
		hero_code = deck.get("investigator_code", "")
	if (not card_definitions.has(hero_code)):
		var hero_name = deck.get("hero_name", hero_code )
		_last_deck_error_msg= "This hero is not in our Database:" + hero_name
		return false
	var slots: Dictionary = deck["slots"]
	if (not slots or slots.empty()):
		_last_deck_error_msg = "invalid deck, can't find cards"	
		return false
	for slot in slots:
		if (not card_definitions.has(slot)):
			_last_deck_error_msg = "We don't support at least one card in this deck (card id:" + str(slot) + ")" 
			return false		
	return true

func replace_text_macro (replacements, macro_value):
	var text = to_json(macro_value)
	for key in replacements.keys():
		var value = replacements[key]
		var to_replace = key
		if typeof(value) in [TYPE_REAL,TYPE_INT,TYPE_BOOL]:
			to_replace = "\"" + key + "\""
			value = str(value).to_lower()
		text = text.replace(to_replace, str(value))
	
	var result = parse_json(text)
	if !result:
		var _error = 1
	return result

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
	scripts_loading = true	
	var script_overrides = load(CFConst.PATH_SETS + "SetScripts_All.gd").new()
	var json_macro_data : Dictionary = WCUtils.read_json_file_with_user_override("Sets/_macros.json")
	
	
	var combined_scripts := {}
	
	#load from user first
	var script_definition_files := CFUtils.list_files_in_directory(
				"user://Sets/", CFConst.SCRIPT_SET_NAME_PREPEND, true)
	
	#then we load from resources (their entries will overwrite user ones only if the user entries don't exist)
	script_definition_files += CFUtils.list_files_in_directory(
				"res://Sets/", CFConst.SCRIPT_SET_NAME_PREPEND, true)
	WCUtils.debug_message("Found " + str(script_definition_files.size()) + " script files")			
	for script_file in script_definition_files:
		var prefix_end = script_file.find(CFConst.SCRIPT_SET_NAME_PREPEND) + CFConst.SCRIPT_SET_NAME_PREPEND.length()
		var extension_idx = script_file.find(".")
		var box_name = script_file.substr(prefix_end, extension_idx-prefix_end)	
		if !box_contents_by_name.has(box_name):
			continue
		var json_card_data : Dictionary
		json_card_data = WCUtils.read_json_file(script_file)
		#delete comments from dictionary
		WCUtils.erase_key_recursive(json_card_data, "_comments")
		json_card_data = replace_macros(json_card_data, json_macro_data)
		
		#we don't support "response" yet but want to in the future. For now they're just interrupts
		json_card_data = WCUtils.search_and_replace (json_card_data, "response", "interrupt", true)
		#bugfix: replace "floats" to "ints"
		json_card_data = WCUtils.replace_real_to_int(json_card_data)
		var _text = to_json(json_card_data)
		for fuzzy_card_name in json_card_data.keys():
			var card_info = retrieve_card_info_from_fuzzy_name(fuzzy_card_name)
			var card_name = card_info["name"]
			var card_code = card_info["code"]
			if card_code:
				if not combined_scripts.get(card_code): #this ensures the first data that was read gets precedence
					var script_data = json_card_data[fuzzy_card_name]
					combined_scripts[card_code]	= script_data
			else:
				var card_datas = box_contents_by_name[box_name].get(card_name, [])
				if !card_datas:
					var error_msg = "scripting for non existing card: " + card_name + ". Check case, character subname, etc..."
					cfc.emit_signal("json_parse_error", error_msg)				
				for card_data in card_datas:
					var card_id = card_data["_code"]
					if not combined_scripts.get(card_id):  #this ensures the first data that was read gets precedence
						var script_data = json_card_data[card_name]
						combined_scripts[card_id]	= script_data	
		
	#once everything is loaded, fill the script of cards that are duplicates
	#we only fill with duplicate data if we don't already have info on this card
	for card_id in duplicates:
		var duplicate_of = duplicates[card_id]
		if not combined_scripts.get(card_id):
			var duplicate_data = combined_scripts.get(duplicate_of, {})	
			combined_scripts[card_id] = duplicate_data		

	for card_id in card_definitions.keys():
		var card_script = script_overrides.get_scripts(combined_scripts, card_id)
		var unmodified_card_script = script_overrides.get_scripts(combined_scripts, card_id, false)
#		print(unmodified_card_script)
		if not card_script.empty():
			combined_scripts[card_id] = card_script
			set_scripts[card_id] = card_script
			unmodified_set_scripts[card_id] = unmodified_card_script
	
	#load additional stuff
	load_deck_definitions()
	
	scripts_loading = false	
	emit_signal("scripts_loaded")

func retrieve_card_info_from_fuzzy_name(fuzzy_card_name):
	var card_name = fuzzy_card_name.strip_edges()
	var card_code = ""
	if "#" in card_name:
		var values = card_name.split("#")
		card_name = values[0].strip_edges()
		card_code = values[1].strip_edges()
	return {
		"name" : card_name,
		"code" : card_code	
	}

func enrich_window_title(selectionWindow, script:ScriptObject, title:String) -> String:
	var result:String = title
	var script_definitions = script.script_definition
	var script_name = script_definitions.name
	var forced_title = script_definitions.get("display_title", "")
	var owner = script.owner
	
	if (forced_title):
		result = forced_title + " - " + result
	else:
	
		result = owner.properties.get("shortname", owner.canonical_name) + " - " + result
	
	match script_name:
		"enemy_attack":
			var target_str = ""
			if script.trigger_details.has(SP.TRIGGER_TARGET_HERO):
				target_str = " " +  script.trigger_details.get(SP.TRIGGER_TARGET_HERO)
			result = owner.get_display_name() + " attacks" + target_str +". Choose 1 defender or cancel for undefended" 
		"pay_as_resource":
			result = owner.canonical_name + " - Select at least " + str(selectionWindow.selection_count) + " resources."
	match forced_title:
		"__end_phase_discard__":
			var cancel_str = "."
			if selectionWindow.cancel_button.visible:
				cancel_str = " or cancel to keep your hand"
			result = owner.get_display_name() + ": Player phase end. Choose cards to discard" +cancel_str			
		"__mulligan__":
			var cancel_str = "."
			if selectionWindow.cancel_button.visible:
				cancel_str = " or cancel to keep your hand"
			result = owner.get_display_name() + ": Mulligan. Choose cards to discard" +cancel_str			
	return result;

#A poor man's mechanism to pass parameters betwen scenes
func set_next_scene_params(params : Dictionary):
	next_scene_params = params.duplicate()
	
func get_next_scene_params() -> Dictionary:
	return next_scene_params

var _img_filename_cache:= {}
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
	if !(card_code and card_set):
		return ""
		
	var key = card_set + "_" + card_code
	if _img_filename_cache.has(key):
		return _img_filename_cache[key]
	
	var filename = "Sets/images/" + card_set + "/" + card_code + ".png"
	var file = File.new()
	for prefix in["user://", "res://"]: #user has priority
		if file.file_exists(prefix + filename):	
			_img_filename_cache[key] = prefix + filename
			return _img_filename_cache[key]
	
	for prefix in["user://", "res://"]: #user has priority
		if ResourceLoader.exists(prefix + filename):	
			_img_filename_cache[key] = prefix + filename
			return _img_filename_cache[key]
	
	#if we didn't find it, we still set it to its final destination of user folder, 
	#which will direct the system to download it there
	_img_filename_cache[key] = "user://" + filename
	return _img_filename_cache[key] #todo return graceful fallback



func get_villain_portrait(card_id) -> Texture:
	var area = 	Rect2 ( 65, 60, 155, 155 )
	var result = get_sub_texture(card_id, area)
	if result:
		return result
	return fallback_villain_portrait(card_id, area)
	
func fallback_villain_portrait(card_id, area) -> Texture:
	var filename = "res://assets/other/villain_card.png"
	var texture = get_external_texture(filename)
	var sub_tex= _get_cropped_texture(texture , area)
	return sub_tex	

func get_scheme_portrait(card_id) -> Texture:
	var real_id = card_id			
	var area = 	Rect2 ( 55, 15, 200, 155 )
	return get_sub_texture(real_id, area)
	
func get_hero_portrait(card_id) -> Texture:
	var area = 	Rect2 ( 60, 40, 170, 180 )
	var result = get_sub_texture(card_id, area)
	if result:
		return result
	return fallback_hero_portrait(card_id, area)
	
func fallback_hero_portrait(card_id, area) -> Texture:
	var filename = "res://assets/other/hero_card.png"
	var texture = get_external_texture(filename)
	var sub_tex= _get_cropped_texture(texture , area)
	return sub_tex		
	
func get_sub_texture(card_id, area):
	var filename = get_img_filename(card_id)
	var texture = get_external_texture(filename)
	if !texture:
		return null
	var sub_tex= _get_cropped_texture(texture , area)
	return sub_tex		

func instance_ghost_card(original_card, controller_id) -> Card:
	var card_id = original_card.canonical_id
	#var owner_id = original_card.get_owner_hero_id()
	var card = ._instance_card(card_id)
	card.set_script(load("res://src/wc/GhostCard.gd"))
	card.canonical_name = card_definitions[card_id]["Name"]
	card.canonical_id = card_id	
	card.set_real_card(original_card)
	#TODO We set GUID here in the hope that all clients create their cards in the exact 
	#same order. This might be a very flawed assertion could need a significant overhaul	
	var _tmp = guidMaster.set_guid(card)
	card.init_owner_hero_id(controller_id)
	card.set_controller_hero_id(controller_id)	
	return card

func instance_card(card_id: String, owner_id:int) -> Card:
	if (!card_definitions.has(card_id)):
		#TODO error handling
		var _error = 1
		return null
		
	var card = ._instance_card(card_id)
	#TODO We set GUID here in the hope that all clients create their cards in the exact 
	#same order. This might be a very flawed assertion could need a significant overhaul
	#we also don't assign a GUID to cards created without an owner, those are usually
	#used for local targeting, etc...
	if (owner_id >=0):	
		var _tmp = guidMaster.set_guid(card)
	card.init_owner_hero_id(owner_id)
	card.set_controller_hero_id(owner_id)
	return card
	
#card here is either a card id or a card name, we try to accomodate for both
func get_corrected_card_id (card) -> String:
	#if it's in the database, it's already an id
	if self.card_definitions.has(card):
		var card_data = self.card_definitions[card]
		return card_data["_code"]
	
	#otherwise it's a short name or a long name
	var actual_card_name = lowercase_card_name_to_name.get(card.to_lower(), "")
	if !actual_card_name:
		actual_card_name = shortname_to_name.get(card.to_lower(), "")
		
	#we got the card's full name, now we reach for its actual id by looking in all sets
	#in some cases this is a non unique situation, beware!
	var boxes = box_contents_by_name
	for box_name in boxes:
		var box = boxes[box_name]
		if box.has(actual_card_name):
			var card_datas = box[actual_card_name]
			return card_datas[0]["_code"]
	return ""

#mark a download as failed to avoid constantly attempting it
var failed_files:= {}

func get_failed_files():
	if failed_files:
		return failed_files
	var filename = "user://failed_image_downloads.json"
	var _failed_files = WCUtils.read_json_file(filename)
	failed_files =  _failed_files if _failed_files else {}
	#return failed_files

func fail_img_download(card_id):
	var file = File.new()
	var filename = "user://failed_image_downloads.json"
	get_failed_files()
	failed_files[card_id] = true
	var to_print = to_json(failed_files)	
	file.open(filename, File.WRITE)
	file.store_string(to_print)
	file.close()  		

func is_image_download_failed(card_id):
	get_failed_files()
	return failed_files.get(card_id, false)

func get_image_dl_url(card_id):
	var card_data = get_card_by_id(card_id) 
	var base_url = game_settings.get("images_base_url")
	if !base_url:
		fail_img_download(card_id)
		return ""
	if !card_data:
		if CFConst.ATTEMPT_TO_GUESS_IMAGE_URL:
			var url = base_url + "/bundles/cards/" + str(card_id) + ".png"
			return url
	if !card_data.has("imagesrc"):
			var duplicate_of = card_data.get("duplicate_of_code", "")
			if duplicate_of:
				return get_image_dl_url(duplicate_of)
			else:
				fail_img_download(card_id)
				return ""
	var url = base_url + card_data["imagesrc"]
	return url

#this precaches files on the system due to a bug in Godot
#see https://github.com/godotengine/godot/issues/87274	
var _cached_filesystem: Dictionary = {}

func _cache_filesystem():
	for folder in ["res://Test", "res://Sets", "res://Decks"]:
		var list = CFUtils.list_files_in_directory(folder)
		_cached_filesystem[folder] = list
		_cached_filesystem[folder+ "/"] = list

#Loads PCK files for additional resources
func preload_pck():
	_cache_filesystem()
	
	var database = cfc.game_settings.get("database", {})
	if typeof(database) != TYPE_DICTIONARY:
		var _error = 1
		#TODO error
		return
	
	var file = File.new()
	
	#for each set, try to load package files for it
	#loading data from a file overrides the previous one, so a package file
	#has higher priority (its content will override previously loaded ones if they exist)
	#lower priority <<< higher priority
	#res pck <<< res zip <<< user pck <<< user zip
	#user files have priority to let users put mods in their user folder
	#zip files have priority because I have found they have better compatibility
	# (pck files will refuse to load if wrong godot version number for example)
	# see https://www.reddit.com/r/godot/comments/11pfoon/comment/jbxyp2x/
	for set in database.keys():
		for folder in ["res://", "user://"]:		
			for format in [".pck", ".zip"]:
				var filename = folder + set + format
				if file.file_exists(filename):
					var _success_res = ProjectSettings.load_resource_pack(filename)
	return
#
# Network related functions


var _network_id = 0
func get_network_unique_id():
	if _network_id:
		 return _network_id
	if gameData.is_multiplayer_game:
		if !get_tree():
			return 1
		_network_id = get_tree().get_network_unique_id()
		return _network_id
	return 1
	
func is_game_master() -> bool:	
	if !gameData.is_multiplayer_game:
		return true
	return get_tree().is_network_server() 

var _log_buffer := ""
func INIT_LOG():
	var file = File.new()
	var network_id = cfc.get_network_unique_id() if get_tree().has_network_peer() else 0
	var player = gameData.get_player_by_network_id(network_id) if network_id else null
	var player_id = player.get_id()	if player else 0
	var filename = "user://log_" + str(player_id) +".txt"
	if (file.file_exists(filename)):
		return
	file.open(filename, File.WRITE)
	file.close() 	
	
func LOG(to_print:String):
	if !cfc._debug and !CFConst.FORCE_LOGS:
		return
	_log_buffer+= Time.get_datetime_string_from_system() + " - " + to_print + "\n"	
	if _log_buffer.length() < 2000:
		return
	FLUSH_LOG()
	
func FLUSH_LOG():
	INIT_LOG()
	var file = File.new()
	var network_id = cfc.get_network_unique_id() if get_tree().has_network_peer() else 0
	var player = gameData.get_player_by_network_id(network_id)  if network_id else null
	var player_id = player.get_id()	if player else 0
	file.open("user://log_" + str(player_id) +".txt", File.READ_WRITE)
	file.seek_end()
	file.store_string(_log_buffer + "\n")
	file.close() 
	_log_buffer = ""

func LOG_VARIANT(to_print):
#	if !cfc._debug:
#		return
	var my_json_string = JSON.print(to_print, '\t')
	LOG(my_json_string)
	
func LOG_DICT(to_print:Dictionary):
#	if !cfc._debug:
#		return
	var my_json_string = JSON.print(to_print, '\t')
	LOG(my_json_string)
	
func add_ongoing_process(object, description:String = ""):
	if (!description):
		if typeof(object) == TYPE_DICTIONARY:
			description = "dictionary"
		else:
			description = object.get_class()
		
	if (!_ongoing_processes.has(object)):
		_ongoing_processes[object] = {}
	if (!_ongoing_processes[object].has(description)):
		_ongoing_processes[object][description] = 0	

	_ongoing_processes[object][description] +=1
	return _ongoing_processes[object][description]
	
func remove_ongoing_process(object, description:String = ""):
	if (!description):
		if typeof(object) == TYPE_DICTIONARY:
			description = "dictionary"
		else:
			description = object.get_class()
		
	if (!_ongoing_processes.has(object)):
		return 0
		
	if (!_ongoing_processes[object].has(description)):
		return 0
				
	_ongoing_processes[object][description] -=1
	if (!_ongoing_processes[object][description]):
		_ongoing_processes[object].erase(description)
		if !_ongoing_processes[object]:
			var _found = _ongoing_processes.erase(object)
		return 0
	return _ongoing_processes[object][description]
	
func is_process_ongoing() -> int:
	return _ongoing_processes.size()	

func reset_ongoing_process_stack():
	_ongoing_processes = {}

func buttons_grab_focus_on_mouse_entered(node):
	if node as Button:
		node.connect("mouse_entered", node, "grab_focus")
	if node.has_method("get_children"):
		for child in node.get_children():
			buttons_grab_focus_on_mouse_entered(child)

var stretch_mode = -1
func get_screen_stretch_mode():
	if stretch_mode >=0:
		return stretch_mode
	var stretch_mode_str = ProjectSettings.get_setting("display/window/stretch/mode")
	match stretch_mode_str:
		"viewport":
			stretch_mode = SceneTree.STRETCH_MODE_VIEWPORT
		"2d":
			stretch_mode = SceneTree.STRETCH_MODE_2D
		_:	
			stretch_mode = SceneTree.STRETCH_MODE_DISABLED
	return stretch_mode

func is_modal_event_ongoing():
	if get_modal_menu():
		return true
	if gameData.is_ongoing_blocking_announce():
		return true
	return false

func _rpc(object, func_name, arg0=null,
	arg1 =null,
	arg2 =null,
	arg3 =null,
	arg4 =null,
	arg5 =null,
	arg6 = null,
	arg7 = null,
	arg8 = null,
	arg9 = null):

	var params = []
	for i in [arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9]:
		if i== null:
			break
		params.append(i)

	if gameData.is_multiplayer_game:
		object.callv("rpc", [func_name] +  params)
	else:
		#object.callv(func_name, params)
		object.call_deferred("callv", func_name,  params)	
func _rpc_id(object, client_id, func_name, arg0=null,
	arg1 =null,
	arg2 =null,
	arg3 =null,
	arg4 =null,
	arg5 =null,
	arg6 = null,
	arg7 = null,
	arg8 = null,
	arg9 = null):

	var params = []
	for i in [arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9]:
		if i== null:
			break
		params.append(i)

	if gameData.is_multiplayer_game:
		object.callv("rpc_id", [client_id,func_name] + params)
	else:
		object.call_deferred("callv", func_name,  params)	

func get_rpc_sender_id():
	if gameData.is_multiplayer_game:
		return get_tree().get_rpc_sender_id()
	return 1

# Ensures proper cleanup when a card is queue_free() for any reason
func _on_tree_exiting():	
	FLUSH_LOG()

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		FLUSH_LOG()
	
func quit_game() -> void:
	.quit_game()
	gameData.cleanup_post_game()		
