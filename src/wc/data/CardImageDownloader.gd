class_name CardImageDownloader
extends Node

const servers := [
	{
		"url": "https://marvelcdb.com",
		"is_up": true,
		"health_check": "not_started",
		"health_check_url": ""		
	},
	{
		"url": "https://mc4db.merlindumesnil.net",
		"is_up": true,
		"health_check": "not_started",	
		"health_check_url": "",		
		"modifications": {
			"extension": ".webp",
			"replace_path": {
				"from": "/bundles/cards/",
				"to": "/bundles/cards/EN/[box_name]/"
			}
		}
	},	
]

#[
#{
#	"url": ,
#	"destination":
#}
#]
var cards_to_download = []
var priority_cards_to_download = []
var current_file = {}

var dl_ok = 0
var dl_errors = 0
var http_request: HTTPRequest = null

signal one_server_check_completed()
signal download_complete(card_id)

func _ready():
	var dir:Directory = Directory.new()
	dir.make_dir_recursive("user://Sets/tmp_images")
	fileDownloader.connect("file_downloaded", self, "_file_downloaded")
	fileDownloader.connect("download_error", self, "_download_error")

func get_stats():
	var stats = {
		"downloaded_ok" : dl_ok,
		"download_errors" : dl_errors,
		"remaining": cards_to_download.size(),
		"current_url": current_file.get("url", "")
	}
	return stats

func _process(_delta:float):
	process_next_file()

func process_next_file():
	if current_file: #already processing
		return	
	
	if priority_cards_to_download:
		cards_to_download = cards_to_download + priority_cards_to_download
		priority_cards_to_download = []
	
	if !cards_to_download:
		return

	if !is_all_servers_checked():
		return
		
	current_file = cards_to_download.pop_back()
	var dest_file = current_file.get("destination", "")
	if WCUtils.file_exists(dest_file):
		current_file = {}
		return
	
	process_current_file()

func select_server():
	for s in servers:
		if s.get("is_up"):
			return s
	return {}

func process_current_file():

	var path:String = current_file.get("url")


	if path.begins_with("http"):	
		for s in servers:
			if path.begins_with(s["url"]):
				if !s.get("is_up"):
					path = path.replace(s["url"], "")
				break
	
	#if path is relative, 
	#target the appropriate server and attempt download
	if !path.begins_with("http"):
		var s = select_server()
		if !s:
			var _error = 1
			return
		var base_url = s.get("url","")
		if !base_url:
			var _error = 1
			return
		

		
		var modifications = s.get("modifications", {})
		var extension = modifications.get("extension", "")
		if extension:
			var split_path = path.split(".")
			path = split_path[0] + extension	
		
		var replace_path = modifications.get("replace_path", {})
		if replace_path:
			var from = replace_path["from"]
			var to = replace_path["to"]
			to = path_variable_process(to, current_file)
			path = path.replace(from, to)
		path = base_url + path
	
	current_file["path"] = path			
	fileDownloader.start_download([path])

func path_variable_process(to, current_file):
	var card_id = current_file["card_id"]
	var box_name = "core"
	var card_data = cfc.card_definitions[card_id]
	if card_data and card_data.get("_set", ""): 
		box_name = card_data["_set"]
	
	var replacements = {
		"box_name": box_name
	}
	
	for key in replacements:
		var to_seek = "[" + key + "]"
		var replacement = replacements[key]
		to = to.replace(to_seek, replacement)
	
	return to
	
func retry_or_cancel_current_file():
	var path:String = current_file.get("path")
	
	var found = false
	var previous_base = ""
	var server = {}
	for s in servers:
		if !s.get("is_up"):
			continue		
		if found:
			server = s
			break
		var base_url = s.get("url")
		if path.begins_with(base_url):
			previous_base = base_url
			found = true
	
	if !server:
		current_file = {}
		return

	var url = current_file["path"]
	url = url.replace(previous_base, server["url"])	

	var modifications = server.get("modifications", {})
	var extension = modifications.get("extension", "")
	if extension:
		var split_path = url.split(".")
		url = split_path[0] + extension	
	
	var to_add = {		
		"url": url,
		"destination": current_file["destination"],
		"card_id": current_file["card_id"]				
	}
	
	cards_to_download.append(to_add)	

func _download_error(url, _filename):
	if url != current_file.get("path", ""):
		var _error = 1
		return

	dl_errors += 1
	retry_or_cancel_current_file()

func _file_downloaded(url, filename):
	if url != current_file.get("path", ""):
		var _error = 1
		return
	
	var destination = current_file.get("destination")
	if destination:
		var result = _img_download_completed(url, filename)
		if result:
			dl_ok += 1
	else:
		destination = filename
	emit_signal("download_complete",  current_file.get("card_id"))
	current_file = {}
	process_next_file()


func add_card(card_id, priority = false):
	var img_filename = cfc.get_img_filename(card_id)
	if WCUtils.file_exists(img_filename):
		return
	if cfc.is_image_download_failed(card_id):
		return
	var url = cfc.get_image_dl_url(card_id)
	if !url:
		return
	
	#we're good to go. create folders as needed
	create_img_folders(card_id)	

	#add the card to the download list
	var to_add = {
		"url": url,
		"destination": img_filename,
		"card_id": card_id,
	}
	if priority:
		priority_cards_to_download.append(to_add)
	else:
		cards_to_download.append(to_add)
	
	check_servers_health()

func is_all_servers_checked():
	for s in servers:
		if s.get("health_check") != "complete":
			return false
	return true	
	
#ping servers to see if they're ok for download
func check_servers_health():
	if is_all_servers_checked():
		return
	for s in servers:
		if s.get("health_check") == "not_started":
			s["health_check"] = "in_progress"
			http_request = HTTPRequest.new()
			add_child(http_request)	
			http_request.connect("request_completed", self, "_health_check_complete")
			var url = s["url"] + s["health_check_url"]
			var error = http_request.request(url)
			if error != OK:
				s["health_check"] = "complete"
				s["is_up"] = false
				continue
			else:
				yield(self, "one_server_check_completed")
			if http_request:
				remove_child(http_request)
				http_request.queue_free()			

func _health_check_complete(result, response_code, headers, body):
	var current_server = {}
	for s in servers:
		if s.get("health_check") == "in_progress":
			current_server = s
			break
	if !current_server:
		var _error = 1
		return
	current_server["health_check"] = "complete"
	if result == HTTPRequest.RESULT_SUCCESS:
		current_server["is_up"] = true
	else:
		current_server["is_up"] = false

	emit_signal("one_server_check_completed")			
			
				
func create_img_folders(card_id):
	var card_data = cfc.card_definitions[card_id]
	if card_data and card_data.get("_set", ""):
		var dir = Directory.new()		
		dir.make_dir_recursive("user://Sets/images/" + card_data["_set"])	
	
	
func _img_download_completed(url, filename):

	var dir:Directory = Directory.new()
	var destination = current_file.get("destination", "")
	var card_key = current_file.get("card_id", "")
	
	if !destination or !card_key:
		var _error = 1
		_download_error(url, filename)
		return false

	var image = WCUtils.load_img(filename)
	if !image:
		var _error = 1
		_download_error(url, filename)
		return false

	mask_image(image, destination, card_key)
	var error = dir.remove(filename)
	if error != OK:
		var _tmp = 1
	
	return true


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
	
#load all images that are still missing from local folder	
func load_pending_images():
	for card_key in cfc.card_definitions.keys():	
		add_card(card_key)
	var _tmp =1
