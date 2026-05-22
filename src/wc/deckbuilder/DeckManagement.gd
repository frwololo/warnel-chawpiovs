# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Node

#
#constants
#

#
#sub scenes
#
var deckData = preload("res://src/wc/deckbuilder/DeckData.tscn")



#
#data
#
var all_decks := {} #deckData components
var names_to_id:= {} #hero display name to id
var hero_id_to_display_name:= {} #hero display name to id

var ERROR_COLOR := 	Color(1,0.11,0.1)
var OK_COLOR := 	Color(0.1,11,0.1)
#
# download info
#
var http_request: HTTPRequest = null

#
# shortcuts
#
onready var error_label := get_node("%message")
onready var back_button := get_node("%BackButton")
onready var clone_button := get_node("%CloneButton")
onready var edit_button := get_node("%EditButton")
onready var delete_button := get_node("%DeleteButton")
onready var export_button := get_node("%ExportButton")
onready var download_button := get_node("%DownloadDeckButton")
onready var reset_all_button := get_node("%ResetAllButton")

onready var deck_container := get_node("%Decks")
onready var main_container := get_node("%MainMenu")
onready var new_deck_menu := get_node("%NewDeckContainer")
onready var export_container := get_node("%ExportContainer")
onready var export_data := get_node("%ExportData")
onready var deck_scroll := get_node("%DecksScroll")
onready var heroes_filter:OptionButton = get_node("%HeroesFilter")
onready var heroes_filter2:OptionButton = get_node("%HeroesFilter2")
onready var deck_picture_highlight: TextureRect = get_node("%DeckPicture2")

var focus_chosen = false
var current_selected_deck_id = 0
var current_deck = null
var local_deck_max_id = 0
var do_highlight = false


func grab_default_focus():
	for child in deck_container.get_children():
		child.grab_focus()	
		return
	
	#last hope
	get_node("%BackButton").grab_focus()

func critical_error():
	error_label.visible = true
	error_label.add_color_override("font_color", Color8(255, 50,50))
	error_label.text = "It seems there was a critical issue loading the database. Please check your network connection and your local files (settings, Sets/*, etc...)"

func _ready():
	gameData.play_music("deck_editor*")
	get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")	
	get_viewport().connect("size_changed", self, '_on_Menu_resized')


	http_request = HTTPRequest.new()
	add_child(http_request)	
	http_request.connect("request_completed", self, "_deck_download_completed")

	cfc.buttons_grab_focus_on_mouse_entered(self)	

	#buttons signals
	back_button.connect("pressed", self, "_on_CancelButton_pressed")
	download_button.connect("pressed", self, "_on_DownloadDeck_pressed")	
	clone_button.connect("pressed", self, "_clone_pressed")
	edit_button.connect("pressed", self, "_edit_pressed")
	delete_button.connect("pressed", self, "_delete_pressed")
	export_button.connect("pressed", self, "_export_pressed")	
	reset_all_button.connect("pressed", self, "_reset_all_pressed")
	
	
	resize()
	
	#load data
	_load_decks()
	_filter_decks()
	_load_heroes()
	
	#initial UI state
	disable_deck_buttons()
	var loading_panel = get_node("%LoadingPanel")	
	loading_panel.visible = false	
	
	tab_select(main_container)

	
	if gameData.editor_deck_data:
		highlight_deck(gameData.editor_deck_data["id"])

func disable_deck_buttons(value = true):
	delete_button.disabled = value
	clone_button.disabled = value
	export_button.disabled = value	
	edit_button.disabled = value	

func enable_deck_buttons(value = true):
	disable_deck_buttons(!value)
	
	
func tab_select(chosen_container):
	for container in [main_container, new_deck_menu, export_container]:
		container.visible =  (container == chosen_container)

#TODO: need to do this hack because gamepadHandler "gui_focus_changed" only works automatically when the
#board has been set up
#this is because a new viewport is created for the board
func gui_focus_changed(control):
	gamepadHandler.gui_focus_changed(control)

