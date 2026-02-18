class_name AudioManager
extends Node2D

var music_player: AudioStreamPlayer = null
var sfx_players:= []
var current_music_filename := ""
var music_collection := {}
var sfx_collection := {}
var _sfx_collection_traits := {}


var playlist_filter = ""
var play_all_mode = false
var play_all_random_mode = false

const SFX_CHANNELS = 8
var last_sound_played = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	load_sfx_collection()
	load_music_collection()
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	for _i in range (SFX_CHANNELS):
		var player = AudioStreamPlayer.new()
		sfx_players.append(player)
		add_child(player)
		
	music_player.connect("finished", self, "song_finished")
	scripting_bus.connect("card_moved_to_board", self,  "_card_moved_to_board")
	scripting_bus.connect("card_moved_to_pile", self,  "_card_moved_to_pile")

func _card_moved_to_pile(card_owner, details):
	#moving a lot of cards early game, too noisy
	if !gameData._game_started:
		return
	
	var source = details["source"].to_lower()
	var destination = details["destination"].to_lower()
	#gets annoying quickly since the game makes us discard a lot to play
	if source.begins_with("hand"):
		return
	
	#When shuffling discard into deck this gets annoying,
	#so deactivating this use case for now
	if source.begins_with("discard") and destination.begins_with("deck"):
		return	
		
	play_sfx_from_path(["card_moved_to_pile"], card_owner)
	
func _card_moved_to_board(card_owner, _details):
	if card_owner.is_boost():
		return
	
	play_sfx_from_path(["card_moved_to_board"], card_owner)

#TODO
func load_sfx_collection():
	#load from res first
	var sfx_files := CFUtils.list_files_in_directory(
				"res://assets/audio/Sfx/", "", true)
	sfx_files += CFUtils.list_imported_in_directory(
				"res://assets/audio/Sfx/", "", true)
	#then we load from user
	sfx_files += CFUtils.list_imported_in_directory(
				"user://Sfx/", "", true)	
	sfx_files += CFUtils.list_files_in_directory(
				"user://Sfx/", "", true)				
	var result = []	
	for file in sfx_files:	
		if file.ends_with(".mp3"):
			result.append(file)
	
	for file in result:
		var basename = file.get_file()
		basename = basename.split(".")[0]
		if ("-") in basename:
			var filters = basename.split("-")[0]
			if filters.begins_with("trait_"):
				_sfx_collection_traits[filters] = 1
		sfx_collection[basename] = {"filename": file}
#		var components = basename.split("-")
#		var current_node = sfx_collection
#		for component in components:
#			if !current_node.has(component):
#				current_node[component] = {"filename": file}
#			current_node = current_node[component]
			
	var _tmp = 1

func get_available_player():
	for player in sfx_players:
		if !player.is_playing():
			return player
	return null

func load_stream(sfx_collection_node):
	if not typeof(sfx_collection_node) == TYPE_DICTIONARY:
		return null
	
	if sfx_collection_node.has("stream"):
		return sfx_collection_node["stream"]
		
	var filename = sfx_collection_node.get("filename", "")
	if !filename:
		return null
	
	var stream = WCUtils.load_audio(filename)
	if stream as AudioStreamMP3:
		stream.loop = false
	sfx_collection_node["stream"] = stream
	
	return stream
	

func find_sound_for_card_event(event_name, card_owner = null):
	var shortname = ""
	var type_code = ""
	if is_instance_valid(card_owner):
		shortname = card_owner.get_property("shortname", "").to_lower()
		type_code = card_owner.get_property("type_code", "").to_lower()	
	
	if shortname:
		var fullname = shortname + "-" + event_name
		if sfx_collection.has(fullname):
			return load_random_sfx_starts_with(fullname)

	if is_instance_valid(card_owner):
		for trait in _sfx_collection_traits:
			if card_owner.get_property(trait, 0, true):
				var fullname = trait + "-" + event_name
				if sfx_collection.has(fullname):
					return load_random_sfx_starts_with(fullname)
		
		var type_code_key = "type_" + type_code + "-" + event_name
		if sfx_collection.has(type_code_key):
			return load_random_sfx_starts_with(type_code_key)

	return load_random_sfx_starts_with(event_name)	

func find_sound_for_event(event):
	var card_owner = event.owner
	var event_name = event.script_name.to_lower()
	
	return find_sound_for_card_event(event_name, card_owner)
	

var sfx_wildcard_cache = {}
func get_all_sfx_starting_with(string):
	if !sfx_wildcard_cache.has(string):
		sfx_wildcard_cache[string] = []
		for key in sfx_collection:
			if key.begins_with(string):
				sfx_wildcard_cache[string].append(key)

	return sfx_wildcard_cache[string]

