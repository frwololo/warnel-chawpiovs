# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:UNUSED_VARIABLE
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCUtils
extends "res://src/core/CFUtils.gd"


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

static func read_json_file_with_user_override(file_path) -> Dictionary:
	var result = read_json_file("res://" + file_path)
	if !result:
		result = {}
	var user_data = read_json_file("user://" + file_path)
	if !user_data:
		return result
	#we have a user file and possibly a res file.
	#if they're both dictionaries, we want to overwrite res entries with existing user entries
	#otherwise we just return the user data	
	if typeof (user_data) != TYPE_DICTIONARY or typeof(result) != TYPE_DICTIONARY:
		return user_data
		
	for key in user_data:
		result[key] = user_data[key]
	return result

#Read json file into dictionary (or array!)
static func read_json_file(file_path):
	var content_as_text
	var file = File.new()
	var err = file.open(file_path, File.READ)
	if err != OK:
		if ResourceLoader.exists(file_path):
			content_as_text = ResourceLoader.load(file_path)
		else:
			return null
	else:
		content_as_text = file.get_as_text()
	var json_errors = validate_json(content_as_text)
	if (json_errors):
		var error_msg = file_path + " - " + json_errors
		print_debug(error_msg)
		cfc.emit_signal("json_parse_error", error_msg)
		cfc.LOG(error_msg)
		return {}
	var content_as_dictionary = parse_json(content_as_text)
	return content_as_dictionary

#Print debug message
static func debug_message(msg):
	if OS.has_feature("debug") and not cfc.is_testing:
		print_debug(msg)
		

#checks if a file exists either as a resource or
#on disk
static func file_exists(file:String):
	if !file.begins_with("res://") and !file.begins_with("user://"):
		return file_exists("res://" + file) or file_exists("user://" + file)	
	if ResourceLoader.exists(file):
		return true
	var _file = File.new()
	return _file.file_exists(file)	


#load Image Data from jpeg/png file	
#either from resources or from filesystem (filesystem prioritized)	
static func load_img(file) -> Image :
	var img = Image.new()
	#attempt from local file first, resource after
	var img_file = File.new()
	if img_file.open(file, File.READ):
		if ResourceLoader.exists(file):
			var tex = ResourceLoader.load(file)
			img = tex.get_data()
		else:
			return null
	else:
		var bytes = img_file.get_buffer(img_file.get_len())
		img_file.close()
		
		
		var extension = file.get_extension().to_lower()
		var error_code = 0
		if extension == "png":
			error_code = img.load_png_from_buffer(bytes)
		else:
			error_code = img.load_jpg_from_buffer(bytes)
		if error_code:
			return null	
	return img	


static func ordered_hash(dict:Dictionary):
	var sorted_dictionary = deep_dict_sort(dict)
	return sorted_dictionary.hash()

static func deep_dict_sort(value) -> Dictionary:
	var result
	match typeof(value):
		TYPE_DICTIONARY:
			result = {}
			var keys = value.keys()
			keys.sort()
			for key in keys:
				result[key] = deep_dict_sort(value[key])
		TYPE_ARRAY:
			result= []
			for element in value:
				result.append(deep_dict_sort(element))
		_:
			result = value
	return result

static func json_equal (lh, rh)-> bool:
	if (typeof(lh) != typeof(rh)):
		return false
	match typeof(lh):
		TYPE_DICTIONARY:
			for key in lh:
				if not rh.has(key):
					return false
				if ! (json_equal(lh[key], rh[key])):
					return false
			return true	
		TYPE_ARRAY:
			if lh.size() != rh.size():
				return false
			for i in range(lh.size()):
				var left = lh[i]
				var right = rh[i]
				if (!json_equal(left,right)):
					return false
			return true	
		_:
			return(lh==rh)

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
	return (a.get("card") < b.get("card"))

	
static func to_grayscale(_texture : Texture) -> Texture:
	var texture = _texture
	if _texture as AtlasTexture:
		texture = _texture.get_atlas()
		var _tmp = 1		
	else:
		pass
	var cur_image = texture.get_data()
	if cur_image.is_compressed():
		cur_image.decompress()
	var image = Image.new()
	image.copy_from(cur_image)
	image.convert(Image.FORMAT_LA8)
	image.convert(Image.FORMAT_RGBA8) # Not strictly necessary
	
	var image_texture = ImageTexture.new()
	image_texture.create_from_image(image)
	if _texture as AtlasTexture:
		image_texture = cfc._get_cropped_texture(image_texture, _texture.get_region())
	return image_texture

