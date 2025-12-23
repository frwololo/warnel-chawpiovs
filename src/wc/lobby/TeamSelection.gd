# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Node

#
#constants
#
var HERO_COUNT = 4 #TODO move to config

#
#sub scenes
#
#Selector drag and drop on the left panel
var heroSelect = preload("res://src/wc/lobby/HeroSelect.tscn")
#Deck Selection element once in the team (right panel)
var heroDeckSelect = preload("res://src/wc/lobby/HeroDeckSelect.tscn")

var scenarioSelect = preload("res://src/wc/lobby/ScenarioSelect.tscn")

#
#data
#
var team := {} #container for the team information, indexed by slot id (0,1,2,3)
var _scenario:= ""
var _rotation = 0
var _preview_rotation = 0
var launch_data

var ERROR_COLOR := 	Color(1,0.11,0.1)
var OK_COLOR := 	Color(0.1,11,0.1)
#
# download info
#
var http_request: HTTPRequest = null

#integers per client
var _pending_ack:= {}
#
# shortcuts
#
onready var main_menu := $MainMenu
onready var modular_container: OptionButton = get_node("%EncounterSelect")
onready var expert_mode: CheckBox = get_node("%ExpertMode")
onready var all_heroes_container = get_node("%Heroes")
onready var heroes_container = get_node("%TeamContainer")
onready var ready_button = get_node("%ReadyButton")
onready var launch_button = get_node("%LaunchButton")
onready var all_scenarios_container = get_node("%Scenarios")
onready var v_folder_label = get_node("%FolderLabel")
# Called when the node enters the scene tree for the first time.
func _ready():
	# If nothing's setup, start server for Single player mode
	if (not get_tree().get_network_peer()):
		gameData.init_1player()

	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")


	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	_create_team_container()
	_load_scenarios()
	_load_encounters()

	# Wait for scripts to load before creating hero container
	# This ensures idx_hero_to_deck_ids is populated (load_deck_definitions runs in load_script_definitions)
	print("TeamSelection: _ready() - checking scripts loading status")
	print("TeamSelection: scripts_loading = ", cfc.scripts_loading)
	print("TeamSelection: has_signal('scripts_loaded') = ", cfc.has_signal("scripts_loaded"))

	# Connect to scripts_loaded signal to create hero container when ready
	if cfc.has_signal("scripts_loaded"):
		# Check if scripts are already loaded
		if not cfc.scripts_loading:
			# Scripts already loaded, create hero container immediately
			print("TeamSelection: Scripts already loaded, creating hero container immediately")
			_create_hero_container()
		else:
			# Scripts still loading, wait for the signal
			print("TeamSelection: Scripts still loading, connecting to scripts_loaded signal")
			cfc.connect("scripts_loaded", self, "_on_scripts_loaded", [], CONNECT_ONESHOT)
	else:
		# Signal doesn't exist yet (shouldn't happen, but handle it)
		# Wait a bit and try again
		print("TeamSelection: scripts_loaded signal doesn't exist yet, waiting...")
		yield(get_tree().create_timer(0.1), "timeout")
		if cfc.has_signal("scripts_loaded") and not cfc.scripts_loading:
			print("TeamSelection: Signal now exists and scripts loaded, creating hero container")
			_create_hero_container()
		elif cfc.has_signal("scripts_loaded"):
			print("TeamSelection: Signal now exists but still loading, connecting to signal")
			cfc.connect("scripts_loaded", self, "_on_scripts_loaded", [], CONNECT_ONESHOT)
		else:
			print("TeamSelection: WARNING - scripts_loaded signal still doesn't exist after wait")

	ready_button.hide() #todo do something with this guy
	launch_button.hide()
	launch_button.connect('pressed', self, 'on_button_pressed', [launch_button.name])

	if !cfc.is_game_master():
		get_node("%EncounterSelect").disabled = true
		get_node("%ExpertMode").disabled = true

	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_deck_download_completed")


