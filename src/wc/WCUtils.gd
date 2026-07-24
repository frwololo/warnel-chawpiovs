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
			return {}
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
		if !bytes:
			return null
			
		var PNG_HEADER = [137,80,78,71,13,10,26,10]
		var WEBP_HEADER = [82,73,70,70]
		var JPEG_HEADER = [255,216,255]
		
		var format = "jpg"
		
		#guessing the format of the image based on header, can't trust the filename
		if bytes[0] == PNG_HEADER[0]:
				format = "png"
		elif bytes[0] == WEBP_HEADER[0]:
				format = "webp"
		elif bytes[0] == JPEG_HEADER[0]:
				format = "jpg"
		else:
			return null


		var loaded_ok = FAILED
		match format:
			"png":
				loaded_ok = img.load_png_from_buffer(bytes)
			"jpg":
				loaded_ok = img.load_jpg_from_buffer(bytes)
			"webp":
				loaded_ok = img.load_webp_from_buffer(bytes)					
		
		if loaded_ok != OK:
			return null	
	return img	

static func load_audio(file) -> AudioStream:
	var img = Image.new()
	#attempt from local file first, resource after
	var audio_file = File.new()
	if audio_file.open(file, File.READ):
		if ResourceLoader.exists(file):
			var audio = ResourceLoader.load(file)
			return audio
		return null
		
	var bytes = audio_file.get_buffer(audio_file.get_len())
	audio_file.close()
	
	var result:AudioStreamMP3 = AudioStreamMP3.new()
	result.data = bytes	
	return result	


static func ordered_hash(dict:Dictionary):
	var sorted_dictionary = deep_dict_sort(dict)
	return sorted_dictionary.hash()

#script can either be a script object (in which case its owner will be computed)
#or a dict script definition (in which case the owner object also needs to be passed as parameter)			
static func script_signature(script, owner = null):
	var definition := {}
	if typeof(script) == TYPE_DICTIONARY:
		definition = {
			"owner": owner,
			"definition": script
		}		
	else:			
		definition = {
			"owner": script.owner,
			"definition": script.script_definition
		}
	var signature = ordered_hash(definition)
	return signature


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

static func merge_variant(data1, data2, deep_merge: bool = false):
	if typeof(data1)!= typeof(data2):
		var _error = 1
		return null
	match typeof(data1):
		TYPE_DICTIONARY:
			return merge_dict(data1, data2, deep_merge)
		TYPE_ARRAY:
			return merge_array(data1, data2, deep_merge)
	
	var _error = 1
	return data1
	

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
	if a.get("stage", 0) < b.get("stage", 0):
		return true
	return false


static func sort_cards(a, b):
	return (a.get("card") < b.get("card"))

	
static func to_grayscale(_texture : Texture) -> Texture:
	var texture = _texture
	if _texture as AtlasTexture:
		texture = _texture.get_atlas()	
	else:
		pass
	if !texture:
		return null
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

#stupid hardcoded exceptions
const _never_replace = {
	"name": "discard",
	"type_code": "villain",
	"display_section": "response"
}	
static func search_and_replace_multi_no_cache (script_definition, replacements:Dictionary, exact_match: bool = false) -> Dictionary:
	var result = null
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				var value = script_definition[key]
				if _never_replace.get(key, "") == str(value):
					result[key] = value
					continue
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

static func get_md5(filepath):
	var file: File = File.new()
	var is_absolute = filepath.begins_with("res://") or filepath.begins_with("user://")
	var md5 = ""
	if is_absolute:
		md5 = file.get_md5(filepath)
	else:
		for path in ["user://", "res://"]:
			md5 = file.get_md5(path + filepath)
			if md5:
				break
	file.close()
	return md5

static func search_and_replace (script_definition, from: String, to, exact_match: bool = false) -> Dictionary:
	var result = null
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				var value = script_definition[key]
				if _never_replace.get(key, "") == str(value):
					result[key] = value
					continue				
				result[key] = search_and_replace(value,from, to, exact_match)

				#do the key too	
				if typeof(key) == TYPE_STRING:
					if ((!exact_match) or (key == from)):
						var new_string = key.replace(from, to)
						if new_string != key:	
							result[new_string] = result[key]
							result.erase(key)

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
				result = to
			else:
				result = script_definition
		_:
			result = script_definition
	return result;

