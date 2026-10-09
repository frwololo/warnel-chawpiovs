# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED
class_name HeroDeckSelect
extends MarginContainer

#onready var lobby = find_parent("Lobby")
#onready var playerName := $PlayerName
#onready var kick := $Kick

var my_owner = 0
var my_index = 0
var hero_id = 0
var deck_id = 0


var players_mode = 1

var _needs_refresh = 0
var item_id_to_deck_id = {}
var deck_id_to_item_id = {}
#
#shortcuts
# 
onready var playerName := get_node("%PlayerName")
onready var deckSelect := get_node("%DeckSelect")
onready var hero_picture := get_node("%HeroPicture")
onready var hero_picture_12 := get_node("%HeroPictureMode12")
onready var lobby = find_parent("TeamSelection")
onready var h_highlights =  get_node("%HorizontalHighlights")
onready var v_highlights =  get_node("%VerticalHighlights")
onready var deck_container:DeckContainer = get_node("%DeckContainer")
onready var deck_select: OptionButton = get_node("%DeckSelect")

func _ready():
	# Create a Panel and apply a StyleBoxFlat with rounded corners
	var style_box = WCUtils.theme_flatbox_1()
	$PanelContainer.add_stylebox_override("panel", style_box)
	
	
	playerName.connect("item_selected", self, "_on_owner_changed")
	deckSelect.connect("item_selected", self, "_on_deck_changed")
	deck_container.connect("resize_done", self, "_on_deck_container_resized")
	_load_players()
	set_players_mode()
	

func set_players_mode(value = 0):
	var previous_value = players_mode
	if value == previous_value:
		return
		
	if value:
		players_mode = value


		
	if players_mode == 1:
		var source_container = $PanelContainer/Mode234
		var dest_container = $PanelContainer/Mode1	
			
		for c in source_container.get_node("HeroContainer").get_children():
			source_container.get_node("HeroContainer").remove_child(c)
			dest_container.get_node("HeroContainer").add_child(c)		

		if source_container.has_node("DeckContainer"):
			var c = source_container.get_node("DeckContainer") 
			source_container.remove_child(c)
			dest_container.get_node("DeckContainer").add_child(c)
			dest_container.get_node("DeckContainer").rect_min_size = c.rect_min_size			
		
		select_tab("Mode1")
	elif (players_mode > 1):
		var source_container = $PanelContainer/Mode1
		var dest_container = 	$PanelContainer/Mode234	
			
		for c in source_container.get_node("HeroContainer").get_children():
			source_container.get_node("HeroContainer").remove_child(c)
			dest_container.get_node("HeroContainer").add_child(c)		

		if source_container.has_node("DeckContainer"):
			var c = source_container.get_node("DeckContainer")
			if c.has_node("DeckContainer"):
				var gc = c.get_node("DeckContainer")
				c.remove_child(gc)
				dest_container.add_child(gc)			
		

		select_tab("Mode234")	


	
	if players_mode in [1, 2]:
		hero_picture_12.visible = true
		hero_picture.visible = false
	else:
		hero_picture_12.visible = false
		hero_picture.visible = true	
		resize_hero_picture()	

	if deck_id:
		#Refresh everything
		#aggressive but ensures proper size
		load_deck_contents(deck_id)
	resize()

func select_tab(tab_name):
	for tab in $PanelContainer.get_children():
		tab.visible = false

	get_node("%" + tab_name).visible = true
	#cfc.default_button_focus(get_node("%" + tab_name))


func _on_deck_container_resized(new_size):
	rect_min_size = Vector2(0,0)
	rect_size = Vector2(0,0)
	var target_size_x = 0
	var target_size_y = 0
	match players_mode:
		1:
			target_size_x = new_size.x
			target_size_y = hero_picture_12.rect_size.y  + new_size.y
			var _tmp =1
		2:
			target_size_x = hero_picture_12.rect_size.x + 20 + new_size.x
			target_size_y = hero_picture_12.rect_size.y 		
		_:
			target_size_x = hero_picture.rect_size.x + 20 + new_size.x
			target_size_y = hero_picture.rect_size.y
	
	if target_size_x:
		$PanelContainer.rect_min_size.x = target_size_x 
		$PanelContainer.rect_size.x = $PanelContainer.rect_min_size.x
		$PanelContainer/Mode1/DeckContainer.rect_min_size.x =new_size.x 
		$PanelContainer/Mode1/DeckContainer.rect_size.x = new_size.x
	if target_size_y:
		$PanelContainer.rect_min_size.y = target_size_y 
		$PanelContainer.rect_size.y = $PanelContainer.rect_min_size.y
		$PanelContainer/Mode1/DeckContainer.rect_min_size.y = new_size.y
		$PanelContainer/Mode1/DeckContainer.rect_size.y = new_size.y 
	var _tmp = $PanelContainer.rect_size
	var _tmp1 = 1		

