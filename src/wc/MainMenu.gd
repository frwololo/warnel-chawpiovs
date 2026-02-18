# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $CenterContainer/VBox/VButtons
onready var exit_button := $CenterContainer/VBox/VButtons/Exit
onready var v_folder_label := get_node("%FolderLabel")
onready var main_title := $CenterContainer/VBox/Label
onready var texture_rect = get_node("%TextureRect")

var http_request: HTTPRequest = null
var _current_destination = ""
var _current_url = ""
var _current_card_key = ""
var _current_percent = 0.0
var _loading_text_prefix =""

enum LOAD_STATUS {
	NOT_STARTED,
	IN_PROGRESS,
	COMPLETE
}

var _load_status = LOAD_STATUS.NOT_STARTED
var _loading_error = false
var _network_error = ""

signal all_downloads_completed()
signal one_download_completed()
signal images_download_completed()
signal sets_download_completed()
signal release_check_completed()

var _next_scene = ""
var _next_scene_counter = 0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	gameData.disconnect_from_network()	
	create_default_folders()
	#hide all buttons while we load, but keep the exit button
	_hide_buttons()	
	exit_button.visible = true
	exit_button.grab_focus()
	
	init_button_signals(v_buttons)
	# warning-ignore:return_value_discarded
	resize()
	_loading_text_prefix = "Loading Card Definitions - "
	v_folder_label.text = _loading_text_prefix
	main_title.text = "LOADING..."
	get_node("%VersionLabel").text = "v. " + CFConst.VERSION
		
	self.connect("all_downloads_completed", self, "_all_downloads_completed")
	self.connect("one_download_completed", self, "_one_download_completed")
	self.connect("images_download_completed", self, "_images_download_completed")
	self.connect("sets_download_completed", self, "_sets_download_completed")	
	cfc.connect("json_parse_error", self, "loading_error")	

	_load_status = LOAD_STATUS.NOT_STARTED
	if cfc.all_loaded:
		_load_status = LOAD_STATUS.COMPLETE
		_all_downloads_completed()		

func init_button_signals(node):
	if node.has_signal('pressed'):			
		node.connect('pressed', self, 'on_button_pressed', [node.name])
		node.connect('mouse_entered', node, 'grab_focus')		

	for child in node.get_children():
		init_button_signals(child)

func loading_error(msg):
	v_folder_label.text = "ERROR: " + msg
	main_title.text = "SCRIPT ERROR :("
	_loading_error  = true

func network_error(msg):
	v_folder_label.text = "NETWORK ERROR: " + msg
	_network_error = msg +"(" + _current_url + ")"
	#push_error(msg)

func display_folder_info():
	if _network_error:
		v_folder_label.add_color_override("font_color", Color8(255, 0,0))
		v_folder_label.text = "There was a network error while downloading game resources. Gameplay might be impacted.\n" +  _network_error
		return
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")

func _set_download_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		network_error("Set couldn't be downloaded.")
	else:
		var content = body.get_string_from_utf8()

		var json_result:JSONParseResult = JSON.parse(content)
		if (json_result.error != OK):
			network_error("Set couldn't be downloaded.")
		else:
			var file = File.new()
			var filename = _current_destination
			var to_print = JSON.print(json_result.result, "\t")
			file.open(filename, File.WRITE)
			file.store_string(to_print)
			file.close()  		
	
	emit_signal("one_download_completed")

func _img_download_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		network_error("Image couldn't be downloaded")

	else:
		var PNG_HEADER = [137,80,78,71,13,10,26,10]
		var image = Image.new()
		var formats = ["png", "jpg"]
		
		#guessing the format of the image based on header, can't trust the filename
		for i in range (PNG_HEADER.size()):
			if body[i] != PNG_HEADER[i]:
				formats = ["jpg", "png"]
				break
		
		var loaded_ok = FAILED
		var i = 0
		while loaded_ok!=OK and i < formats.size():
			var format = formats[i]
			match format:
				"png":
					loaded_ok = image.load_png_from_buffer(body)
				"jpg":
					loaded_ok = image.load_jpg_from_buffer(body)
			i+=1
			
		if loaded_ok != OK:
			network_error("Couldn't load the image - " + _current_url)
		else:
			var tmp_filename = "user://Sets/tmp_images/tmp.png"
			image.save_png(tmp_filename)
			mask_image(image, _current_destination, _current_card_key)


	emit_signal("one_download_completed")