func _process(delta:float):
	if do_highlight:
		deck_picture_highlight.rect_min_size *= 1.03
		deck_picture_highlight.modulate.a *= 0.9
		var size_diff = deck_picture_highlight.rect_size - current_deck.deck_picture.rect_size
		deck_picture_highlight.rect_position = current_deck.get_global_position() - size_diff/2
		if 	deck_picture_highlight.modulate.a < 0.1:
			stop_highlight()

func highlight_deck(deck_id):
	deck_selected(deck_id)
	start_highlight()	
	
func resize():
	var stretch_mode = cfc.get_screen_stretch_mode()

	var screen_size = get_viewport().size
	deck_scroll.rect_min_size = screen_size - Vector2(50, 20)
	deck_scroll.rect_min_size.y -= 300
	new_deck_menu.rect_min_size = screen_size
	export_container.rect_min_size = screen_size
	export_data.rect_min_size =  Vector2(screen_size.x /3, screen_size.y  - 100)
	if stretch_mode == SceneTree.STRETCH_MODE_VIEWPORT and screen_size.x > 1800:
		pass
	else:	
		pass

func _load_hero_base_cards(hero_id):
	var hero_data = cfc.get_card_by_id(hero_id)
	var set_name = hero_data["card_set_code"].to_lower()
	var all_set_cards = cfc.cards_by_set[set_name]
	var slots = {}
	for card in all_set_cards:
		var type = card["type_code"].to_lower()
		if type in ["hero", "alter_ego", "obligation"]:
			continue 
		var quantity = card.get("quantity", 1)
		slots[card["_code"]] = quantity

	return slots	
		
#creates a new deck then goes to editing mode
func create_and_edit_new_deck(hero_id = ""):
	if !hero_id:
		#ask for hero id selection
		tab_select(new_deck_menu)
		return
	var hero_name = cfc.get_card_name_by_id(hero_id)
	var deck_data = {
		"hero_code": hero_id,
		"slots": _load_hero_base_cards(hero_id),
		"name": hero_name + " - New Deck",
	}
	save_local_deck(deck_data)
	edit_deck(deck_data)

#runs editing mode with currently selected deck
func edit_deck(deck_data):
	self.queue_free()
	gameData.disconnect_from_network()
	gameData.editor_deck_data = deck_data
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'deckbuilder/DeckEdit.tscn')	

func deck_selected(deck_id):
	#unselect
	get_node("%DeckTitle").text = ""
	if deck_id == -1:
		if current_deck and is_instance_valid(current_deck):
			current_deck.hide_highlights()		
		current_deck = null
		current_selected_deck_id = 0
		disable_deck_buttons()
		return
	
	#new deck
	if !deck_id:
		#TODO
		create_and_edit_new_deck(get_current_filter_hero_id())
		return
		
	if current_selected_deck_id == deck_id:
		return

	enable_deck_buttons()
		
	if current_deck:
		current_deck.hide_highlights()
	
	current_selected_deck_id = deck_id
	current_deck = all_decks.get(current_selected_deck_id)
	if current_deck:
		current_deck.show_highlights()
		get_node("%DeckTitle").text = current_deck.get_full_name()	
		yield(get_tree(), "idle_frame")
		deck_scroll.ensure_control_visible(current_deck)


func start_highlight():
	if !current_deck:
		return
	do_highlight = true
	deck_picture_highlight.visible = true
	deck_picture_highlight.expand = true
	deck_picture_highlight.texture = current_deck.get_texture()
	deck_picture_highlight.rect_min_size = current_deck.deck_picture.rect_size
	deck_picture_highlight.rect_size = deck_picture_highlight.rect_min_size
	deck_picture_highlight.rect_position = current_deck.get_global_position()
	
	
func stop_highlight():
	if !current_deck:
		return
		
	do_highlight = false
	deck_picture_highlight.rect_min_size = current_deck.deck_picture.rect_min_size
	deck_picture_highlight.modulate.a = 1
	deck_picture_highlight.visible = false