#Quickstart for tests
#TODO remove
	if (cfc.is_game_master() and CFConst.DEBUG_AUTO_START_MULTIPLAYER):
		if (gameData.is_multiplayer_game):
			yield(get_tree().create_timer(0.5), "timeout")
			owner_changed(1, 1)
			rpc("assign_hero", "01001a", 0)
			rpc("assign_hero", "01010a", 1)
			yield(get_tree().create_timer(0.5), "timeout")
			scenario_select("01097")
			yield(get_tree().create_timer(0.5), "timeout")
			if CFConst.DEBUG_AUTO_START_MULTIPLAYER:
				_launch_server_game()
#		else:
#			yield(get_tree().create_timer(0.05), "timeout")
#			#rpc("assign_hero", "01001a", 0) #peter
#			rpc("assign_hero", "01010a", 0)#carol
#			yield(get_tree().create_timer(0.2), "timeout")
#			_launch_server_game()
		pass

func _process(delta:float):
	var scenario_picture:TextureRect = get_node("%ScenarioTexture")
	scenario_picture.rect_pivot_offset = scenario_picture.rect_size / 2
	scenario_picture.rect_rotation = _rotation
	scenario_picture.rect_size = Vector2(150, 150)

	var large_picture = get_node("%LargePicture")
	large_picture.rect_position = get_tree().current_scene.get_global_mouse_position()
	large_picture.rect_size = Vector2(300, 420)
	large_picture.rect_rotation = _preview_rotation

func _load_scenarios():
	for scenario_id in cfc.scenarios:

		var new_scenario = scenarioSelect.instance()
		new_scenario.load_scenario(scenario_id)
		new_scenario.name = "scenario_" + scenario_id
		all_scenarios_container.add_child(new_scenario)

func _on_scripts_loaded():
	# Called when scripts_loaded signal fires - now safe to create hero container
	print("TeamSelection: scripts_loaded signal received, creating hero container")
	_create_hero_container()

func _create_hero_container():
	print("TeamSelection: _create_hero_container() called")
	print("TeamSelection: idx_hero_to_deck_ids size = ", cfc.idx_hero_to_deck_ids.size())
	print("TeamSelection: idx_hero_to_deck_ids keys = ", cfc.idx_hero_to_deck_ids.keys())

	var heroes_added = 0
	var heroes_skipped = 0

	for hero_id in cfc.idx_hero_to_deck_ids:
		print("TeamSelection: Processing hero_id = ", hero_id)

		#skip heroes that are not implemented
		var hero_card_data = cfc.get_card_by_id(hero_id)
		if !hero_card_data or hero_card_data.empty():
			print("TeamSelection: SKIPPED hero_id ", hero_id, " - card data not found")
			heroes_skipped += 1
			continue

		var alter_ego_id = hero_card_data.get("back_card_code", "undef")
		print("TeamSelection: hero_id = ", hero_id, ", alter_ego_id = ", alter_ego_id)

		var has_hero_scripts = cfc.unmodified_set_scripts.get(hero_id, {})
		var has_alter_ego_scripts = cfc.unmodified_set_scripts.get(alter_ego_id, {})
		print("TeamSelection: has_hero_scripts = ", !has_hero_scripts.empty(), ", has_alter_ego_scripts = ", !has_alter_ego_scripts.empty())

		if !has_hero_scripts and !has_alter_ego_scripts:
			print("TeamSelection: SKIPPED hero_id ", hero_id, " - no scripts found for hero or alter_ego")
			heroes_skipped += 1
			continue

		var new_hero = heroSelect.instance()
		new_hero.load_hero(hero_id)
		all_heroes_container.add_child(new_hero)
		heroes_added += 1
		print("TeamSelection: ADDED hero_id ", hero_id, " to hero container")

	print("TeamSelection: Hero container creation complete - Added: ", heroes_added, ", Skipped: ", heroes_skipped)


func _load_encounters():
	var modular_sets = cfc.modular_encounters.keys()
	modular_sets.sort()
	for modular_set in modular_sets:
		#TODO more advanced?
		var display_name = modular_set
		modular_container.add_item(display_name)


func _create_team_container():
	for i in HERO_COUNT:
		var new_team_member = heroDeckSelect.instance()
		new_team_member.set_idx(i)
		heroes_container.add_child(new_team_member)
		team[i] = HeroDeckData.new()