func resize_hero_picture():
	var screen_size = get_viewport().size/cfc.screen_scale
	if screen_size.x > 1800:
		hero_picture.rect_min_size = Vector2(140, 200)
		if players_mode == 4:
			hero_picture.rect_min_size = Vector2(100, 150)
	else:		
		hero_picture.rect_min_size = Vector2(100, 100)
		if players_mode == 4:
			hero_picture.rect_min_size = Vector2(70, 70)				
	hero_picture.rect_size = hero_picture.rect_min_size	
	
func resize():
	var screen_size = get_viewport().size/cfc.screen_scale
	if screen_size.x > 1800:
		hero_picture_12.rect_min_size = Vector2(300, 300)
	else:		
		hero_picture_12.rect_min_size = Vector2(200, 200)
		get_node("%PlayerName").clip_text = true
	
	resize_hero_picture()
	hero_picture_12.rect_size = hero_picture_12.rect_min_size	
	h_highlights.rect_min_size = hero_picture.rect_min_size
	v_highlights.rect_min_size = hero_picture.rect_min_size
	h_highlights.rect_size = hero_picture.rect_size
	v_highlights.rect_size = hero_picture.rect_size	
	
func set_idx(idx):
	my_index = idx
	
func _load_players():
	var players:Dictionary = gameData.network_players
	for player in players:
		playerName.add_item(players[player].name, players[player].id)
	set_owner(1)
	if (not cfc.is_game_master()):
		playerName.set_disabled(true)
	if (players.size() < 2):
		playerName.hide()

func _toggle_gui():
	var my_owner_network_id = gameData.get_player_by_index(my_owner).network_id
	if (cfc.get_network_unique_id() == my_owner_network_id) :
		deckSelect.set_disabled(false)
	else:
		deckSelect.set_disabled(true)	
	
func set_owner (id):
	var playerSelector:OptionButton = get_node("%PlayerName")
	playerSelector.select(playerSelector.get_item_index(id))
	my_owner = id
	_toggle_gui()
		
func _on_deck_changed(index):
	var my_owner_network_id = gameData.get_player_by_index(my_owner).network_id
	var new_deck_id = item_id_to_deck_id.get(deckSelect.get_item_id(index))	
	if typeof(new_deck_id) == TYPE_STRING:
		match new_deck_id:
			"__dl__":
				lobby.display_download_menu()
				deck_select.select(0)
				return
			"__edit__":
				get_tree().current_scene.queue_free()	
				gameData.disconnect_from_network()
				gameData.editor_deck_data = deck_container.original_deck_data
				get_tree().change_scene(CFConst.PATH_CUSTOM + 'deckbuilder/DeckEdit.tscn')
				return	
			"__create__":
				get_tree().current_scene.queue_free()	
				gameData.disconnect_from_network()
				gameData.editor_command = {
					"page": "create_deck",
					"hero_id": self.hero_id
				}
				get_tree().change_scene(CFConst.PATH_CUSTOM + 'deckbuilder/DeckManagement.tscn')
				return
		return
		
	if (cfc.get_network_unique_id() == my_owner_network_id) :
		lobby.deck_changed(new_deck_id, my_index)
		
	load_deck_contents(new_deck_id)

func reset_deck_contents():
	deck_container.reset()

func load_deck_contents(new_deck_id):
	reset_deck_contents()
	var deck_info = cfc.deck_definitions[new_deck_id]
	var settings = 	{
			"show_hero": false,
			"show_headers": false,
			"show_deck_info": false,
			"scrollable" :false,
			"can_add_cards": false,
			"columns": 6,
			"max_size_x": 1200,
			"max_size_y": 600			
	}
	match players_mode:
		1:
			pass
		2:
			settings["columns"] = 7
			settings["margin_top"] = 10
			settings["margin_left"] = -25
			settings["max_size_x"] = 850
			settings["max_size_y"] = hero_picture_12.rect_min_size.y + 300			
		_:
			settings["columns"] = 9
			settings["max_size_x"] = 800
			settings["max_size_y"] = hero_picture.rect_min_size.y + 50

			
	deck_container.setup(settings)
	deck_container.load_cards(deck_info)

#deck change notification from a remote caller
func set_deck (_deck_id, caller_id):
	var index = deck_id_to_item_id.get(_deck_id, -1)
	if index <0: #deck doesn't exist on my side, I need to download it
		_needs_refresh = _deck_id
		print_debug("requesting deck download for " + str(_deck_id))		
		lobby.request_deck_data(caller_id, _deck_id)

	else:
		deckSelect.select(index)
		deck_id = _deck_id

func refresh_decks():
	#keep the currently selected index in tmp variable,
	#unless it was previsouly set during a download request
	if !_needs_refresh:
		var item_id = deckSelect.get_item_id(deckSelect.get_selected())
		_needs_refresh = item_id_to_deck_id.get(item_id, 0)

	#reload our hero to refresh the deck list
	load_hero(hero_id)

	#set the correct selected item again
	if deck_id_to_item_id.has(_needs_refresh):
		var index = deckSelect.get_item_index(deck_id_to_item_id.get(_needs_refresh))
		deckSelect.select(index)
	print_debug("received download for " + str(_needs_refresh))	
	_needs_refresh = 0
	#_on_deck_changed(deckSelect.selected)	
	