#shortcut for cleanliness because get_focus_owner needs a control node...
func get_focus_owner():
	var focus_owner = back_button.get_focus_owner()
	if !focus_owner:
		grab_default_focus()
		focus_owner = back_button.get_focus_owner()
	return focus_owner

func _load_heroes():
	for hero_id in cfc.idx_hero_to_deck_ids:
		#skip heroes that are not implemented
		var hero_card_data = cfc.get_card_by_id(hero_id)
		var alter_ego_id =  hero_card_data.get("back_card_code", "undef")
		if !cfc.unmodified_set_scripts.get(hero_id,{}) and\
			 !cfc.unmodified_set_scripts.get(alter_ego_id,{}):
			continue
		var hero_name = cfc.get_card_name_by_id(hero_id)
		var alter_ego_name = cfc.get_card_name_by_id(alter_ego_id)
		var display_name = hero_name + " - " + alter_ego_name
		if hero_name == alter_ego_name:
			display_name = hero_name
		names_to_id[display_name] = hero_id
		hero_id_to_display_name[hero_id] = display_name
	
	#sort by hero name and build the optionsMenu
	var ordered_names = names_to_id.keys()
	ordered_names.sort()	
		
	for display_name in ordered_names:
		heroes_filter.add_item(display_name)
		heroes_filter2.add_item(display_name)

func _load_decks():
	if all_decks:
		return
	
	var empty_deck = deckData.instance()
	all_decks[0] = empty_deck
				
	for deck_info in cfc.deck_definitions.values():
		_load_one_deck(deck_info.duplicate(true))

func _load_one_deck(deck_info):
	var new_deck = deckData.instance()
	new_deck.load_deck(deck_info)
	all_decks[deck_info["id"]] = new_deck
	var filepath = deck_info.get("filepath", "")
	var is_local = filepath.find("local_")
	if is_local >= 0:
		var local_id = filepath.substr(is_local + 6)
		local_id = local_id.replace(".json", "")
		local_id = int(local_id)
		if local_id > local_deck_max_id:
			local_deck_max_id = local_id
	return new_deck

func _filter_decks(hero_id = ""):
	_load_decks()
	for c in deck_container.get_children():
		deck_container.remove_child(c)
		
	var no_deck_loaded = true
	#show in alphabetical order
	var decks:Array = []
	if hero_id:
		var deck_ids = cfc.idx_hero_to_deck_ids[hero_id]
		for deck_id in deck_ids:
			decks.append(cfc.deck_definitions[deck_id])
	else:
		for hero_id in cfc.idx_hero_to_deck_ids:
			var deck_ids = cfc.idx_hero_to_deck_ids[hero_id]
			for deck_id in deck_ids:
				decks.append(cfc.deck_definitions[deck_id])		

	decks.push_front({"id": 0})
	for deck_data in decks:
		var deck_id = deck_data["id"]
		var deck_component = all_decks.get(deck_id, null)
		if deck_component:	
			deck_container.add_child(deck_component)
			if deck_id:
				no_deck_loaded = false

	if no_deck_loaded:
		critical_error()

#
# Deck Download functionality
#

func deck_download_error(msg):
	var label = get_node("%DeckDownloadError")
	label.add_color_override("font_color", ERROR_COLOR)	
	label.text = msg
	push_error(msg)
	
func process_deck_download(deck_data):
	cfc.load_one_deck(deck_data)		
	var json_deck_data = cfc.save_one_deck_to_file(deck_data)

	if cfc._last_deck_error_msg:
		deck_download_error(cfc._last_deck_error_msg)
	else:
		var label = get_node("%DeckDownloadError")
		label.add_color_override("font_color", OK_COLOR)
		var hero_id = json_deck_data.get("hero_code", "")
		label.text = "Deck Downloaded:" + str(deck_data["id"]) + " for " + hero_id_to_display_name.get(hero_id, "") 
		refresh_deck_containers(json_deck_data)
	

