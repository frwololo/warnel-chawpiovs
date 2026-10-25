class_name ServerConfig
extends Node


var remote_config := {}
var current_tracked_url = ""
var config_is_loaded = false

# Called when the node enters the scene tree for the first time.
func _ready():
	fileDownloader.connect("file_downloaded", self, "_file_downloaded")
	fileDownloader.connect("download_error", self, "_download_error")
	retrieve_server_global_config()
	
#gets a url setting and adds the main server name if it's missing
func get_server_url(url:String) -> String:
	if url.begins_with("http"):
		return url
	
	var server_base:String = cfc.get_setting("server")
	if server_base.ends_with("/") and url.begins_with("/"):
		url = url.substr(1)	
	return  server_base + url

func get_server_url_setting(setting_name):
	var value = cfc.get_setting(setting_name)
	var url = get_server_url(value)
	return url	

func get_remote_config_url():
	return get_server_url(CFConst.SERVER_REMOTE_CONFIG_URL)

func get_child_setting(key: String, setting_name: String):
	if not remote_config.has(key):
		return ""
	return remote_config[key].get(setting_name, "")	

func get_setting(setting_name: String):
	if "/" in setting_name:
		var settings = setting_name.split("/")
		if settings.size() > 1:
			return get_child_setting(settings[0], settings[1])
	return remote_config.get(setting_name, "")

func retrieve_server_global_config():
	var config_url = get_remote_config_url()
	var urls = PoolStringArray([config_url])
	fileDownloader.start_download(urls)
	current_tracked_url = config_url
	return config_url

func _file_downloaded(url, destination):
	#ignore if not for us
	if url != get_remote_config_url():
		return
		
	var my_json = WCUtils.read_json_file(destination)
	if my_json:
		remote_config = my_json
	#remove the file when we're done
	var dir:Directory = Directory.new()		
	dir.remove(destination)

	config_is_loaded = true

func _download_error(url, filename):
	#ignore if not for us
	if url != get_remote_config_url():
		return
			
	remote_config = {}
	#the load was a failure, but we tried so we mark "loaded " as true
	config_is_loaded = true

func is_loaded():
	return config_is_loaded

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
