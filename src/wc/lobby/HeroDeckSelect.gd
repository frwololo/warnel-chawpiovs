# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends VBoxContainer

#onready var lobby = find_parent("Lobby")
#onready var playerName := $PlayerName
#onready var kick := $Kick

var my_owner = 0
var my_index = 0
var hero_id = 0
var deck_id = 0

var _needs_refresh = 0

#
#shortcuts
# 
onready var playerName := $PlayerName
onready var deckSelect := $DeckSelect
onready var lobby = find_parent("TeamSelection")

func _ready():
	playerName.connect("item_selected", self, "_on_owner_changed")
	deckSelect.connect("item_selected", self, "_on_deck_changed")	
	_load_players()
	
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
	if (cfc.get_network_unique_id() == my_owner_network_id) :
		var _deck_id = deckSelect.get_item_id(index)
		lobby.deck_changed(_deck_id, my_index)

#deck change notification from a remote caller
func set_deck (_deck_id, caller_id):
	var index = deckSelect.get_item_index(_deck_id)
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
		_needs_refresh = deckSelect.get_item_id(deckSelect.get_selected())

	#reload our hero to refresh the deck list
	load_hero(hero_id)

	#set the correct selected item again
	var index = deckSelect.get_item_index(_needs_refresh)
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

func load_hero(_hero_id):
	hero_id = _hero_id

	var hero_picture: TextureRect = get_node("%HeroPicture")
	var deck_select: OptionButton = get_node("%DeckSelect")
	deck_select.clear()
	
	var img = 0
	var decks = 0
	if (hero_id):
		img = cfc.get_hero_portrait(hero_id)
		decks = cfc.idx_hero_to_deck_ids[hero_id]
	if (img and decks):
		var imgtex = ImageTexture.new()
		imgtex.create_from_image(img)	
		hero_picture.texture = imgtex
		hero_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		for _deck_id in decks:
			var deck_data = cfc.deck_definitions[_deck_id]
			var hero_name = cfc.get_card_name_by_id(hero_id)
			var deck_name: String = deck_data.name
			deck_name = deck_name.replacen(hero_name, "").trim_prefix(" ")
			deck_name = deck_name.trim_prefix("- ")
			deck_select.add_item(deck_name, deck_data.id)
		#force refresh of selected data	
		_on_deck_changed(deckSelect.selected)		
	else:
		hero_picture.texture = null	




func gain_focus():
	if gamepadHandler.is_mouse_input():
		return
		
	var hero_picture: TextureRect = get_node("%HeroPicture")
	var v = $Panel/VerticalHighlights
	v.visible = true
	var h = $Panel/HorizontalHighlights
	h.visible = true
	h.rect_size = hero_picture.rect_size
	#$HorizontalHighlights.rect_position = rect_position
	v.rect_size = hero_picture.rect_size	
	
func lose_focus():
	var v = $Panel/VerticalHighlights
	var h = $Panel/HorizontalHighlights	
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