func _on_owner_changed(id):
	if cfc.is_game_master():
		#item_selected passes the id which is 0 indexed, but players are 1 indexed
		my_owner = id+1 
		_toggle_gui()
		lobby.owner_changed(id, my_index)

func card_image_download_complete(card_id):
	if card_id != hero_id:
		return
	reload_texture()

func reload_texture(callback_owner = null):
	if !hero_id:
		return
	var imgtex = cfc.get_hero_portrait(hero_id, callback_owner)
	if (imgtex and cfc.idx_hero_to_deck_ids[hero_id]):	
		hero_picture.texture = imgtex

		var filename = cfc.get_img_filename(hero_id)	
		var new_img = WCUtils.load_img(filename)
		if new_img:
			var imgtex2 = ImageTexture.new()
			imgtex2.create_from_image(new_img)	
			hero_picture_12.texture = imgtex2
			#hero_picture_12.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			# In case the generic art has been modulated, we switch it back to normal colour
			hero_picture_12.self_modulate = Color(1,1,1)
		else:
			var fallback_texture = cfc.fallback_hero_card_texture(hero_id)
			hero_picture_12.texture = fallback_texture
		
		resize()
	else:
		hero_picture.texture = null	
		hero_picture_12.texture = null	
		
func load_hero(_hero_id):
	hero_id = _hero_id
	
	reset_deck_contents()
	deck_select.clear()
	
	var decks = 0
	var last_deck_id = 0 	
	if (hero_id):
		reload_texture(self)
		decks = cfc.idx_hero_to_deck_ids[hero_id]
		last_deck_id = load_last_used_deck(hero_id)
	if (decks):	
		var current_idx = 0
		item_id_to_deck_id = {}
		deck_id_to_item_id = {}
		var hero_name = cfc.get_card_name_by_id(hero_id)		
		for _deck_id in decks:
			var deck_data = cfc.deck_definitions[_deck_id]
			var deck_name: String = deck_data.name
			deck_name = deck_name.replacen(hero_name, "").trim_prefix(" ")
			deck_name = deck_name.trim_prefix("- ")
			item_id_to_deck_id[current_idx] = deck_data.id
			deck_id_to_item_id[deck_data.id] = current_idx
			deck_select.add_item(deck_name, current_idx)
			if str(deck_data.id) == str(last_deck_id):
				deck_select.select(deck_select.get_item_count() -1)
			current_idx += 1
		
		var additional_entries = {
			"__dl__" : "...MarvelCDB Download",
			"__edit__": "...Edit this Deck",
			"__create__": "...Create a new deck for " + hero_name
			}
		for key in additional_entries:
			deck_select.add_item(additional_entries[key], current_idx)
			item_id_to_deck_id[current_idx] = key 
			deck_id_to_item_id[key] = current_idx
			current_idx += 1				
		#force refresh of selected data	
		_on_deck_changed(deckSelect.selected)		
	else:
		hero_picture.texture = null	
		hero_picture_12.texture = null


func load_last_used_deck(my_hero_id):
	var last_deck_used = cfc.game_settings.get("last_deck", {})	
	return last_deck_used.get(my_hero_id, 0)

func gain_focus():
	if gamepadHandler.is_mouse_input():
		return
		
	var v = $Panel/VerticalHighlights
	v.visible = true
	var h = $Panel/HorizontalHighlights
	h.visible = true
	match players_mode:
		1, 2:
			h.rect_size = hero_picture_12.rect_size
			#$HorizontalHighlights.rect_position = rect_position
			v.rect_size = hero_picture_12.rect_size				
		_:
			h.rect_size = hero_picture.rect_size
			#$HorizontalHighlights.rect_position = rect_position
			v.rect_size = hero_picture.rect_size	
	
func lose_focus():
	var v = v_highlights
	var h = h_highlights	
	v.visible = false
	h.visible = false
	


func _on_HeroPicture_focus_entered():
	gain_focus()


func _on_HeroPicture_focus_exited():
	lose_focus()


func _on_HeroPicture_gui_input(event):
	if event is InputEventMouseButton: 
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I don't want this hero
			lobby.request_release_hero_slot(hero_id)
	elif event is InputEvent:
		if event.is_action_pressed("ui_accept"):	
			#Tell the server I don't want this hero
			lobby.request_release_hero_slot(hero_id)


func _on_HeroPictureMode12_focus_entered():
	gain_focus()


func _on_HeroPictureMode12_focus_exited():
	lose_focus()


func _on_HeroPictureMode12_gui_input(event):
	_on_HeroPicture_gui_input(event)