func load_random_sfx_starts_with(string):
	var list = get_all_sfx_starting_with(string)
	if !list:
		return null
	var random_index = randi() % list.size()
	
	var key = list[random_index]
	if sfx_collection[key].has("filename"):
		var stream = load_stream(sfx_collection[key])
		return stream

	return null
	
func play_random_sfx_starts_with(string):
	var stream = load_random_sfx_starts_with(string)
	if stream:
		play_sfx_stream(stream)
	
func play_sfx_from_path(path:Array, card_owner = null):	
	if card_owner and path.size() == 1:
		var stream = find_sound_for_card_event(path[0], card_owner)
		play_sfx_stream(stream)
		return
	
	var root = sfx_collection
	for node in path:
		if !root.has(node):
			return
		root = root[node]
	if root and root.has("filename"):
		var stream = load_stream(root)
		play_sfx_stream(stream)

func play_sfx(event):
	if !event:
		return
				
	var stream = find_sound_for_event(event)	
	play_sfx_stream(stream)

func play_sfx_stream(stream):
	if !stream:
		return
	
	var now = Time.get_ticks_msec()
	while now - last_sound_played < 50:
		now = Time.get_ticks_msec()
		yield(get_tree().create_timer(0.01), "timeout")
		
	var player = get_available_player()
	if !player:
		return			
	player.set_stream(stream)
	var sfx_volume = cfc.game_settings.get('sfx_volume', 5)
	player.volume_db = linear2db(float(sfx_volume) / 100.0)	
	player.play()
	self.last_sound_played = Time.get_ticks_msec()
		

func load_music_collection():
	#load from res first
	var music_files := CFUtils.list_files_in_directory(
				"res://assets/audio/Music/", "", true)
	music_files += CFUtils.list_imported_in_directory(
				"res://assets/audio/Music/", "", true)
	#then we load from user
	music_files += CFUtils.list_imported_in_directory(
				"user://Music/", "", true)	
	music_files += CFUtils.list_files_in_directory(
				"user://Music/", "", true)				
	var result = {}		
	for file in music_files:	
		if file.ends_with(".mp3"):
			result[file] = null
	music_collection["generic"] = result

func get_music_stream(filename) -> AudioStream:
	if !has_music(filename):
		return null

	if !music_collection["generic"][filename]:
		music_collection["generic"][filename] = WCUtils.load_audio(filename)

	return music_collection["generic"][filename]
	
func has_music(filename):
	return music_collection.get("generic", {}).has(filename)

func play_music_by_shortname(shortname):
	if !music_collection.has("generic"):
		return
	for key in music_collection["generic"]:
		if shortname in key:
			start_music(key)
			return

func song_finished():
	if play_all_mode:
		play_all(playlist_filter)
		return
		
	if play_all_random_mode:
		play_random(playlist_filter)
		return
		
var music_wildcard_cache = {}
func get_all_music_starting_with(string):
	if !music_wildcard_cache.has(string):
		music_wildcard_cache[string] = []
		for key in music_collection.get("generic", {}):
			if string in key:
				music_wildcard_cache[string].append(key)

	return music_wildcard_cache[string]

func get_random_music_starts_with(string):
	var list = get_all_music_starting_with(string)
	if !list:
		return null
	var random_index = randi() % list.size()
	
	var key = list[random_index]

	return key

func play_random(filter = ""):
	var filename = get_random_music_starts_with(filter)
	if filename:
		start_music(filename, false)	

func play_all_random(filter=""):
	play_all_random_mode = true	
	playlist_filter = filter	
	play_random(filter)

func play_all(filter = ""):
	#not initialized
	if !music_collection.has("generic"):
		return
		
	#initialized but empty
	if !music_collection["generic"]:
		return	
	
	play_all_mode = true	
	playlist_filter = filter
	var found_current = false if current_music_filename else true
	var next_filename = ""
	for filename in music_collection["generic"]:
		if !found_current:
			if filename == current_music_filename:
				found_current = true
			continue
		if filter in filename:
			next_filename = filename
			break
	#if we didn't find the next song, we might be at the end of the playlist,
	#try again from the beginning		
	if !next_filename and current_music_filename:
		current_music_filename = ""
		play_all(filter)
		return
		
	if !next_filename:
		return
		
	start_music(next_filename, false)				
	
func start_music(filename, loop = true):
	#if asked to play the same file as current, just start playing
	if filename == current_music_filename:
		if !music_player.is_playing():
			music_player.play()
		return

	if !has_music(filename):
		return

	var music_stream = get_music_stream(filename)
	if !music_stream:
		return

	if music_stream as AudioStreamMP3:
		music_stream.loop = loop

	var music_volume = cfc.game_settings.get('music_volume', 20)
	music_player.volume_db = linear2db(float(music_volume) / 100.0)
	current_music_filename = filename

	music_player.set_stream(music_stream)
	music_player.play()