static func has_interrupt_or_response (script_definition, trigger: String) -> bool:
	var match_list = ["interrupt_" + trigger, "response_" + trigger]
	match typeof(script_definition):
		TYPE_DICTIONARY:
			for key in script_definition.keys():
				if key in match_list:
					return true
				var value = script_definition[key]
				if key in ["interrupt", "response"]:
					if value.has("event_name"):
						var event_name = value["event_name"]
						match typeof(event_name):
							TYPE_STRING:
								if event_name == trigger:
									return true
							TYPE_ARRAY:
								if trigger in event_name:
									return true
							_:
								pass
						
				if has_interrupt_or_response(value, trigger):
					return true

		TYPE_ARRAY:
			for x in script_definition:
				if has_interrupt_or_response(x, trigger):
					return true

	return false

#TODO call find_string_in_variant instead
static func is_string_in_variant (script_definition, needle: String) -> bool:
	match typeof(script_definition):
		TYPE_DICTIONARY:
			for key in script_definition.keys():
				var value = script_definition[key]
				if is_string_in_variant(value, needle):
					return true

				#do the key too	
				if ((typeof(key) == TYPE_STRING) and (needle in key)):
					return true

		TYPE_ARRAY:
			for x in script_definition:
				if is_string_in_variant(x, needle):
					return true

		TYPE_STRING:
			return (needle in script_definition)
	return false

static func find_string_in_variant (script_definition, needle: String, result_path:Array = []) -> Array:
	match typeof(script_definition):
		TYPE_DICTIONARY:
			for key in script_definition.keys():
				var value = script_definition[key]
				var result = find_string_in_variant(value, needle, result_path)
				if result:
					result = [key] + result
					return result

				#do the key too	
				if ((typeof(key) == TYPE_STRING) and (needle in key)):
					return result_path

		TYPE_ARRAY:
			for x in script_definition:
				var result =  find_string_in_variant(x, needle, result_path)
				if result:
					return result

		TYPE_STRING:
			if (needle in script_definition):
				return [script_definition]
	return result_path

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
	
static func replace_text_macro (replacements, macro_value):
	if typeof(replacements) != TYPE_DICTIONARY:
		print_debug("error in macro replacements: " + str(replacements))
		return {}
		
	var text = to_json(macro_value)
	for key in replacements.keys():
		var value = replacements[key]
		var to_replace = key
		if typeof(value) in [TYPE_REAL,TYPE_INT,TYPE_BOOL, TYPE_ARRAY, TYPE_DICTIONARY]:
			to_replace = "\"" + key + "\""
			value = JSON.print(value).to_lower()
		text = text.replace(to_replace, str(value))
	
	var result = parse_json(text)
	if !result:
		var _error = 1
	return result

static func replace_one_macro(script_definition, macro_key, macro_value):
	var result = null
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				if (key == macro_key):
					var replacements = script_definition[key]
					var dict_or_array = replace_text_macro(replacements, macro_value)
					match typeof(dict_or_array):
						TYPE_DICTIONARY:
							var dict = dict_or_array
							for replaced_key in dict.keys():
								if result.has(replaced_key):
									result[replaced_key] = merge_variant(result[replaced_key], dict[replaced_key], true)
									print_debug("macro might overwrite other data: " + key + JSON.print(result))
								else:
									result[replaced_key] = dict[replaced_key]
								
								if typeof(result[replaced_key]) == TYPE_DICTIONARY:
									result[replaced_key]["macro_name"] = macro_key
								else:
									result["macro_name"] = macro_key
						_: #array
							result = dict_or_array
				else:
					var replaced = replace_one_macro(script_definition[key], macro_key, macro_value)
					if result.has(key):
						result[key] = merge_variant(result[key], replaced, true)
						print_debug("macro might overwrite other data: " + key + JSON.print(result))
					else:	
						result[key] = replaced
		TYPE_ARRAY:	
			result = []
			for value in script_definition:
				result.append(replace_one_macro(value, macro_key, macro_value))
		_:
			result = script_definition
	return result;	

static func replace_macros(json_card_data, local_macro_data, json_macro_data):
	var result = json_card_data
	var macro_data = merge_dict(json_macro_data, local_macro_data)
	for macro_key in macro_data.keys():
		result = replace_one_macro(result, macro_key, macro_data[macro_key])
	return result	