func refresh_deck_containers(json_deck_data):
	#add deck to current data
	var _created_deck = _load_one_deck(json_deck_data)
	#refresh display
	_filter_by_hero(heroes_filter.get_selected())		
	
	#force switch to "all heroes" if the deck isn't for the current hero
	var hero_id = json_deck_data.get("hero_code", "")
	var current_hero_filter = get_current_filter_hero_id()	
	if hero_id and current_hero_filter:
		if hero_id != current_hero_filter:
			heroes_filter.select(0)	
			_filter_by_hero(0)
	
	highlight_deck(json_deck_data["id"])
	


func _on_Menu_resized() -> void:
	resize()



#
# Deck Download functions
#

var _deck_dl_backup = false
func _deck_download_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Deck couldn't be downloaded.")
	else:
		var content = body.get_string_from_utf8()

		var json_result:JSONParseResult = JSON.parse(content)
		if (json_result.error != OK):
			if !_deck_dl_backup:
				_deck_dl_backup = true
				_on_DownloadDeck_pressed()
				return
			push_error("DEck couldn't be downloaded.")
		else:
			process_deck_download(json_result.result)	 		
	
	_deck_dl_backup = false
	var button = get_node("%DownloadDeckButton")
	button.disabled = false
	var loading_panel = get_node("%LoadingPanel")	
	loading_panel.visible = false	

func start_deck_download(deck_id_str):
	var button = get_node("%DownloadDeckButton")
	button.disabled = true
	var base_url = cfc.game_settings.get("decks_base_url","")
	if _deck_dl_backup:
		base_url = cfc.game_settings.get("decks_base_url_backup","")
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
	
func get_current_filter_hero_id():
	var index = heroes_filter.get_selected()
	if !index:
		return ""
	var hero_name = heroes_filter.get_item_text(index)
	var hero_id = names_to_id[hero_name]
	return hero_id

func _on_DownloadDeck_pressed():
	var to_download:LineEdit = get_node("%DownloadDeckNumber")
	if !to_download.text.is_valid_integer():
		return
	
	var loading_panel = get_node("%LoadingPanel")	
	loading_panel.visible = true
	for c in loading_panel.get_children():
		c.rect_min_size = loading_panel.rect_size
			
	start_deck_download(to_download.text)
	pass # Replace with function body.

func get_current_deck_name(full_name:= true):
	if !current_deck:
		return "--"

	if full_name:
		return current_deck.get_full_name()
		
	return current_deck.get_display_name()

#deletes current selected deck
func ask_delete_deck():
	#exclude "create deck" option which is 0
	if !current_selected_deck_id:
		return	
		
	var dialog:ConfirmationDialog = ConfirmationDialog.new()
	dialog.window_title = "Delete Deck?"
	var text = "Delete Deck : " + get_current_deck_name() + "?"
	
	if cfc.res_deck_ids.has(current_selected_deck_id):
		text+= "\n" + "Note that this is a Default deck: a clean copy will be recreated at startup"
	else:
		text += " This can't be undone."
	dialog.set_text(text)
	dialog.connect("confirmed", self, "delete_deck")
	add_child(dialog)
	dialog.popup_centered()		

func delete_deck():
	#exclude "create deck" option which is 0
	if !current_selected_deck_id:
		return
			
	if !current_deck:
		var _error = 1
		return
		
	var filepath = current_deck.deck_data.get("filepath", "")
	if !filepath:
		var _error = 1
		return
	
	var dir = Directory.new()
	dir.remove(filepath)
	all_decks.erase(current_selected_deck_id)
	cfc.remove_one_deck(current_selected_deck_id)
	current_deck.queue_free()
	deck_selected(-1)
	_filter_by_hero(heroes_filter.get_selected())	
	pass

#clones current selected deck
func export_current_deck():
	#exclude "create deck" option which is 0
	if !current_deck:
		return
	tab_select(export_container)
	var text = current_deck.export_for_mcdb()
	export_data.text = text

	

