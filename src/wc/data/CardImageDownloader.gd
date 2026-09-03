class_name CardImageDownloader
extends Node

const default_servers := {
	"marvelcdb": 
		{
			"url": "https://marvelcdb.com",
			"path": "/bundles/cards/[card_id].png",
			"prioritize_relative_image_src": true,		
		},	
	"cerebro":
		{
			"url": "https://cerebrodatastorage.blob.core.windows.net",
			"path": "/cerebro-cards/official/[card_id].jpg",
			"uppercase_card_id": true,
			"card_id_override": "printed_card_id",					
		},	
	"mc4db":	
		{
			"url": "https://mc4db.merlindumesnil.net",
			"fanmade_support": true,		
			"path": "/bundles/cards/EN/[box_name]/[card_id].webp"
		},	
}

#[
#{
#	"url": ,
#	"destination":,
#   "card_id"
#}
#]
var cards_to_download = []
var priority_cards_to_download = []
var current_file = {}

var already_tried_servers_per_card = {}

var dl_ok = 0
var dl_errors = 0
var last_error_msg := ""
var global_error_msg := ""
var servers:= {}
var tracked_urls = {}

var http_request: HTTPRequest = null

signal one_server_check_completed()
signal download_complete(card_id)

static func get_default_servers():
	return default_servers

func init_servers():
	if servers:
		return servers
		
	var result = cfc.get_setting("image_servers")
	if !result:
		result = default_servers
	
	servers = result.duplicate(true)
	for server_name in servers:
		var server = servers[server_name]
		server["is_up"] = true #assume server is up so we can start downloading
		server["health_check"] = "not_started"
		if !server.has("health_check_url"):
			server["health_check_url"] = ""
	return servers

func _ready():
	var dir:Directory = Directory.new()
	dir.make_dir_recursive("user://Sets/tmp_images")
	fileDownloader.connect("file_downloaded", self, "_file_downloaded")
	fileDownloader.connect("download_error", self, "_download_error")
	init_servers()