remotesync func client_scenario_select(scenario_id):
	_scenario = scenario_id

	var default_modular = ScenarioDeckData.get_recommended_modular_encounter(scenario_id)
	if default_modular:
		var modular_option:OptionButton = get_node("%EncounterSelect")
		for i in modular_option.get_item_count():
			if modular_option.get_item_text(i) == default_modular:
				modular_option.select(i)
				break

	var scenario_scene = all_scenarios_container.get_node("scenario_" + scenario_id)
	if (scenario_scene):
		var imgtex = scenario_scene.get_texture()
		var scenario_picture: TextureRect = get_node("%ScenarioTexture")
		if (imgtex):
			scenario_picture.texture = imgtex
			scenario_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			scenario_picture.rect_size = Vector2(150, 150)
			_rotation = scenario_scene._rotation
			scenario_picture.rect_rotation = _rotation
		var scenario_title = get_node("%ScenarioTitle")
		scenario_title.text = scenario_scene.get_text()

	ack()

func scenario_select(scenario_id):
	if (not cfc.is_game_master()):
		return
	add_pending_acks()
	rpc("client_scenario_select", scenario_id)

puppet func modular_encounter_select(index):
	ack()
	get_node("%EncounterSelect").select(index)

func _on_EncounterSelect_item_selected(index):
	if (not cfc.is_game_master()):
		return
	add_pending_acks()
	rpc("modular_encounter_select", index)
	pass # Replace with function body.

puppet func expert_mode_toggle (button_pressed):
	ack()
	get_node("%ExpertMode").set_pressed_no_signal(button_pressed)

func _on_ExpertMode_toggled(button_pressed):
	if (not cfc.is_game_master()):
		return
	add_pending_acks()
	rpc("expert_mode_toggle", button_pressed)
	pass # Replace with function body.
	pass # Replace with function body.


func request_hero_slot(hero_id):
	rpc_id(1, "get_next_hero_slot",hero_id)

#Attempt to get a slot for a given hero for a given player
#If succesful, tell everyone to update their info
mastersync func get_next_hero_slot(hero_id) -> int:
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id()
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.get_hero_id() == hero_id):
			return -1

	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.owner.network_id == client_id and data.get_hero_id() == ""):
			add_pending_acks()
			rpc("assign_hero", hero_id, i)
			return i
	return -1

remotesync func assign_hero(hero_id, slot):
	#data update
	var hero_deck_data: HeroDeckData = team[slot]
	var previous_hero_id = hero_deck_data.get_hero_id()
	hero_deck_data.set_hero_id(hero_id) #todo could use a signal here and the GUI would be listening

	#gui update
	var hero_deck_select = heroes_container.get_child(slot)
	hero_deck_select.load_hero(hero_id)
	if hero_id:
		for child in all_heroes_container.get_children():
			if child.hero_id == hero_id:
				child.disable()
	if previous_hero_id and previous_hero_id!= hero_id:
		for child in all_heroes_container.get_children():
			if child.hero_id == previous_hero_id:
				child.enable()
	ack()

func verify_launch_button():
	if check_ready_to_launch():
		launch_button.show()
	else:
		launch_button.hide()

func check_ready_to_launch() -> bool:
	if !cfc.is_game_master():
		return false

	#can't launch without scenario
	if (!_scenario):
		return false

	#some clients are still processing stuff
	if are_acks_pending():
		return false

	#can't launch if all players don't have at least one hero
	var players_with_heroes:= {}

	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.get_hero_id()):
			if (data.owner.network_id):
				players_with_heroes[data.owner.network_id] = true
			if (!data.deck_id) or heroes_container.get_child(i).deckSelect.get_selected() == -1:
				return false
	if players_with_heroes.size() != gameData.network_players.size():
		return false

	return true


func request_release_hero_slot(hero_id):
	rpc_id(1, "release_hero_slot",hero_id)

