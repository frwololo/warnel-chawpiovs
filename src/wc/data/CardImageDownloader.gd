class_name CardImageDownloader
extends Node

const servers := [
	{
		"url": "https://marvelcdb.com",
		"is_up": true,		
	},
	{
		"url": "https://db.merlindumesnil.net",
		"is_up": true,
		"modifications": {
			"extension": ".jpg"
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
		
		path = base_url + path
	
	current_file["path"] = path			
	fileDownloader.start_download([path])

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
	pass

	
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