func mask_image(image:Image, destination, card_key):
	if not destination:
		var _error = 1
		return
	var mask_filename = "res://assets/utils/wc_card_mask.png"	
	var mask_tex = load(mask_filename)
	var mask_image = mask_tex.get_data()	
	
	#var mask_image = Image.new()
	#mask_image.load(mask_filename)
	var transparent_filename = "res://assets/utils/wc_transparent.png"	
	var transparent_tex = load(transparent_filename)
	var transparent_image = transparent_tex.get_data()		
	#var transparent_image = Image.new()
	#transparent_image.load(transparent_filename)
	
	var card_data = cfc.card_definitions[card_key]
	if card_data and card_data.get("_horizontal", false):
		#needs rotation
		image = WCUtils.rotate_90(image, false)
		
	image.convert(transparent_image.get_format())
	if image.get_size() != transparent_image.get_size():
		var size = transparent_image.get_size()
		image.resize(size.x, size.y)
	var rect = image.get_used_rect()
	
	#image.blit_rect(transparent_image, rect,Vector2(0,0))	
	image.blit_rect_mask(transparent_image,mask_image, rect,Vector2(0,0))	
	image.fix_alpha_edges()
	image.save_png(destination)	

func download_database():	
	var database = cfc.game_settings.get("database", {})
	if typeof(database) != TYPE_DICTIONARY:
		var _error = 1
		#TODO error
		return
		
	for set in database.keys():
		yield(get_tree(), "idle_frame")	
		var url = database[set]
		var filename = "Sets/" + CFConst.CARD_SET_NAME_PREPEND  + set + ".json"		
		if WCUtils.file_exists(filename):
			continue
		if !url:
			continue
		if !http_request:
			http_request = HTTPRequest.new()
			add_child(http_request)	
			http_request.connect("request_completed", self, "_set_download_completed")

			
		# Perform the HTTP request. should return a json file
		self._current_destination = "user://" + filename
		self._current_url = url
		var error = http_request.request(url)
		if error != OK:
			network_error("An error occurred in the HTTP request.")
			continue
		yield(self, "one_download_completed")
	if http_request:
		remove_child(http_request)
		http_request.queue_free()
	emit_signal ("sets_download_completed")			

func _images_download_completed():	
	emit_signal("all_downloads_completed")

func _recursive_visible_buttons(node, value = true):
	if node.has_signal('pressed'):			
		node.visible = value	

	for child in node.get_children():
		_recursive_visible_buttons(child, value)

func _hide_buttons():
	#activate the interface buttons after download is finished
	_recursive_visible_buttons(v_buttons, false)
	
func _show_buttons():
	#activate the interface buttons after download is finished
	_recursive_visible_buttons(v_buttons)

	cfc.default_button_focus(v_buttons)
	
func _all_downloads_completed():
	if (_loading_error):
		return
			
	_show_buttons()
	display_folder_info()

	main_title.text = "WARNEL CHAWPIOVS"
	main_title.visible = false

#	texture_rect.rect_size = Vector2(50,50)
#	texture_rect.rect_scale = Vector2(0.5,0.5)
#	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.visible = true
#	texture_rect.get_parent().rect_min_size = texture_rect.rect_size * texture_rect.rect_scale
#	texture_rect.get_parent().rect_size = texture_rect.rect_size * texture_rect.rect_scale
	cfc.all_loaded = true
	gameData.play_music("menu")
	check_for_new_release()

func check_for_new_release():
	http_request = HTTPRequest.new()
	add_child(http_request)	
	http_request.connect("request_completed", self, "_version_check_completed")	
	var url = CFConst.VERSION_CHECK_URL
	var error = http_request.request(url)
	
	if error != OK:
		network_error("Couldn't check for latest release")
		return
		
	yield(get_tree(), "idle_frame")
	yield(self, "release_check_completed")
	remove_child(http_request)
	http_request.queue_free()	

func _version_check_completed(result, response_code, headers, body):
	var latest_release_data = {}
	if result != HTTPRequest.RESULT_SUCCESS:
		network_error("Couldn't check for version update")

	else:
		var content = body.get_string_from_utf8()

		var json_result:JSONParseResult = JSON.parse(content)
		if (json_result.error != OK):
			network_error("Couldn't check for version update")
		else:
			var json_data = json_result.result
			if typeof(json_data) == TYPE_ARRAY and json_data:
				latest_release_data = json_data[0]
			else:
				network_error("Couldn't check for version update")
	
	if latest_release_data:
		var version = latest_release_data.get("tag_name", "")
		var is_newer = cfc.v1_newer_than_v2(version, CFConst.VERSION)
		if is_newer:
			message_newer_version_available(version)

	emit_signal("release_check_completed")	

func message_newer_version_available(version):
	v_folder_label.bbcode_text = "[color=green]New Version " + version + " available. [/color][color=aqua][url=" + CFConst.GITHUB_URL + "]Download Page[/url][/color]"


func create_default_folders():
	var dir = Directory.new()
	for folder in ["Sets", "Decks", "Saves", "Music", "Sfx"]:
		dir.make_dir_recursive("user://" + folder + "/")
	
	