#Attempt to release a slot for a given hero for a given player
#If succesful, tell everyone to update their info
remotesync func release_hero_slot(hero_id) -> int:
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id()
#	var remaining_team_members = 0;
#	for i in HERO_COUNT:
#		var data: HeroDeckData = team[i]
#		if (data.hero_id):
#			remaining_team_members += 1
	var result = -1
	for i in HERO_COUNT:
		var data: HeroDeckData = team[i]
		if (data.owner.network_id == client_id and data.get_hero_id() == hero_id):
			rpc("assign_hero", "", i)
#			remaining_team_members -=1
#			if (not remaining_team_members):
#				launch_button.hide()
			result = i
			break
	verify_launch_button()
	return result

func owner_changed(id, index):
	#item_selected passes the id which is 0 indexed, but players are 1 indexed
	var player : PlayerData = gameData.get_player_by_index(id+1)
	team[index].owner = player
	rpc("remote_owner_changed",id,index)

remote func remote_owner_changed (id, index):
	#update data
	#item_selected passes the id which is 0 indexed, but players are 1 indexed
	var player : PlayerData = gameData.get_player_by_index(id+1)
	team[index].owner = player
	#update GUI
	var _heroDeckSelect = heroes_container.get_child(index)
	_heroDeckSelect.set_owner(id+1)

func deck_changed(_deck_id, hero_index):
	team[hero_index].deck_id = _deck_id
	rpc("remote_deck_changed",_deck_id, hero_index)

remote func remote_deck_changed (_deck_id, hero_index):
	var client_id =  get_tree().get_rpc_sender_id()
	#update data
	team[hero_index].deck_id = _deck_id
	#update GUI
	var _heroDeckSelect = heroes_container.get_child(hero_index)
	_heroDeckSelect.set_deck(_deck_id, client_id)

func request_deck_data(caller_id, _deck_id):
	rpc_id(caller_id, "upload_deck_data", _deck_id)

remotesync func upload_deck_data(_deck_id):
	var client_id =  get_tree().get_rpc_sender_id()
	var deck_data = cfc.deck_definitions[_deck_id]
	rpc_id(client_id, "receive_deck_data", _deck_id, deck_data)

remotesync func receive_deck_data(_deck_id, deck_data):
	var _client_id =  get_tree().get_rpc_sender_id()
	var existing_data = cfc.deck_definitions.get(_deck_id, {})
	if existing_data:
		var checksum1= WCUtils.ordered_hash(existing_data)
		var checksum2 = WCUtils.ordered_hash(deck_data)
		if checksum1 != checksum2:
			#TODO error handling
			var _error = 1
		#return
	process_deck_download(deck_data)

func deck_download_error(msg):
	var label = get_node("%DeckDownloadError")
	label.add_color_override("font_color", ERROR_COLOR)
	label.text = msg
	push_error(msg)

func process_deck_download(deck_data):
	cfc.load_one_deck(deck_data)
	cfc.save_one_deck_to_file(deck_data)
	refresh_deck_containers()

	if cfc._last_deck_error_msg:
		deck_download_error(cfc._last_deck_error_msg)
	else:
		var label = get_node("%DeckDownloadError")
		label.add_color_override("font_color", OK_COLOR)
		label.text = "Deck Downloaded:" + str(deck_data["id"])


func refresh_deck_containers():
	for child in heroes_container.get_children():
		child.refresh_decks()

var _ready_to_launch:= {}
mastersync func ready_to_launch():
	var client_id =  get_tree().get_rpc_sender_id()
	_ready_to_launch[client_id] = true
	if _ready_to_launch.size() == gameData.network_players.size():
		_ready_to_launch = {}
		rpc("launch_client_game")

func _launch_server_game():
	launch_button.hide()
	var serialized_team = {}
	for key in team.keys():
		serialized_team[key] = team[key].savestate_to_json()

	launch_data = {
		"team": serialized_team,
		"scheme_id" : _scenario,
		"modular_encounters":[get_selected_modular()], #TODO maybe more than one eventually
		"expert_mode": is_expert_mode()
	}
	rpc("get_launch_data_from_server", launch_data)
	#_launch_game()

remotesync func get_launch_data_from_server(_scenario_data):
	launch_data = _scenario_data
	rpc_id(1, "ready_to_launch")