# Recursively deletes a directory and all its contents
static func delete_dir_recursive(path: String) -> bool:
	var dir := Directory.new()
	
	# Try to open the directory
	if dir.open(path) != OK:
		push_error("Failed to open directory: %s" % path)
		return false
	
	dir.list_dir_begin(true, false)
	var file_name = dir.get_next()
	
	while file_name != "":
		var file_path = path.plus_file(file_name)
		
		if dir.current_is_dir():
			# Recursively delete subdirectory
			if not delete_dir_recursive(file_path):
				dir.list_dir_end()
				return false
		else:
			# Delete file
			var err = dir.remove(file_path)
			if err != OK:
				push_error("Failed to delete file: %s" % file_path)
				dir.list_dir_end()
				return false
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# Remove the now-empty directory itself
	var err = dir.remove(path)
	if err != OK:
		push_error("Failed to remove directory: %s" % path)
		return false
	
	return true


#deletes all user additional resources
const delete_pck_mark = "user://.delete_all_pck"
static func mark_all_pck_for_deletion():
	var file = File.new()
	file.open(delete_pck_mark, File.WRITE)
	file.store_string("1")
	file.close()
	
static func check_delete_all_pck():	
	var file = File.new()
	
	if !file.file_exists(delete_pck_mark):
		return
	
	var dir = Directory.new()

	var database = cfc.game_settings.get("database", {})
	if typeof(database) != TYPE_DICTIONARY:
		var _error = 1
		#TODO error
		return

	#for each set, try to load package files for it
	#loading data from a file overrides the previous one, so a package file
	#has higher priority (its content will override previously loaded ones if they exist)
	#lower priority <<< higher priority
	#res pck <<< res zip <<< user pck <<< user zip
	#user files have priority to let users put mods in their user folder
	#zip files have priority because I have found they have better compatibility
	# (pck files will refuse to load if wrong godot version number for example)
	# see https://www.reddit.com/r/godot/comments/11pfoon/comment/jbxyp2x/
	for set in database.keys() + CFConst.ALLOWED_PCK_NAMES:
		for folder in ["user://"]:		
			for format in [".pck", ".zip"]:
				var filename = folder + set + format
				if file.file_exists(filename):
					var result = dir.remove(filename)
	
	dir.remove(delete_pck_mark)
	return

static func large_card_preview_offset(large_picture, container, preview_card_size):
	var mouse_pos = container.get_tree().current_scene.get_global_mouse_position()
	if gamepadHandler.is_mouse_input():		
		large_picture.rect_position = container.get_tree().current_scene.get_global_mouse_position() + Vector2(20, 20)
	else:
		var focused = container.get_focus_owner()
		if focused:
			mouse_pos = focused.get_global_position() + focused.rect_size/2
			large_picture.rect_position = mouse_pos + Vector2(20, 20)
	large_picture.rect_size = preview_card_size
#	large_picture.rect_scale = cfc.screen_scale
#	large_picture.rect_rotation = _preview_rotation
	
	var correction_offset = preview_card_size
	var top_left = large_picture.rect_position
	var bottom_left = large_picture.rect_position + Vector2(0, large_picture.rect_size.y)
	var top_right = large_picture.rect_position+ Vector2(large_picture.rect_size.x, 0)
	var bottom_right = large_picture.rect_position  + large_picture.rect_size
	
	if large_picture.rect_rotation == 90:
		correction_offset = Vector2(0, correction_offset.x)
		large_picture.rect_position.x += large_picture.rect_size.y	
		top_right = large_picture.rect_position
		top_left = large_picture.rect_position + Vector2(-large_picture.rect_size.y, 0)
		bottom_left = top_left + Vector2(0,large_picture.rect_size.x)
		bottom_right = top_right + Vector2(0,large_picture.rect_size.x)
		var _tmp = bottom_right
	
	#check for out of bounds preview and correct accordingly
	var screen_size = container.get_viewport().size/cfc.screen_scale
	var out_of_bounds = bottom_right
	if out_of_bounds.x > screen_size.x:
		large_picture.rect_position.x = mouse_pos.x - 50 - correction_offset.x

	if out_of_bounds.y > screen_size.y:
		large_picture.rect_position.y = screen_size.y - 50 - correction_offset.y