#clones current selected deck
func clone_deck():
	#exclude "create deck" option which is 0
	if !current_selected_deck_id:
		return
			
	if !current_deck:
		var _error = 1
		return
	
	var data = current_deck.deck_data.duplicate()
	data["name"] += " (copy)"
	save_local_deck(data)	
	_filter_by_hero(heroes_filter.get_selected())	
	highlight_deck(data["id"])

func save_local_deck(data, new_id = true):
	var id = data.get("id", CFConst.LOCAL_DECK_ID_OFFSET + local_deck_max_id)
	if new_id:
		local_deck_max_id+=1
		id = CFConst.LOCAL_DECK_ID_OFFSET + local_deck_max_id
	var filepath = "user://Decks/local_" + str(local_deck_max_id) + ".json"
	data["id"] = id
	cfc.save_one_deck_to_file(data, filepath)
	_load_one_deck(data)
	
#deletes all decks (this will reload the default ones)	
func ask_reset_all_decks():
	var dialog:ConfirmationDialog = ConfirmationDialog.new()
	dialog.window_title = "Delete All Decks?"
	var text = "This will delete all user-created decks\nand reload the default decks.\nAre you sure?"

	dialog.set_text(text)
	dialog.connect("confirmed", self, "reset_all_decks")
	add_child(dialog)
	dialog.popup_centered()		
	
func reset_all_decks():
	var dir = Directory.new()
	var files = CFUtils.list_files_in_directory("user://Decks/")
	
	#delete all decks
	for file in files:
		if file.ends_with(".json"):
			dir.remove("user://Decks/" + file)
	
	#reload database and copy default decks from res folder				
	cfc.load_deck_definitions()
	
	#clear data from this page and reload
	for key in all_decks:
		var deck_scene = all_decks[key]
		deck_scene.queue_free()
	all_decks = {}
	deck_selected(-1)
	_filter_by_hero(heroes_filter.get_selected())	


	
func _on_CancelButton_pressed():
	gameData.editor_deck_data = {}
	self.queue_free()
	gameData.disconnect_from_network()
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

func _delete_pressed():
	ask_delete_deck()

func _export_pressed():
	export_current_deck()

func _clone_pressed():
	clone_deck()

func _edit_pressed():
	edit_deck(current_deck.deck_data)
	
func _reset_all_pressed():
	ask_reset_all_decks()	

func _filter_by_hero(index):
	if !index:
		_filter_decks()
		return
		
	#specific hero id
	var hero_name = heroes_filter.get_item_text(index)
	var hero_id = names_to_id[hero_name]
	_filter_decks(hero_id)
	
func _on_HeroesFilter_item_selected(index):
	#all heroes
	if index:
		reset_all_button.visible = false
	else:
		reset_all_button.visible = true
	_filter_by_hero(index)



func _on_DeckCreateHeroButton_pressed():
	var hero_name = heroes_filter2.get_item_text(heroes_filter2.get_selected())
	var hero_id = names_to_id[hero_name]
	create_and_edit_new_deck(hero_id)


func _on_CloseExportButton_pressed():
	OS.window_fullscreen = cfc.game_settings.get("fullscreen", false) 
	tab_select(main_container)
	highlight_deck(current_selected_deck_id)


func _on_ClipboardButton_pressed():
	export_data.select_all() #this isn't useful but serves as a visual indication
	OS.set_clipboard(export_data.text)
	var message = "Deck copied to clipboard"
	var msg_dialog:AcceptDialog = AcceptDialog.new()
	msg_dialog.window_title = message
	add_child(msg_dialog)
	msg_dialog.popup_centered()		


func _on_MCDBButton_pressed():
	OS.window_fullscreen = false
	OS.set_clipboard(export_data.text)
	OS.shell_open("https://marvelcdb.com/deck/import")


func _on_DownloadDeckNumber_text_entered(new_text):
	_on_DownloadDeck_pressed()
