class_name WCUtils
extends "res://src/core/CFUtils.gd"


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

#Read json file into dictionary
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
		

#load Texture from jpeg/png file		
static func load_img(file):
	var img_file = File.new()
	if img_file.open(file, File.READ):
		return null
	var bytes = img_file.get_buffer(img_file.get_len())
	var img = Image.new()
	
	var extension = file.get_extension().to_lower()
	var error_code = 0
	if extension == "png":
		error_code = img.load_png_from_buffer(bytes)
	else:
		error_code = img.load_jpg_from_buffer(bytes)
	if error_code:
		img_file.close()
		return null
	var imgtex = ImageTexture.new()
	imgtex.create_from_image(img)
	img_file.close()
	return imgtex		