static func search_and_replace_str (orig_str:String, replacements:Dictionary, exact_match:bool = false):
	var new_str = orig_str
	for to_replace in replacements:
		if (orig_str == to_replace):
			return replacements[to_replace]
		if (!exact_match):		
			new_str = new_str.replace(to_replace, replacements[to_replace])
			if new_str != orig_str:
				return new_str
	return new_str

#this is a heavy dictionary string replace so we cache the results
#in my tests, most calls (>90%) result in a cache hit
const _search_and_replace_multi_cache = {}
static func search_and_replace_multi(script_definition, replacements:Dictionary, exact_match: bool = false) -> Dictionary:
	var _cache_key = {
		"definition": script_definition,
		"replacements": replacements,
		"exact_match": exact_match,
	}.hash()
	if !_search_and_replace_multi_cache.has(_cache_key):
		_search_and_replace_multi_cache[_cache_key] = search_and_replace_multi_no_cache (script_definition, replacements, exact_match)
	
	var result = _search_and_replace_multi_cache[_cache_key].duplicate(true)
	return result
	
static func search_and_replace_multi_no_cache (script_definition, replacements:Dictionary, exact_match: bool = false) -> Dictionary:
	var result = null
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				var value = script_definition[key]
				result[key] = search_and_replace_multi_no_cache(value, replacements, exact_match)

				#do the key too	
				if typeof(key) == TYPE_STRING:
						var new_string = search_and_replace_str(key, replacements, exact_match)
						result[new_string] = result[key]
						#TODO erase???	

		TYPE_ARRAY:
			result = []
			for x in script_definition:
				var computed = search_and_replace_multi_no_cache(x,replacements, exact_match)
				#special case, if replacing with an array, we flatten it
				if typeof(computed) == TYPE_ARRAY and typeof(x) == TYPE_STRING:
					for element in computed:
						result.append(element)
				else:
					result.append(computed)

		TYPE_STRING:
			result = search_and_replace_str(script_definition, replacements, exact_match)
		_:
			result = script_definition
	return result;

static func search_and_replace (script_definition, from: String, to, exact_match: bool = false) -> Dictionary:
	var result = null
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				var value = script_definition[key]
				result[key] = search_and_replace(value,from, to, exact_match)

				#do the key too	
				if typeof(key) == TYPE_STRING:
					if ((!exact_match) or (key == from)):
						var new_string = key.replace(from, to)	
						result[new_string] = result[key]
						#TODO erase???	

		TYPE_ARRAY:
			result = []
			for x in script_definition:
				var computed = search_and_replace(x,from, to, exact_match)
				#special case, if replacing with an array, we flatten it
				if typeof(computed) == TYPE_ARRAY and typeof(x) == TYPE_STRING:
					for element in computed:
						result.append(element)
				else:
					result.append(computed)

		TYPE_STRING:
			if (!exact_match):
				result = script_definition.replace(from, to)	
			elif (script_definition == from):
				if from == "any_discard":
					var _tmp = 1
				result = to
			else:
				result = script_definition
		_:
			result = script_definition
	return result;

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

#recursively erases a key from a json object
static func erase_key_recursive(data, key_to_erase: String) -> void:
	match typeof(data):
		TYPE_DICTIONARY:
			for key in data.keys():
				if key == key_to_erase:
					data.erase(key)
				else:
					erase_key_recursive(data[key], key_to_erase)
		TYPE_ARRAY:
			for element in data:
				erase_key_recursive(element, key_to_erase)
		_:
			pass

static func rotate_90(image, clockwise = true):
	var tmp_image = Image.new()
	var size = image.get_size()
	var format = image.get_format()
	tmp_image.create(size.y, size.x,false, format)
	image.lock()
	tmp_image.lock()
	for x in range(size.x):
		for y in range(size.y):
			if clockwise:
				tmp_image.set_pixel(size.y-(y+1),x, image.get_pixel(x,y))				
			else:
				tmp_image.set_pixel(y,size.x-(x+1), image.get_pixel(x,y))
	image.unlock()
	tmp_image.unlock()
	return tmp_image