func create_img_folders(card_data):
	var set = card_data["_set"]
	var dir = Directory.new()
	dir.make_dir_recursive("user://Sets/tmp_images")
	dir.make_dir_recursive("user://Sets/images/" + set)

func start_images_dl():
	http_request = HTTPRequest.new()
	add_child(http_request)	
	http_request.connect("request_completed", self, "_img_download_completed")
	_loading_text_prefix = "Downloading Images - "
	
	var total_images = cfc.card_definitions.size()
	var i = 0
	
	for card_key in cfc.card_definitions.keys():
		i+=1
		var card = cfc.card_definitions[card_key]
		_current_percent = i*100/total_images
		var card_id = card["_code"]
		var img_filename = cfc.get_img_filename(card_id)
		if WCUtils.file_exists(img_filename):
			continue
		if cfc.is_image_download_failed(card_id):
			continue
		var url = cfc.get_image_dl_url(card_id)
		if !url:
			continue
		#we're good to go. create folders as needed
		create_img_folders(card)	
		# Perform the HTTP request. should return a png image
		self._current_destination = img_filename
		self._current_url = url
		self._current_card_key = card_key
		var error = http_request.request(url)
		if error != OK:
			network_error("An error occurred in the HTTP request for card" + card_id)
			continue
		yield(get_tree(), "idle_frame")
		yield(self, "one_download_completed")
	remove_child(http_request)
	http_request.queue_free()
	emit_signal ("images_download_completed")	
	
func _sets_download_completed():
	#database download is complete, we load all sets then start the images
	cfc.load_cards_database()
	if cfc.scripts_loading:
		yield(cfc,"scripts_loaded")

	if (_loading_error):
		return		
	start_images_dl()

func _process(delta):
#	var target_size = get_viewport().size
#	if target_size.x > 1800:
#		texture_rect.rect_min_size = Vector2(1616, 604)
#		texture_rect.rect_size = texture_rect.rect_min_size

	if (_loading_error):
		return
	
	if _load_status == LOAD_STATUS.NOT_STARTED:	
		_load_status = LOAD_STATUS.IN_PROGRESS
		if cfc.game_settings.get("load_cards_online", true):
			download_database()
		else:
			_load_status = LOAD_STATUS.COMPLETE
			_all_downloads_completed()

	if cfc._cards_loaded <  cfc._total_cards :
		#warning-ignore:INTEGER_DIVISION
		var percent_loaded:int = (100*cfc._cards_loaded) / cfc._total_cards
		v_folder_label.text = _loading_text_prefix +  str(percent_loaded) + "%"
	
	if 	_next_scene_counter:
		_next_scene_counter-=1
		if !_next_scene_counter:
			var new_scene = _next_scene
			_next_scene = ""
			get_tree().call_deferred("change_scene", new_scene)	
	
func _one_download_completed():
	if (_loading_error):
		return
			
	v_folder_label.text = _loading_text_prefix +  str(_current_percent) + "% - " + _current_url

func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"SinglePlayer":
			# warning-ignore:return_value_discarded
			next_scene(CFConst.PATH_CUSTOM + 'lobby/TeamSelection.tscn')
		"Multiplayer":		
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'menus/MultiplayerMenu1.tscn')
		"Credits":
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'menus/Credits.tscn')
		"Options":
			$OptionsMenu.show_me($CenterContainer)

		"Exit":
			get_tree().quit()

func next_scene(scene_path):
	get_node("%LoadingPanel").visible = true
	_next_scene_counter = 2
	_next_scene = scene_path

func resize():
	var stretch_mode = cfc.get_screen_stretch_mode()
	if stretch_mode != SceneTree.STRETCH_MODE_VIEWPORT:
		return	
	var target_size = get_viewport().size
	if target_size.x > CFConst.LARGE_SCREEN_WIDTH:
		#loading a higher res title screen
		texture_rect.texture = load("res://assets/icons/title.png")
		texture_rect.rect_min_size = Vector2(1616, 604)
		texture_rect.rect_size = texture_rect.rect_min_size

	v_folder_label.rect_min_size.x = target_size.x - 200
	self.margin_right = target_size.x
	self.margin_bottom = target_size.y
	self.rect_size = target_size
	$CenterContainer.rect_size = target_size
	$CenterContainer/LoadingPanel/ColorRect.rect_min_size = target_size
#	$CenterContainer/LoadingPanel/Panel.rect_min_size = target_size
	$CenterContainer/LoadingPanel/ColorRect.rect_size = target_size
#	$CenterContainer/LoadingPanel/Panel.rect_size = target_size	
	$CenterContainer/LoadingPanel.rect_min_size = target_size
	$CenterContainer/LoadingPanel.rect_size = target_size


	


func _on_FolderLabel_meta_clicked(meta):
	# `meta` is of Variant type, so convert it to a String to avoid script errors at run-time.
	OS.shell_open(str(meta))
