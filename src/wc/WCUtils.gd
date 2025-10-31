# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:UNUSED_VARIABLE
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCUtils
extends "res://src/core/CFUtils.gd"


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

#Read json file into dictionary (or array!)
static func read_json_file(file_path):
	var file = File.new()
	var err = file.open(file_path, File.READ)
	if err != OK:
		return null
	var content_as_text = file.get_as_text()
	var json_errors = validate_json(content_as_text)
	if (json_errors):
		var error_msg = file_path + " - " + json_errors
		print_debug(error_msg)
		cfc.LOG(error_msg)
		return null #TODO intentionally returning null here to force a crash until we have proper error reporting
	var content_as_dictionary = parse_json(content_as_text)
	return content_as_dictionary

#Print debug message
static func debug_message(msg):
	if OS.has_feature("debug") and not cfc.is_testing:
		print_debug(msg)
		

#load Image Data from jpeg/png file		
static func load_img(file) -> Image :
	var img_file = File.new()
	if img_file.open(file, File.READ):
		return null
	var bytes = img_file.get_buffer(img_file.get_len())
	img_file.close()
	
	var img = Image.new()	
	var extension = file.get_extension().to_lower()
	var error_code = 0
	if extension == "png":
		error_code = img.load_png_from_buffer(bytes)
	else:
		error_code = img.load_jpg_from_buffer(bytes)
	if error_code:
		return null	
	return img	

static func merge_array(array_1: Array, array_2: Array, deep_merge: bool = false) -> Array:
	var new_array = array_1.duplicate(true)
	var compare_array = new_array
	var item_exists

	if deep_merge:
		compare_array = []
		for item in new_array:
			if item is Dictionary or item is Array:
				compare_array.append(JSON.print(item))
			else:
				compare_array.append(item)

	for item in array_2:
		item_exists = item
		if item is Dictionary or item is Array:
			item = item.duplicate(true)
			if deep_merge:
				item_exists = JSON.print(item)

		if not item_exists in compare_array:
			new_array.append(item)
	return new_array

#merges data from dict_2 into dict1 (overwriting if needed)		
static func merge_dict(dict_1: Dictionary, dict_2: Dictionary, deep_merge: bool = false) -> Dictionary:
	var new_dict = dict_1.duplicate(true)
	for key in dict_2:
		if key in new_dict:
			if deep_merge and dict_1[key] is Dictionary and dict_2[key] is Dictionary:
				new_dict[key] = merge_dict(dict_1[key], dict_2[key], deep_merge)
			elif deep_merge and dict_1[key] is Array and dict_2[key] is Array:
				new_dict[key] = merge_array(dict_1[key], dict_2[key], deep_merge)
			else:
				new_dict[key] = dict_2[key]
		else:
			new_dict[key] = dict_2[key]
	return new_dict

#check if all elements of dict1 can be found in dict2
#This doesn't mean the dictionaries are necessarily equal
static func is_element1_in_element2 (element1, element2, order_doesnt_matter: Array = [])-> bool:
	
	if (typeof(element1) != typeof(element2)):
		return false
	
	match typeof(element1):	
		TYPE_DICTIONARY:
			for key in element1:
				if not element2.has(key):
					return false
				var val1 = element1[key]
				var val2 = element2[key]
				
				if (key in order_doesnt_matter and typeof(val1) == TYPE_ARRAY and typeof(val2) == TYPE_ARRAY ):
					val1.sort()
					val2.sort()
																
				if !is_element1_in_element2(val1, val2, order_doesnt_matter):
					return false
		TYPE_ARRAY:
			#array order generally matters but we can skip elements from element2
			if (element1.size() > element2.size()): #Should we rather check for not equal here?
				return false
			var i:int = 0
			var j:int = 0
			for value in element1:
				var found = false
				while (j < element2.size() and !found ):
					found = is_element1_in_element2(element1[i], element2[j], order_doesnt_matter)
					j+= 1
				if (!found):
					return false
				i+=1
		TYPE_STRING:
			#we don't care for the case
			if (element1.to_lower() != element2.to_lower()):
				return false
		_:	
			if (element1 != element2):
				return false
	return true


static func sort_stage(a, b):
	if a["stage"] < b["stage"]:
		return true
	return false


static func sort_cards(a, b):
	if !(typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY):
		return a < b
		
	return (a.get("card") < b.get("card"))
	
static func to_grayscale(texture : Texture) -> Texture:
	var image = texture.get_data()
	image.convert(Image.FORMAT_LA8)
	image.convert(Image.FORMAT_RGBA8) # Not strictly necessary
	
	var image_texture = ImageTexture.new()
	image_texture.create_from_image(image)
	return image_texture
	

# we operate directly on the dictionary without duplicate for speed reasons. Make a copy prior if needed
static func search_and_replace (script_definition, from: String, to, exact_match: bool = false) -> Dictionary:
	match typeof(script_definition):
		TYPE_DICTIONARY:	
			for key in script_definition.keys():
				var value = script_definition[key]
				match typeof(value):
					TYPE_STRING:
						if (!exact_match):
							script_definition[key] = value.replace(from, to)
						elif (value == from):
							script_definition[key] = to
					TYPE_ARRAY:
						for x in value:
							search_and_replace(x,from, to, exact_match)
					TYPE_DICTIONARY:
						search_and_replace(value,from, to, exact_match)	
					
				#do the key too	
				if typeof(key) == TYPE_STRING:
					if ((!exact_match) or (key == from)):
						var new_string = key.replace(from, to)	
						script_definition[new_string] = script_definition[key]
						#TODO erase???	
		TYPE_STRING:
			if ((!exact_match) or (script_definition == from)):
				script_definition = script_definition.replace(from, to)	
	return script_definition;

#replace "REAL" (float) numbers into "INT".
#Patch utility for json loading issues
static func replace_real_to_int (script_definition):
	var result
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				result[key] = replace_real_to_int(script_definition[key])
		TYPE_ARRAY:	
			result = []
			for value in script_definition:
				result.append(replace_real_to_int(value))
		TYPE_REAL:
			result = int(script_definition)
		_:
			result = script_definition
	return result;
				
static func disable_and_hide_node(node:Node) -> void:
	node.set_process(false) # = Mode: Disabled
	node.visible = false

static func enable_and_show_node(node:Node) -> void:
	node.set_process(true)
	node.visible = true

