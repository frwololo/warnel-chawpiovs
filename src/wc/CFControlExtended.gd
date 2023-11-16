# Card Gaming Framework Control Singleton
#
# Add it to your autoloads with the name 'cfc'
class_name CFControlExtended
extends CFControl

#cache variables
var known_types : Dictionary
var unknown_types: Dictionary

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
	

# Returns a Dictionary with the combined Card definitions of all set files
func load_card_definitions() -> Dictionary:
	var combined_sets := .load_card_definitions();
	# Load from external user files as well	
	var loaded_definitions : Array
	var set_files = CFUtils.list_files_in_directory(
			"user://Sets/", CFConst.CARD_SET_NAME_PREPEND)
	WCUtils.debug_message(set_files.size())		
	for set_file in set_files:
		var json_card_data : Array
		json_card_data = WCUtils.read_json_file("user://Sets/" + set_file)
		for card_data in json_card_data:
			#skip unknown types gracefully: don't load cards with unknown type
			#TODO: assign them a generic type
			if _is_type_known(card_data[CardConfig.SCENE_PROPERTY]):
				combined_sets[card_data["Name"]] = card_data
	return(combined_sets)


# Returns a Dictionary with the combined Script definitions of all set files
func load_script_definitions() -> void:
	.load_script_definitions();
	#TODO load scripts from user folder