remotesync func launch_client_game():
	_launch_game()

func get_selected_modular():
	return modular_container.get_item_text(modular_container.selected)

func is_expert_mode():
	return expert_mode.pressed

func _launch_game():
	# server pressed on launch, start the game!
	if !launch_data:
		var _error = 1
		return
		#panic!
	var serialized_team = launch_data["team"]
	#team = {}
	for key in serialized_team.keys():
		team[key].loadstate_from_json(serialized_team[key])
	gameData.set_team_data(team)

	gameData.set_scenario_data(launch_data)
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'menus/GetReady.tscn')

func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"LaunchButton":
			_launch_server_game()
		#"Cancel":
			#TODO disconnect?
		#	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

func _on_Menu_resized() -> void:
	for tab in [main_menu]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x


#
# Network Sanity functions
#

func add_pending_acks(except_me:=true):
	var my_id = cfc.get_network_unique_id()
	for client_id in gameData.network_players:
		if client_id == my_id and except_me:
			continue
		add_pending_ack(client_id)

func add_pending_ack(client_id):
	if (!_pending_ack.has(client_id)):
		_pending_ack[client_id] = 0
	_pending_ack[client_id] +=1

func remove_pending_ack(client_id):
	if (!_pending_ack.has(client_id)):
		_pending_ack[client_id] = 0

	if (_pending_ack[client_id]) > 0:
		_pending_ack[client_id] -=1
		return true
	else:
		var _error = 1
		return false

func ack():
	rpc_id(1, "master_ack")

mastersync func master_ack():
	var client_id = get_tree().get_rpc_sender_id()
	remove_pending_ack(client_id)
	verify_launch_button()

func are_acks_pending():
	for client_id in gameData.network_players:
		if (!_pending_ack.has(client_id)):
			_pending_ack[client_id] = 0
		if _pending_ack[client_id]:
			return true
	return false

func _deck_download_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Set couldn't be downloaded.")
	else:
		var content = body.get_string_from_utf8()

		var json_result:JSONParseResult = JSON.parse(content)
		if (json_result.error != OK):
			push_error("Set couldn't be downloaded.")
		else:
			process_deck_download(json_result.result)

	var button = get_node("%DownloadDeckButton")
	button.disabled = false

func start_deck_download(deck_id_str):
	var button = get_node("%DownloadDeckButton")
	button.disabled = true
	var base_url = cfc.game_settings.get("decks_base_url","")
	if !base_url:
		deck_download_error("missing download url in settings file")
		button.disabled = false
		return
	var url = base_url + deck_id_str + ".json"
	var error = http_request.request(url)
	if error != OK:
		deck_download_error("An error occurred in the HTTP request.")
		button.disabled = false
		return


func _on_DownloadDeck_pressed():
	var to_download:LineEdit = get_node("%DownloadDeckNumber")
	if !to_download.text.is_valid_integer():
		return
	start_deck_download(to_download.text)
	pass # Replace with function body.


func _on_OpenFolderButton_pressed():
	OS.shell_open(ProjectSettings.globalize_path("user://"))
	pass # Replace with function body.

func show_preview(card_id):
	var large_picture = get_node("%LargePicture")

	var card_data = cfc.get_card_by_id(card_id)
	var horizontal = card_data["_horizontal"]
	var filename = cfc.get_img_filename(card_id)
	var new_img = WCUtils.load_img(filename)
	if not new_img:
		return
	var imgtex = ImageTexture.new()
	imgtex.create_from_image(new_img)
	large_picture.texture = imgtex
	large_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# In case the generic art has been modulated, we switch it back to normal colour
	large_picture.self_modulate = Color(1,1,1)
	large_picture.visible = true
	if horizontal:
		_preview_rotation = 90
	else:
		_preview_rotation = 0
	large_picture.rect_size = Vector2(300, 420)

func hide_preview(card_id):
	var large_picture = get_node("%LargePicture")
	large_picture.visible = false


func _on_CancelButton_pressed():
	self.queue_free()
	gameData.disconnect_from_network()
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')