func get_stats():
	var stats = {
		"downloaded_ok" : dl_ok,
		"download_errors" : dl_errors,
		"remaining": cards_to_download.size(),
		"current_url": current_file.get("url", ""),
		"last_error_msg": last_error_msg,
		"high_priority_error_msg": global_error_msg
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

	if !at_least_one_server_up():
		return
		
	current_file = cards_to_download.pop_back()
	var dest_file = current_file.get("destination", "")
	if WCUtils.file_exists(dest_file):
		current_file = {}
		return
	
	process_current_file()


func process_current_file():
	var card_id = current_file.get("card_id","") 
	
	if !current_file.has("url"):
		current_file["url"] = get_next_image_dl_url(card_id)
	
	var url = current_file["url"]
	if !url:
		#error happened without even tring a download (couldn't find dl link), we flag it
		dl_errors += 1
		FileDownloader.LOG("could not compute a download url for card_id:" + card_id)	
		current_file = {}
		return
	
	tracked_urls[url] = true	
	fileDownloader.start_download([url])


func generate_dl_path(card_id, server_info):
	var box_name = "core"
	var card_data = cfc.card_definitions.get(card_id, {})
	if card_data and card_data.get("_set", ""): 
		box_name = card_data["_set"]
	
	var processed_card_id = card_id
	
	if card_data.get("fanmade", false):
		#because we modify fanmade ids to avoid conflicts with official content,
		# we need to un-modify them here for the original server to find them
		processed_card_id = processed_card_id.replace(box_name + "_", "")

	# ffg have reversed A/B between Hero and Alter-ego on some cards. 
	# Some Databases choose to follow FFG, others such as marvel cdb swapped it
	# Since we based our initial work on MarvelCDB, we have to "force" use the printed id
	# in some cases. This is done when the image server defines a specific field (e.g. printed_card_id)
	# to use in lieu of he card_id	
	var card_id_override = server_info.get("card_id_override", "")
	if card_id_override and card_data.get(card_id_override, ""):	
		processed_card_id = card_data[card_id_override]

	if server_info.get("uppercase_card_id", false):
		processed_card_id = processed_card_id.to_upper()
		
	var replacements = {
		"box_name": box_name,
		"card_id": processed_card_id
	}
	
	var to = server_info["path"]
	for key in replacements:
		var to_seek = "[" + key + "]"
		var replacement = replacements[key]
		to = to.replace(to_seek, replacement)
	
	return to
	
func retry_or_cancel_current_file():
	var card_id = current_file.get("card_id", "")	
	var url = get_next_image_dl_url(card_id)
	if !url:
		FileDownloader.LOG("retry_or_cancel_current_file: final failure for " + card_id + " " + current_file.get("url"))					
		return

	var to_add = {		
		"url": url,
		"destination": current_file["destination"],
		"card_id": card_id				
	}
	
	cards_to_download.append(to_add)

func _download_error(url, filename):
	
	if !tracked_urls.get(url, false):
		#this failure doesn't concern us
		return
		
	if url != current_file.get("url", ""):
		FileDownloader.LOG("_download_error triggered but url unexpected:" + url + "(filename:" + filename + ") - expected: " + current_file.get("url", ""))	
		var _error = 1
		return

	dl_errors += 1
	FileDownloader.LOG("_download_error triggered for url:" + url + "(filename:" + filename + ") - doing retry or cancel")	
	retry_or_cancel_current_file()
	
	#cancel failed download
	current_file = {}		

func _file_downloaded(url, filename):
	if !tracked_urls.get(url, false):
		#this download doesn't concern us
		return
			
	var result = true
	if url != current_file.get("url", ""):
		FileDownloader.LOG("_file_downloaded triggered but url unexpected:" + url + "(filename:" + filename + ") - expected: " + current_file.get("url", ""))			
		var _error = 1
		dl_errors += 1
		return
	
	var destination = current_file.get("destination")
	if destination:
		result = _img_download_completed(url, filename)
		if result:
			dl_ok += 1
	else:
		destination = filename
		#TODO error here?

	if result:
		tracked_urls.erase(url)
		emit_signal("download_complete",  current_file.get("card_id"))

	current_file = {}
	process_next_file()

func mark_server_as_tried(card_id, server):
	if !already_tried_servers_per_card.has(card_id):
		already_tried_servers_per_card[card_id] = {}
		
	already_tried_servers_per_card[card_id][server] = true	
	

func get_next_image_dl_url(card_id):	
	var url = ""

	if !already_tried_servers_per_card.has(card_id):
		already_tried_servers_per_card[card_id] = {}
		 
	for server in servers:
		if already_tried_servers_per_card[card_id].get(server, false):
			continue
		if !servers[server].get("is_up"):
			continue			
		url = _get_image_dl_url_for_server(card_id, server)
		mark_server_as_tried(card_id, server)	
		if url:
			break

	#if all download urls failed while we know we are online,
	#we mark this image as failed 
	if !url and at_least_one_server_up():
		fail_img_download(card_id)
	return url
		
func _get_image_dl_url_for_server(card_id, server):	
	var server_info = servers.get(server, {})
	if !server_info:
		return ""	
		
	var card_data = cfc.get_card_by_id(card_id)
	if !card_data:
		#card data missing can happen when referencing a "duplicate_of_code"
		#card which we don't support yet
		#in that case we try to craft the url using normal rules
		return server_info["url"] + generate_dl_path(card_id, server_info)
	

	
	#if this is a fanmade card, need a server that supports those
	if card_data.get("fanmade", false):
		if !server_info.get("fanmade_support", false):
			return ""

	var image_src = card_data.get("imagesrc", "")
	
	#hardcoded absolute url, we invalidate all servers and return this url
	if image_src.begins_with("http"): 
		for s in servers:
			mark_server_as_tried(card_id, s)		
		return image_src
		
	if !image_src:
		var duplicate_of = card_data.get("duplicate_of_code", "")
		if duplicate_of:
			return _get_image_dl_url_for_server(duplicate_of, server)
	

	if image_src and server_info.get("prioritize_relative_image_src", false):
		# marvelcdb's image_src often overrides card_id, etc...
		# so we use it for that server		
		return server_info["url"] + image_src	


	#other servers will generally craft the url based on the card id,
	# this is the most "normal" use case
	return server_info["url"] + generate_dl_path(card_id, server_info)
			

#mark a download as failed to avoid constantly attempting it
var failed_files:= {}

func get_failed_files():
	if failed_files:
		return failed_files
	var filename = "user://failed_image_downloads.json"
	var _failed_files = WCUtils.read_json_file(filename)
	failed_files =  _failed_files if _failed_files else {}

	var last_check = failed_files.get("_last_check", 0)
	var current_time = Time.get_unix_time_from_system()
	var older_time = current_time - (3600 * 24 * 5)
	if !last_check or last_check < 	older_time:
		failed_files = {}
		failed_files["_last_check"] = current_time
	#return failed_files

func fail_img_download(card_id):
	var file = File.new()
	var filename = "user://failed_image_downloads.json"
	get_failed_files()
	failed_files[card_id] = true
	failed_files["_last_check"] = Time.get_unix_time_from_system()
	var to_print = to_json(failed_files)	
	file.open(filename, File.WRITE)
	file.store_string(to_print)
	file.close()  		

func is_image_download_failed(card_id):
	get_failed_files()
	return failed_files.get(card_id, false)


func add_card(card_id, priority = false):
	var img_filename = cfc.get_img_filename(card_id)
	if WCUtils.file_exists(img_filename):
		return
	if is_image_download_failed(card_id):
		return

	#we're good to go. create folders as needed
	create_img_folders(card_id)	

	#add the card to the download list
	var to_add = {
		"destination": img_filename,
		"card_id": card_id,
	}
	if priority:
		priority_cards_to_download.append(to_add)
	else:
		cards_to_download.append(to_add)
	
	check_servers_health()

func is_all_servers_checked():
	for server_name in servers:
		var s = servers[server_name]
		if s.get("health_check") != "complete":
			return false
	return true	

func at_least_one_server_up():
	for server_name in servers:
		var s = servers[server_name]
		if s.get("is_up") and (s.get("health_check") == "complete"):
			return s
			
	if !is_all_servers_checked():
		return		
	global_error_msg = "Image Servers down? Check your internet connection"		
	return {}
	
	
	
#ping servers to see if they're ok for download
var _health_check_started = false
func check_servers_health():
	if _health_check_started:
		return
	_health_check_started = true

	for server_name in servers:
		var s = servers[server_name]
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
				FileDownloader.LOG("check_servers_health error for url: " + url + "(error:" + str(error) + ")")	
			else:
				yield(self, "one_server_check_completed")
			if http_request and (http_request in get_children()):
				remove_child(http_request)
				http_request.queue_free()			

func _health_check_complete(result, _response_code, _headers, _body):
	var current_server = {}
	for server_name in servers:
		var s = servers[server_name]
		if s.get("health_check") == "in_progress":
			current_server = s
			break
	if !current_server:
		var _error = 1
		FileDownloader.LOG("Called Server Health Check complete current_server is empty")
		return
	current_server["health_check"] = "complete"
	if result == HTTPRequest.RESULT_SUCCESS:
		current_server["is_up"] = true
	else:
		current_server["is_up"] = false
		FileDownloader.LOG("Server is down " + current_server.get("url", ""))

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
		FileDownloader.LOG("destination or card_id missing in current_file:" + JSON.print(current_file, '\t'))
		_download_error(url, filename)
		return false

	var image = WCUtils.load_img(filename)
	if !image:
		var _error = 1
		FileDownloader.LOG("unable to load img file:" + filename + " - current_file: " + JSON.print(current_file, '\t'))		
		_download_error(url, filename)
		return false

	var result_img = mask_image(image, destination, card_key)
	if !result_img:
		FileDownloader.LOG("unable to post_process img file:" + filename + " - current_file: " + JSON.print(current_file, '\t'))		
		dl_errors += 1
		return false
		
	var error = dir.remove(filename)
	if error != OK:
		FileDownloader.LOG("warning: could not remove tmp file:" + filename)		
		var _error = 1
	
	return true


func mask_image(image:Image, destination, card_key):
	if not destination:
		var _error = 1
		return null
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
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var rect = image.get_used_rect()
	
	#image.blit_rect(transparent_image, rect,Vector2(0,0))	
	image.blit_rect_mask(transparent_image,mask_image, rect,Vector2(0,0))	
	image.fix_alpha_edges()
	image.save_png(destination)
	return image	
	
#load all images that are still missing from local folder	
func load_pending_images():
	for card_key in cfc.card_definitions.keys():	
		add_card(card_key)
	#_preprocess_all_downloads()	

##Stores all download links for debug purposes
#func _preprocess_all_downloads():
#	var result = {}
#	for server in servers:
#		result[server] = []		
#		for data in cards_to_download:
#			var card_id = data["card_id"]
#			var card_data = cfc.get_card_by_id(card_id)
#			var url = _get_image_dl_url_for_server(card_id, server)
#			if !url:
#				continue
#			var url_data = {
#				"card_id": card_id,
#				"set_name": card_data.get("_set", "_unk"), 
#				"url": url
#			}
#			result[server].append(url_data)
#
#	var file = File.new()
#	file.open("user://all_images.json", File.WRITE)
#	file.store_string(JSON.print(result, '\t'))
#	file.close()
#	return 
