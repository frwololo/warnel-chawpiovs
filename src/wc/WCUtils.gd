class_name WCUtils
extends "res://src/core/CFUtils.gd"


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

#Read json file into dictionary (or array!)
static func read_json_file(file_path):
	var file = File.new()
	file.open(file_path, File.READ)
	var content_as_text = file.get_as_text()
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
		
static func merge_dict(dict_1: Dictionary, dict_2: Dictionary, deep_merge: bool = false) -> Dictionary:
	var new_dict = dict_1.duplicate(true)
	for key in dict_2:
		if key in new_dict:
			if deep_merge and dict_1[key] is Dictionary and dict_2[key] is Dictionary:
				new_dict[key] = merge_dict(dict_1[key], dict_2[key])
			elif deep_merge and dict_1[key] is Array and dict_2[key] is Array:
				new_dict[key] = merge_array(dict_1[key], dict_2[key])
			else:
				new_dict[key] = dict_2[key]
		else:
			new_dict[key] = dict_2[key]
	return new_dict


static func sort_stage(a, b):
	if a["stage"] < b["stage"]:
		return true
	return false
